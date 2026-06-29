import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerTabStoreTests: XCTestCase {
    func testInitialStoreCreatesSingleTabForInitialPane() async throws {
        let root = try makeTemporaryDirectory()
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)

        await store.loadInitialDirectory()

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabIndex, 0)
        XCTAssertEqual(store.tabs[0].title, root.lastPathComponent)
        XCTAssertEqual(store.activePane.location, .fileSystem(root.standardizedFileURL))
    }

    func testNewTabCopiesCurrentLocationAndActivatesIt() async throws {
        let root = try makeTemporaryDirectory()
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()

        await store.newTab()

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.activeTabIndex, 1)
        XCTAssertEqual(store.activePane.location, .fileSystem(root.standardizedFileURL))
        XCTAssertEqual(store.pathInput, root.path)
    }

    func testSwitchingTabsPreservesIndependentNavigationAndSearch() async throws {
        let root = try makeTemporaryDirectory()
        let alpha = root.appendingPathComponent("Alpha", isDirectory: true)
        let beta = root.appendingPathComponent("Beta", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)

        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.navigate(to: alpha)
        store.setSearchQuery("one")

        await store.newTab()
        await store.navigate(to: beta)
        store.setSearchQuery("two")

        await store.selectTab(at: 0)
        XCTAssertEqual(store.activePane.location, .fileSystem(alpha.standardizedFileURL))
        XCTAssertEqual(store.searchQuery, "one")

        await store.selectTab(at: 1)
        XCTAssertEqual(store.activePane.location, .fileSystem(beta.standardizedFileURL))
        XCTAssertEqual(store.searchQuery, "two")
    }

    func testSwitchingTabsRestoresIndependentRecursiveSearchResults() async throws {
        let root = try makeTemporaryDirectory()
        let alpha = root.appendingPathComponent("Alpha", isDirectory: true)
        let beta = root.appendingPathComponent("Beta", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try "one".write(to: alpha.appendingPathComponent("OneResult.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: beta.appendingPathComponent("TwoResult.txt"), atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchScope(.recursive)
        store.setSearchQuery("OneResult")
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["OneResult.txt"])

        await store.newTab()
        store.setSearchScope(.recursive)
        store.setSearchQuery("TwoResult")
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["TwoResult.txt"])

        await store.selectTab(at: 0)
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.searchQuery, "OneResult")
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["OneResult.txt"])

        await store.selectTab(at: 1)
        await store.waitForSearchForTesting()

        XCTAssertEqual(store.searchQuery, "TwoResult")
        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["TwoResult.txt"])
    }

    func testCannotCloseLastTab() async throws {
        let root = try makeTemporaryDirectory()
        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)

        await store.closeActiveTab()

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabIndex, 0)
    }

    func testClosingActiveTabActivatesNeighbor() async throws {
        let root = try makeTemporaryDirectory()
        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let store = ExplorerStore(initialURL: root, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.newTab()
        await store.navigate(to: child)

        await store.closeActiveTab()

        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabIndex, 0)
        XCTAssertEqual(store.activePane.location, .fileSystem(root.standardizedFileURL))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderTabs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
