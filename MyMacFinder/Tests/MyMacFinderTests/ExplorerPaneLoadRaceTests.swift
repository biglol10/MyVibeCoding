import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerPaneLoadRaceTests: XCTestCase {
    private var tempDirectory: URL!
    private var root: URL!
    private var slow: URL!
    private var fast: URL!
    private var settingsStore: PaneRaceSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderPaneRace-\(UUID().uuidString)", isDirectory: true)
        let root = tempDirectory.appendingPathComponent("Root", isDirectory: true)
        let slow = tempDirectory.appendingPathComponent("Slow", isDirectory: true)
        let fast = tempDirectory.appendingPathComponent("Fast", isDirectory: true)
        self.root = root
        self.slow = slow
        self.fast = fast
        for directory in [root, slow, fast] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        settingsStore = PaneRaceSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    @MainActor
    func testOlderNavigationCannotOverwriteNewerLocationEntriesSearchOrLoading() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [entry(named: "root.txt", in: root)],
            slow.standardizedFileURL: [entry(named: "slow.txt", in: slow)],
            fast.standardizedFileURL: [entry(named: "fast.txt", in: fast)]
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await service.suspendNextRead(at: slow)

        let olderNavigation = Task { @MainActor in
            await store.navigate(to: slow)
        }
        await service.waitUntilReadIsSuspended(at: slow)

        await store.navigate(to: fast)
        store.setSearchQuery("fast")
        await service.resumeRead(at: slow)
        await olderNavigation.value

        XCTAssertEqual(store.activePane.location, .fileSystem(fast.standardizedFileURL))
        XCTAssertEqual(store.activePane.entries.map(\.name), ["fast.txt"])
        XCTAssertEqual(store.pathInput, fast.path)
        XCTAssertEqual(store.searchQuery, "fast")
        XCTAssertFalse(store.activePane.isLoading)
        XCTAssertNil(store.visibleError)
        XCTAssertEqual(store.activePane.backStack, [.fileSystem(root.standardizedFileURL)])
    }

    @MainActor
    func testStaleNavigationErrorDoesNotSurfaceAfterNewerSuccess() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [],
            fast.standardizedFileURL: [entry(named: "fast.txt", in: fast)]
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await service.suspendNextRead(at: slow)

        let olderNavigation = Task { @MainActor in
            await store.navigate(to: slow)
        }
        await service.waitUntilReadIsSuspended(at: slow)
        await store.navigate(to: fast)
        await service.failRead(at: slow, with: .readFailed("stale pane failure"))
        await olderNavigation.value

        XCTAssertEqual(store.activePane.location, .fileSystem(fast.standardizedFileURL))
        XCTAssertEqual(store.activePane.entries.map(\.name), ["fast.txt"])
        XCTAssertNil(store.visibleError)
        XCTAssertFalse(store.activePane.isLoading)
    }

    @MainActor
    func testRemovedSecondaryPaneIgnoresLateReadWithoutArrayTrap() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [],
            slow.standardizedFileURL: [entry(named: "slow.txt", in: slow)]
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        let primaryPaneID = store.panes[0].id
        store.activatePane(at: 1)
        await service.suspendNextRead(at: slow)

        let removedPaneNavigation = Task { @MainActor in
            await store.navigate(to: slow)
        }
        await service.waitUntilReadIsSuspended(at: slow)
        store.activatePane(at: 0)
        await store.setPaneMode(.single)
        await service.resumeRead(at: slow)
        await removedPaneNavigation.value

        XCTAssertEqual(store.panes.count, 1)
        XCTAssertEqual(store.panes[0].id, primaryPaneID)
        XCTAssertEqual(store.panes[0].location, .fileSystem(root.standardizedFileURL))
        XCTAssertFalse(store.panes[0].isLoading)
    }

    @MainActor
    func testGoBackMutatesOriginalPaneHistoryWhenActivePaneChangesDuringRead() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [],
            slow.standardizedFileURL: []
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await store.navigate(to: slow)
        await store.setPaneMode(.dual)
        let originalPaneID = store.panes[0].id
        let otherPaneID = store.panes[1].id
        await service.suspendNextRead(at: root)

        let backNavigation = Task { @MainActor in
            await store.goBack()
        }
        await service.waitUntilReadIsSuspended(at: root)
        store.activatePane(at: 1)
        await service.resumeRead(at: root)
        await backNavigation.value

        let originalPane = try XCTUnwrap(store.panes.first(where: { $0.id == originalPaneID }))
        let otherPane = try XCTUnwrap(store.panes.first(where: { $0.id == otherPaneID }))
        XCTAssertEqual(originalPane.location, .fileSystem(root.standardizedFileURL))
        XCTAssertTrue(originalPane.backStack.isEmpty)
        XCTAssertEqual(originalPane.forwardStack, [.fileSystem(slow.standardizedFileURL)])
        XCTAssertEqual(otherPane.location, .fileSystem(slow.standardizedFileURL))
        XCTAssertTrue(otherPane.backStack.isEmpty)
        XCTAssertTrue(otherPane.forwardStack.isEmpty)
    }

    @MainActor
    func testGoForwardMutatesOriginalPaneHistoryWhenActivePaneChangesDuringRead() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [],
            slow.standardizedFileURL: []
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await store.navigate(to: slow)
        await store.goBack()
        await store.setPaneMode(.dual)
        let originalPaneID = store.panes[0].id
        let otherPaneID = store.panes[1].id
        await service.suspendNextRead(at: slow)

        let forwardNavigation = Task { @MainActor in
            await store.goForward()
        }
        await service.waitUntilReadIsSuspended(at: slow)
        store.activatePane(at: 1)
        await service.resumeRead(at: slow)
        await forwardNavigation.value

        let originalPane = try XCTUnwrap(store.panes.first(where: { $0.id == originalPaneID }))
        let otherPane = try XCTUnwrap(store.panes.first(where: { $0.id == otherPaneID }))
        XCTAssertEqual(originalPane.location, .fileSystem(slow.standardizedFileURL))
        XCTAssertEqual(originalPane.backStack, [.fileSystem(root.standardizedFileURL)])
        XCTAssertTrue(originalPane.forwardStack.isEmpty)
        XCTAssertEqual(otherPane.location, .fileSystem(root.standardizedFileURL))
        XCTAssertTrue(otherPane.backStack.isEmpty)
        XCTAssertTrue(otherPane.forwardStack.isEmpty)
    }

    @MainActor
    func testQueuedMultiPaneRefreshDoesNotRestoreCapturedLocationAfterPaneNavigates() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: [entry(named: "root.txt", in: root)],
            slow.standardizedFileURL: [entry(named: "slow.txt", in: slow)],
            fast.standardizedFileURL: [entry(named: "fast.txt", in: fast)]
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        store.activatePane(at: 1)
        await store.navigate(to: slow)
        let secondaryPaneID = store.activePane.id
        store.activatePane(at: 0)
        await service.suspendNextRead(at: root)

        let refresh = Task { @MainActor in
            await store.setShowHiddenFiles(true)
        }
        await service.waitUntilReadIsSuspended(at: root)

        store.activatePane(at: 1)
        await store.navigate(to: fast)
        await service.resumeRead(at: root)
        await refresh.value

        let secondaryPane = try XCTUnwrap(store.panes.first(where: { $0.id == secondaryPaneID }))
        XCTAssertEqual(secondaryPane.location, .fileSystem(fast.standardizedFileURL))
        XCTAssertEqual(secondaryPane.entries.map(\.name), ["fast.txt"])
        XCTAssertEqual(store.pathInput, fast.path)
        XCTAssertFalse(secondaryPane.isLoading)
    }

    @MainActor
    func testRenameCompletionDoesNotNavigatePaneBackToOriginalLocation() async throws {
        let source = root.appendingPathComponent("source.txt")
        let conflictingDestination = root.appendingPathComponent("renamed.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: conflictingDestination, atomically: true, encoding: .utf8)
        let resolver = SuspendingPaneRaceConflictResolver()
        let store = ExplorerStore(
            initialURL: root,
            fileOperationService: FileOperationService(conflictResolver: resolver),
            settingsStore: settingsStore,
            directoryWatcher: nil
        )
        await store.loadInitialDirectory()
        let paneID = store.activePane.id

        let rename = Task { @MainActor in
            await store.rename(source, to: "renamed.txt", inPane: paneID)
        }
        await resolver.waitUntilRequested()
        await store.navigate(to: fast)
        await resolver.resume(with: .keepBoth)
        await rename.value

        XCTAssertEqual(store.activePane.location, .fileSystem(fast.standardizedFileURL))
        XCTAssertEqual(store.pathInput, fast.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed copy.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testNewFolderCompletionKeepsSelectionAndRenameRequestOnOriginatingPane() async throws {
        let service = ControllablePaneFileSystemService(entriesByURL: [
            root.standardizedFileURL: []
        ])
        let store = makeStore(fileSystemService: service)
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        let originatingPaneID = store.activePane.id
        let otherPaneID = store.panes[1].id
        await service.suspendNextRead(at: root)

        let createFolder = Task { @MainActor in
            await store.perform(.newFolder)
        }
        await service.waitUntilReadIsSuspended(at: root)
        store.activatePane(at: 1)
        await service.resumeRead(at: root)
        await createFolder.value

        let createdURL = root.appendingPathComponent("Untitled Folder").standardizedFileURL
        let originatingPane = try XCTUnwrap(store.panes.first(where: { $0.id == originatingPaneID }))
        let otherPane = try XCTUnwrap(store.panes.first(where: { $0.id == otherPaneID }))
        XCTAssertEqual(originatingPane.selectedURLs, [createdURL])
        XCTAssertTrue(otherPane.selectedURLs.isEmpty)
        XCTAssertEqual(store.inlineRenameRequest?.paneID, originatingPaneID)
        XCTAssertEqual(store.inlineRenameRequest?.url.standardizedFileURL, createdURL)
        XCTAssertEqual(store.activePane.id, otherPaneID)
    }

    @MainActor
    private func makeStore(fileSystemService: any FileSystemServicing) -> ExplorerStore {
        ExplorerStore(
            initialURL: root,
            fileSystemService: fileSystemService,
            settingsStore: settingsStore,
            directoryWatcher: nil
        )
    }

    private func entry(named name: String, in directory: URL) -> FileEntry {
        let url = directory.appendingPathComponent(name)
        return FileEntry(
            url: url,
            name: name,
            kind: .file,
            typeDescription: "File",
            fileExtension: url.pathExtension,
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
    }
}

private final class PaneRaceSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings { settings }
    func save(_ settings: ExplorerSettings) { self.settings = settings }
}

private actor ControllablePaneFileSystemService: FileSystemServicing {
    private let entriesByURL: [URL: [FileEntry]]
    private var suspendedReadCounts: [URL: Int] = [:]
    private var readContinuations: [URL: CheckedContinuation<[FileEntry], Error>] = [:]
    private var waiterContinuations: [URL: CheckedContinuation<Void, Never>] = [:]

    init(entriesByURL: [URL: [FileEntry]]) {
        self.entriesByURL = entriesByURL
    }

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        let url = url.standardizedFileURL
        if let remaining = suspendedReadCounts[url], remaining > 0 {
            suspendedReadCounts[url] = remaining - 1
            waiterContinuations.removeValue(forKey: url)?.resume()
            return try await withCheckedThrowingContinuation { continuation in
                readContinuations[url] = continuation
            }
        }
        return entriesByURL[url] ?? []
    }

    func suspendNextRead(at url: URL) {
        let url = url.standardizedFileURL
        suspendedReadCounts[url, default: 0] += 1
    }

    func waitUntilReadIsSuspended(at url: URL) async {
        let url = url.standardizedFileURL
        if readContinuations[url] != nil {
            return
        }
        await withCheckedContinuation { continuation in
            waiterContinuations[url] = continuation
        }
    }

    func resumeRead(at url: URL) {
        let url = url.standardizedFileURL
        readContinuations.removeValue(forKey: url)?.resume(returning: entriesByURL[url] ?? [])
    }

    func failRead(at url: URL, with error: ExplorerError) {
        readContinuations.removeValue(forKey: url)?.resume(throwing: error)
    }
}

private actor SuspendingPaneRaceConflictResolver: FileConflictResolving {
    private var resolutionContinuation: CheckedContinuation<FileConflictDecision, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var didRequest = false

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        didRequest = true
        requestWaiter?.resume()
        requestWaiter = nil
        return await withCheckedContinuation { continuation in
            resolutionContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        if didRequest {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiter = continuation
        }
    }

    func resume(with decision: FileConflictDecision) {
        resolutionContinuation?.resume(returning: decision)
        resolutionContinuation = nil
    }
}
