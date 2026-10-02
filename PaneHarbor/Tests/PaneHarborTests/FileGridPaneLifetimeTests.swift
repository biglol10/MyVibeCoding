import AppKit
import SwiftUI
import XCTest
@testable import PaneHarbor

final class FileGridPaneLifetimeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GridLifetime-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "fixture".write(to: root.appendingPathComponent("한글 공백.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testRightPaneIdentitySurvivesMovingFromIndexOneToZero() async throws {
        let store = makeStore()
        await store.refresh()
        await store.setPaneMode(.dual)
        let left = store.panes[0].id
        let right = store.panes[1].id
        XCTAssertTrue(store.activatePane(withID: right))
        await store.setPaneMode(.single)

        XCTAssertEqual(store.panes[0].id, right)
        XCTAssertNotNil(store.pane(withID: right))
        XCTAssertEqual(store.visibleEntries(forPaneID: right).map(\.name), ["한글 공백.txt"])
        XCTAssertTrue(store.activatePane(withID: right))
        XCTAssertNil(store.pane(withID: left))
        XCTAssertTrue(store.visibleEntries(forPaneID: left).isEmpty)
        XCTAssertFalse(store.isCommandEnabled(.newFile, forPaneID: left))
        XCTAssertFalse(store.activatePane(withID: left))
        XCTAssertEqual(store.activePane.id, right, "A retired view must not activate an unrelated pane")
    }

    @MainActor
    func testRetiredDropDelegateRejectsRemovedPaneWhileSurvivorStillAccepts() async {
        let store = makeStore()
        await store.setPaneMode(.dual)
        let left = delegate(store, id: store.panes[0].id)
        let right = delegate(store, id: store.panes[1].id)
        XCTAssertTrue(left.isAvailable)
        XCTAssertTrue(right.isAvailable)
        store.activatePane(at: 1)
        await store.setPaneMode(.single)
        XCTAssertFalse(left.isAvailable)
        XCTAssertTrue(right.isAvailable, "A surviving pane remains valid after its array index changes")
    }

    @MainActor
    func testOldTabCallbacksDoNotTargetNewTabWithSamePaneIndex() async {
        let store = makeStore()
        let oldID = store.activePane.id
        let oldDrop = delegate(store, id: oldID)
        await store.perform(.newTab)
        let newID = store.activePane.id
        XCTAssertNotEqual(oldID, newID)
        XCTAssertNil(store.pane(withID: oldID))
        XCTAssertFalse(store.activatePane(withID: oldID))
        XCTAssertFalse(oldDrop.isAvailable)
        XCTAssertEqual(store.activePane.id, newID)
    }

    @MainActor
    func testHostedGridCanFinishLayoutAfterItsPaneIsRemoved() async {
        let store = makeStore()
        await store.refresh()
        await store.setPaneMode(.dual)
        let removedID = store.panes[1].id
        let host = NSHostingView(rootView: FileGridView(paneID: removedID, thumbnails: true).environmentObject(store))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        host.layoutSubtreeIfNeeded()
        store.activatePane(at: 0)
        await store.setPaneMode(.single)
        host.layoutSubtreeIfNeeded()
        XCTAssertNil(store.pane(withID: removedID))
        XCTAssertEqual(store.panes.count, 1)
    }

    @MainActor
    private func makeStore() -> ExplorerStore {
        ExplorerStore(initialURL: root, settingsStore: GridLifetimeSettingsStore())
    }

    @MainActor
    private func delegate(_ store: ExplorerStore, id: PaneID) -> FileGridDropDelegate {
        FileGridDropDelegate(store: store, paneID: id, destination: root, disabled: false)
    }
}

private final class GridLifetimeSettingsStore: ExplorerSettingsStoring {
    var value = ExplorerSettings()
    func load() throws -> ExplorerSettings { value }
    func save(_ settings: ExplorerSettings) throws { value = settings }
}
