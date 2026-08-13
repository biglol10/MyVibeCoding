import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSessionStoreTests: XCTestCase {
    func testTransientStoresDoNotShareSnapshots() throws {
        let first = TransientExplorerSessionStore()
        let second = TransientExplorerSessionStore()
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [
                        ExplorerSessionPane(
                            location: .fileSystem(URL(fileURLWithPath: "/first", isDirectory: true)),
                            sort: EntrySortDescriptor(),
                            group: .none
                        )
                    ],
                    activePaneIndex: 0
                )
            ],
            activeTabIndex: 0
        )

        try first.save(snapshot)

        XCTAssertEqual(try first.load(), snapshot)
        XCTAssertNil(try second.load())
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "ExplorerSessionStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
    }

    func testMissingSessionReturnsNil() throws {
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: "session")

        XCTAssertNil(try store.load())
    }

    func testSessionRoundTripsStableWorkspaceState() throws {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        let desktop = URL(fileURLWithPath: "/tmp/desktop", isDirectory: true)
        let snapshot = ExplorerSessionSnapshot(
            tabs: [
                ExplorerSessionTab(
                    panes: [
                        ExplorerSessionPane(
                            location: .fileSystem(home),
                            sort: EntrySortDescriptor(key: .dateModified, direction: .descending),
                            group: EntryGroupDescriptor(key: .kind)
                        ),
                        ExplorerSessionPane(
                            location: .fileSystem(desktop),
                            sort: EntrySortDescriptor(key: .size, direction: .ascending),
                            group: nil
                        )
                    ],
                    activePaneIndex: 1
                )
            ],
            activeTabIndex: 0
        )
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: "session")

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testCorruptSessionThrowsWithoutChangingStoredBytes() {
        let key = "session"
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: key)
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: key)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: key), corruptData)
    }

    func testOversizedSessionThrowsBeforeDecodeAndPreservesBytes() {
        let key = "session"
        let oversizedData = Data(repeating: 0x41, count: 33)
        defaults.set(oversizedData, forKey: key)
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: key, maximumPayloadBytes: 32)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.data(forKey: key), oversizedData)
    }

    func testUnsupportedSessionVersionThrowsAndPreservesBytes() throws {
        let key = "session"
        let unsupported = ExplorerSessionSnapshot(version: 99, tabs: [], activeTabIndex: 0)
        let data = try JSONEncoder().encode(unsupported)
        defaults.set(data, forKey: key)
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: key)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ExplorerSessionStoreError, .unsupportedVersion(99))
        }
        XCTAssertEqual(defaults.data(forKey: key), data)
    }

    func testResetRemovesOnlyConfiguredSessionKey() throws {
        defaults.set(Data("session".utf8), forKey: "session")
        defaults.set(Data("keep".utf8), forKey: "neighbor")
        let store = UserDefaultsExplorerSessionStore(defaults: defaults, key: "session")

        try store.reset()

        XCTAssertNil(defaults.data(forKey: "session"))
        XCTAssertEqual(defaults.data(forKey: "neighbor"), Data("keep".utf8))
    }

    @MainActor
    func testRestorationNormalizesCountsAndRegeneratesRuntimeState() {
        let fallback = PaneLocation.fileSystem(URL(fileURLWithPath: "/tmp/fallback", isDirectory: true))
        let sessionPanes = (0..<4).map { index in
            ExplorerSessionPane(
                location: .fileSystem(URL(fileURLWithPath: "/tmp/pane-\(index)", isDirectory: true)),
                sort: EntrySortDescriptor(key: .name),
                group: nil
            )
        }
        let sessionTabs = (0..<25).map { _ in
            ExplorerSessionTab(panes: sessionPanes, activePaneIndex: 99)
        }
        let snapshot = ExplorerSessionSnapshot(tabs: sessionTabs, activeTabIndex: 99)

        let restored = snapshot.restoredWorkspace(fallbackLocation: fallback, paneMode: .dual)

        XCTAssertEqual(restored.tabs.count, 20)
        XCTAssertEqual(restored.activeTabIndex, 19)
        XCTAssertTrue(restored.tabs.allSatisfy { $0.panes.count == 2 })
        XCTAssertTrue(restored.tabs.allSatisfy { $0.activePaneIndex == 1 })
        XCTAssertTrue(restored.tabs.flatMap(\.panes).allSatisfy { pane in
            pane.entries.isEmpty
                && pane.selectedURLs.isEmpty
                && pane.backStack.isEmpty
                && pane.forwardStack.isEmpty
                && pane.error == nil
                && !pane.isLoading
        })
        XCTAssertEqual(Set(restored.tabs.map(\.id)).count, restored.tabs.count)
        XCTAssertEqual(Set(restored.tabs.flatMap(\.panes).map(\.id)).count, restored.tabs.flatMap(\.panes).count)
    }

    @MainActor
    func testEmptySessionRestoresOneFallbackPane() {
        let fallback = PaneLocation.fileSystem(URL(fileURLWithPath: "/tmp/fallback", isDirectory: true))
        let snapshot = ExplorerSessionSnapshot(tabs: [], activeTabIndex: -1)

        let restored = snapshot.restoredWorkspace(fallbackLocation: fallback, paneMode: .single)

        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.activeTabIndex, 0)
        XCTAssertEqual(restored.tabs[0].panes.count, 1)
        XCTAssertEqual(restored.tabs[0].panes[0].location, fallback)
    }
}
