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
            try? FileManager.default.removeItem(at: tempDirectory)
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
