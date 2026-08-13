import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSessionRestorationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderSessionRestoration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testEnabledRestorationRebuildsTabsAndDualPanesBeforeInitialLoad() throws {
        let first = try makeDirectory("first")
        let second = try makeDirectory("second")
        let third = try makeDirectory("third")
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [sessionPane(first), sessionPane(second)],
                    activePaneIndex: 1
                ),
                ExplorerSessionTab(
                    panes: [sessionPane(third)],
                    activePaneIndex: 0
                )
            ],
            activeTabIndex: 1
        )

        let store = makeStore(
            settings: ExplorerSettings(paneMode: .dual, restorePreviousSession: true),
            snapshot: snapshot
        )

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.activeTabIndex, 1)
        XCTAssertEqual(store.panes.count, 2)
        XCTAssertEqual(store.panes[0].currentURL, third.standardizedFileURL)
        XCTAssertEqual(store.panes[1].currentURL, third.standardizedFileURL)
        XCTAssertTrue(store.searchQuery.isEmpty)
        XCTAssertTrue(store.activePane.selectedURLs.isEmpty)
        XCTAssertTrue(store.undoStack.isEmpty)
    }

    @MainActor
    func testDisabledRestorationStartsAtInitialLocationWithoutDeletingSnapshot() throws {
        let initial = try makeDirectory("initial")
        let restored = try makeDirectory("restored")
        let sessionStore = RestorationSessionStore(
            snapshot: ExplorerSessionSnapshot(
                tabs: [ExplorerSessionTab(panes: [sessionPane(restored)], activePaneIndex: 0)],
                activeTabIndex: 0
            )
        )

        let store = makeStore(
            initialURL: initial,
            settings: ExplorerSettings(restorePreviousSession: false),
            sessionStore: sessionStore
        )

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activePane.currentURL, initial.standardizedFileURL)
        XCTAssertEqual(sessionStore.resetCallCount, 0)
        XCTAssertNotNil(sessionStore.snapshot)
    }

    @MainActor
    func testInitialValidationReplacesOnlyMissingRestoredPane() async throws {
        let initial = try makeDirectory("initial")
        let valid = try makeDirectory("valid")
        let missing = tempDirectory.appendingPathComponent("missing", isDirectory: true)
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [sessionPane(valid), sessionPane(missing)],
                    activePaneIndex: 1
                )
            ],
            activeTabIndex: 0
        )
        let store = makeStore(
            initialURL: initial,
            settings: ExplorerSettings(paneMode: .dual, restorePreviousSession: true),
            snapshot: snapshot
        )

        await store.loadInitialDirectory()

        XCTAssertEqual(store.panes[0].currentURL, valid.standardizedFileURL)
        XCTAssertEqual(store.panes[1].currentURL, initial.standardizedFileURL)
        XCTAssertNil(store.panes[0].error)
        XCTAssertNil(store.panes[1].error)
    }

    @MainActor
    func testInitialValidationReplacesArchiveLocationWhenZipHostIsMissing() async throws {
        let initial = try makeDirectory("initial")
        let missingZip = tempDirectory.appendingPathComponent("missing.zip")
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [
                        ExplorerSessionPane(
                            location: .archive(ArchiveLocation(archiveURL: missingZip, internalPath: "Nested")),
                            sort: EntrySortDescriptor(),
                            group: nil
                        )
                    ],
                    activePaneIndex: 0
                )
            ],
            activeTabIndex: 0
        )
        let store = makeStore(initialURL: initial, snapshot: snapshot)

        await store.loadInitialDirectory()

        XCTAssertEqual(store.activePane.location, .fileSystem(initial.standardizedFileURL))
        XCTAssertNil(store.activePane.error)
    }

    @MainActor
    func testInitialRestoredReadFailureFallsBackOnceToInitialLocation() async throws {
        let initial = try makeDirectory("initial")
        let restored = try makeDirectory("restored")
        let fileSystem = RestorationFileSystemService(failingURL: restored)
        let snapshot = ExplorerSessionSnapshot(
            tabs: [ExplorerSessionTab(panes: [sessionPane(restored)], activePaneIndex: 0)],
            activeTabIndex: 0
        )
        let store = makeStore(
            initialURL: initial,
            snapshot: snapshot,
            fileSystemService: fileSystem,
            pathStatusChecker: AlwaysReadablePathStatusChecker()
        )

        await store.loadInitialDirectory()

        let readURLs = await fileSystem.readURLs()
        XCTAssertEqual(store.activePane.currentURL, initial.standardizedFileURL)
        XCTAssertEqual(readURLs, [restored.standardizedFileURL, initial.standardizedFileURL])
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testInactiveRestoredTabFallsBackWhenItsFirstReadLaterFails() async throws {
        let initial = try makeDirectory("initial")
        let later = try makeDirectory("later")
        let fileSystem = RestorationFileSystemService(failingURL: later)
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(panes: [sessionPane(initial)], activePaneIndex: 0),
                ExplorerSessionTab(panes: [sessionPane(later)], activePaneIndex: 0)
            ],
            activeTabIndex: 0
        )
        let store = makeStore(
            initialURL: initial,
            snapshot: snapshot,
            fileSystemService: fileSystem,
            pathStatusChecker: AlwaysReadablePathStatusChecker()
        )
        await store.loadInitialDirectory()

        await store.selectTab(at: 1)

        let readURLs = await fileSystem.readURLs()
        XCTAssertEqual(store.activePane.currentURL, initial.standardizedFileURL)
        XCTAssertNil(store.visibleError)
        XCTAssertEqual(
            readURLs,
            [initial.standardizedFileURL, later.standardizedFileURL, initial.standardizedFileURL]
        )
    }

    @MainActor
    func testSuccessfulNavigationBeforeInitialRestoreLoadConsumesFallback() async throws {
        let initial = try makeDirectory("initial")
        let restored = try makeDirectory("restored")
        let destination = try makeDirectory("destination")
        let snapshot = ExplorerSessionSnapshot(
            tabs: [ExplorerSessionTab(panes: [sessionPane(restored)], activePaneIndex: 0)],
            activeTabIndex: 0
        )
        let store = makeStore(initialURL: initial, snapshot: snapshot)

        await store.navigate(to: destination)
        try FileManager.default.removeItem(at: destination)
        await store.setShowHiddenFiles(true)

        XCTAssertEqual(store.activePane.currentURL, destination.standardizedFileURL)
        XCTAssertNotNil(store.visibleError)
    }

    @MainActor
    func testDelayedValidationCannotOverwriteNewerNavigation() async throws {
        let initial = try makeDirectory("initial")
        let restored = try makeDirectory("restored")
        let destination = try makeDirectory("destination")
        let pathStatusChecker = BlockingRestoredPathStatusChecker(blockedURL: restored)
        let snapshot = ExplorerSessionSnapshot(
            tabs: [ExplorerSessionTab(panes: [sessionPane(restored)], activePaneIndex: 0)],
            activeTabIndex: 0
        )
        let store = makeStore(
            initialURL: initial,
            snapshot: snapshot,
            pathStatusChecker: pathStatusChecker
        )
        let initialLoad = Task { @MainActor in
            await store.loadInitialDirectory()
        }
        await pathStatusChecker.waitUntilBlocked()

        await store.navigate(to: destination)
        await pathStatusChecker.resumeBlockedStatus()
        await initialLoad.value

        XCTAssertEqual(store.activePane.currentURL, destination.standardizedFileURL)
    }

    @MainActor
    private func makeStore(
        initialURL: URL? = nil,
        settings: ExplorerSettings = ExplorerSettings(restorePreviousSession: true),
        snapshot: ExplorerSessionSnapshot? = nil,
        sessionStore: RestorationSessionStore? = nil,
        fileSystemService: any FileSystemServicing = FileSystemService(),
        pathStatusChecker: any PathStatusChecking = FileManagerPathStatusChecker()
    ) -> ExplorerStore {
        ExplorerStore(
            initialURL: initialURL ?? tempDirectory,
            fileSystemService: fileSystemService,
            settingsStore: RestorationSettingsStore(settings: settings),
            sidebarFavoritesStore: RestorationSidebarStore(),
            sessionStore: sessionStore ?? RestorationSessionStore(snapshot: snapshot),
            directoryWatcher: nil,
            pathStatusChecker: pathStatusChecker
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sessionPane(_ url: URL) -> ExplorerSessionPane {
        ExplorerSessionPane(
            location: .fileSystem(url),
            sort: EntrySortDescriptor(),
            group: nil
        )
    }
}

private final class RestorationSettingsStore: ExplorerSettingsStoring {
    var settings: ExplorerSettings

    init(settings: ExplorerSettings) {
        self.settings = settings
    }

    func load() -> ExplorerSettings { settings }
    func save(_ settings: ExplorerSettings) { self.settings = settings }
}

private final class RestorationSidebarStore: SidebarFavoritesStoring {
    func load() -> SidebarState { SidebarState(favorites: [], recentFolders: []) }
    func save(_ state: SidebarState) {}
}

private final class RestorationSessionStore: ExplorerSessionStoring {
    var snapshot: ExplorerSessionSnapshot?
    private(set) var resetCallCount = 0

    init(snapshot: ExplorerSessionSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> ExplorerSessionSnapshot? { snapshot }
    func save(_ snapshot: ExplorerSessionSnapshot) { self.snapshot = snapshot }
    func reset() {
        resetCallCount += 1
        snapshot = nil
    }
}

private actor RestorationReadRecorder {
    private var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url.standardizedFileURL)
    }

    func values() -> [URL] { urls }
}

