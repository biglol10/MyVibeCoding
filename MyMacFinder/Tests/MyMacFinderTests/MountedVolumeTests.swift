import Foundation
import XCTest
@testable import MyMacFinder

final class MountedVolumeTests: XCTestCase {
    func testDisplayNameFallsBackToLastPathComponent() {
        let volume = MountedVolume(
            url: URL(fileURLWithPath: "/Volumes/Team Share", isDirectory: true),
            name: ""
        )

        XCTAssertEqual(volume.displayName, "Team Share")
    }

    func testSystemImageSeparatesNetworkRemovableAndLocalVolumes() {
        let network = MountedVolume(
            url: URL(fileURLWithPath: "/Volumes/Network", isDirectory: true),
            name: "Network",
            isLocal: false
        )
        let removable = MountedVolume(
            url: URL(fileURLWithPath: "/Volumes/USB", isDirectory: true),
            name: "USB",
            isLocal: true,
            isRemovable: true
        )
        let local = MountedVolume(
            url: URL(fileURLWithPath: "/", isDirectory: true),
            name: "Macintosh HD",
            isLocal: true,
            isRemovable: false
        )

        XCTAssertEqual(network.systemImageName, "network")
        XCTAssertEqual(removable.systemImageName, "externaldrive")
        XCTAssertEqual(local.systemImageName, "internaldrive")
    }

    func testSidebarSortingPutsNetworkVolumesBeforeLocalVolumes() {
        let volumes = [
            MountedVolume(
                url: URL(fileURLWithPath: "/", isDirectory: true),
                name: "Macintosh HD",
                isLocal: true
            ),
            MountedVolume(
                url: URL(fileURLWithPath: "/Volumes/Project", isDirectory: true),
                name: "Project",
                isLocal: false
            ),
            MountedVolume(
                url: URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true),
                name: "Backup",
                isLocal: true,
                isRemovable: true
            )
        ]

        XCTAssertEqual(
            MountedVolume.sortedForSidebar(volumes).map(\.displayName),
            ["Project", "Backup", "Macintosh HD"]
        )
    }
}
