import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerVolumeStoreTests: XCTestCase {
    func testRefreshMountedVolumesPublishesSortedSidebarVolumes() async {
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            directoryWatcher: nil,
            volumeService: StubVolumeService(
                result: .success([
                    MountedVolume(
                        url: URL(fileURLWithPath: "/", isDirectory: true),
                        name: "Macintosh HD",
                        isLocal: true
                    ),
                    MountedVolume(
                        url: URL(fileURLWithPath: "/Volumes/Team", isDirectory: true),
                        name: "Team",
                        isLocal: false
                    )
                ])
            )
        )

        await store.refreshMountedVolumes()

        XCTAssertEqual(store.mountedVolumes.map(\.displayName), ["Team", "Macintosh HD"])
        XCTAssertNil(store.volumeError)
    }

    func testRefreshMountedVolumesStoresReadableError() async {
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            directoryWatcher: nil,
            volumeService: StubVolumeService(result: .failure(ExplorerError.permissionDenied("/Volumes")))
        )

        await store.refreshMountedVolumes()

        XCTAssertTrue(store.mountedVolumes.isEmpty)
        XCTAssertEqual(store.volumeError, .permissionDenied("/Volumes"))
    }

    func testMissingMountedVolumeClickRemovesItAndStoresReadableError() async throws {
        let root = try makeFixture()
        let missing = root.appendingPathComponent("MissingVolume", isDirectory: true)
        let volume = MountedVolume(
            url: missing,
            name: "Missing Volume",
            isLocal: false
        )
        let store = ExplorerStore(
            initialURL: root,
            directoryWatcher: nil,
            volumeService: StubVolumeService(result: .success([volume]))
        )
        await store.refreshMountedVolumes()
        store.setToolbarTextInputFocused(true)

        await store.navigateToMountedVolume(volume)

        XCTAssertEqual(store.requestedFocus, .clear)
        XCTAssertFalse(store.isToolbarTextInputFocused)
        XCTAssertEqual(store.activePane.currentURL, root.standardizedFileURL)
        XCTAssertTrue(store.mountedVolumes.isEmpty)
        XCTAssertEqual(store.volumeError, .pathDoesNotExist(missing.standardizedFileURL.path))
    }

    func testUnreadableMountedVolumeClickDoesNotNavigateAndKeepsVolumeVisible() async throws {
        let root = try makeFixture()
        let unreadable = try makeFixture()
        let volume = MountedVolume(
            url: unreadable,
            name: "Unreadable Volume",
            isLocal: false,
            isReadable: false
        )
        let store = ExplorerStore(
            initialURL: root,
            directoryWatcher: nil,
            volumeService: StubVolumeService(result: .success([volume]))
        )
        await store.refreshMountedVolumes()

        await store.navigateToMountedVolume(volume)

        XCTAssertEqual(store.activePane.currentURL, root.standardizedFileURL)
        XCTAssertEqual(store.mountedVolumes.map(\.url), [unreadable.standardizedFileURL])
        XCTAssertEqual(store.volumeError, .permissionDenied(unreadable.standardizedFileURL.path))
    }

    func testMountedVolumeNavigationChecksPathStatusOffMainThread() async throws {
        let root = try makeFixture()
        let volumeURL = try makeFixture()
        let checker = ThreadRecordingPathStatusChecker(
            statuses: [
                volumeURL.standardizedFileURL: FilePathStatus(
                    exists: true,
                    isDirectory: true,
                    isReadable: true
                )
            ]
        )
        let volume = MountedVolume(
            url: volumeURL,
            name: "Threaded Volume",
            isLocal: false
        )
        let store = ExplorerStore(
            initialURL: root,
            directoryWatcher: nil,
            volumeService: StubVolumeService(result: .success([volume])),
            pathStatusChecker: checker
        )
        await store.refreshMountedVolumes()

        await store.navigateToMountedVolume(volume)

        XCTAssertEqual(checker.recordedWasMainThread, false)
        XCTAssertEqual(store.activePane.currentURL, volumeURL.standardizedFileURL)
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderVolumeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

private struct StubVolumeService: VolumeListing {
    let result: Result<[MountedVolume], Error>

    func mountedVolumes() async throws -> [MountedVolume] {
        try result.get()
    }
}

private final class ThreadRecordingPathStatusChecker: PathStatusChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let statuses: [URL: FilePathStatus]
    private var wasMainThread: Bool?

    init(statuses: [URL: FilePathStatus]) {
        self.statuses = statuses
    }

    var recordedWasMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return wasMainThread
    }

    func status(for url: URL) async -> FilePathStatus {
        recordThread()
        return statuses[url.standardizedFileURL] ?? FilePathStatus(
            exists: false,
            isDirectory: false,
            isReadable: false
        )
    }

    private func recordThread() {
        lock.lock()
        wasMainThread = Thread.isMainThread
        lock.unlock()
    }
}
