import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSortSettingsTests: XCTestCase {
    private var tempDirectory: URL!
    private var settingsStore: InMemoryExplorerSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderSortSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settingsStore = InMemoryExplorerSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    @MainActor
    func testLoadsPersistedDefaultSortOnStartup() async throws {
        try "a".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "z".write(to: tempDirectory.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        settingsStore.settings = ExplorerSettings(
            defaultSort: EntrySortDescriptor(key: .name, direction: .descending, folderFileOrdering: .mixed)
        )

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        XCTAssertEqual(store.activePane.sort, settingsStore.settings.defaultSort)
        XCTAssertEqual(store.activePane.entries.map(\.name), ["z.txt", "a.txt"])
    }

    @MainActor
    func testSettingDefaultSortPersistsAndResortsExistingPanes() async throws {
        try "small".write(to: tempDirectory.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try "large file".write(to: tempDirectory.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        let descriptor = EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .mixed)
        store.setDefaultSort(descriptor)

        XCTAssertEqual(store.defaultSort, descriptor)
        XCTAssertEqual(settingsStore.settings.defaultSort, descriptor)
        XCTAssertEqual(store.activePane.sort, descriptor)
        XCTAssertEqual(store.activePane.entries.map(\.name), ["large.txt", "small.txt"])
    }

    @MainActor
    func testSettingDefaultSortUpdatesInactiveTabs() async throws {
        try "small".write(to: tempDirectory.appendingPathComponent("a-small.txt"), atomically: true, encoding: .utf8)
        try "large file".write(to: tempDirectory.appendingPathComponent("z-large.txt"), atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()
        await store.newTab()

        let descriptor = EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .mixed)
        store.setDefaultSort(descriptor)

        await store.selectTab(at: 0)

        XCTAssertEqual(store.activePane.sort, descriptor)
        XCTAssertEqual(store.activePane.entries.map(\.name), ["z-large.txt", "a-small.txt"])
    }

    @MainActor
    func testSortingActivePaneBySameColumnTogglesDirection() async throws {
        try "a".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "z".write(to: tempDirectory.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        store.sortActivePane(by: .name)
        XCTAssertEqual(store.activePane.sort.direction, .descending)
        XCTAssertEqual(store.activePane.entries.map(\.name), ["z.txt", "a.txt"])

        store.sortActivePane(by: .name)
        XCTAssertEqual(store.activePane.sort.direction, .ascending)
        XCTAssertEqual(store.activePane.entries.map(\.name), ["a.txt", "z.txt"])
    }

    @MainActor
    func testSortingActivePaneByNewColumnUsesAscendingAndKeepsFolderFileOrdering() async throws {
        try "a".write(to: tempDirectory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "longer".write(to: tempDirectory.appendingPathComponent("longer.txt"), atomically: true, encoding: .utf8)
        settingsStore.settings = ExplorerSettings(
            defaultSort: EntrySortDescriptor(key: .name, direction: .ascending, folderFileOrdering: .filesFirst)
        )
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        store.sortActivePane(by: .size)

        XCTAssertEqual(
            store.activePane.sort,
            EntrySortDescriptor(key: .size, direction: .ascending, folderFileOrdering: .filesFirst)
        )
        XCTAssertEqual(store.activePane.entries.map(\.name), ["a.txt", "longer.txt"])
    }

    @MainActor
    func testRecursiveSearchCompletionUsesLatestPaneSort() async throws {
        let searchService = PendingSortSearchService()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: settingsStore,
            directoryWatcher: nil,
            fileSearchService: searchService
        )
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("txt")
        await searchService.waitUntilStarted()

        store.sortActivePane(by: .name)
        await searchService.finish(with: [
            makeSearchEntry(name: "a.txt"),
            makeSearchEntry(name: "z.txt")
        ])
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePane.sort.direction, .descending)
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["z.txt", "a.txt"])
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

private final class InMemoryExplorerSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}

private actor PendingSortSearchService: FileSearchServicing {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<[FileEntry], Error>?
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
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func finish(with entries: [FileEntry]) {
        resultContinuation?.resume(returning: entries)
        resultContinuation = nil
    }
}
