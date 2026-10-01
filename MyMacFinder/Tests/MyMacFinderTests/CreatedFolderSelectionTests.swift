import Foundation
import XCTest
@testable import MyMacFinder

final class CreatedFolderSelectionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // Reproduce the real app's /Users/Shared path. /var aliases can mask URL flag differences.
        root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
            .appendingPathComponent("CreatedFolderSelection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testNewFolderUsesSameDirectoryURLAsLoadedRow() async throws {
        let store = ExplorerStore(initialURL: root, settingsStore: SelectionTestSettingsStore(), directoryWatcher: nil)
        await store.refresh()

        await store.perform(.newFolder)

        let entry = try XCTUnwrap(store.activePane.entries.first { $0.name == "Untitled Folder" })
        XCTAssertEqual(store.activePane.selectedURLs, [entry.url])
        XCTAssertEqual(store.inlineRenameRequest?.url, entry.url)
        XCTAssertEqual(store.activeSelectedEntries.map(\.name), ["Untitled Folder"])
    }

    @MainActor
    func testRenamedFolderRemainsSelectedUsingLoadedDirectoryURL() async throws {
        let folder = root.appendingPathComponent("Old Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let store = ExplorerStore(initialURL: root, settingsStore: SelectionTestSettingsStore(), directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([try XCTUnwrap(store.activePane.entries.first).url])

        await store.renameSelected(to: "Renamed Folder")

        let entry = try XCTUnwrap(store.activePane.entries.first { $0.name == "Renamed Folder" })
        XCTAssertEqual(store.activePane.selectedURLs, [entry.url])
        XCTAssertEqual(store.activeSelectedEntries.map(\.name), ["Renamed Folder"])
    }

    @MainActor
    func testWatcherRefreshDuringCreationCannotDiscardSelectionAndRename() async throws {
        let reader = SuspendedSelectionDirectoryReader()
        let watcher = SelectionDirectoryWatcher()
        let store = ExplorerStore(
            initialURL: root,
            fileSystemService: reader,
            settingsStore: SelectionTestSettingsStore(),
            directoryWatcher: watcher,
            watcherDebounceNanoseconds: 0
        )
        await store.refresh()
        await reader.suspendNextRead()
        let creation = Task { @MainActor in await store.perform(.newFolder) }
        await reader.waitUntilSuspended()

        // An external edit and the app's own create can trigger the same watcher.
        let external = root.appendingPathComponent("external change.txt")
        try Data("concurrent edit".utf8).write(to: external)
        watcher.trigger()
        try await Task.sleep(nanoseconds: 50_000_000)
        let duringMutationReadCount = await reader.readCount
        XCTAssertEqual(duringMutationReadCount, 2, "Watcher must defer instead of superseding the mutation's read")
        await reader.resume()
        await creation.value
        try await Task.sleep(nanoseconds: 100_000_000)

        let entry = try XCTUnwrap(store.activePane.entries.first { $0.name == "Untitled Folder" })
        XCTAssertEqual(store.activePane.selectedURLs, [entry.url])
        XCTAssertEqual(store.inlineRenameRequest?.url, entry.url)
        XCTAssertTrue(store.activePane.entries.contains { $0.name == "external change.txt" })
        let finalReadCount = await reader.readCount
        XCTAssertGreaterThanOrEqual(finalReadCount, 3, "Deferred external refresh must still run")
    }

}


@MainActor
private final class SelectionDirectoryWatcher: DirectoryWatching {
    private var callback: (@Sendable () -> Void)?
    func startWatching(_ urls: [URL], onChange: @escaping @Sendable () -> Void) { callback = onChange }
    func stopWatching() { callback = nil }
    func trigger() { callback?() }
}

private actor SuspendedSelectionDirectoryReader: FileSystemServicing {
    private(set) var readCount = 0
    private var shouldSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func suspendNextRead() { shouldSuspend = true }
    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        readCount += 1
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil }
        }
        return try await FileSystemService().contentsOfDirectory(at: url, options: options)
    }
}

private final class SelectionTestSettingsStore: ExplorerSettingsStoring {
    private var settings = ExplorerSettings()
    func load() -> ExplorerSettings { settings }
    func save(_ value: ExplorerSettings) { settings = value }
}
