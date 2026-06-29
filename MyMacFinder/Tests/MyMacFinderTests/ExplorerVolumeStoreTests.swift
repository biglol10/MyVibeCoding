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
}

private struct StubVolumeService: VolumeListing {
    let result: Result<[MountedVolume], Error>

    func mountedVolumes() async throws -> [MountedVolume] {
        try result.get()
    }
}