private struct RestorationFileSystemService: FileSystemServicing {
    let failingURL: URL
    private let recorder = RestorationReadRecorder()

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        await recorder.record(url)
        if url.standardizedFileURL == failingURL.standardizedFileURL {
            throw ExplorerError.readFailed("Injected restored location failure")
        }
        return []
    }

    func readURLs() async -> [URL] {
        await recorder.values()
    }
}

private struct AlwaysReadablePathStatusChecker: PathStatusChecking {
    func status(for url: URL) async -> FilePathStatus {
        FilePathStatus(exists: true, isDirectory: true, isReadable: true)
    }
}

private actor BlockingRestoredPathStatusChecker: PathStatusChecking {
    private let blockedURL: URL
    private var statusContinuation: CheckedContinuation<FilePathStatus, Never>?
    private var waiterContinuation: CheckedContinuation<Void, Never>?
    private var didBlock = false

    init(blockedURL: URL) {
        self.blockedURL = blockedURL.standardizedFileURL
    }

    func status(for url: URL) async -> FilePathStatus {
        guard url.standardizedFileURL == blockedURL else {
            return FilePathStatus(exists: true, isDirectory: true, isReadable: true)
        }

        didBlock = true
        waiterContinuation?.resume()
        waiterContinuation = nil
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func waitUntilBlocked() async {
        guard !didBlock else {
            return
        }
        await withCheckedContinuation { continuation in
            waiterContinuation = continuation
        }
    }

    func resumeBlockedStatus() {
        statusContinuation?.resume(
            returning: FilePathStatus(exists: true, isDirectory: true, isReadable: true)
        )
        statusContinuation = nil
    }
}
