import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public typealias FinderTagPrompt = @MainActor @Sendable (FileEntry) -> [FinderTag]?
public typealias FilePasteboardReader = @MainActor @Sendable () -> [URL]
public typealias FilePasteboardWriter = @MainActor @Sendable ([URL]) -> Void

@MainActor
public final class ExplorerStore: ObservableObject {
    private struct SidebarFavoriteCandidate {
        var url: URL
        var title: String
    }

    @Published public private(set) var panes: [PaneState] {
        didSet {
            syncActiveTabState()
        }
    }
    @Published public var pathInput: String {
        didSet {
            syncActiveTabState()
        }
    }
    @Published public private(set) var visibleError: ExplorerError?
    @Published public private(set) var showHiddenFiles: Bool
    @Published public private(set) var paneMode: ExplorerPaneMode
    @Published public private(set) var defaultSort: EntrySortDescriptor
    @Published public private(set) var calculatedFolderSizes: [URL: Int64]
    @Published public private(set) var searchQuery: String {
        didSet {
            syncActiveTabState()
        }
    }
    @Published public private(set) var searchOptions: ExplorerSearchOptions {
        didSet {
            syncActiveTabState()
        }
    }
    @Published public private(set) var recursiveSearchResults: [FileEntry]?
    @Published public private(set) var isSearching: Bool
    @Published public private(set) var requestedFocus: ExplorerFocusTarget?
    @Published public private(set) var undoStack: [FileUndoAction]
    @Published public var isInspectorVisible: Bool {
        didSet {
            persistSettings()
        }
    }
    @Published public private(set) var activePaneIndex: Int {
        didSet {
            syncActiveTabState()
        }
    }
    @Published public private(set) var tabs: [ExplorerTab]
    @Published public private(set) var activeTabIndex: Int
    @Published public private(set) var mountedVolumes: [MountedVolume]
    @Published public private(set) var volumeError: ExplorerError?
    @Published public private(set) var favoriteSidebarItems: [SidebarFavoriteItem]
    @Published public private(set) var recentFolders: [SidebarRecentFolder]
    @Published public private(set) var activeOperationProgress: FileOperationProgressSnapshot?
    @Published public private(set) var isToolbarTextInputFocused: Bool
    @Published public private(set) var grantedFolderSummaries: [FolderAccessGrantSummary]
    @Published public private(set) var pendingPermissionRecoveryPath: String?
    @Published private var fileClipboard: FileClipboard?
    public let sandboxPolicy: SandboxPolicySummary

    private let fileSystemService: any FileSystemServicing
    private let finderTagService: any FinderTagServicing
    private let finderTagPrompt: FinderTagPrompt
    private let fileOperationService: FileOperationService
    private let archiveBrowser: any ArchiveBrowsing
    private let zipExtractor: any ZipExtracting
    private let zipCompressor: any ZipCompressing
    private let fileSearchService: any FileSearchServicing
    private let volumeService: any VolumeListing
    private let folderSizeService: any FolderSizeCalculating
    private let quickLookService: (any QuickLooking)?
    private let settingsStore: ExplorerSettingsStoring
    private let sidebarFavoritesStore: SidebarFavoritesStoring
    private let pathResolver: PathResolver
    private let pathInputCommandResolver: PathInputCommandResolver
    private let externalAppLauncher: any ExternalAppLaunching
    private let directoryWatcher: DirectoryWatching?
    private let bookmarkStore: any SecurityScopedBookmarkStoring
    private let folderAccessService: any UserSelectedFolderAccessing
    private let filePasteboardReader: FilePasteboardReader
    private let filePasteboardWriter: FilePasteboardWriter
    private let watcherDebounceNanoseconds: UInt64
    private let operationProgressAutoDismissNanoseconds: UInt64
    private var watcherRefreshTask: Task<Void, Never>?
    private var operationProgressAutoDismissTask: Task<Void, Never>?
    private var watchedDirectoryURLs: Set<URL>
    private var isApplyingTabState: Bool
    private var searchTask: Task<Void, Never>?
    private var activeOperationReporter: FileOperationProgressReporter?
    private var activeFolderAccesses: [FolderAccessGrantID: ResolvedFolderAccess]
    private var unavailableFolderGrantIDs: Set<FolderAccessGrantID>
    private var sidebarState: SidebarState
    private static let maxRecentFolders = 5

