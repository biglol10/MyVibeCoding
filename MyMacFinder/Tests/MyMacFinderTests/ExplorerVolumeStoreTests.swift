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
