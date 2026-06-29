import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerFocusCommandTests: XCTestCase {
    private var tempDirectory: URL!
    private var settingsStore: InMemoryExplorerFocusSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFocusCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settingsStore = InMemoryExplorerFocusSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testFocusCommandsPublishAndClearFocusRequests() async {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)

        await store.perform(.focusSearch)
        XCTAssertEqual(store.requestedFocus, .search)

        store.clearFocusRequest()
        XCTAssertNil(store.requestedFocus)

        await store.perform(.focusPath)
        XCTAssertEqual(store.requestedFocus, .path)
    }

    @MainActor
    func testToolbarFocusClearRequestPublishesClearAndMarksInputUnfocused() {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        store.setToolbarTextInputFocused(true)

        store.requestToolbarFocusClear()

        XCTAssertEqual(store.requestedFocus, .clear)
        XCTAssertFalse(store.isToolbarTextInputFocused)
    }

    @MainActor
    func testClearSearchCommandClearsSearchQuery() async {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        store.setSearchQuery("alpha")

        await store.perform(.clearSearch)

        XCTAssertEqual(store.searchQuery, "")
    }

    @MainActor
    func testToggleHiddenFilesCommandReloadsWithHiddenEntries() async throws {
        try "secret".write(to: tempDirectory.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()
        XCTAssertFalse(store.activePane.entries.contains { $0.name == ".secret" })

        await store.perform(.toggleHiddenFiles)

        XCTAssertTrue(store.showHiddenFiles)
        XCTAssertTrue(store.activePane.entries.contains { $0.name == ".secret" })
    }
}

private final class InMemoryExplorerFocusSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
