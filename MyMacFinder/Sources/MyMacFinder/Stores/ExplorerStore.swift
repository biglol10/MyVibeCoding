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

    private struct SearchContext: Sendable {
        var generation: UInt64
        var tabID: ExplorerTabID
        var paneID: PaneID
        var rootURL: URL
        var scope: SearchScope
        var criteria: FileEntrySearchCriteria
        var showHiddenFiles: Bool
    }

    private struct FinderTagPopulationContext: Sendable {
        var tabID: ExplorerTabID
        var paneID: PaneID
        var rootURL: URL
        var scope: SearchScope
        var ordinaryQuery: String
        var explicitTagQuery: String
    }

    private struct OwnedUndoSource: Sendable {
        var url: URL
        var expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity?
    }

    private struct UndoOwnershipSnapshot: Sendable {
        var identities: [String: FileSystemPathIdentity.FileSystemEntryIdentity]
    }

    private enum UndoStep: Sendable {
        case trash([OwnedUndoSource])
        case move(source: OwnedUndoSource, destination: URL)
    }

    private enum UndoJournalEntry: Sendable {
        case trashed(FileTrashRecord, expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity)
        case moved(
            source: URL,
            destination: URL,
            expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
        )
    }

    private enum SimulatedUndoEntry {
        case missing
        case present(FileSystemPathIdentity.FileSystemEntryIdentity)
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
    @Published public private(set) var previewMode: FilePreviewMode
    @Published public private(set) var previewByteLimit: FilePreviewByteLimit
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
    @Published public private(set) var inlineRenameRequest: InlineRenameRequest?
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
    @Published public private(set) var folderAccessPersistenceErrorMessage: String?
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
    private let pathStatusChecker: any PathStatusChecking
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
    private var searchGeneration: UInt64
    private var paneLoadGenerations: [PaneID: UInt64]
    private var finderTagPopulationTask: Task<Void, Never>?
    private var finderTagPopulationToken: UUID
    private var activeOperationReporter: FileOperationProgressReporter?
    private var activeFolderAccesses: [FolderAccessGrantID: ResolvedFolderAccess]
    private var unavailableFolderGrantIDs: Set<FolderAccessGrantID>
    private var undoOwnershipStack: [UndoOwnershipSnapshot]
    private var sidebarState: SidebarState
    private var missingFavoriteURLs: Set<URL>
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
        pathStatusChecker: any PathStatusChecking = FileManagerPathStatusChecker(),
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
        self.previewMode = settings.previewMode
        self.previewByteLimit = settings.previewByteLimit
        self.calculatedFolderSizes = [:]
        self.searchQuery = ""
        self.searchOptions = ExplorerSearchOptions()
        self.recursiveSearchResults = nil
        self.isSearching = false
        self.requestedFocus = nil
        self.inlineRenameRequest = nil
        self.undoStack = []
        self.undoOwnershipStack = []
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
        self.favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites, missingURLs: [])
        self.recentFolders = sidebarState.recentFolders
        self.activeOperationProgress = nil
        self.isToolbarTextInputFocused = false
        self.grantedFolderSummaries = []
        self.folderAccessPersistenceErrorMessage = nil
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
        self.pathStatusChecker = pathStatusChecker
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
        self.searchGeneration = 0
        self.paneLoadGenerations = [:]
        self.finderTagPopulationTask = nil
        self.finderTagPopulationToken = UUID()
        self.activeOperationReporter = nil
        self.activeFolderAccesses = [:]
        self.unavailableFolderGrantIDs = []
        self.sidebarState = sidebarState
        self.missingFavoriteURLs = []

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

    public func setPreviewByteLimit(_ limit: FilePreviewByteLimit) {
        guard previewByteLimit != limit else {
            return
        }
        previewByteLimit = limit
        persistSettings()
    }

    public func setPreviewMode(_ mode: FilePreviewMode) {
        guard previewMode != mode else {
            return
        }
        previewMode = mode
        persistSettings()
    }

    public func requestToolbarFocusClear() {
        isToolbarTextInputFocused = false
        requestedFocus = .clear
    }

    public func isCommandEnabled(_ command: ExplorerCommand) -> Bool {
        isCommandEnabled(command, forPaneAt: activePaneIndex)
    }

    public func isCommandEnabled(_ command: ExplorerCommand, forPaneAt paneIndex: Int) -> Bool {
        guard panes.indices.contains(paneIndex) else {
            return false
        }
        if isToolbarTextInputFocused && command.yieldsToTextEditing {
            return false
        }
        if (command == .copyToOppositePane || command == .moveToOppositePane)
            && oppositePaneDestination(for: paneIndex) == nil {
            return false
        }
        let pane = panes[paneIndex]
        let selectedEntries = visibleEntries(forPaneAt: paneIndex).filter { pane.selectedURLs.contains($0.url) }

        return command.isEnabled(
            selectionCount: pane.selectedURLs.count,
            canPaste: canPaste,
            canUndo: canUndo,
            canCloseTab: canCloseTab,
            canGoBack: !pane.backStack.isEmpty,
            canGoForward: !pane.forwardStack.isEmpty,
            canGoUp: canGoUp(forPaneAt: paneIndex),
            selectedEntries: selectedEntries,
            isArchiveLocation: pane.location.isArchive
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
        await refreshFavoriteSidebarItemStatuses()
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
            if await pathStatusChecker.status(for: targetURL).exists {
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
            visibleError = .operationFailed(error.localizedDescription)
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
        let status = await pathStatusChecker.status(for: url)
        guard status.exists, status.isDirectory else {
            mountedVolumes.removeAll { $0.url.standardizedFileURL == url }
            volumeError = .pathDoesNotExist(url.path)
            return
        }
        guard volume.isReadable, status.isReadable else {
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
        let status = await pathStatusChecker.status(for: url)
        guard status.exists, status.isDirectory else {
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
            visibleError = .operationFailed(error.localizedDescription)
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
            visibleError = .operationFailed(error.localizedDescription)
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
            visibleError = .operationFailed(error.localizedDescription)
        }
    }

    public func goBack() async {
        guard let target = activePane.backStack.last else {
            return
        }
        let paneID = activePane.id
        let previousLocation = activePane.location
        let previousBackStack = activePane.backStack
        let previousForwardStack = activePane.forwardStack

        do {
            guard let commit = try await loadLocationCommit(target, pushHistory: false, paneID: paneID),
                  let paneIndex = currentPaneIndex(for: commit) else {
                return
            }
            var pane = panes[paneIndex]
            pane.backStack = Array(previousBackStack.dropLast())
            pane.forwardStack = previousForwardStack + [previousLocation]
            panes[paneIndex] = pane
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func goForward() async {
        guard let target = activePane.forwardStack.last else {
            return
        }
        let paneID = activePane.id
        let previousLocation = activePane.location
        let previousBackStack = activePane.backStack
        let previousForwardStack = activePane.forwardStack

        do {
            guard let commit = try await loadLocationCommit(target, pushHistory: false, paneID: paneID),
                  let paneIndex = currentPaneIndex(for: commit) else {
                return
            }
            var pane = panes[paneIndex]
            pane.forwardStack = Array(previousForwardStack.dropLast())
            pane.backStack = previousBackStack + [previousLocation]
            panes[paneIndex] = pane
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func goUp() async {
        requestToolbarFocusClear()
        guard let parent = parentLocation(from: activePane.location) else {
            let canonicalLocation = canonicalized(activePane.location)
            if canonicalLocation != activePane.location {
                do {
                    try await loadLocation(canonicalLocation, pushHistory: false)
                } catch let error as ExplorerError {
                    present(error)
                } catch {
                    visibleError = .readFailed(error.localizedDescription)
                }
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
        guard panes.indices.contains(index), index != activePaneIndex else {
            return
        }

        activePaneIndex = index
        pathInput = activePane.location.displayPath
        recursiveSearchResults = nil
        trimSelectionToVisibleEntries()
        scheduleFinderTagPopulationIfNeeded()
        scheduleSearchIfNeeded()
        startWatchingVisibleDirectories()
    }

    public func setSearchQuery(_ query: String) {
        searchQuery = query
        scheduleFinderTagPopulationIfNeeded()
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
        scheduleFinderTagPopulationIfNeeded()
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
        scheduleFinderTagPopulationIfNeeded()
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

            let newPaneLocation = activePane.location
            panes.append(PaneState(location: newPaneLocation, sort: defaultSort))
            let newPaneID = panes[panes.count - 1].id

            do {
                try await loadLocation(newPaneLocation, pushHistory: false, paneID: newPaneID)
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
        if let recursiveSearchResults {
            self.recursiveSearchResults = SortEngine.sorted(recursiveSearchResults, descriptor: activePane.sort)
        }
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
        if let recursiveSearchResults {
            self.recursiveSearchResults = SortEngine.sorted(recursiveSearchResults, descriptor: descriptor)
        }
    }

    public func renameSelected(to newName: String) async {
        guard activePane.selectedURLs.count == 1, let url = selectedURLs.first else {
            return
        }
        await rename(url, to: newName, inPane: activePane.id)
    }

    public func rename(_ url: URL, to newName: String, inPane paneID: PaneID) async {
        do {
            let sourceURL = url.standardizedFileURL
            guard let paneIndex = panes.firstIndex(where: { $0.id == paneID }),
                  panes[paneIndex].entries.contains(where: {
                      $0.url.standardizedFileURL == sourceURL && !$0.isArchiveBacked
                  }) else {
                return
            }
            let location = panes[paneIndex].location

            let result = try await fileOperationService.rename(sourceURL, to: newName)
            if let renamedURL = result.renamedItem?.destination {
                recordUndo(
                    undoAction(
                        .renamed(FileMoveRecord(source: sourceURL, destination: renamedURL)),
                        from: result
                    ),
                    ownership: result.undoSourceIdentities
                )
                let reloadCommit = try await reloadCapturedPaneCommit(
                    PaneReloadTarget(paneID: paneID, location: location)
                )
                if let reloadCommit,
                   let currentPaneIndex = currentPaneIndex(for: reloadCommit) {
                    panes[currentPaneIndex].selectedURLs = [renamedURL.standardizedFileURL]
                }
            }
        } catch is FileOperationCancellation {
            return
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .operationFailed(error.localizedDescription)
        }
    }

    public func clearInlineRenameRequest(matching requestID: UUID) {
        guard inlineRenameRequest?.id == requestID else {
            return
        }
        inlineRenameRequest = nil
    }

    public func requestInlineRenameForSelection() {
        guard activePane.selectedURLs.count == 1,
              let entry = activeSelectedEntries.first,
              !entry.isArchiveBacked else {
            return
        }

        requestToolbarFocusClear()
        inlineRenameRequest = InlineRenameRequest(
            paneID: activePane.id,
            url: entry.url
        )
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
                } else if activePane.selectedURLs.isEmpty, let currentURL = activePane.location.fileSystemURL {
                    try await externalAppLauncher.openTerminal(at: currentURL)
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
                let target = PaneReloadTarget(paneID: activePane.id, location: activePane.location)
                guard let currentURL = target.location.fileSystemURL else {
                    throw ExplorerError.operationFailed("Cannot create folders inside ZIP archives.")
                }
                let result = try await fileOperationService.createFolder(in: currentURL)
                if !result.createdURLs.isEmpty {
                    recordUndo(.created(result.createdURLs), ownership: result.undoSourceIdentities)
                }
                let reloadCommit = try await reloadCapturedPaneCommit(target)
                if let reloadCommit,
                   let createdURL = result.createdURLs.first,
                   let targetPaneIndex = currentPaneIndex(for: reloadCommit) {
                    panes[targetPaneIndex].selectedURLs = [createdURL.standardizedFileURL]
                    if activePane.id == target.paneID {
                        requestToolbarFocusClear()
                    }
                    inlineRenameRequest = InlineRenameRequest(
                        paneID: target.paneID,
                        url: createdURL
                    )
                }
            case .rename:
                requestInlineRenameForSelection()
            case .duplicate:
                let urls = selectedURLs
                let reporter = makeOperationReporter(
                    kind: .duplicate,
                    title: operationTitle("Duplicating", count: urls.count)
                )
                var createdURLs: [URL] = []
                var replacedItems: [FileTrashRecord] = []
                var undoSourceIdentities: [URL: FileSystemPathIdentity.FileSystemEntryIdentity] = [:]
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
                    undoSourceIdentities.merge(result.undoSourceIdentities) { recorded, _ in recorded }
                    await reporter.update(
                        phase: .running,
                        currentItemName: url.lastPathComponent,
                        completedUnitCount: index + 1,
                        totalUnitCount: urls.count
                    )
                }
                if !createdURLs.isEmpty {
                    recordUndo(
                        undoAction(.copied(createdURLs), replacedItems: replacedItems),
                        ownership: undoSourceIdentities
                    )
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
                            recordUndo(
                                undoAction(.copied(pasteResult.result.createdURLs), from: pasteResult.result),
                                ownership: pasteResult.result.undoSourceIdentities
                            )
                        }
                    case .move:
                        if !pasteResult.result.movedItems.isEmpty {
                            recordUndo(
                                undoAction(.moved(pasteResult.result.movedItems), from: pasteResult.result),
                                ownership: pasteResult.result.undoSourceIdentities
                            )
                        }
                    }
                }
                await refresh()
                await reporter.complete()
            case .copyToOppositePane:
                try await transferSelectedItemsToOppositePane(mode: .copy)
            case .moveToOppositePane:
                try await transferSelectedItemsToOppositePane(mode: .move)
            case .moveToTrash:
                let urls = selectedURLs
                let reporter = makeOperationReporter(
                    kind: .trash,
                    title: operationTitle("Moving to Trash", count: urls.count)
                )
                let result = try await fileOperationService.moveToTrash(urls, progress: reporter)
                if !result.trashedItems.isEmpty {
                    recordUndo(.trashed(result.trashedItems), ownership: result.undoSourceIdentities)
                }
                await refresh()
                await reporter.complete()
            case .calculateFolderSize:
                try await calculateSelectedFolderSize()
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
            let fallbackError = fallbackError(for: command, underlying: error)
            await failActiveOperation(fallbackError)
            present(fallbackError)
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
                    recordUndo(
                        undoAction(.copied(result.createdURLs), from: result),
                        ownership: result.undoSourceIdentities
                    )
                }
                await refresh()
                await reporter.complete()
            case .move:
                let reporter = makeOperationReporter(kind: .move, title: operationTitle("Moving", count: urls.count))
                let result = try await fileOperationService.moveItems(urls, to: destinationFolder, progress: reporter)
                if !result.movedItems.isEmpty {
                    recordUndo(
                        undoAction(.moved(result.movedItems), from: result),
                        ownership: result.undoSourceIdentities
                    )
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
            let fallbackError = ExplorerError.operationFailed(error.localizedDescription)
            await failActiveOperation(fallbackError)
            present(fallbackError)
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
        let result: FolderAccessSelectionResult
        do {
            result = try await folderAccessService.chooseFolder(
                startingAt: startURL,
                sandboxed: sandboxPolicy.isSandboxed
            )
        } catch let error as ExplorerError {
            present(error)
            return
        } catch {
            visibleError = .operationFailed(error.localizedDescription)
            return
        }

        guard case .granted(let grant, let access) = result else {
            return
        }

        do {
            let storedGrants = try bookmarkStore.load()
            try bookmarkStore.save(grant)
            stopSupersededFolderAccesses(for: grant, storedGrants: storedGrants)
            activeFolderAccesses[grant.id] = access
            unavailableFolderGrantIDs.remove(grant.id)
            refreshGrantedFolderSummaries(using: grantsReplacing(grant, in: storedGrants))
            clearFolderAccessPersistenceError()
            await retryPermissionRecoveryIfSafe(path: retryingPermissionPath)
        } catch {
            folderAccessService.stopAccessing(access)
            recordFolderAccessPersistenceError(error)
        }
    }

    public func removeGrantedFolder(id: FolderAccessGrantID) async {
        do {
            let storedGrants = try bookmarkStore.load()
            try bookmarkStore.remove(id: id)
            if let access = activeFolderAccesses.removeValue(forKey: id) {
                folderAccessService.stopAccessing(access)
            }
            unavailableFolderGrantIDs.remove(id)
            refreshGrantedFolderSummaries(using: storedGrants.filter { $0.id != id })
            clearFolderAccessPersistenceError()
            await refreshVisiblePanesAfterAccessChange()
        } catch {
            recordFolderAccessPersistenceError(error)
        }
    }

    public func resetGrantedFolders() async {
        bookmarkStore.reset()
        activeFolderAccesses.values.forEach(folderAccessService.stopAccessing)
        activeFolderAccesses.removeAll()
        unavailableFolderGrantIDs.removeAll()
        grantedFolderSummaries = []
        clearFolderAccessPersistenceError()
        await refreshVisiblePanesAfterAccessChange()
    }

    private var selectedURLs: [URL] {
        activePane.selectedURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func oppositePaneIndex(for paneIndex: Int) -> Int? {
        guard paneMode == .dual,
              panes.count >= 2,
              panes.indices.contains(paneIndex) else {
            return nil
        }
        return paneIndex == 0 ? 1 : 0
    }

    private func oppositePaneDestination(for paneIndex: Int) -> (paneID: PaneID, url: URL)? {
        guard let index = oppositePaneIndex(for: paneIndex),
              panes.indices.contains(index),
              let url = panes[index].location.fileSystemURL?.standardizedFileURL else {
            return nil
        }
        return (panes[index].id, url)
    }

    private func oppositePaneDestination() -> (paneID: PaneID, url: URL)? {
        oppositePaneDestination(for: activePaneIndex)
    }

    private var singleSelectedEntry: FileEntry? {
        guard activePane.selectedURLs.count == 1, let url = selectedURLs.first?.standardizedFileURL else {
            return nil
        }

        return activePane.entries.first { $0.url.standardizedFileURL == url }
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

    private func refreshGrantedFolderSummaries(using grants: [FolderAccessGrant]) {
        grantedFolderSummaries = grants.map { grant in
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
        let grants: [FolderAccessGrant]
        do {
            grants = try bookmarkStore.load()
        } catch {
            grantedFolderSummaries = []
            recordFolderAccessPersistenceError(error)
            return
        }

        guard sandboxPolicy.isSandboxed else {
            grantedFolderSummaries = grants.map { FolderAccessGrantSummary(grant: $0) }
            return
        }

        grantedFolderSummaries = grants.map { grant in
            do {
                let access = try folderAccessService.resolve(grant)

                var resolvedGrant = grant
                resolvedGrant.url = access.url
                if let refreshedBookmarkData = access.refreshedBookmarkData {
                    resolvedGrant.bookmarkData = refreshedBookmarkData
                }
                resolvedGrant.lastResolvedAt = Date()
                do {
                    try bookmarkStore.save(resolvedGrant)
                } catch {
                    folderAccessService.stopAccessing(access)
                    unavailableFolderGrantIDs.insert(grant.id)
                    recordFolderAccessPersistenceError(error)
                    return FolderAccessGrantSummary(
                        grant: grant,
                        availability: .unavailable
                    )
                }

                activeFolderAccesses[grant.id] = access
                unavailableFolderGrantIDs.remove(grant.id)

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

    private func stopSupersededFolderAccesses(
        for grant: FolderAccessGrant,
        storedGrants: [FolderAccessGrant]
    ) {
        let standardizedURL = grant.url.standardizedFileURL
        let supersededIDs = Set(
            storedGrants
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

    private func grantsReplacing(
        _ grant: FolderAccessGrant,
        in storedGrants: [FolderAccessGrant]
    ) -> [FolderAccessGrant] {
        var updatedGrants = storedGrants.filter { existing in
            existing.id != grant.id
                && existing.url.standardizedFileURL != grant.url.standardizedFileURL
        }
        updatedGrants.append(grant)
        return updatedGrants.sorted { lhs, rhs in
            lhs.displayPath.localizedStandardCompare(rhs.displayPath) == .orderedAscending
        }
    }

    private func recordFolderAccessPersistenceError(_ error: Error) {
        let message = error.localizedDescription
        folderAccessPersistenceErrorMessage = message
        visibleError = .operationFailed(message)
    }

    private func clearFolderAccessPersistenceError() {
        if let message = folderAccessPersistenceErrorMessage,
           visibleError == .operationFailed(message) {
            visibleError = nil
        }
        folderAccessPersistenceErrorMessage = nil
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
        favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites, missingURLs: missingFavoriteURLs)
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

    private func refreshFavoriteSidebarItemStatuses() async {
        let favorites = sidebarState.favorites
        guard !favorites.isEmpty else {
            missingFavoriteURLs = []
            favoriteSidebarItems = []
            return
        }

        let checker = pathStatusChecker
        var missingURLs: Set<URL> = []
        for favorite in favorites {
            let status = await checker.status(for: favorite.url)
            if !status.exists || !status.isDirectory {
                missingURLs.insert(favorite.url.standardizedFileURL)
            }
        }

        guard sidebarState.favorites.map(\.id) == favorites.map(\.id) else {
            return
        }
        missingFavoriteURLs = missingURLs
        favoriteSidebarItems = Self.favoriteItems(from: favorites, missingURLs: missingURLs)
    }

    private static func favoriteItems(from favorites: [SidebarFavorite], missingURLs: Set<URL>) -> [SidebarFavoriteItem] {
        favorites.map { favorite in
            SidebarFavoriteItem(favorite: favorite, isMissing: missingURLs.contains(favorite.url.standardizedFileURL))
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
            let didLoad = try await loadLocation(.fileSystem(targetURL), pushHistory: true)
            if didLoad {
                clearError()
            }
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
                defaultSort: defaultSort,
                previewMode: previewMode,
                previewByteLimit: previewByteLimit
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
        cancelFinderTagPopulation()
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
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = nil

        guard isShowingRecursiveSearchResults, let rootURL = activePane.location.fileSystemURL else {
            recursiveSearchResults = nil
            isSearching = false
            return
        }

        let service = fileSearchService
        let criteria = activeSearchCriteria
        let standardizedRootURL = rootURL.standardizedFileURL
        let context = SearchContext(
            generation: generation,
            tabID: activeTab.id,
            paneID: activePane.id,
            rootURL: standardizedRootURL,
            scope: searchOptions.scope,
            criteria: criteria,
            showHiddenFiles: showHiddenFiles
        )
        let options = DirectoryReadOptions(
            showHiddenFiles: showHiddenFiles,
            includeFinderTags: Self.searchRequiresFinderTags(criteria)
        )
        recursiveSearchResults = nil
        isSearching = true

        searchTask = Task { [weak self] in
            do {
                let results = try await service.search(
                    in: standardizedRootURL,
                    criteria: criteria,
                    options: options
                )
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self, self.isCurrentSearchContext(context) else {
                        return
                    }
                    self.recursiveSearchResults = SortEngine.sorted(results, descriptor: self.activePane.sort)
                    self.isSearching = false
                    self.trimSelectionToVisibleEntries()
                }
            } catch is CancellationError {
                return
            } catch let error as ExplorerError {
                await MainActor.run { [weak self] in
                    guard let self, self.isCurrentSearchContext(context) else { return }
                    self.recursiveSearchResults = []
                    self.isSearching = false
                    self.present(error)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.isCurrentSearchContext(context) else { return }
                    self.recursiveSearchResults = []
                    self.isSearching = false
                    self.visibleError = .readFailed(error.localizedDescription)
                }
            }
        }
    }

    private static func searchRequiresFinderTags(_ criteria: FileEntrySearchCriteria) -> Bool {
        !criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !criteria.finderTagQuery.isEmpty
    }

    private func isCurrentSearchContext(_ context: SearchContext) -> Bool {
        guard searchGeneration == context.generation,
              tabs.indices.contains(activeTabIndex),
              tabs[activeTabIndex].id == context.tabID,
              panes.indices.contains(activePaneIndex),
              panes[activePaneIndex].id == context.paneID,
              panes[activePaneIndex].location.fileSystemURL?.standardizedFileURL == context.rootURL,
              searchOptions.scope == context.scope,
              activeSearchCriteria == context.criteria,
              showHiddenFiles == context.showHiddenFiles else {
            return false
        }
        return true
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
            throw ExplorerError.operationFailed("Cannot paste into ZIP archives.")
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

    private func transferSelectedItemsToOppositePane(mode: FileClipboardMode) async throws {
        let sourcePaneID = activePane.id
        let urls = selectedURLs
        guard !urls.isEmpty else {
            return
        }
        guard !activePane.location.isArchive else {
            throw ExplorerError.operationFailed("Cannot copy or move items out of ZIP archive panes.")
        }
        guard let destination = oppositePaneDestination() else {
            throw ExplorerError.operationFailed("Other pane is not a folder destination.")
        }

        let kind: FileOperationKind = mode == .copy ? .copy : .move
        let verb = mode == .copy ? "Copying to Other Pane" : "Moving to Other Pane"
        let reporter = makeOperationReporter(kind: kind, title: operationTitle(verb, count: urls.count))

        switch mode {
        case .copy:
            let result = try await fileOperationService.copyItems(urls, to: destination.url, progress: reporter)
            if !result.createdURLs.isEmpty {
                recordUndo(
                    undoAction(.copied(result.createdURLs), from: result),
                    ownership: result.undoSourceIdentities
                )
            }
        case .move:
            let result = try await fileOperationService.moveItems(urls, to: destination.url, progress: reporter)
            if !result.movedItems.isEmpty {
                recordUndo(
                    undoAction(.moved(result.movedItems), from: result),
                    ownership: result.undoSourceIdentities
                )
            }
        }

        try await reloadPanes(ids: Set([sourcePaneID, destination.paneID]))
        await reporter.complete()
    }

    private func reloadPanes(ids: Set<PaneID>) async throws {
        let targets = panes.compactMap { pane -> PaneReloadTarget? in
            guard ids.contains(pane.id) else { return nil }
            return PaneReloadTarget(paneID: pane.id, location: pane.location)
        }
        for target in targets {
            try await reloadCapturedPane(target)
        }
    }

    private func recordUndo(
        _ action: FileUndoAction?,
        ownership: [URL: FileSystemPathIdentity.FileSystemEntryIdentity]
    ) {
        guard let action else {
            return
        }
        var snapshot = UndoOwnershipSnapshot(identities: [:])
        for (url, identity) in ownership {
            snapshot.identities[undoOwnershipKey(for: url)] = identity
        }
        undoOwnershipStack.append(snapshot)
        undoStack.append(action)
    }

    private func undoOwnershipKey(for url: URL) -> String {
        FileSystemPathIdentity.canonicalPathPreservingLeaf(url).path
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
        let ownership = undoOwnershipStack.popLast() ?? UndoOwnershipSnapshot(identities: [:])

        do {
            try await undo(action, ownership: ownership)
        } catch {
            undoOwnershipStack.append(ownership)
            undoStack.append(action)
            throw error
        }
    }

    private func undo(_ action: FileUndoAction, ownership: UndoOwnershipSnapshot) async throws {
        let steps = undoSteps(for: action, ownership: ownership)
        try preflightUndo(steps)

        var journal: [UndoJournalEntry] = []
        do {
            for step in steps {
                try Task.checkCancellation()
                switch step {
                case .trash(let sources):
                    let expectedIdentities = try Dictionary(
                        uniqueKeysWithValues: sources.map { source in
                            guard let expectedIdentity = source.expectedIdentity else {
                                throw missingUndoOwnershipError(source.url)
                            }
                            return (source.url.standardizedFileURL, expectedIdentity)
                        }
                    )
                    let result = try await fileOperationService.moveToTrash(
                        sources.map(\.url),
                        expectedIdentities: expectedIdentities
                    )
                    guard result.trashedItems.count == sources.count else {
                        throw ExplorerError.operationFailed("Undo Trash returned an incomplete transaction result.")
                    }
                    for (record, source) in zip(result.trashedItems, sources) {
                        guard let expectedIdentity = source.expectedIdentity else {
                            throw missingUndoOwnershipError(source.url)
                        }
                        journal.append(.trashed(record, expectedIdentity: expectedIdentity))
                    }
                case .move(let source, let destination):
                    guard let expectedIdentity = source.expectedIdentity else {
                        throw missingUndoOwnershipError(source.url)
                    }
                    try restoreItem(
                        from: source.url,
                        to: destination,
                        expectedIdentity: expectedIdentity
                    )
                    journal.append(
                        .moved(
                            source: source.url,
                            destination: destination,
                            expectedIdentity: expectedIdentity
                        )
                    )
                }
            }
        } catch {
            let rollbackFailures = rollbackUndoJournal(journal)
            guard rollbackFailures.isEmpty else {
                throw ExplorerError.operationFailed(
                    "Undo failed (\(error.localizedDescription)) and rollback was incomplete: "
                        + rollbackFailures.joined(separator: "; ")
                )
            }
            throw error
        }
    }

    private func undoSteps(
        for action: FileUndoAction,
        ownership: UndoOwnershipSnapshot
    ) -> [UndoStep] {
        func owned(_ url: URL) -> OwnedUndoSource {
            OwnedUndoSource(
                url: url,
                expectedIdentity: ownership.identities[undoOwnershipKey(for: url)]
            )
        }

        switch action {
        case .created(let urls), .copied(let urls), .extracted(let urls), .compressed(let urls):
            return [.trash(urls.map(owned))]
        case .moved(let records):
            return records.reversed().map {
                .move(source: owned($0.destination), destination: $0.source)
            }
        case .renamed(let record):
            return [.move(source: owned(record.destination), destination: record.source)]
        case .trashed(let records), .restoreReplacements(let records):
            return records.map { .move(source: owned($0.trashed), destination: $0.original) }
        case .compound(_, let actions):
            return actions.flatMap { undoSteps(for: $0, ownership: ownership) }
        }
    }

    private func preflightUndo(_ steps: [UndoStep]) throws {
        var simulatedEntries: [String: SimulatedUndoEntry] = [:]

        func key(for url: URL) -> String {
            undoOwnershipKey(for: url)
        }

        func identity(_ url: URL) -> FileSystemPathIdentity.FileSystemEntryIdentity? {
            if let entry = simulatedEntries[key(for: url)] {
                switch entry {
                case .missing:
                    return nil
                case .present(let identity):
                    return identity
                }
            }
            return FileSystemPathIdentity.entryIdentity(url)
        }

        func requireOwnedIdentity(_ source: OwnedUndoSource) throws -> FileSystemPathIdentity.FileSystemEntryIdentity {
            guard let expectedIdentity = source.expectedIdentity else {
                throw missingUndoOwnershipError(source.url)
            }
            guard let currentIdentity = identity(source.url) else {
                throw missingUndoSourceError(source.url)
            }
            guard currentIdentity == expectedIdentity else {
                throw changedUndoSourceError(source.url)
            }
            return expectedIdentity
        }

        for step in steps {
            switch step {
            case .trash(let sources):
                for source in sources {
                    _ = try requireOwnedIdentity(source)
                    simulatedEntries[key(for: source.url)] = .missing
                }
            case .move(let source, let destination):
                let expectedIdentity = try requireOwnedIdentity(source)
                if identity(destination) != nil,
                   !isAllowedCaseOnlyUndo(source: source.url, destination: destination) {
                    throw undoDestinationExistsError(destination)
                }
                simulatedEntries[key(for: source.url)] = .missing
                simulatedEntries[key(for: destination)] = .present(expectedIdentity)
            }
        }
    }

    private func rollbackUndoJournal(_ journal: [UndoJournalEntry]) -> [String] {
        var failures: [String] = []
        for entry in journal.reversed() {
            let source: URL
            let destination: URL
            let expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
            switch entry {
            case .trashed(let record, let identity):
                source = record.trashed
                destination = record.original
                expectedIdentity = identity
            case .moved(let originalSource, let originalDestination, let identity):
                source = originalDestination
                destination = originalSource
                expectedIdentity = identity
            }

            do {
                try restoreItem(
                    from: source,
                    to: destination,
                    expectedIdentity: expectedIdentity
                )
            } catch {
                failures.append("\(source.path) -> \(destination.path): \(error.localizedDescription)")
            }
        }
        return failures
    }

    private func restoreItem(
        from source: URL,
        to destination: URL,
        expectedIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
    ) throws {
        guard let currentIdentity = FileSystemPathIdentity.entryIdentity(source) else {
            throw missingUndoSourceError(source)
        }
        guard currentIdentity == expectedIdentity else {
            throw changedUndoSourceError(source)
        }
        if FileSystemPathIdentity.entryExists(destination),
           !isAllowedCaseOnlyUndo(source: source, destination: destination) {
            throw undoDestinationExistsError(destination)
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw ExplorerError.operationFailed(
                "Cannot undo \(source.path) to \(destination.path): \(error.localizedDescription)"
            )
        }
        guard FileSystemPathIdentity.entryIdentity(destination) == expectedIdentity else {
            throw ExplorerError.operationFailed(
                "Undo moved an item but destination ownership could not be verified at \(destination.path); "
                    + "automatic rollback was not attempted."
            )
        }
    }

    private func isAllowedCaseOnlyUndo(source: URL, destination: URL) -> Bool {
        do {
            return try FileSystemPathIdentity.isCaseOnlyRenameOfSameItem(
                source: source,
                destination: destination
            )
        } catch {
            return false
        }
    }

    private func missingUndoSourceError(_ source: URL) -> ExplorerError {
        .operationFailed("Cannot undo because the item is missing: \(source.path)")
    }

    private func missingUndoOwnershipError(_ source: URL) -> ExplorerError {
        .operationFailed("Cannot undo because recorded ownership is unavailable: \(source.path)")
    }

    private func changedUndoSourceError(_ source: URL) -> ExplorerError {
        .operationFailed("Cannot undo because the recorded item changed: \(source.path)")
    }

    private func undoDestinationExistsError(_ destination: URL) -> ExplorerError {
        .operationFailed("Cannot undo because the destination already exists: \(destination.path)")
    }

    private func calculateSelectedFolderSize() async throws {
        guard
            activePane.selectedURLs.count == 1,
            let url = selectedURLs.first,
            activePaneVisibleEntries.first(where: { $0.url == url })?.isDirectoryLike == true
        else {
            return
        }

        let service = folderSizeService
        let size = try await Task.detached {
            try service.size(of: url)
        }.value
        calculatedFolderSizes[url.standardizedFileURL] = size
    }

    private func extractSelectedZips() async throws {
        guard let currentURL = activePane.location.fileSystemURL?.standardizedFileURL else {
            throw ExplorerError.archiveFailed("Cannot extract ZIP files inside ZIP archives.")
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
            recordUndo(
                undoAction(.extracted(result.createdURLs), from: result),
                ownership: result.undoSourceIdentities
            )
        }
        await refresh()
        await reporter.complete()
    }

    private func compressSelectedItems() async throws {
        guard let currentURL = activePane.location.fileSystemURL?.standardizedFileURL else {
            throw ExplorerError.archiveFailed("Cannot create ZIP files inside ZIP archives.")
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
            recordUndo(
                undoAction(.compressed(result.createdURLs), from: result),
                ownership: result.undoSourceIdentities
            )
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

    func fallbackError(for command: ExplorerCommand, underlying error: Error) -> ExplorerError {
        switch command {
        case .extractZip, .compressToZip:
            return .archiveFailed(error.localizedDescription)
        case .openInTerminal, .openInVSCode:
            return .externalCommandFailed(error.localizedDescription)
        case .newFolder, .duplicate, .editTags, .paste, .copyToOppositePane, .moveToOppositePane,
             .moveToTrash, .calculateFolderSize, .undo, .rename:
            return .operationFailed(error.localizedDescription)
        case .open, .chooseOpenWithApplication, .quickLook, .revealInFinder, .copyPath,
             .selectAll, .addToFavorites, .copy, .cut, .refresh, .focusSearch, .focusPath, .clearSearch,
             .toggleHiddenFiles, .toggleInspector, .goBack, .goForward, .goUp, .newTab, .closeTab,
             .nextTab, .previousTab:
            return .readFailed(error.localizedDescription)
        }
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

    private func cancelFinderTagPopulation() {
        finderTagPopulationTask?.cancel()
        finderTagPopulationTask = nil
        finderTagPopulationToken = UUID()
    }

    private func scheduleFinderTagPopulationIfNeeded() {
        cancelFinderTagPopulation()

        let criteria = activeSearchCriteria
        guard searchOptions.scope == .currentFolder,
              Self.searchRequiresFinderTags(criteria),
              panes.indices.contains(activePaneIndex),
              let rootURL = panes[activePaneIndex].location.fileSystemURL else {
            return
        }

        let paneIndex = activePaneIndex
        let context = FinderTagPopulationContext(
            tabID: activeTab.id,
            paneID: panes[paneIndex].id,
            rootURL: rootURL.standardizedFileURL,
            scope: searchOptions.scope,
            ordinaryQuery: criteria.query,
            explicitTagQuery: criteria.finderTagQuery
        )
        let entries = panes[paneIndex].entries
        let finderTagService = finderTagService
        let token = UUID()
        finderTagPopulationToken = token

        finderTagPopulationTask = Task.detached(priority: .userInitiated) { [weak self] in
            var tagsByURL: [URL: [FinderTag]] = [:]
            tagsByURL.reserveCapacity(entries.count)

            for entry in entries where !entry.isArchiveBacked {
                guard !Task.isCancelled else {
                    return
                }
                do {
                    tagsByURL[entry.url.standardizedFileURL] = try finderTagService.tags(for: entry.url)
                } catch {
                    tagsByURL[entry.url.standardizedFileURL] = entry.finderTags
                }
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self,
                      self.finderTagPopulationToken == token,
                      self.isCurrentFinderTagPopulationContext(context),
                      let currentPaneIndex = self.panes.firstIndex(where: { $0.id == context.paneID }) else {
                    return
                }

                self.panes[currentPaneIndex].entries = self.panes[currentPaneIndex].entries.map { entry in
                    guard let tags = tagsByURL[entry.url.standardizedFileURL] else {
                        return entry
                    }
                    return entry.replacingFinderTags(tags)
                }
                self.trimSelectionToVisibleEntries()
                self.finderTagPopulationTask = nil
            }
        }
    }

    private func isCurrentFinderTagPopulationContext(_ context: FinderTagPopulationContext) -> Bool {
        guard tabs.indices.contains(activeTabIndex),
              tabs[activeTabIndex].id == context.tabID,
              panes.indices.contains(activePaneIndex),
              panes[activePaneIndex].id == context.paneID,
              panes[activePaneIndex].location.fileSystemURL?.standardizedFileURL == context.rootURL,
              searchOptions.scope == context.scope,
              searchQuery == context.ordinaryQuery,
              searchOptions.finderTagQuery == context.explicitTagQuery else {
            return false
        }
        return true
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
            let entry = singleSelectedEntry,
            !entry.isArchiveBacked
        else {
            return
        }

        let currentTags = await finderTags(for: entry)
        guard let tags = finderTagPrompt(entry.replacingFinderTags(currentTags)) else {
            return
        }

        cancelFinderTagPopulation()
        try await setFinderTags(tags, for: entry.url)
        await refresh()
        updateFinderTags(tags, for: entry.url)
        updateSelection([entry.url.standardizedFileURL])
        trimSelectionToVisibleEntries()
    }

    private func finderTags(for entry: FileEntry) async -> [FinderTag] {
        let service = finderTagService
        let url = entry.url
        let fallback = entry.finderTags
        return await Task.detached(priority: .utility) {
            (try? service.tags(for: url)) ?? fallback
        }.value
    }

    private func setFinderTags(_ tags: [FinderTag], for url: URL) async throws {
        let service = finderTagService
        try await Task.detached(priority: .utility) {
            try service.setTags(tags, for: url)
        }.value
    }

    private func updateFinderTags(_ tags: [FinderTag], for url: URL) {
        let standardizedURL = url.standardizedFileURL
        for index in panes.indices {
            panes[index].entries = panes[index].entries.map { entry in
                entry.url.standardizedFileURL == standardizedURL ? entry.replacingFinderTags(tags) : entry
            }
        }
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
        let paneID = activePane.id
        let location = activePane.location
        do {
            try await loadLocation(location, pushHistory: false, paneID: paneID)
        } catch let error as ExplorerError {
            present(error)
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    private func reloadAllPanes() async {
        let targets = panes.map { PaneReloadTarget(paneID: $0.id, location: $0.location) }
        for target in targets {
            do {
                try await reloadCapturedPane(target)
            } catch let error as ExplorerError {
                present(error)
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
        }
    }

    private func reloadWatchedPanes() async {
        let targets = panes.indices.compactMap { index -> PaneReloadTarget? in
            guard let url = watchedDirectoryURL(for: panes[index].location),
                  watchedDirectoryURLs.contains(url) else {
                return nil
            }
            return PaneReloadTarget(paneID: panes[index].id, location: panes[index].location)
        }

        for target in targets {
            do {
                try await reloadCapturedPane(target)
            } catch let error as ExplorerError {
                present(error)
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
        }
    }

    private struct PaneReloadTarget {
        var paneID: PaneID
        var location: PaneLocation
    }

    private struct PaneLoadCommit {
        var paneID: PaneID
        var generation: UInt64
        var location: PaneLocation
    }

    @discardableResult
    private func reloadCapturedPane(_ target: PaneReloadTarget) async throws -> Bool {
        try await reloadCapturedPaneCommit(target) != nil
    }

    private func reloadCapturedPaneCommit(_ target: PaneReloadTarget) async throws -> PaneLoadCommit? {
        guard let paneIndex = panes.firstIndex(where: { $0.id == target.paneID }),
              canonicalized(panes[paneIndex].location) == canonicalized(target.location) else {
            return nil
        }
        return try await loadLocationCommit(target.location, pushHistory: false, paneID: target.paneID)
    }

    @discardableResult
    private func loadLocation(
        _ requestedLocation: PaneLocation,
        pushHistory: Bool,
        paneIndex: Int? = nil,
        paneID requestedPaneID: PaneID? = nil
    ) async throws -> Bool {
        try await loadLocationCommit(
            requestedLocation,
            pushHistory: pushHistory,
            paneIndex: paneIndex,
            paneID: requestedPaneID
        ) != nil
    }

    private func loadLocationCommit(
        _ requestedLocation: PaneLocation,
        pushHistory: Bool,
        paneIndex: Int? = nil,
        paneID requestedPaneID: PaneID? = nil
    ) async throws -> PaneLoadCommit? {
        let location = canonicalized(requestedLocation)
        let targetPaneID: PaneID
        if let requestedPaneID {
            guard panes.contains(where: { $0.id == requestedPaneID }) else {
                return nil
            }
            targetPaneID = requestedPaneID
        } else {
            let targetPaneIndex = paneIndex ?? activePaneIndex
            guard panes.indices.contains(targetPaneIndex) else {
                return nil
            }
            targetPaneID = panes[targetPaneIndex].id
        }
        let generation = nextPaneLoadGeneration(for: targetPaneID)
        guard let startingPaneIndex = currentPaneIndex(for: targetPaneID, generation: generation) else {
            return nil
        }
        let shouldShowHiddenFiles = showHiddenFiles

        panes[startingPaneIndex].isLoading = true

        let entries: [FileEntry]
        do {
            switch location {
            case .fileSystem(let url):
                entries = try await fileSystemService.contentsOfDirectory(
                    at: url,
                    options: DirectoryReadOptions(
                        showHiddenFiles: shouldShowHiddenFiles,
                        includeFinderTags: false
                    )
                )
            case .archive(let archiveLocation):
                entries = try await archiveBrowser
                    .list(archiveLocation, showHiddenFiles: shouldShowHiddenFiles)
                    .map(makeFileEntry)
            }
        } catch {
            guard let currentPaneIndex = currentPaneIndex(for: targetPaneID, generation: generation) else {
                return nil
            }
            panes[currentPaneIndex].isLoading = false
            throw error
        }

        guard let targetPaneIndex = currentPaneIndex(for: targetPaneID, generation: generation) else {
            return nil
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
        pane.isLoading = false
        panes[targetPaneIndex] = pane

        if targetPaneIndex == activePaneIndex {
            pathInput = location.displayPath
            if didChangeLocation {
                clearSearch()
            } else {
                recursiveSearchResults = nil
                scheduleSearchIfNeeded()
            }
            scheduleFinderTagPopulationIfNeeded()
            startWatchingVisibleDirectories()
            if case .fileSystem(let url) = location {
                recordRecentFolder(url)
            }
        }
        return PaneLoadCommit(
            paneID: targetPaneID,
            generation: generation,
            location: location
        )
    }

    private func nextPaneLoadGeneration(for paneID: PaneID) -> UInt64 {
        let generation = (paneLoadGenerations[paneID] ?? 0) &+ 1
        paneLoadGenerations[paneID] = generation
        return generation
    }

    private func currentPaneIndex(for paneID: PaneID, generation: UInt64) -> Int? {
        guard paneLoadGenerations[paneID] == generation else {
            return nil
        }
        return panes.firstIndex(where: { $0.id == paneID })
    }

    private func currentPaneIndex(for commit: PaneLoadCommit) -> Int? {
        guard let paneIndex = currentPaneIndex(for: commit.paneID, generation: commit.generation),
              canonicalized(panes[paneIndex].location) == canonicalized(commit.location) else {
            return nil
        }
        return paneIndex
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

    public func waitForFinderTagPopulationForTesting() async {
        await finderTagPopulationTask?.value
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
