import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
private final class TestDirectoryWatcher: DirectoryWatching {
    private(set) var watchedURLs: [URL] = []
    private var onChange: (@Sendable () -> Void)?

    func startWatching(_ urls: [URL], onChange: @escaping @Sendable () -> Void) {
        watchedURLs.append(contentsOf: urls.map(\.standardizedFileURL))
        self.onChange = onChange
    }

    func stopWatching() {
        onChange = nil
    }

    func triggerChange() {
        onChange?()
    }
}

final class ExplorerStoreWatcherTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderWatcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testLoadInitialDirectoryStartsWatcher() async {
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: InMemoryExplorerWatcherSettingsStore(),
            directoryWatcher: watcher,
            watcherDebounceNanoseconds: 0
        )

        await store.loadInitialDirectory()

        XCTAssertEqual(watcher.watchedURLs.map(\.path), [tempDirectory.standardizedFileURL.path])
    }

    @MainActor
    func testNavigateRestartsWatcherForNewFolder() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: InMemoryExplorerWatcherSettingsStore(),
            directoryWatcher: watcher,
            watcherDebounceNanoseconds: 0
        )

        await store.loadInitialDirectory()
        await store.navigate(to: child)

        XCTAssertEqual(watcher.watchedURLs.map(\.path), [
            tempDirectory.standardizedFileURL.path,
            child.standardizedFileURL.path
        ])
    }

    @MainActor
    func testWatcherChangeRefreshesEntries() async throws {
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: InMemoryExplorerWatcherSettingsStore(),
            directoryWatcher: watcher,
            watcherDebounceNanoseconds: 0
        )
        await store.loadInitialDirectory()

        let externalFile = tempDirectory.appendingPathComponent("external.txt")
        try "external".write(to: externalFile, atomically: true, encoding: .utf8)
        watcher.triggerChange()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "external.txt" })
    }

    @MainActor
    func testWatcherChangeRefreshesInactiveVisiblePane() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(
            initialURL: tempDirectory,
            settingsStore: InMemoryExplorerWatcherSettingsStore(),
            directoryWatcher: watcher,
            watcherDebounceNanoseconds: 0
        )
        await store.loadInitialDirectory()
        await store.setPaneMode(.dual)
        store.activatePane(at: 1)
        await store.navigate(to: child)
        store.activatePane(at: 0)

        let externalFile = child.appendingPathComponent("external-in-child.txt")
        try "external".write(to: externalFile, atomically: true, encoding: .utf8)
        watcher.triggerChange()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.panes[1].entries.contains { $0.name == "external-in-child.txt" })
    }
}

private final class InMemoryExplorerWatcherSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
