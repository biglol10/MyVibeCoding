import Foundation
import XCTest
@testable import MyMacSearchAppSupport

final class VolumeAvailabilityMonitorTests: XCTestCase {
    func testDifferentVolumeAtSameMountPathRequiresExplicitRecovery() async {
        let checker = VolumeAvailabilityChecker(client: FakeVolumeClient(reachable: true, uuid: "new"))

        let state = await checker.availability(rootPath: "/Volumes/Work", expectedVolumeUUID: "old")

        XCTAssertEqual(state, .identityMismatch(actualUUID: "new"))
    }

    func testMissingRootIsOfflineWithoutInspectingIdentity() async {
        let checker = VolumeAvailabilityChecker(client: FakeVolumeClient(reachable: false, uuid: "old"))

        let state = await checker.availability(rootPath: "/Volumes/Work", expectedVolumeUUID: "old")

        XCTAssertEqual(state, .offline)
    }

    func testMissingExpectedIdentityRequiresExplicitRecovery() async {
        let checker = VolumeAvailabilityChecker(client: FakeVolumeClient(reachable: true, uuid: "actual"))

        let state = await checker.availability(rootPath: "/Volumes/Work", expectedVolumeUUID: nil)

        XCTAssertEqual(state, .identityMismatch(actualUUID: "actual"))
    }
}

private struct FakeVolumeClient: VolumeResourceReading {
    let reachable: Bool
    let uuid: String?

    func resource(for rootPath: String) -> VolumeResource {
        VolumeResource(isReachable: reachable, volumeUUID: uuid)
    }
}
