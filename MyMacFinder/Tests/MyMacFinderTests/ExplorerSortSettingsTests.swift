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
            try? FileManager.default.removeItem(at: tempDirectory)
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
