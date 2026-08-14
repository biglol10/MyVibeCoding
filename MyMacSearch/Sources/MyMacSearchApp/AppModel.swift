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
    private(set) var isResolvingScopes = false

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
        guard let searchViewModel, let selectedID = searchViewModel.primaryEntryID else {
            return nil
        }
        return searchViewModel.rows.first { $0.id == selectedID }
    }

    var selectedEntries: [IndexedEntry] {
        guard let searchViewModel else { return [] }
        return searchViewModel.rows.filter { searchViewModel.selectedEntryIDs.contains($0.id) }
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
        guard !isResolvingScopes else {
            settingsError = "Wait for the selected volume to finish loading."
            return
        }
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
        let urls = panel.urls.map(\.standardizedFileURL).filter { !existing.contains($0.path) }
        guard !urls.isEmpty else { return }
        isResolvingScopes = true
        Task {
            defer { isResolvingScopes = false }
            let descriptors = await Task.detached(priority: .userInitiated) {
                urls.map(Self.volumeDescriptor(for:))
            }.value
            for descriptor in descriptors {
                settings.scopes.append(
                    SearchScopeSetting(
                        rootPath: descriptor.path,
                        volumeType: descriptor.type,
                        expectedVolumeUUID: descriptor.uuid
                    )
                )
                if descriptor.type == .external { settings.externalVolumesEnabled = true }
                if descriptor.type == .network { settings.networkVolumesEnabled = true }
            }
            settings.scopes.sort { $0.rootPath.localizedStandardCompare($1.rootPath) == .orderedAscending }
        }
    }

    func removeScope(id: String) {
        settings.scopes.removeAll { $0.id == id }
    }

    func resumeIndexing() {
        let scopes = allowedIndexScopes()
        coordinator?.start(
            scopes: scopes,
            initiallyUnavailableScopeIDs: Set(scopes.filter { $0.volumeType != .internalLocal }.map(\.id))
        )
        if let coordinator { startVolumeMonitoring(coordinator: coordinator) }
    }

    func perform(_ action: ResultAction) {
        guard let entry = selectedEntry, let actionService else { return }
        let entries = selectedEntries
        actionError = nil
        Task {
            do {
                switch action {
                case .copyPath where entries.count > 1:
                    try await actionService.copyPaths(entries)
                case .revealInFinder where entries.count > 1:
                    let available = entries.filter { coordinator?.isScopeUnavailable($0.scopeID) != true }
                    let unavailableCount = entries.count - available.count
                    guard !available.isEmpty else {
                        throw ResultActionError.partialFailure(missing: 0, unavailable: unavailableCount)
                    }
                    try await actionService.revealInFinder(available)
                    if unavailableCount > 0 {
                        throw ResultActionError.partialFailure(missing: 0, unavailable: unavailableCount)
                    }
                default:
                    if action != .copyPath, coordinator?.isScopeUnavailable(entry.scopeID) == true {
                        throw ResultActionError.partialFailure(missing: 0, unavailable: 1)
                    }
                    try await actionService.perform(action, entry: entry)
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func toggleQuickLook() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        var validEntries: [IndexedEntry] = []
        var unavailableCount = 0
        for entry in entries {
            if coordinator?.isScopeUnavailable(entry.scopeID) == true {
                unavailableCount += 1
            } else if FileManager.default.fileExists(atPath: entry.path) {
                validEntries.append(entry)
            } else {
                coordinator?.removeMissingPath(entry.path)
            }
        }
        guard !validEntries.isEmpty else {
            actionError = unavailableCount > 0
                ? "The indexed volume is not currently available. Cached results were preserved."
                : "The selected paths are no longer available."
            return
        }
        let selectedIndex = validEntries.firstIndex { $0.id == searchViewModel?.primaryEntryID } ?? 0
        quickLook.updateSelection(validEntries.map { URL(fileURLWithPath: $0.path) }, selectedIndex: selectedIndex)
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

    func copyIndexIssuePath(_ path: String) {
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(path, forType: .string) {
            actionError = "The issue path could not be copied."
        }
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
                initialSortIsExplicit: settings.preferredSort != nil,
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
                let scopes = allowedIndexScopes()
                coordinator.start(
                    scopes: scopes,
                    initiallyUnavailableScopeIDs: Set(scopes.filter { $0.volumeType != .internalLocal }.map(\.id))
                )
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

    nonisolated private static func volumeDescriptor(
        for url: URL
    ) -> (path: String, type: IndexedVolumeType, uuid: String?) {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeUUIDStringKey,
            .volumeURLForRemountingKey
        ])
        let type: IndexedVolumeType
        if values?.volumeIsLocal == false {
            type = .network
        } else if values?.volumeIsInternal == false {
            type = .external
        } else {
            type = .internalLocal
        }
        let fallbackIdentity = values?.volumeURLForRemounting.flatMap { remountURL in
            remountURL.isFileURL ? nil : "remount:\(remountURL.absoluteString)"
        }
        return (
            url.path,
            type,
            type == .internalLocal ? nil : (values?.volumeUUIDString ?? fallbackIdentity)
        )
    }
}