    public init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystemService: any FileSystemServicing = FileSystemService(),
        fileOperationService: FileOperationService = FileOperationService(),
        archiveBrowser: any ArchiveBrowsing = ArchiveBrowsingService(),
        settingsStore: ExplorerSettingsStoring = UserDefaultsExplorerSettingsStore(),
        sidebarFavoritesStore: SidebarFavoritesStoring = UserDefaultsSidebarFavoritesStore(),
        directoryWatcher: DirectoryWatching? = DirectoryWatcherService(),
        finderTagService: any FinderTagServicing = FinderTagService(),
        finderTagPrompt: FinderTagPrompt? = nil,
        sandboxPolicy: SandboxPolicySummary = .current(),
        bookmarkStore: any SecurityScopedBookmarkStoring = SecurityScopedBookmarkStore(),
        folderAccessService: any UserSelectedFolderAccessing = UserSelectedFolderAccessService(),
        zipExtractor: any ZipExtracting = ZipExtractionService(),
        zipCompressor: any ZipCompressing = ZipCompressionService(),
        fileSearchService: any FileSearchServicing = FileSearchService(),
        volumeService: any VolumeListing = VolumeService(),
        folderSizeService: any FolderSizeCalculating = FolderSizeService(),
        quickLookService: (any QuickLooking)? = QuickLookPreviewService(),
        filePasteboardReader: @escaping FilePasteboardReader = {
            FileDropPasteboardReader.fileURLs(from: .general)
        },
        filePasteboardWriter: @escaping FilePasteboardWriter = { urls in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        },
        watcherDebounceNanoseconds: UInt64 = 250_000_000,
        operationProgressAutoDismissNanoseconds: UInt64 = 1_000_000_000,
        pathResolver: PathResolver = PathResolver(
            aliases: [
                "@home": FileManager.default.homeDirectoryForCurrentUser,
                "@desktop": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
                "@downloads": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            ]
        ),
        pathInputCommandResolver: PathInputCommandResolver? = nil,
        externalAppLauncher: any ExternalAppLaunching = AppKitExternalAppLauncher()
    ) {
        let settings = settingsStore.load()
        let loadedSidebarState = sidebarFavoritesStore.load()
        let sidebarState = Self.normalizedSidebarState(loadedSidebarState)
        let initialLocation = PaneLocation.fileSystem(initialURL.standardizedFileURL)
        var panes = [PaneState(location: initialLocation, sort: settings.defaultSort)]
        if settings.paneMode == .dual {
            panes.append(PaneState(location: initialLocation, sort: settings.defaultSort))
        }
        let initialPathInput = initialURL.path
        let initialActivePaneIndex = 0

        self.panes = panes
        self.pathInput = initialPathInput
        self.visibleError = nil
        self.showHiddenFiles = settings.showHiddenFiles
        self.paneMode = settings.paneMode
        self.defaultSort = settings.defaultSort
        self.calculatedFolderSizes = [:]
        self.searchQuery = ""
        self.searchOptions = ExplorerSearchOptions()
        self.recursiveSearchResults = nil
        self.isSearching = false
        self.requestedFocus = nil
        self.undoStack = []
        self.isInspectorVisible = settings.isInspectorVisible
        self.activePaneIndex = initialActivePaneIndex
        self.tabs = [
            ExplorerTab(
                panes: panes,
                activePaneIndex: initialActivePaneIndex,
                pathInput: initialPathInput
            )
        ]
        self.activeTabIndex = 0
        self.mountedVolumes = []
        self.volumeError = nil
        self.favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites)
        self.recentFolders = sidebarState.recentFolders
        self.activeOperationProgress = nil
        self.isToolbarTextInputFocused = false
        self.grantedFolderSummaries = []
        self.pendingPermissionRecoveryPath = nil
        self.sandboxPolicy = sandboxPolicy
        self.fileSystemService = fileSystemService
        self.finderTagService = finderTagService
        self.finderTagPrompt = finderTagPrompt ?? Self.defaultFinderTagPrompt
        self.fileOperationService = fileOperationService
        self.archiveBrowser = archiveBrowser
        self.zipExtractor = zipExtractor
        self.zipCompressor = zipCompressor
        self.fileSearchService = fileSearchService
        self.volumeService = volumeService
        self.folderSizeService = folderSizeService
        self.quickLookService = quickLookService
        self.filePasteboardReader = filePasteboardReader
        self.filePasteboardWriter = filePasteboardWriter
        self.settingsStore = settingsStore
        self.sidebarFavoritesStore = sidebarFavoritesStore
        self.pathResolver = pathResolver
        self.pathInputCommandResolver = pathInputCommandResolver ?? PathInputCommandResolver(pathResolver: pathResolver)
        self.externalAppLauncher = externalAppLauncher
        self.directoryWatcher = directoryWatcher
        self.bookmarkStore = bookmarkStore
        self.folderAccessService = folderAccessService
        self.watcherDebounceNanoseconds = watcherDebounceNanoseconds
        self.operationProgressAutoDismissNanoseconds = operationProgressAutoDismissNanoseconds
        self.fileClipboard = nil
        self.watcherRefreshTask = nil
        self.operationProgressAutoDismissTask = nil
        self.watchedDirectoryURLs = []
        self.isApplyingTabState = false
        self.searchTask = nil
        self.activeOperationReporter = nil
        self.activeFolderAccesses = [:]
        self.unavailableFolderGrantIDs = []
        self.sidebarState = sidebarState

        loadPersistedFolderGrants()
        if sidebarState != loadedSidebarState {
            persistSidebarState()
        }
    }

    public var activePane: PaneState {
        panes[activePaneIndex]
    }

    public var activeTab: ExplorerTab {
        tabs[activeTabIndex]
    }

    public var activePaneVisibleEntries: [FileEntry] {
        visibleEntries(forPaneAt: activePaneIndex)
    }

    public var activeSelectedEntries: [FileEntry] {
        activePaneVisibleEntries.filter { activePane.selectedURLs.contains($0.url) }
    }

    public func setToolbarTextInputFocused(_ isFocused: Bool) {
        isToolbarTextInputFocused = isFocused
    }

    public func requestToolbarFocusClear() {
        isToolbarTextInputFocused = false
        requestedFocus = .clear
    }

    public func isCommandEnabled(_ command: ExplorerCommand) -> Bool {
        if isToolbarTextInputFocused && command.yieldsToTextEditing {
            return false
        }

        return command.isEnabled(
            selectionCount: activePane.selectedURLs.count,
            canPaste: canPaste,
            canUndo: canUndo,
            canCloseTab: canCloseTab,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            canGoUp: canGoUp,
            selectedEntries: activeSelectedEntries,
            isArchiveLocation: activePane.location.isArchive
        )
    }

    public var canGoBack: Bool {
        !activePane.backStack.isEmpty
    }

    public var canGoForward: Bool {
        !activePane.forwardStack.isEmpty
    }

    public var canGoUp: Bool {
        canGoUp(from: activePane.location)
    }

    public func canGoUp(forPaneAt index: Int) -> Bool {
        guard panes.indices.contains(index) else {
            return false
        }
        return canGoUp(from: panes[index].location)
    }

    public var hasVisibleError: Binding<Bool> {
        Binding(
            get: { self.visibleError != nil },
            set: { newValue in
                if !newValue {
                    self.visibleError = nil
                    self.pendingPermissionRecoveryPath = nil
                }
            }
        )
    }

    public var visibleErrorMessage: String {
        visibleError.map { PermissionGuidance(error: $0, sandbox: sandboxPolicy).message } ?? ""
    }

    public var visibleErrorGuidance: PermissionGuidance? {
        visibleError.map { PermissionGuidance(error: $0, sandbox: sandboxPolicy) }
    }

    public var canPaste: Bool {
        fileClipboard?.isEmpty == false || !filePasteboardReader().isEmpty
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canCloseTab: Bool {
        tabs.count > 1
    }

    public var isShowingRecursiveSearchResults: Bool {
        searchOptions.scope == .recursive
            && hasActiveSearchCriteria
            && activePane.location.fileSystemURL != nil
    }

    public func visibleEntries(forPaneAt index: Int) -> [FileEntry] {
        guard panes.indices.contains(index) else {
            return []
        }

        let entries = panes[index].entries
        guard index == activePaneIndex else {
            return entries
        }

        if isShowingRecursiveSearchResults {
            return recursiveSearchResults ?? []
        }

        return FileEntrySearchFilter.filtered(entries, criteria: activeSearchCriteria)
    }

    public func calculatedFolderSize(for url: URL) -> Int64? {
        calculatedFolderSizes[url.standardizedFileURL]
    }

    public var canAddActiveFolderToFavorites: Bool {
        guard let url = activePane.location.fileSystemURL?.standardizedFileURL else {
            return false
        }

        return canAddFavorite(url: url)
    }

    public var canAddPrimaryFolderToFavorites: Bool {
        guard let candidate = primaryFolderFavoriteCandidate else {
            return false
        }

        return canAddFavorite(url: candidate.url)
    }

    public func loadInitialDirectory() async {
        await refreshMountedVolumes()
        await reloadAllPanes()
    }

    public func refreshMountedVolumes() async {
        do {
            mountedVolumes = MountedVolume.sortedForSidebar(try await volumeService.mountedVolumes())
            volumeError = nil
        } catch let error as ExplorerError {
            mountedVolumes = []
            volumeError = error
        } catch {
            mountedVolumes = []
            volumeError = .readFailed(error.localizedDescription)
        }
    }

    public func addSelectedFolderToFavorites() async {
        guard
            activeSelectedEntries.count == 1,
            let entry = activeSelectedEntries.first,
            !entry.isArchiveBacked,
            entry.isDirectoryLike
        else {
            return
        }

        addFavorite(url: entry.url, title: entry.name)
    }

    public func addActiveFolderToFavorites() {
        guard
            canAddActiveFolderToFavorites,
            let url = activePane.location.fileSystemURL
        else {
            return
        }

        addFavorite(url: url, title: sidebarTitle(for: url))
    }

    public func addPrimaryFolderToFavorites() {
        guard let candidate = primaryFolderFavoriteCandidate, canAddFavorite(url: candidate.url) else {
            return
        }

        addFavorite(url: candidate.url, title: candidate.title)
    }

    public func removeFavorite(id: SidebarFavorite.ID) {
        sidebarState.favorites.removeAll { $0.id == id }
        persistSidebarState()
    }

    public func moveFavorite(fromOffsets source: IndexSet, toOffset destination: Int) {
        sidebarState.favorites.move(fromOffsets: source, toOffset: destination)
        persistSidebarState()
    }

    public func moveFavorite(id: SidebarFavorite.ID, toOffset destination: Int) {
        guard let sourceIndex = sidebarState.favorites.firstIndex(where: { $0.id == id }) else {
            return
        }

        let favorite = sidebarState.favorites.remove(at: sourceIndex)
        var insertionIndex = destination
        if sourceIndex < destination {
            insertionIndex -= 1
        }
        insertionIndex = max(sidebarState.favorites.startIndex, min(insertionIndex, sidebarState.favorites.endIndex))
        sidebarState.favorites.insert(favorite, at: insertionIndex)
        persistSidebarState()
    }

    public func moveFavorite(id: SidebarFavorite.ID, before destinationID: SidebarFavorite.ID) {
        guard let destinationIndex = sidebarState.favorites.firstIndex(where: { $0.id == destinationID }) else {
            return
        }

        moveFavorite(id: id, toOffset: destinationIndex)
    }

    public func moveFavoriteUp(id: SidebarFavorite.ID) {
        guard
            let index = sidebarState.favorites.firstIndex(where: { $0.id == id }),
            index > sidebarState.favorites.startIndex
        else {
            return
        }

        sidebarState.favorites.swapAt(index, index - 1)
        persistSidebarState()
    }

    public func moveFavoriteDown(id: SidebarFavorite.ID) {
        guard
            let index = sidebarState.favorites.firstIndex(where: { $0.id == id }),
            index < sidebarState.favorites.index(before: sidebarState.favorites.endIndex)
        else {
            return
        }

        sidebarState.favorites.swapAt(index, index + 1)
        persistSidebarState()
    }

    public func newTab() async {
        syncActiveTabState()

        let tab = makeTab(startingAt: activePane.location)
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        applyTabState(tab)
        await reloadAllPanes()
    }

    public func closeActiveTab() async {
        await closeTab(at: activeTabIndex)
    }

    public func closeTab(at index: Int) async {
        guard canCloseTab, tabs.indices.contains(index) else {
            return
        }

        syncActiveTabState()
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if index < activeTabIndex {
            activeTabIndex -= 1
        }

        applyTabState(tabs[activeTabIndex])
        await reloadAllPanes()
    }

    public func selectTab(at index: Int) async {
        guard tabs.indices.contains(index), index != activeTabIndex else {
            return
        }

        syncActiveTabState()
        activeTabIndex = index
        applyTabState(tabs[index])
        await reloadAllPanes()
    }

    public func selectNextTab() async {
        guard !tabs.isEmpty else {
            return
        }
        await selectTab(at: (activeTabIndex + 1) % tabs.count)
    }

    public func selectPreviousTab() async {
        guard !tabs.isEmpty else {
            return
        }
        await selectTab(at: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }

    public func resolveAndNavigate(_ rawPath: String) async {
        do {
            let targetURL = try pathResolver.resolve(rawPath, relativeTo: activePane.currentURL)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                await navigate(to: targetURL)
                return
            }

            if let command = pathInputCommandResolver.command(for: rawPath, currentURL: activePane.currentURL) {
                await performPathInputCommand(command)
                return
            }

            await navigate(to: targetURL)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func navigate(to targetURL: URL) async {
        await navigate(to: .fileSystem(targetURL.standardizedFileURL))
    }

    public func navigateFromSidebar(to targetURL: URL) async {
        requestToolbarFocusClear()
        await navigate(to: targetURL)
    }

    public func navigateToMountedVolume(_ volume: MountedVolume) async {
        requestToolbarFocusClear()
        let url = volume.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            mountedVolumes.removeAll { $0.url.standardizedFileURL == url }
            volumeError = .pathDoesNotExist(url.path)
            return
        }
        guard volume.isReadable, FileManager.default.isReadableFile(atPath: url.path) else {
            volumeError = .permissionDenied(url.path)
            return
        }

        await navigate(to: url)
        if activePane.currentURL == url {
            volumeError = nil
        }
    }

    public func navigateToRecentFolder(_ folder: SidebarRecentFolder) async {
        requestToolbarFocusClear()
        let url = folder.url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            visibleError = nil
            removeRecentFolder(url)
            return
        }

        await navigate(to: url)
    }

    private func navigate(to location: PaneLocation) async {
        do {
            try await loadLocation(location, pushHistory: true)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func open(_ url: URL) async {
        guard let entry = activePaneVisibleEntries.first(where: { $0.url == url }) else {
            return
        }

        switch entry.source {
        case .fileSystem:
            if archiveBrowser.canOpen(entry.url) {
                await navigate(to: .archive(ArchiveLocation(archiveURL: entry.url, internalPath: "")))
            } else if entry.isDirectoryLike {
                await navigate(to: .fileSystem(entry.url))
            } else {
                externalAppLauncher.openDefault(entry.url)
            }
        case .archive(let location):
            if entry.isDirectoryLike {
                await navigate(to: .archive(location))
            } else {
                do {
                    externalAppLauncher.openDefault(try await archiveBrowser.temporaryExtract(location))
                } catch {
                    visibleError = .readFailed(error.localizedDescription)
                }
            }
        }
    }

    public func openWithApplications(forPaneAt index: Int) -> [OpenWithApplication] {
        guard panes.indices.contains(index) else {
            return []
        }
        let pane = panes[index]
        guard pane.location.fileSystemURL != nil, let firstURL = pane.selectedURLs.first else {
            return []
        }
        return externalAppLauncher.applications(toOpen: firstURL)
    }

    public func openSelected(with application: OpenWithApplication) async {
        do {
            try await externalAppLauncher.open(selectedURLs, with: application)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    private func performPathInputCommand(_ command: PathInputCommand) async {
        do {
            switch command {
            case .openTerminal(let directory):
                try await externalAppLauncher.openTerminal(at: directory)
            case .openVSCode(let target):
                try await externalAppLauncher.openVSCode(at: target)
            case .openDefault(let target):
                externalAppLauncher.openDefault(target)
            }
            requestToolbarFocusClear()
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func goBack() async {
        guard let target = activePane.backStack.last else {
            return
        }
        var pane = activePane
        pane.backStack.removeLast()
        pane.forwardStack.append(pane.location)
        panes[activePaneIndex] = pane
        try? await loadLocation(target, pushHistory: false)
    }

    public func goForward() async {
        guard let target = activePane.forwardStack.last else {
            return
        }
        var pane = activePane
        pane.forwardStack.removeLast()
        pane.backStack.append(pane.location)
        panes[activePaneIndex] = pane
        try? await loadLocation(target, pushHistory: false)
    }

    public func goUp() async {
        requestToolbarFocusClear()
        guard let parent = parentLocation(from: activePane.location) else {
            let canonicalLocation = canonicalized(activePane.location)
            if canonicalLocation != activePane.location {
                try? await loadLocation(canonicalLocation, pushHistory: false)
            } else {
                pathInput = canonicalLocation.displayPath
            }
            return
        }
        await navigate(to: parent)
    }

    public func refresh() async {
        await loadCurrentDirectory()
    }

    public func updateSelection(_ urls: Set<URL>) {
        isToolbarTextInputFocused = false
        panes[activePaneIndex].selectedURLs = urls
    }

    public func activatePane(at index: Int) {
        guard panes.indices.contains(index) else {
            return
        }

        activePaneIndex = index
        pathInput = activePane.location.displayPath
        trimSelectionToVisibleEntries()
        startWatchingVisibleDirectories()
    }

    public func setSearchQuery(_ query: String) {
        searchQuery = query
        scheduleSearchIfNeeded()
        trimSelectionToVisibleEntries()
    }

    public func clearSearch() {
        setSearchQuery("")
    }

    public func setSearchScope(_ scope: SearchScope) {
        guard searchOptions.scope != scope else {
            return
        }
        var options = searchOptions
        options.scope = scope
        searchOptions = options
        recursiveSearchResults = nil
        scheduleSearchIfNeeded()
        trimSelectionToVisibleEntries()
    }

    public func setSearchKindFilter(_ kind: SearchKindFilter) {
        guard searchOptions.kind != kind else {
            return
        }
        var options = searchOptions
        options.kind = kind
        searchOptions = options
        recursiveSearchResults = nil
        scheduleSearchIfNeeded()
        trimSelectionToVisibleEntries()
    }

    public func setSearchFileExtension(_ fileExtension: String) {
        let fileExtension = ExplorerSearchOptions.normalizedExtension(fileExtension)
        guard searchOptions.fileExtension != fileExtension else {
            return
        }
        var options = searchOptions
        options.fileExtension = fileExtension
        searchOptions = options
        recursiveSearchResults = nil
        scheduleSearchIfNeeded()
        trimSelectionToVisibleEntries()
    }

    public func setSearchFinderTagQuery(_ finderTagQuery: String) {
        let finderTagQuery = ExplorerSearchOptions.normalizedTagQuery(finderTagQuery)
        guard searchOptions.finderTagQuery != finderTagQuery else {
            return
        }
        var options = searchOptions
        options.finderTagQuery = finderTagQuery
        searchOptions = options
        recursiveSearchResults = nil
        populateFinderTagsForActivePaneEntriesIfNeeded()
        scheduleSearchIfNeeded()
        trimSelectionToVisibleEntries()
    }

    public func clearFocusRequest() {
        requestedFocus = nil
    }

    public func setPaneMode(_ mode: ExplorerPaneMode) async {
        switch mode {
        case .single:
            let paneToKeep = activePane
            panes = [paneToKeep]
            activePaneIndex = 0
            paneMode = .single
            pathInput = activePane.location.displayPath
            startWatchingVisibleDirectories()
            persistSettings()
        case .dual:
            paneMode = .dual
            if panes.count > 2 {
                panes = Array(panes.prefix(2))
                activePaneIndex = min(activePaneIndex, panes.count - 1)
            }

            guard panes.count == 1 else {
                pathInput = activePane.location.displayPath
                startWatchingVisibleDirectories()
                persistSettings()
                return
            }

            let newPaneIndex = panes.count
            let newPaneLocation = activePane.location
            panes.append(PaneState(location: newPaneLocation, sort: defaultSort))

            do {
                try await loadLocation(newPaneLocation, pushHistory: false, paneIndex: newPaneIndex)
            } catch let error as ExplorerError {
                present(error)
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
            persistSettings()
        }
    }

    public func setShowHiddenFiles(_ showHiddenFiles: Bool) async {
        guard self.showHiddenFiles != showHiddenFiles else {
            return
        }

        self.showHiddenFiles = showHiddenFiles
        persistSettings()
        await reloadAllPanes()
    }

    public func setDefaultSort(_ descriptor: EntrySortDescriptor) {
        defaultSort = descriptor
        applySort(descriptor, to: &panes)
        for index in tabs.indices {
            if index == activeTabIndex {
                tabs[index].panes = panes
            } else {
                applySort(descriptor, to: &tabs[index].panes)
            }
        }
        persistSettings()
    }

    private func applySort(_ descriptor: EntrySortDescriptor, to panes: inout [PaneState]) {
        for index in panes.indices {
            panes[index].sort = descriptor
            panes[index].entries = SortEngine.sorted(panes[index].entries, descriptor: descriptor)
        }
    }

    public func sortActivePane(by key: SortKey) {
        var descriptor = activePane.sort
        if descriptor.key == key {
            descriptor.direction = descriptor.direction == .ascending ? .descending : .ascending
        } else {
            descriptor.key = key
            descriptor.direction = .ascending
        }

        panes[activePaneIndex].sort = descriptor
        panes[activePaneIndex].entries = SortEngine.sorted(activePane.entries, descriptor: descriptor)
    }

    public func renameSelected(to newName: String) async {
        do {
            guard activePane.selectedURLs.count == 1, let url = selectedURLs.first else {
                return
            }

            let result = try await fileOperationService.rename(url, to: newName)
            await refresh()
            if let renamedURL = result.renamedItem?.destination {
                recordUndo(undoAction(.renamed(FileMoveRecord(source: url, destination: renamedURL)), from: result))
                updateSelection([renamedURL.standardizedFileURL])
            }
        } catch is FileOperationCancellation {
            return
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func perform(_ command: ExplorerCommand) async {
        do {
            switch command {
            case .selectAll:
                selectAllVisibleEntries()
            case .addToFavorites:
                await addSelectedFolderToFavorites()
            case .open:
                if let first = selectedURLs.first {
                    await open(first)
                }
            case .openInTerminal:
                if let first = activeSelectedEntries.first, first.isDirectoryLike {
                    try await externalAppLauncher.openTerminal(at: first.url)
                }
            case .openInVSCode:
                if let first = activeSelectedEntries.first, first.isDirectoryLike {
                    try await externalAppLauncher.openVSCode(at: first.url)
                }
            case .chooseOpenWithApplication:
                await chooseApplicationForSelectedItems()
            case .quickLook:
                try await quickLookSelected()
            case .revealInFinder:
                revealSelectedInFinder()
            case .copyPath:
                copySelectedPaths()
            case .newFolder:
                guard let currentURL = activePane.location.fileSystemURL else {
                    throw ExplorerError.readFailed("Cannot create folders inside ZIP archives.")
                }
                let result = try await fileOperationService.createFolder(in: currentURL)
                if !result.createdURLs.isEmpty {
                    recordUndo(.created(result.createdURLs))
                }
                await refresh()
            case .rename:
                guard let newName = promptForRenameName() else { return }
                await renameSelected(to: newName)
            case .duplicate:
                let urls = selectedURLs
                let reporter = makeOperationReporter(
                    kind: .duplicate,
                    title: operationTitle("Duplicating", count: urls.count)
                )
                var createdURLs: [URL] = []
                var replacedItems: [FileTrashRecord] = []
                for (index, url) in urls.enumerated() {
                    try await reporter.checkCancellation()
                    await reporter.update(
                        phase: .running,
                        currentItemName: url.lastPathComponent,
                        completedUnitCount: index,
                        totalUnitCount: urls.count
                    )
                    let result = try await fileOperationService.duplicate(url)
                    createdURLs.append(contentsOf: result.createdURLs)
                    replacedItems.append(contentsOf: result.replacedItems)
                    await reporter.update(
                        phase: .running,
                        currentItemName: url.lastPathComponent,
                        completedUnitCount: index + 1,
                        totalUnitCount: urls.count
                    )
                }
                if !createdURLs.isEmpty {
                    recordUndo(undoAction(.copied(createdURLs), replacedItems: replacedItems))
                }
                await refresh()
                await reporter.complete()
            case .extractZip:
                try await extractSelectedZips()
            case .compressToZip:
                try await compressSelectedItems()
            case .editTags:
                try await editTagsForSelectedEntry()
            case .copy:
                fileClipboard = FileClipboard(urls: selectedURLs, mode: .copy)
                filePasteboardWriter(selectedURLs)
            case .cut:
                fileClipboard = FileClipboard(urls: selectedURLs, mode: .move)
                filePasteboardWriter(selectedURLs)
            case .paste:
                let clipboard = pasteSourceClipboard()
                guard !clipboard.isEmpty else { return }
                let kind: FileOperationKind = clipboard.mode == .copy ? .copy : .move
                let verb = clipboard.mode == .copy ? "Copying" : "Moving"
                let reporter = makeOperationReporter(
                    kind: kind,
                    title: operationTitle(verb, count: clipboard.urls.count)
                )
                if let pasteResult = try await pasteClipboard(clipboard, progress: reporter) {
                    switch pasteResult.mode {
                    case .copy:
                        if !pasteResult.result.createdURLs.isEmpty {
                            recordUndo(undoAction(.copied(pasteResult.result.createdURLs), from: pasteResult.result))
                        }
                    case .move:
                        if !pasteResult.result.movedItems.isEmpty {
                            recordUndo(undoAction(.moved(pasteResult.result.movedItems), from: pasteResult.result))
                        }
                    }
                }
                await refresh()
                await reporter.complete()
            case .moveToTrash:
                let urls = selectedURLs
                let reporter = makeOperationReporter(
                    kind: .trash,
                    title: operationTitle("Moving to Trash", count: urls.count)
                )
                let result = try await fileOperationService.moveToTrash(urls, progress: reporter)
                if !result.trashedItems.isEmpty {
                    recordUndo(.trashed(result.trashedItems))
                }
                await refresh()
                await reporter.complete()
            case .calculateFolderSize:
                try calculateSelectedFolderSize()
            case .refresh:
                await refresh()
            case .focusSearch:
                requestedFocus = .search
            case .focusPath:
                requestedFocus = .path
            case .clearSearch:
                clearSearch()
            case .toggleHiddenFiles:
                await setShowHiddenFiles(!showHiddenFiles)
            case .toggleInspector:
                isInspectorVisible.toggle()
            case .goBack:
                await goBack()
            case .goForward:
                await goForward()
            case .goUp:
                await goUp()
            case .undo:
                try await undoLatest()
                await refresh()
            case .newTab:
                await newTab()
            case .closeTab:
                await closeActiveTab()
            case .nextTab:
                await selectNextTab()
            case .previousTab:
                await selectPreviousTab()
            }
        } catch is FileOperationCancellation {
            await activeOperationReporter?.cancel()
            return
        } catch is CancellationError {
            await activeOperationReporter?.cancel()
            return
        } catch let error as ExplorerError {
            await failActiveOperation(error)
            present(error)
        } catch {
            await failActiveOperation(error)
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func performDrop(
        urls: [URL],
        destinationFolder: URL,
        operation: DropOperation
    ) async {
        do {
            try FileDropValidator.validate(
                urls: urls,
                destinationFolder: destinationFolder,
                operation: operation
            )

            switch operation {
            case .copy:
                let reporter = makeOperationReporter(kind: .copy, title: operationTitle("Copying", count: urls.count))
                let result = try await fileOperationService.copyItems(urls, to: destinationFolder, progress: reporter)
                if !result.createdURLs.isEmpty {
                    recordUndo(undoAction(.copied(result.createdURLs), from: result))
                }
                await refresh()
                await reporter.complete()
            case .move:
                let reporter = makeOperationReporter(kind: .move, title: operationTitle("Moving", count: urls.count))
                let result = try await fileOperationService.moveItems(urls, to: destinationFolder, progress: reporter)
                if !result.movedItems.isEmpty {
                    recordUndo(undoAction(.moved(result.movedItems), from: result))
                }
                await refresh()
                await reporter.complete()
            }
        } catch is FileOperationCancellation {
            await activeOperationReporter?.cancel()
            return
        } catch is CancellationError {
            await activeOperationReporter?.cancel()
            return
        } catch let error as ExplorerError {
            await failActiveOperation(error)
            present(error)
        } catch {
            await failActiveOperation(error)
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func cancelActiveOperation() {
        guard let activeOperationReporter else {
            return
        }
        Task {
            await activeOperationReporter.cancel()
        }
    }

    public func clearCompletedOperationProgress() {
        clearCompletedOperationProgress(cancelScheduledDismiss: true)
    }

    private func clearCompletedOperationProgress(cancelScheduledDismiss: Bool) {
        guard let phase = activeOperationProgress?.phase,
              phase == .completed || phase == .failed || phase == .cancelled else {
            return
        }
        if cancelScheduledDismiss {
            operationProgressAutoDismissTask?.cancel()
            operationProgressAutoDismissTask = nil
        }
        activeOperationProgress = nil
        activeOperationReporter = nil
    }

    public func clearError() {
        visibleError = nil
        pendingPermissionRecoveryPath = nil
    }

    public func chooseFolderForAccess() async {
        await chooseFolderForAccess(
            startingAt: permissionRecoveryStartURL(),
            retryingPermissionPath: pendingPermissionRecoveryPath
        )
    }

    public func chooseFolderForAccess(startingAt startURL: URL?) async {
        await chooseFolderForAccess(
            startingAt: startURL,
            retryingPermissionPath: pendingPermissionRecoveryPath
        )
    }

    public func chooseFolderForAccess(startingAt startURL: URL?, retryingPermissionPath: String?) async {
        do {
            let result = try await folderAccessService.chooseFolder(
                startingAt: startURL,
                sandboxed: sandboxPolicy.isSandboxed
            )
            guard case .granted(let grant, let access) = result else {
                return
            }

            stopSupersededFolderAccesses(for: grant)
            try bookmarkStore.save(grant)
            activeFolderAccesses[grant.id] = access
            unavailableFolderGrantIDs.remove(grant.id)
            refreshGrantedFolderSummaries()
            await retryPermissionRecoveryIfSafe(path: retryingPermissionPath)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func removeGrantedFolder(id: FolderAccessGrantID) async {
        if let access = activeFolderAccesses.removeValue(forKey: id) {
            folderAccessService.stopAccessing(access)
        }
        bookmarkStore.remove(id: id)
        refreshGrantedFolderSummaries()
        await refreshVisiblePanesAfterAccessChange()
    }

    public func resetGrantedFolders() async {
        activeFolderAccesses.values.forEach(folderAccessService.stopAccessing)
        activeFolderAccesses.removeAll()
        bookmarkStore.reset()
        refreshGrantedFolderSummaries()
        await refreshVisiblePanesAfterAccessChange()
    }

    private var selectedURLs: [URL] {
        activePane.selectedURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func selectAllVisibleEntries() {
        updateSelection(Set(activePaneVisibleEntries.map(\.url)))
    }

    private func present(_ error: ExplorerError) {
        visibleError = error
        if case .permissionDenied(let path) = error {
            pendingPermissionRecoveryPath = URL(fileURLWithPath: path).standardizedFileURL.path
        }
    }

    private func refreshGrantedFolderSummaries() {
        grantedFolderSummaries = bookmarkStore.load().map { grant in
            if let access = activeFolderAccesses[grant.id] {
                return FolderAccessGrantSummary(
                    grant: grant,
                    availability: .available,
                    isStale: access.isStale
                )
            }
            if unavailableFolderGrantIDs.contains(grant.id) {
                return FolderAccessGrantSummary(
                    grant: grant,
                    availability: .unavailable
                )
            }
            return FolderAccessGrantSummary(grant: grant)
        }
    }

    private func loadPersistedFolderGrants() {
        let grants = bookmarkStore.load()
        guard sandboxPolicy.isSandboxed else {
            grantedFolderSummaries = grants.map { FolderAccessGrantSummary(grant: $0) }
            return
        }

        grantedFolderSummaries = grants.map { grant in
            do {
                let access = try folderAccessService.resolve(grant)
                activeFolderAccesses[grant.id] = access
                unavailableFolderGrantIDs.remove(grant.id)

                var resolvedGrant = grant
                resolvedGrant.url = access.url
                resolvedGrant.lastResolvedAt = Date()
                try? bookmarkStore.save(resolvedGrant)

                return FolderAccessGrantSummary(
                    grant: resolvedGrant,
                    availability: .available,
                    isStale: access.isStale
                )
            } catch {
                unavailableFolderGrantIDs.insert(grant.id)
                return FolderAccessGrantSummary(
                    grant: grant,
                    availability: .unavailable
                )
            }
        }
    }

    private func stopSupersededFolderAccesses(for grant: FolderAccessGrant) {
        let standardizedURL = grant.url.standardizedFileURL
        let supersededIDs = Set(
            bookmarkStore.load()
                .filter { existing in
                    existing.id == grant.id || existing.url.standardizedFileURL == standardizedURL
                }
                .map(\.id)
        )
        let activeIDs = activeFolderAccesses.compactMap { id, access -> FolderAccessGrantID? in
            if id == grant.id || supersededIDs.contains(id) || access.url.standardizedFileURL == standardizedURL {
                return id
            }
            return nil
        }

        for id in activeIDs {
            if let access = activeFolderAccesses.removeValue(forKey: id) {
                folderAccessService.stopAccessing(access)
            }
            unavailableFolderGrantIDs.remove(id)
        }
    }

    private func addFavorite(url: URL, title: String) {
        let standardizedURL = url.standardizedFileURL
        guard canAddFavorite(url: standardizedURL) else {
            return
        }

        sidebarState.favorites.append(
            SidebarFavorite(
                title: title.isEmpty ? sidebarTitle(for: standardizedURL) : title,
                url: standardizedURL
            )
        )
        persistSidebarState()
    }

    private var primaryFolderFavoriteCandidate: SidebarFavoriteCandidate? {
        if
            activeSelectedEntries.count == 1,
            let entry = activeSelectedEntries.first,
            !entry.isArchiveBacked,
            entry.isDirectoryLike
        {
            return SidebarFavoriteCandidate(url: entry.url.standardizedFileURL, title: entry.name)
        }

        guard let url = activePane.location.fileSystemURL?.standardizedFileURL else {
            return nil
        }

        return SidebarFavoriteCandidate(url: url, title: sidebarTitle(for: url))
    }

    private func canAddFavorite(url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return !sidebarState.favorites.contains { $0.url == standardizedURL }
    }

    private func recordRecentFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        sidebarState.recentFolders.removeAll { $0.url == standardizedURL }
        sidebarState.recentFolders.insert(SidebarRecentFolder(url: standardizedURL), at: 0)
        if sidebarState.recentFolders.count > Self.maxRecentFolders {
            sidebarState.recentFolders = Array(sidebarState.recentFolders.prefix(Self.maxRecentFolders))
        }
        persistSidebarState()
    }

    private func removeRecentFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let previousCount = sidebarState.recentFolders.count
        sidebarState.recentFolders.removeAll { $0.url == standardizedURL }
        guard sidebarState.recentFolders.count != previousCount else {
            return
        }

        persistSidebarState()
    }

    private func persistSidebarState() {
        favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites)
        recentFolders = sidebarState.recentFolders
        sidebarFavoritesStore.save(sidebarState)
    }

    private static func normalizedSidebarState(_ state: SidebarState) -> SidebarState {
        var normalized = state

        var seenFavoriteURLs: Set<URL> = []
        normalized.favorites = normalized.favorites.compactMap { favorite in
            var favorite = favorite
            favorite.url = favorite.url.standardizedFileURL
            guard seenFavoriteURLs.insert(favorite.url).inserted else {
                return nil
            }
            return favorite
        }

        var seenRecentURLs: Set<URL> = []
        normalized.recentFolders = normalized.recentFolders.compactMap { folder in
            let standardizedURL = folder.url.standardizedFileURL
            guard seenRecentURLs.insert(standardizedURL).inserted else {
                return nil
            }
            return SidebarRecentFolder(url: standardizedURL, title: folder.title)
        }

        if normalized.recentFolders.count > maxRecentFolders {
            normalized.recentFolders = Array(normalized.recentFolders.prefix(maxRecentFolders))
        }
        return normalized
    }

    private func sidebarTitle(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private static func favoriteItems(from favorites: [SidebarFavorite]) -> [SidebarFavoriteItem] {
        favorites.map { favorite in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: favorite.url.path, isDirectory: &isDirectory)
            return SidebarFavoriteItem(favorite: favorite, isMissing: !exists || !isDirectory.boolValue)
        }
    }

    private func permissionRecoveryStartURL() -> URL? {
        if let pendingPermissionRecoveryPath {
            return URL(fileURLWithPath: pendingPermissionRecoveryPath, isDirectory: true)
                .standardizedFileURL
        }
        return activePane.location.fileSystemURL?.standardizedFileURL
    }

    private func retryPermissionRecoveryIfSafe(path: String?) async {
        guard let path else {
            await refreshVisiblePanesAfterAccessChange()
            return
        }

        let targetURL = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
        do {
            try await loadLocation(.fileSystem(targetURL), pushHistory: true)
            clearError()
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    private func refreshVisiblePanesAfterAccessChange() async {
        await reloadAllPanes()
    }

    private func persistSettings() {
        settingsStore.save(
            ExplorerSettings(
                paneMode: paneMode,
                isInspectorVisible: isInspectorVisible,
                showHiddenFiles: showHiddenFiles,
                defaultSort: defaultSort
            )
        )
    }

    private func canGoUp(from location: PaneLocation) -> Bool {
        parentLocation(from: location) != nil
    }

    private func parentLocation(from location: PaneLocation) -> PaneLocation? {
        switch canonicalized(location) {
        case .fileSystem(let url):
            let parent = url.deletingLastPathComponent().standardizedFileURL
            guard parent.path != url.path else {
                return nil
            }
            return .fileSystem(parent)
        case .archive(let location):
            if location.internalPath.isEmpty {
                return .fileSystem(location.archiveURL.deletingLastPathComponent().standardizedFileURL)
            }
            return .archive(location.parent)
        }
    }

    private func canonicalized(_ location: PaneLocation) -> PaneLocation {
        switch location {
        case .fileSystem(let url):
            return .fileSystem(url.standardizedFileURL)
        case .archive(let location):
            return .archive(ArchiveLocation(archiveURL: location.archiveURL, internalPath: location.internalPath))
        }
    }

    private func makeTab(startingAt location: PaneLocation) -> ExplorerTab {
        var tabPanes = [PaneState(location: location, sort: defaultSort)]
        if paneMode == .dual {
            tabPanes.append(PaneState(location: location, sort: defaultSort))
        }
        return ExplorerTab(
            panes: tabPanes,
            activePaneIndex: 0,
            pathInput: location.displayPath
        )
    }

    private func syncActiveTabState() {
        guard !isApplyingTabState, tabs.indices.contains(activeTabIndex) else {
            return
        }

        var tab = tabs[activeTabIndex]
        tab.panes = panes
        tab.activePaneIndex = activePaneIndex
        tab.pathInput = pathInput
        tab.searchQuery = searchQuery
        tab.searchOptions = searchOptions
        tabs[activeTabIndex] = tab
    }

    private func applyTabState(_ tab: ExplorerTab) {
        let tab = normalizedTabForCurrentPaneMode(tab)
        isApplyingTabState = true
        panes = tab.panes
        activePaneIndex = tab.activePaneIndex
        pathInput = tab.pathInput
        searchQuery = tab.searchQuery
        searchOptions = tab.searchOptions
        recursiveSearchResults = nil
        isApplyingTabState = false
        syncActiveTabState()
        startWatchingVisibleDirectories()
    }

    private func normalizedTabForCurrentPaneMode(_ tab: ExplorerTab) -> ExplorerTab {
        var tab = tab
        if tab.panes.isEmpty {
            tab.panes = [PaneState(location: .fileSystem(FileManager.default.homeDirectoryForCurrentUser), sort: defaultSort)]
            tab.activePaneIndex = 0
        }

        tab.activePaneIndex = min(max(tab.activePaneIndex, 0), tab.panes.count - 1)

        switch paneMode {
        case .single:
            let paneToKeep = tab.panes[tab.activePaneIndex]
            tab.panes = [paneToKeep]
            tab.activePaneIndex = 0
        case .dual:
            if tab.panes.count > 2 {
                tab.panes = Array(tab.panes.prefix(2))
                tab.activePaneIndex = min(tab.activePaneIndex, tab.panes.count - 1)
            }
            if tab.panes.count == 1 {
                tab.panes.append(PaneState(location: tab.panes[0].location, sort: defaultSort))
            }
        }

        if !tab.panes.indices.contains(tab.activePaneIndex) {
            tab.activePaneIndex = 0
        }
        tab.pathInput = tab.panes[tab.activePaneIndex].location.displayPath
        return tab
    }

    private var activeSearchCriteria: FileEntrySearchCriteria {
        FileEntrySearchCriteria(
            query: searchQuery,
            kind: searchOptions.kind,
            fileExtension: searchOptions.fileExtension,
            tagQuery: searchOptions.finderTagQuery
        )
    }

    private var hasActiveSearchCriteria: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || searchOptions.kind != .any
            || !searchOptions.fileExtension.isEmpty
            || !searchOptions.finderTagQuery.isEmpty
    }

    private func scheduleSearchIfNeeded() {
        searchTask?.cancel()
        searchTask = nil

        guard isShowingRecursiveSearchResults, let rootURL = activePane.location.fileSystemURL else {
            recursiveSearchResults = nil
            isSearching = false
            return
        }

        let service = fileSearchService
        let criteria = activeSearchCriteria
        let options = DirectoryReadOptions(
            showHiddenFiles: showHiddenFiles,
            includeFinderTags: !criteria.finderTagQuery.isEmpty
        )
        let sort = activePane.sort
        isSearching = true

        searchTask = Task { [weak self] in
            do {
                let results = try await service.search(in: rootURL, criteria: criteria, options: options)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self, self.searchQuery == criteria.query, self.searchOptions.scope == .recursive else {
                        return
                    }
                    self.recursiveSearchResults = SortEngine.sorted(results, descriptor: sort)
                    self.isSearching = false
                    self.trimSelectionToVisibleEntries()
                }
            } catch is CancellationError {
                return
            } catch let error as ExplorerError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.recursiveSearchResults = []
                    self.isSearching = false
                    self.present(error)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.recursiveSearchResults = []
                    self.isSearching = false
                    self.visibleError = .readFailed(error.localizedDescription)
                }
            }
        }
    }

    private func pasteSourceClipboard() -> FileClipboard {
        if let fileClipboard, !fileClipboard.isEmpty {
            return fileClipboard
        }
        return FileClipboard(urls: filePasteboardReader(), mode: .copy)
    }

    private func pasteClipboard(
        _ clipboard: FileClipboard,
        progress: FileOperationProgressReporter? = nil
    ) async throws -> (mode: FileClipboardMode, result: FileOperationResult)? {
        guard !clipboard.isEmpty else { return nil }
        guard let currentURL = activePane.location.fileSystemURL else {
            throw ExplorerError.readFailed("Cannot paste into ZIP archives.")
        }
        switch clipboard.mode {
        case .copy:
            return (
                clipboard.mode,
                try await fileOperationService.copyItems(clipboard.urls, to: currentURL, progress: progress)
            )
        case .move:
            let result = try await fileOperationService.moveItems(clipboard.urls, to: currentURL, progress: progress)
            self.fileClipboard = nil
            return (clipboard.mode, result)
        }
    }

    private func recordUndo(_ action: FileUndoAction?) {
        guard let action else {
            return
        }
        undoStack.append(action)
    }

    private func undoAction(_ action: FileUndoAction, from result: FileOperationResult) -> FileUndoAction {
        undoAction(action, replacedItems: result.replacedItems)
    }

    private func undoAction(_ action: FileUndoAction, replacedItems: [FileTrashRecord]) -> FileUndoAction {
        guard !replacedItems.isEmpty else {
            return action
        }
        return .compound(
            title: action.title,
            actions: [
                action,
                .restoreReplacements(replacedItems)
            ]
        )
    }

    private func undoLatest() async throws {
        guard let action = undoStack.popLast() else {
            return
        }

        do {
            try await undo(action)
        } catch {
            undoStack.append(action)
            throw error
        }
    }

    private func undo(_ action: FileUndoAction) async throws {
        switch action {
        case .created(let urls), .copied(let urls), .extracted(let urls), .compressed(let urls):
            _ = try await fileOperationService.moveToTrash(urls)
        case .moved(let records):
            for record in records.reversed() {
                try restoreItem(from: record.destination, to: record.source)
            }
        case .renamed(let record):
            try restoreItem(from: record.destination, to: record.source)
        case .trashed(let records), .restoreReplacements(let records):
            for record in records {
                try restoreItem(from: record.trashed, to: record.original)
            }
        case .compound(_, let actions):
            for action in actions {
                try await undo(action)
            }
        }
    }

    private func restoreItem(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ExplorerError.readFailed("Cannot undo because the item is missing: \(source.path)")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ExplorerError.readFailed("Cannot undo because the destination already exists: \(destination.path)")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func calculateSelectedFolderSize() throws {
        guard
            activePane.selectedURLs.count == 1,
            let url = selectedURLs.first,
            activePaneVisibleEntries.first(where: { $0.url == url })?.isDirectoryLike == true
        else {
            return
        }

        let size = try folderSizeService.size(of: url)
        calculatedFolderSizes[url.standardizedFileURL] = size
    }

    private func extractSelectedZips() async throws {
        guard let currentURL = activePane.location.fileSystemURL?.standardizedFileURL else {
            throw ExplorerError.readFailed("Cannot extract ZIP files inside ZIP archives.")
        }

        let zipURLs = activeSelectedEntries
            .filter { entry in
                !entry.isArchiveBacked && entry.fileExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
            }
            .map { $0.url.standardizedFileURL }

        guard !zipURLs.isEmpty else {
            return
        }

        let reporter = makeOperationReporter(kind: .extractZip, title: operationTitle("Extracting", count: zipURLs.count))
        let result = try await zipExtractor.extract(zipURLs, to: currentURL, progress: reporter)
        if !result.createdURLs.isEmpty {
            recordUndo(undoAction(.extracted(result.createdURLs), from: result))
        }
        await refresh()
        await reporter.complete()
    }

    private func compressSelectedItems() async throws {
        guard let currentURL = activePane.location.fileSystemURL?.standardizedFileURL else {
            throw ExplorerError.readFailed("Cannot create ZIP files inside ZIP archives.")
        }

        let sourceURLs = activeSelectedEntries
            .filter { !$0.isArchiveBacked }
            .map { $0.url.standardizedFileURL }

        guard !sourceURLs.isEmpty else {
            return
        }

        let reporter = makeOperationReporter(kind: .compressZip, title: operationTitle("Compressing", count: sourceURLs.count))
        let result = try await zipCompressor.compress(sourceURLs, to: currentURL, progress: reporter)
        if !result.createdURLs.isEmpty {
            recordUndo(undoAction(.compressed(result.createdURLs), from: result))
        }
        await refresh()
        if !result.createdURLs.isEmpty {
            updateSelection(Set(result.createdURLs.map(\.standardizedFileURL)))
        }
        await reporter.complete()
    }

    private func makeOperationReporter(
        kind: FileOperationKind,
        title: String
    ) -> FileOperationProgressReporter {
        let snapshot = FileOperationProgressSnapshot(kind: kind, title: title)
        operationProgressAutoDismissTask?.cancel()
        operationProgressAutoDismissTask = nil
        activeOperationProgress = snapshot
        let reporter = FileOperationProgressReporter(initialSnapshot: snapshot) { [weak self] snapshot in
            await MainActor.run {
                self?.handleOperationProgressUpdate(snapshot)
            }
        }
        activeOperationReporter = reporter
        return reporter
    }

    private func handleOperationProgressUpdate(_ snapshot: FileOperationProgressSnapshot) {
        activeOperationProgress = snapshot
        if snapshot.phase == .completed {
            scheduleOperationProgressAutoDismiss(for: snapshot.id)
        } else {
            operationProgressAutoDismissTask?.cancel()
            operationProgressAutoDismissTask = nil
        }
    }

    private func scheduleOperationProgressAutoDismiss(for id: FileOperationID) {
        operationProgressAutoDismissTask?.cancel()
        let delay = operationProgressAutoDismissNanoseconds
        operationProgressAutoDismissTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await MainActor.run {
                guard self.activeOperationProgress?.isAutoDismissibleCompletion(for: id) == true else {
                    return
                }
                self.clearCompletedOperationProgress(cancelScheduledDismiss: false)
                self.operationProgressAutoDismissTask = nil
            }
        }
    }

    private func operationTitle(_ verb: String, count: Int) -> String {
        "\(verb) \(count) \(count == 1 ? "item" : "items")"
    }

    private func failActiveOperation(_ error: Error) async {
        guard let phase = activeOperationProgress?.phase,
              phase == .preparing
                || phase == .resolvingConflict
                || phase == .running
                || phase == .writingArchive
                || phase == .finishing else {
            return
        }
        await activeOperationReporter?.fail(error.localizedDescription)
    }

    private func copySelectedPaths() {
        let paths = activeSelectedEntries.map { entry in
            switch entry.source {
            case .fileSystem:
                return entry.url.path
            case .archive(let location):
                return location.displayPath
            }
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    private func populateFinderTagsForActivePaneEntriesIfNeeded() {
        guard !searchOptions.finderTagQuery.isEmpty, panes.indices.contains(activePaneIndex) else {
            return
        }

        panes[activePaneIndex].entries = panes[activePaneIndex].entries.map { entry in
            guard !entry.isArchiveBacked else {
                return entry
            }
            let tags = (try? finderTagService.tags(for: entry.url)) ?? entry.finderTags
            return entry.replacingFinderTags(tags)
        }
    }

    private func revealSelectedInFinder() {
        guard let first = activeSelectedEntries.first else { return }
        switch first.source {
        case .fileSystem:
            NSWorkspace.shared.activateFileViewerSelecting([first.url])
        case .archive(let location):
        NSWorkspace.shared.activateFileViewerSelecting([location.archiveURL])
        }
    }

    private func editTagsForSelectedEntry() async throws {
        guard
            activeSelectedEntries.count == 1,
            let entry = activeSelectedEntries.first,
            !entry.isArchiveBacked
        else {
            return
        }

        let currentTags = (try? finderTagService.tags(for: entry.url)) ?? entry.finderTags
        guard let tags = finderTagPrompt(entry.replacingFinderTags(currentTags)) else {
            return
        }

        try finderTagService.setTags(tags, for: entry.url)
        await refresh()
        updateFinderTags(tags, for: entry.url)
        updateSelection([entry.url.standardizedFileURL])
        trimSelectionToVisibleEntries()
    }

    private func updateFinderTags(_ tags: [FinderTag], for url: URL) {
        let standardizedURL = url.standardizedFileURL
        for index in panes.indices {
            panes[index].entries = panes[index].entries.map { entry in
                entry.url.standardizedFileURL == standardizedURL ? entry.replacingFinderTags(tags) : entry
            }
        }
    }

    private func promptForRenameName() -> String? {
        guard activePane.selectedURLs.count == 1, let url = selectedURLs.first else {
            return nil
        }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for \(url.lastPathComponent)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: url.lastPathComponent)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }
        return textField.stringValue
    }

    private func chooseApplicationForSelectedItems() async {
        guard !selectedURLs.isEmpty else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open With"
        panel.prompt = "Open"
        panel.message = "Choose an application to open the selected item."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return
        }

        await openSelected(
            with: OpenWithApplication(
                url: applicationURL,
                title: Self.applicationTitle(for: applicationURL),
                bundleIdentifier: Bundle(url: applicationURL)?.bundleIdentifier
            )
        )
    }

    private static func applicationTitle(for url: URL) -> String {
        let bundle = Bundle(url: url)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    private static func defaultFinderTagPrompt(for entry: FileEntry) -> [FinderTag]? {
        let alert = NSAlert()
        alert.messageText = "Edit Tags"
        alert.informativeText = "Enter tags for \(entry.name), separated by commas."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: entry.finderTags.map(\.name).joined(separator: ", "))
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return FinderTag.normalized(textField.stringValue.split(separator: ",").map(String.init))
    }

    private func startWatchingVisibleDirectories() {
        let visibleDirectoryURLs = Set(panes.compactMap { watchedDirectoryURL(for: $0.location) })
        guard !visibleDirectoryURLs.isEmpty else {
            directoryWatcher?.stopWatching()
            watchedDirectoryURLs = []
            return
        }
        guard watchedDirectoryURLs != visibleDirectoryURLs else {
            return
        }

        watchedDirectoryURLs = visibleDirectoryURLs
        directoryWatcher?.startWatching(
            visibleDirectoryURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalRefresh()
            }
        }
    }

    private func watchedDirectoryURL(for location: PaneLocation) -> URL? {
        switch location {
        case .fileSystem(let url):
            return url.standardizedFileURL
        case .archive(let archiveLocation):
            return archiveLocation.archiveURL.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func scheduleExternalRefresh() {
        watcherRefreshTask?.cancel()
        watcherRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if watcherDebounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: watcherDebounceNanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }
            await self.reloadWatchedPanes()
        }
    }

    private func loadCurrentDirectory() async {
        do {
            try await loadLocation(activePane.location, pushHistory: false, paneIndex: activePaneIndex)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    private func reloadAllPanes() async {
        for index in panes.indices {
            do {
                try await loadLocation(panes[index].location, pushHistory: false, paneIndex: index)
            } catch let error as ExplorerError {
                present(error)
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
        }
    }

    private func reloadWatchedPanes() async {
        let targets = panes.indices.compactMap { index -> (Int, PaneLocation)? in
            guard let url = watchedDirectoryURL(for: panes[index].location),
                  watchedDirectoryURLs.contains(url) else {
                return nil
            }
            return (index, panes[index].location)
        }

        for (index, location) in targets where panes.indices.contains(index) {
            do {
                try await loadLocation(location, pushHistory: false, paneIndex: index)
            } catch let error as ExplorerError {
                present(error)
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
        }
    }

    private func loadLocation(_ requestedLocation: PaneLocation, pushHistory: Bool, paneIndex: Int? = nil) async throws {
        let location = canonicalized(requestedLocation)
        let targetPaneIndex = paneIndex ?? activePaneIndex
        guard panes.indices.contains(targetPaneIndex) else {
            return
        }

        panes[targetPaneIndex].isLoading = true
        defer {
            if panes.indices.contains(targetPaneIndex) {
                panes[targetPaneIndex].isLoading = false
            }
        }

        let entries: [FileEntry]
        switch location {
        case .fileSystem(let url):
            entries = try await fileSystemService.contentsOfDirectory(
                at: url,
                options: DirectoryReadOptions(
                    showHiddenFiles: showHiddenFiles,
                    includeFinderTags: targetPaneIndex == activePaneIndex && !searchOptions.finderTagQuery.isEmpty
                )
            )
        case .archive(let archiveLocation):
            entries = try await archiveBrowser
                .list(archiveLocation, showHiddenFiles: showHiddenFiles)
                .map(makeFileEntry)
        }

        var pane = panes[targetPaneIndex]
        let didChangeLocation = pane.location != location
        if pushHistory && didChangeLocation {
            pane.backStack.append(pane.location)
            pane.forwardStack.removeAll()
        }
        pane.location = location
        pane.entries = SortEngine.sorted(entries, descriptor: pane.sort)
        pane.selectedURLs = pane.selectedURLs.intersection(visibleURLs(for: pane.entries, paneIndex: targetPaneIndex))
        pane.error = nil
        panes[targetPaneIndex] = pane

        if targetPaneIndex == activePaneIndex {
            pathInput = location.displayPath
            if didChangeLocation {
                clearSearch()
            } else {
                recursiveSearchResults = nil
                scheduleSearchIfNeeded()
            }
            startWatchingVisibleDirectories()
            if case .fileSystem(let url) = location {
                recordRecentFolder(url)
            }
        }
    }

    private func makeFileEntry(from archiveEntry: ArchiveEntry) -> FileEntry {
        FileEntry(
            url: archiveEntry.location.virtualURL,
            name: archiveEntry.name,
            kind: archiveEntry.isDirectory ? .zipVirtualFolder : .zipVirtualFile,
            typeDescription: archiveEntry.isDirectory ? "ZIP Folder" : "ZIP Item",
            fileExtension: archiveEntry.isDirectory ? "" : URL(fileURLWithPath: archiveEntry.name).pathExtension.lowercased(),
            size: archiveEntry.isDirectory ? nil : archiveEntry.size,
            dateModified: archiveEntry.modifiedAt,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: archiveEntry.name.hasPrefix("."),
            isDirectoryLike: archiveEntry.isDirectory,
            isReadable: true,
            source: .archive(archiveEntry.location)
        )
    }

    private func trimSelectionToVisibleEntries() {
        guard panes.indices.contains(activePaneIndex) else {
            return
        }
        panes[activePaneIndex].selectedURLs = panes[activePaneIndex].selectedURLs
            .intersection(visibleURLs(for: panes[activePaneIndex].entries, paneIndex: activePaneIndex))
    }

    private func visibleURLs(for entries: [FileEntry], paneIndex: Int) -> Set<URL> {
        let visibleEntries: [FileEntry]
        if paneIndex == activePaneIndex, isShowingRecursiveSearchResults {
            visibleEntries = recursiveSearchResults ?? []
        } else if paneIndex == activePaneIndex {
            visibleEntries = FileEntrySearchFilter.filtered(entries, criteria: activeSearchCriteria)
        } else {
            visibleEntries = entries
        }
        return Set(visibleEntries.map(\.url))
    }

    private func quickLookSelected() async throws {
        let urls = try await selectedPreviewURLs()
        try quickLookService?.preview(urls)
    }

    private func selectedPreviewURLs() async throws -> [URL] {
        var urls: [URL] = []
        urls.reserveCapacity(activeSelectedEntries.count)
        for entry in activeSelectedEntries {
            switch entry.source {
            case .fileSystem:
                urls.append(entry.url)
            case .archive(let location):
                urls.append(try await archiveBrowser.temporaryExtract(location))
            }
        }
        return urls
    }

#if DEBUG
    public func waitForSearchForTesting() async {
        await searchTask?.value
    }

    public func replaceActivePaneForTesting(
        location: PaneLocation,
        entries: [FileEntry],
        selectedURLs: Set<URL>
    ) {
        panes[activePaneIndex].location = location
        panes[activePaneIndex].entries = entries
        panes[activePaneIndex].selectedURLs = selectedURLs
        pathInput = location.displayPath
    }
#endif
}
