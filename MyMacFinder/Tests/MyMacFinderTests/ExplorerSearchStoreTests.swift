import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSearchStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var settingsStore: InMemoryExplorerSearchSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderSearchStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settingsStore = InMemoryExplorerSearchSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    @MainActor
    func testSearchFiltersOnlyTheActivePaneAndTrimsHiddenSelection() async throws {
        let alpha = tempDirectory.appendingPathComponent("Alpha.txt")
        let beta = tempDirectory.appendingPathComponent("Beta.pdf")
        try "alpha".write(to: alpha, atomically: true, encoding: .utf8)
        try "beta".write(to: beta, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        store.updateSelection([alpha.standardizedFileURL, beta.standardizedFileURL])

        store.setSearchQuery("alpha")

        XCTAssertEqual(store.searchQuery, "alpha")
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Alpha.txt"])
        XCTAssertEqual(store.visibleEntries(forPaneAt: 1).map(\.name), ["Alpha.txt", "Beta.pdf"])
        XCTAssertEqual(store.activePane.selectedURLs, [alpha.standardizedFileURL])
    }

    @MainActor
    func testClearingSearchRestoresTheActivePaneVisibleEntries() async throws {
        let alpha = tempDirectory.appendingPathComponent("Alpha.txt")
        let beta = tempDirectory.appendingPathComponent("Beta.pdf")
        try "alpha".write(to: alpha, atomically: true, encoding: .utf8)
        try "beta".write(to: beta, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        store.setSearchQuery("alpha")
        store.clearSearch()

        XCTAssertEqual(store.searchQuery, "")
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Alpha.txt", "Beta.pdf"])
    }

    @MainActor
    func testChangingFoldersClearsSearchQuery() async throws {
        let alpha = tempDirectory.appendingPathComponent("Alpha.txt")
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        let childFile = child.appendingPathComponent("Beta.txt")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "alpha".write(to: alpha, atomically: true, encoding: .utf8)
        try "beta".write(to: childFile, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()
        store.setSearchQuery("Alpha")

        await store.navigate(to: child)

        XCTAssertEqual(store.searchQuery, "")
        XCTAssertEqual(store.activePane.currentURL, child.standardizedFileURL)
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Beta.txt"])
    }

    @MainActor
    func testRefreshingSameFolderKeepsSearchQuery() async throws {
        let alpha = tempDirectory.appendingPathComponent("Alpha.txt")
        let beta = tempDirectory.appendingPathComponent("Beta.pdf")
        try "alpha".write(to: alpha, atomically: true, encoding: .utf8)
        try "beta".write(to: beta, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()
        store.setSearchQuery("Alpha")

        await store.refresh()

        XCTAssertEqual(store.searchQuery, "Alpha")
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Alpha.txt"])
    }

    @MainActor
    func testCancelledRecursiveSearchFailureDoesNotSurfaceAfterSearchClears() async throws {
        let searchService = ControllableFailingSearchService()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()

        store.setSearchScope(.recursive)
        store.setSearchQuery("missing")
        await searchService.waitUntilSearchStarted()

        store.clearSearch()
        await searchService.finish(with: .readFailed("stale search failure"))
        await Task.yield()
        await Task.yield()

        XCTAssertNil(store.visibleError)
        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.isShowingRecursiveSearchResults)
    }

    @MainActor
    func testSwitchingActivePaneClearsRecursiveResultsAndSearchesTheNewRoot() async throws {
        let left = tempDirectory.appendingPathComponent("Left", isDirectory: true)
        let right = tempDirectory.appendingPathComponent("Right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        try "left".write(
            to: left.appendingPathComponent("LeftReport.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "right".write(
            to: right.appendingPathComponent("RightReport.txt"),
            atomically: true,
            encoding: .utf8
        )
        let store = ExplorerStore(
            initialURL: left,
            settingsStore: settingsStore,
            directoryWatcher: nil
        )
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        store.activatePane(at: 1)
        await store.navigate(to: right)
        store.activatePane(at: 0)
        store.setSearchScope(.recursive)
        store.setSearchQuery("report")
        await store.waitForSearchForTesting()
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["LeftReport.txt"])

        store.activatePane(at: 1)

        XCTAssertTrue(store.activePaneVisibleEntries.isEmpty)
        await store.waitForSearchForTesting()
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["RightReport.txt"])
    }

    @MainActor
    func testReactivatingCurrentPaneDoesNotRestartRecursiveSearch() async throws {
        let searchService = CountingImmediateSearchService()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("report")
        await store.waitForSearchForTesting()
        let initialRequestCount = await searchService.requestCount

        store.activatePane(at: store.activePaneIndex)
        await Task.yield()

        let finalRequestCount = await searchService.requestCount
        XCTAssertEqual(finalRequestCount, initialRequestCount)
    }

    @MainActor
    func testNonCooperativeStaleSearchSuccessCannotOverwriteNewerResults() async throws {
        let staleEntry = makeSearchEntry(name: "stale.txt")
        let currentEntry = makeSearchEntry(name: "current.txt")
        let searchService = NonCooperativeSequencedSearchService(
            subsequentResult: .success([currentEntry])
        )
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("stale")
        await searchService.waitUntilFirstRequestStarts()

        store.setSearchQuery("current")
        await store.waitForSearchForTesting()
        await searchService.finishFirstRequest(with: .success([staleEntry]))
        await Task.yield()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["current.txt"])
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testNonCooperativeStaleGeneralErrorCannotOverwriteNewerState() async throws {
        let currentEntry = makeSearchEntry(name: "current.txt")
        let searchService = NonCooperativeSequencedSearchService(
            subsequentResult: .success([currentEntry])
        )
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("stale")
        await searchService.waitUntilFirstRequestStarts()

        store.setSearchQuery("current")
        await store.waitForSearchForTesting()
        await searchService.finishFirstRequest(
            with: .failure(NSError(domain: "StaleSearch", code: 7))
        )
        await Task.yield()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["current.txt"])
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testHiddenFileSettingChangeRejectsSearchCompletingDuringPaneReload() async throws {
        let staleEntry = makeSearchEntry(name: "stale-hidden-state.txt")
        let currentEntry = makeSearchEntry(name: "current-hidden-state.txt")
        let fileSystemService = BlockingSecondDirectoryReadService()
        let searchService = NonCooperativeSequencedSearchService(
            subsequentResult: .success([currentEntry])
        )
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileSystemService: fileSystemService,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("state")
        await searchService.waitUntilFirstRequestStarts()

        let hiddenFilesTask = Task { @MainActor in
            await store.setShowHiddenFiles(true)
        }
        await fileSystemService.waitUntilSecondReadStarts()
        await searchService.finishFirstRequest(with: .success([staleEntry]))
        await Task.yield()
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.activePaneVisibleEntries.isEmpty)

        await fileSystemService.finishSecondRead()
        await hiddenFilesTask.value
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["current-hidden-state.txt"])
    }

    private func makeSearchEntry(name: String) -> FileEntry {
        let url = tempDirectory.appendingPathComponent(name)
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

private final class InMemoryExplorerSearchSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}

