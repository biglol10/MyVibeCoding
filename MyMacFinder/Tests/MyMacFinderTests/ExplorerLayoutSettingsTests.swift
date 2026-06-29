import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerLayoutSettingsTests: XCTestCase {
    private var tempDirectory: URL!
    private var settingsStore: InMemoryExplorerSettingsStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settingsStore = InMemoryExplorerSettingsStore()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testDefaultLayoutIsSinglePaneWithInspectorVisible() {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)

        XCTAssertEqual(store.paneMode, .single)
        XCTAssertEqual(store.panes.count, 1)
        XCTAssertEqual(store.activePaneIndex, 0)
        XCTAssertTrue(store.isInspectorVisible)
    }

    @MainActor
    func testSwitchingToDualPaneCreatesLoadedSecondPaneAtCurrentFolder() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.refresh()

        await store.setPaneMode(.dual)

        XCTAssertEqual(store.paneMode, .dual)
        XCTAssertEqual(store.panes.count, 2)
        XCTAssertEqual(store.panes.map { $0.currentURL.standardizedFileURL }, [
            tempDirectory.standardizedFileURL,
            tempDirectory.standardizedFileURL
        ])
        XCTAssertTrue(store.panes[1].entries.contains { $0.name == "note.txt" })
    }

    @MainActor
    func testSwitchingBackToSinglePaneKeepsActivePane() async throws {
        let left = tempDirectory.appendingPathComponent("left", isDirectory: true)
        let right = tempDirectory.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: left, settingsStore: settingsStore)
        await store.refresh()
        await store.setPaneMode(.dual)
        store.activatePane(at: 1)
        await store.navigate(to: right)

        await store.setPaneMode(.single)

        XCTAssertEqual(store.paneMode, .single)
        XCTAssertEqual(store.panes.count, 1)
        XCTAssertEqual(store.activePaneIndex, 0)
        XCTAssertEqual(store.activePane.currentURL.standardizedFileURL, right.standardizedFileURL)
    }

    @MainActor
    func testInspectorVisibilityCanBeConfigured() {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)

        store.isInspectorVisible = false

        XCTAssertFalse(store.isInspectorVisible)
    }

    @MainActor
    func testLoadsPersistedLayoutSettingsOnStartup() async throws {
        let hiddenFile = tempDirectory.appendingPathComponent(".secret")
        try "secret".write(to: hiddenFile, atomically: true, encoding: .utf8)
        settingsStore.settings = ExplorerSettings(
            paneMode: .dual,
            isInspectorVisible: false,
            showHiddenFiles: true
        )

        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.loadInitialDirectory()

        XCTAssertEqual(store.paneMode, .dual)
        XCTAssertEqual(store.panes.count, 2)
        XCTAssertFalse(store.isInspectorVisible)
        XCTAssertTrue(store.showHiddenFiles)
        XCTAssertTrue(store.panes[0].entries.contains { $0.name == ".secret" })
        XCTAssertTrue(store.panes[1].entries.contains { $0.name == ".secret" })
    }

    @MainActor
    func testPersistsLayoutSettingsWhenTheyChange() async {
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)

        await store.setPaneMode(.dual)
        store.isInspectorVisible = false
        await store.setShowHiddenFiles(true)

        XCTAssertEqual(
            settingsStore.settings,
            ExplorerSettings(paneMode: .dual, isInspectorVisible: false, showHiddenFiles: true)
        )
    }

    @MainActor
    func testShowHiddenFilesRefreshesCurrentDirectoryImmediately() async throws {
        let visibleFile = tempDirectory.appendingPathComponent("visible.txt")
        let hiddenFile = tempDirectory.appendingPathComponent(".secret")
        try "visible".write(to: visibleFile, atomically: true, encoding: .utf8)
        try "secret".write(to: hiddenFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, settingsStore: settingsStore)
        await store.refresh()

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "visible.txt" })
        XCTAssertFalse(store.activePane.entries.contains { $0.name == ".secret" })

        await store.setShowHiddenFiles(true)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == ".secret" })
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
