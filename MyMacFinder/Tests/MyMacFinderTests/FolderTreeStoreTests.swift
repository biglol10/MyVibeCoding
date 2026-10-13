import Foundation
import XCTest
@testable import MyMacFinder

final class FolderTreeStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
            .appendingPathComponent("PaneHarbor-Foundation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    @MainActor
    func testFolderTreeLoadsOnlyFoldersAndStopsAncestorSymlinkCycle() async throws {
        let child = root.appendingPathComponent("한글 하위", isDirectory: true)
        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        for url in [child, hidden] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        try Data().write(to: root.appendingPathComponent("file.txt"))
        try FileManager.default.createSymbolicLink(atPath: child.appendingPathComponent("back").path, withDestinationPath: "..")
        let tree = FolderTreeStore()
        await tree.setRoot(root, showHidden: false)
        XCTAssertEqual(tree.rows.map(\.node.title), [root.lastPathComponent, "한글 하위"])
        let childNode = try XCTUnwrap(tree.rows.first { $0.node.url.path == child.path }?.node)
        await tree.toggle(childNode)
        let loop = try XCTUnwrap(tree.rows.first { $0.node.title == "back" }?.node)
        XCTAssertTrue(loop.isCycle)
        await tree.toggle(loop)
        XCTAssertFalse(tree.expanded.contains(loop.url))
        await tree.toggle(childNode)
        XCTAssertFalse(tree.rows.contains { $0.node.title == "back" })
        await tree.setRoot(root, showHidden: true)
        XCTAssertTrue(tree.rows.contains { $0.node.title == ".hidden" })
    }

    @MainActor
    func testFolderTreeNavigationKeepsRootButUnrelatedLocationResetsIt() async throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let tree = FolderTreeStore()
        await tree.setRoot(root, showHidden: false)
        await tree.followNavigation(to: child, showHidden: false)
        XCTAssertEqual(tree.rootURL?.path, root.path)
        await tree.followNavigation(to: root.deletingLastPathComponent(), showHidden: false)
        XCTAssertEqual(tree.rootURL?.path, root.deletingLastPathComponent().path)
    }

    @MainActor
    func testFolderTreeRevealsAncestorAndRefreshesNewFolder() async throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        let leaf = child.appendingPathComponent("leaf", isDirectory: true)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        let tree = FolderTreeStore()
        await tree.setRoot(root, showHidden: false)
        await tree.followNavigation(to: leaf, showHidden: false)
        XCTAssertTrue(tree.rows.contains { $0.node.url.path == leaf.path })
        let created = root.appendingPathComponent("new child", isDirectory: true)
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: false)
        await tree.refreshExpandedDirectory(root)
        XCTAssertTrue(tree.rows.contains { $0.node.url.path == created.path })
        XCTAssertTrue(tree.rows.contains { $0.node.url.path == leaf.path })
    }

    @MainActor
    func testFolderTreeLateReadCannotOverwriteNewRoot() async throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let reader = DelayedTreeReader()
        let tree = FolderTreeStore(reader: reader)
        await reader.holdNextRead()
        let oldRead = Task { @MainActor in await tree.setRoot(root, showHidden: false) }
        await reader.waitUntilHeld()
        await tree.setRoot(child, showHidden: false)
        await reader.release()
        await oldRead.value
        XCTAssertEqual(tree.rootURL?.path, child.path)
        XCTAssertEqual(tree.rows.count, 1)
        XCTAssertTrue(tree.loading.isEmpty)
    }

    @MainActor
    func testFolderTreeMissingDirectoryShowsErrorAndCanCollapse() async throws {
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        let tree = FolderTreeStore()
        await tree.setRoot(missing, showHidden: false)
        XCTAssertNotNil(tree.errors[missing.standardizedFileURL])
        let row = try XCTUnwrap(tree.rows.first)
        await tree.toggle(row.node)
        XCTAssertFalse(tree.expanded.contains(row.node.url))
    }
}

private final class FoundationSettings: ExplorerSettingsStoring {
    private var settings = ExplorerSettings()
    func load() -> ExplorerSettings { settings }
    func save(_ value: ExplorerSettings) { settings = value }
}

private actor DelayedTreeReader: FileSystemServicing {
    private var hold = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func holdNextRead() { hold = true }
    func waitUntilHeld() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        if hold {
            hold = false
            await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        }
        return try await FileSystemService().contentsOfDirectory(at: url, options: options)
    }
}
