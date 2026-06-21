import XCTest
@testable import MyMacCleanCore

final class PermissionCoordinatorTests: XCTestCase {
    func testClassifiesPermissionDeniedErrors() {
        let status = PermissionCoordinator().status(for: CocoaError(.fileReadNoPermission))

        XCTAssertEqual(status, .fullDiskAccessRecommended)
    }

    func testReturnsActionableFullDiskAccessGuidance() {
        let guidance = PermissionCoordinator().fullDiskAccessGuidance(appName: "MyMacClean")

        XCTAssertTrue(guidance.contains("System Settings"))
        XCTAssertTrue(guidance.contains("Full Disk Access"))
        XCTAssertTrue(guidance.contains("MyMacClean"))
    }
}
