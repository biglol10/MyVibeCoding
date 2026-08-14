import AppKit
import Foundation
import MyMacSearchAppSupport
import MyMacSearchCore
import Observation

extension Notification.Name {
    static let myMacSearchFocusSearch = Notification.Name("MyMacSearchFocusSearch")
}

@MainActor
@Observable
final class AppModel {
    var settings: SearchSettings
    private(set) var searchViewModel: SearchViewModel?
    private(set) var indexHealthViewModel: IndexHealthViewModel?
    private(set) var coordinator: IndexCoordinator?
    private(set) var startupError: String?
    private(set) var actionError: String?
    private(set) var settingsError: String?

    let quickLook = QuickLookPreviewController()

    private let applicationSupportURL: URL
    private let homeURL: URL
    private let settingsStore: SearchSettingsStore
    private let shortcutController = GlobalShortcutController()
    private let volumeMonitor = VolumeAvailabilityMonitor()
    private var actionService: ResultActionService?

    init() {
        let environment = ProcessInfo.processInfo.environment
        homeURL = environment["MYMACSEARCH_QA_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        } ?? FileManager.default.homeDirectoryForCurrentUser
        applicationSupportURL = environment["MYMACSEARCH_QA_APPLICATION_SUPPORT"].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        } ?? homeURL.appendingPathComponent(
            "Library/Application Support/MyMacSearch",
            isDirectory: true
        )
        settingsStore = SearchSettingsStore(directoryURL: applicationSupportURL)
        settings = (try? settingsStore.load()) ?? SearchSettings.recommended(homeURL: homeURL)
        rebuildServices(startIndexing: settings.onboardingConfirmed)
        registerGlobalShortcut()
    }

    var needsOnboarding: Bool {
        !settings.onboardingConfirmed
    }

    var selectedEntry: IndexedEntry? {
        guard let searchViewModel, let selectedID = searchViewModel.selectedEntryID else {
            return nil
        }
        return searchViewModel.rows.first { $0.id == selectedID }
    }

    func confirmOnboarding() {
        guard settings.scopes.contains(where: \.isEnabled) else {
            settingsError = "Choose at least one folder to index."
            return
        }
        settings.onboardingConfirmed = true
        persistSettings()
        rebuildServices(startIndexing: true)
    }

    func applySettings() {
        persistSettings()
        rebuildServices(startIndexing: settings.onboardingConfirmed)
        registerGlobalShortcut()
    }

