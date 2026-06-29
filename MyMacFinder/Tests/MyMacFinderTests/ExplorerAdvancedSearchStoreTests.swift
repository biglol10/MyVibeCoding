import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerAdvancedSearchStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var settingsStore: InMemoryExplorerAdvancedSearchSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderAdvancedSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settingsStore = InMemoryExplorerAdvancedSearchSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testCurrentFolderSearchDoesNotIncludeNestedMatches() async throws {
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "deep".write(to: nested.appendingPathComponent("DeepReport.txt"), atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore, directoryWatcher: nil)
        await store.loadInitialDirectory()

        store.setSearchQuery("DeepReport")

        XCTAssertEqual(store.searchOptions.scope, .currentFolder)
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), [])
        XCTAssertFalse(store.isShowingRecursiveSearchResults)
    }

    @MainActor
    func testRecursiveSearchIncludesNestedMatches() async throws {
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "deep".write(to: nested.appendingPathComponent("DeepReport.txt"), atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("DeepReport")
        await store.waitForSearchForTesting()

        XCTAssertTrue(store.isShowingRecursiveSearchResults)
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["DeepReport.txt"])
    }

    @MainActor
    func testAdvancedKindFilterAppliesToRecursiveResults() async throws {
        let reportFolder = tempDirectory.appendingPathComponent("Report Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: reportFolder, withIntermediateDirectories: true)
        try "report".write(to: tempDirectory.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchKindFilter(.folders)
        store.setSearchQuery("report")
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Report Folder"])
    }

    @MainActor
    func testAdvancedTagFilterAppliesToCurrentFolderResults() async throws {
        let workFile = tempDirectory.appendingPathComponent("WorkReport.txt")
        let personalFile = tempDirectory.appendingPathComponent("PersonalNotes.txt")
        try "work".write(to: workFile, atomically: true, encoding: .utf8)
        try "personal".write(to: personalFile, atomically: true, encoding: .utf8)
        let tagService = FinderTagService()
        try tagService.setTags([FinderTag("Work")], for: workFile)
        try tagService.setTags([FinderTag("Personal")], for: personalFile)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchFinderTagQuery("work")

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["WorkReport.txt"])
    }

    @MainActor
    func testAdvancedTagFilterAppliesToRecursiveResults() async throws {
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let workFile = nested.appendingPathComponent("DeepWorkReport.txt")
        try "work".write(to: workFile, atomically: true, encoding: .utf8)
        let tagService = FinderTagService()
        try tagService.setTags([FinderTag("Work")], for: workFile)

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchFinderTagQuery("work")
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["DeepWorkReport.txt"])
    }
}

private final class InMemoryExplorerAdvancedSearchSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
