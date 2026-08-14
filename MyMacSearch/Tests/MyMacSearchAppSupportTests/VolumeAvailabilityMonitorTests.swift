import Foundation
import XCTest
@testable import MyMacSearchAppSupport

final class VolumeAvailabilityMonitorTests: XCTestCase {
    func testDifferentVolumeAtSameMountPathRequiresExplicitRecovery() {
        let checker = VolumeAvailabilityChecker(client: FakeVolumeClient(reachable: true, uuid: "new"))

        let state = checker.availability(rootPath: "/Volumes/Work", expectedVolumeUUID: "old")

        XCTAssertEqual(state, .identityMismatch(actualUUID: "new"))
    }

    func testMissingRootIsOfflineWithoutInspectingIdentity() {
        let checker = VolumeAvailabilityChecker(client: FakeVolumeClient(reachable: false, uuid: "old"))

        let state = checker.availability(rootPath: "/Volumes/Work", expectedVolumeUUID: "old")

        XCTAssertEqual(state, .offline)
    }
}

private struct FakeVolumeClient: VolumeResourceReading {
    let reachable: Bool
    let uuid: String?

    func resource(for rootPath: String) -> VolumeResource {
        VolumeResource(isReachable: reachable, volumeUUID: uuid)
    }
}