    func addScopes() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders to index"
        panel.prompt = "Add Folders"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }

        let existing = Set(settings.scopes.map(\.rootPath))
        for url in panel.urls.map(\.standardizedFileURL) where !existing.contains(url.path) {
            let volumeType = Self.volumeType(for: url)
            let expectedVolumeUUID: String?
            if volumeType == .internalLocal {
                expectedVolumeUUID = nil
            } else {
                expectedVolumeUUID = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            }
            settings.scopes.append(
                SearchScopeSetting(
                    rootPath: url.path,
                    volumeType: volumeType,
                    expectedVolumeUUID: expectedVolumeUUID
                )
            )
            if volumeType == .external { settings.externalVolumesEnabled = true }
            if volumeType == .network { settings.networkVolumesEnabled = true }
        }
        settings.scopes.sort { $0.rootPath.localizedStandardCompare($1.rootPath) == .orderedAscending }
    }

    func removeScope(id: String) {
        settings.scopes.removeAll { $0.id == id }
    }

    func resumeIndexing() {
        coordinator?.start(scopes: allowedIndexScopes())
    }

    func perform(_ action: ResultAction) {
        guard let entry = selectedEntry, let actionService else { return }
        actionError = nil
        Task {
            do {
                try await actionService.perform(action, entry: entry)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func toggleQuickLook() {
        guard let entry = selectedEntry else { return }
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            coordinator?.removeMissingPath(entry.path)
            actionError = ResultActionError.missingPath(entry.path).localizedDescription
            return
        }
        quickLook.updateSelection(url)
        quickLook.togglePanel()
    }

    func activateSearchWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .myMacSearchFocusSearch, object: nil)
    }

    func clearSearch() {
        searchViewModel?.query = ""
        NotificationCenter.default.post(name: .myMacSearchFocusSearch, object: nil)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissActionError() {
        actionError = nil
    }

    private func rebuildServices(startIndexing: Bool) {
        coordinator?.pause()
        volumeMonitor.stop()
        startupError = nil
        do {
            let databaseURL = applicationSupportURL.appendingPathComponent("Index.sqlite3")
            let writer = try SQLiteIndexWriter(databaseURL: databaseURL)
            let reader = try SQLiteIndexReader(databaseURL: databaseURL)
            let healthReader = try SQLiteIndexHealthReader(databaseURL: databaseURL)
            let healthViewModel = IndexHealthViewModel(
                reader: healthReader,
                verifier: SQLiteIndexVerifier(databaseURL: databaseURL)
            )
            let metadataClient = FoundationFileMetadataClient()
            let policy = IndexingPolicy(
                homePath: homeURL.path,
                includeHidden: settings.includeHidden,
                userExcludedPaths: Set(settings.excludedPaths)
            )
            let scanner = FileScanner(metadataClient: metadataClient, policy: policy)
            let coordinator = IndexCoordinator(
                scanner: scanner,
                writer: writer,
                metadataClient: metadataClient,
                policy: policy,
                watcher: FSEventsWatcher()
            )
            self.coordinator = coordinator
            let searchViewModel = SearchViewModel(
                searcher: reader,
                libraryStore: SearchLibraryStore(directoryURL: applicationSupportURL),
                initialSort: settings.preferredSort ?? .modifiedNewest,
                onExplicitSortChange: { [weak self] sort in
                    guard let self else { return }
                    self.settings.preferredSort = sort
                    self.persistSettings()
                }
            )
            self.searchViewModel = searchViewModel
            self.indexHealthViewModel = healthViewModel
            actionService = ResultActionService { [weak coordinator] path in
                coordinator?.removeMissingPath(path)
            }
            searchViewModel.refresh()
            if startIndexing {
                coordinator.start(scopes: allowedIndexScopes())
                startVolumeMonitoring(coordinator: coordinator)
            }
        } catch {
            startupError = error.localizedDescription
            searchViewModel = nil
            indexHealthViewModel = nil
            coordinator = nil
            actionService = nil
        }
    }

    func refreshIndexHealth(force: Bool = true) {
        indexHealthViewModel?.refresh(liveStates: coordinator?.scopeStates ?? [:], force: force)
    }

    func verifyIndex() {
        indexHealthViewModel?.verify()
    }

    func rescan(scopeID: String) {
        coordinator?.rescan(scopeID: scopeID)
        refreshIndexHealth()
    }

    func rescanAllScopes() {
        coordinator?.rescanAll()
        refreshIndexHealth()
    }

    private func startVolumeMonitoring(coordinator: IndexCoordinator) {
        let scopes = settings.scopes.compactMap { scope -> MonitoredVolumeScope? in
            guard scope.isEnabled, scope.volumeType != .internalLocal else { return nil }
            return MonitoredVolumeScope(
                id: scope.id,
                rootPath: scope.rootPath,
                expectedVolumeUUID: scope.expectedVolumeUUID
            )
        }
        volumeMonitor.start(scopes: scopes) { [weak coordinator] scopeID, availability in
            coordinator?.updateAvailability(scopeID: scopeID, availability: availability)
        }
    }

    private func allowedIndexScopes() -> [IndexScope] {
        let databaseURL = applicationSupportURL.appendingPathComponent("Index.sqlite3")
        let persistedScopes = (try? SQLiteIndexReader.loadScopes(at: databaseURL)) ?? []
        let persistedByID = Dictionary(uniqueKeysWithValues: persistedScopes.map { ($0.id, $0) })
        return settings.scopes.compactMap { scope in
            guard scope.isEnabled else { return nil }
            if scope.volumeType == .external, !settings.externalVolumesEnabled { return nil }
            if scope.volumeType == .network, !settings.networkVolumesEnabled { return nil }
            if let persisted = persistedByID[scope.id],
               persisted.rootPath == scope.rootPath,
               persisted.volumeType == scope.volumeType {
                return IndexScope(
                    id: scope.id,
                    rootPath: scope.rootPath,
                    volumeType: scope.volumeType,
                    isEnabled: true,
                    completedGeneration: persisted.completedGeneration,
                    lastEventID: persisted.lastEventID
                )
            }
            return scope.indexScope
        }
    }

    private func persistSettings() {
        do {
            try settingsStore.save(settings)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func registerGlobalShortcut() {
        do {
            try shortcutController.register(settings.globalShortcut) { [weak self] in
                self?.activateSearchWindow()
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private static func volumeType(for url: URL) -> IndexedVolumeType {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsLocalKey,
            .volumeIsInternalKey
        ])
        if values?.volumeIsLocal == false { return .network }
        if values?.volumeIsInternal == false { return .external }
        return .internalLocal
    }
}