private actor ControllableFailingSearchService: FileSearchServicing {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<[FileEntry], Error>?
    private var didStart = false

    func search(
        in rootURL: URL,
        criteria: FileEntrySearchCriteria,
        options: DirectoryReadOptions
    ) async throws -> [FileEntry] {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func waitUntilSearchStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func finish(with error: ExplorerError) {
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }
}

private actor CountingImmediateSearchService: FileSearchServicing {
    private(set) var requestCount = 0

    func search(
        in rootURL: URL,
        criteria: FileEntrySearchCriteria,
        options: DirectoryReadOptions
    ) async throws -> [FileEntry] {
        requestCount += 1
        return []
    }
}

private actor NonCooperativeSequencedSearchService: FileSearchServicing {
    private let subsequentResult: Result<[FileEntry], Error>
    private var requestCount = 0
    private var firstRequestContinuation: CheckedContinuation<[FileEntry], Error>?
    private var firstRequestStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstRequestDidStart = false

    init(subsequentResult: Result<[FileEntry], Error>) {
        self.subsequentResult = subsequentResult
    }

    func search(
        in rootURL: URL,
        criteria: FileEntrySearchCriteria,
        options: DirectoryReadOptions
    ) async throws -> [FileEntry] {
        requestCount += 1
        if requestCount == 1 {
            firstRequestDidStart = true
            firstRequestStartedContinuation?.resume()
            firstRequestStartedContinuation = nil
            return try await withCheckedThrowingContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }
        return try subsequentResult.get()
    }

    func waitUntilFirstRequestStarts() async {
        if firstRequestDidStart {
            return
        }
        await withCheckedContinuation { continuation in
            firstRequestStartedContinuation = continuation
        }
    }

    func finishFirstRequest(with result: Result<[FileEntry], Error>) {
        guard let continuation = firstRequestContinuation else { return }
        firstRequestContinuation = nil
        continuation.resume(with: result)
    }
}

private actor BlockingSecondDirectoryReadService: FileSystemServicing {
    private var readCount = 0
    private var secondReadContinuation: CheckedContinuation<[FileEntry], Error>?
    private var secondReadStartedContinuation: CheckedContinuation<Void, Never>?
    private var didStartSecondRead = false

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        readCount += 1
        guard readCount == 2 else {
            return []
        }

        didStartSecondRead = true
        secondReadStartedContinuation?.resume()
        secondReadStartedContinuation = nil
        return try await withCheckedThrowingContinuation { continuation in
            secondReadContinuation = continuation
        }
    }

    func waitUntilSecondReadStarts() async {
        if didStartSecondRead {
            return
        }
        await withCheckedContinuation { continuation in
            secondReadStartedContinuation = continuation
        }
    }

    func finishSecondRead() {
        secondReadContinuation?.resume(returning: [])
        secondReadContinuation = nil
    }
}
