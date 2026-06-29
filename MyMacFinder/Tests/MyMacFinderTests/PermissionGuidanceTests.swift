import Foundation
import XCTest
@testable import MyMacFinder

final class PermissionGuidanceTests: XCTestCase {
    func testSandboxSummaryDetectsSandboxedEnvironment() {
        let sandboxed = SandboxPolicySummary.current(
            environment: ["APP_SANDBOX_CONTAINER_ID": "com.biglol.MyMacFinder"]
        )
        let unrestricted = SandboxPolicySummary.current(environment: [:])

        XCTAssertTrue(sandboxed.isSandboxed)
        XCTAssertEqual(sandboxed.statusTitle, "Sandboxed")
        XCTAssertFalse(unrestricted.isSandboxed)
        XCTAssertEqual(unrestricted.statusTitle, "Unrestricted")
    }

    func testPermissionDeniedGuidanceMentionsPathAndFullDiskAccess() {
        let guidance = PermissionGuidance(
            error: .permissionDenied("/Users/biglol/Documents"),
            sandbox: SandboxPolicySummary(isSandboxed: false)
        )

        XCTAssertEqual(guidance.primaryActionTitle, "Open Privacy Settings")
        XCTAssertTrue(guidance.message.contains("/Users/biglol/Documents"))
        XCTAssertTrue(guidance.message.contains("Full Disk Access"))
    }

    func testNonPermissionErrorsDoNotShowPrivacyAction() {
        let guidance = PermissionGuidance(
            error: .pathDoesNotExist("/missing"),
            sandbox: SandboxPolicySummary(isSandboxed: false)
        )

        XCTAssertNil(guidance.primaryActionTitle)
        XCTAssertEqual(guidance.message, "Path does not exist: /missing")
    }

    func testSandboxedPermissionDeniedPrefersChooseFolderRecovery() {
        let guidance = PermissionGuidance(
            error: .permissionDenied("/Users/biglol/Documents"),
            sandbox: SandboxPolicySummary(isSandboxed: true)
        )

        XCTAssertEqual(guidance.recoveryAction, .chooseFolder)
        XCTAssertEqual(guidance.primaryActionTitle, "Choose Folder...")
        XCTAssertTrue(guidance.message.contains("/Users/biglol/Documents"))
    }

    func testUnrestrictedPermissionDeniedUsesPrivacySettingsRecovery() {
        let guidance = PermissionGuidance(
            error: .permissionDenied("/Users/biglol/Documents"),
            sandbox: SandboxPolicySummary(isSandboxed: false)
        )

        XCTAssertEqual(guidance.recoveryAction, .openPrivacySettings)
        XCTAssertEqual(guidance.primaryActionTitle, "Open Privacy Settings")
    }

    func testNonPermissionErrorHasNoRecoveryAction() {
        let guidance = PermissionGuidance(
            error: .pathDoesNotExist("/missing"),
            sandbox: SandboxPolicySummary(isSandboxed: true)
        )

        XCTAssertEqual(guidance.recoveryAction, .none)
        XCTAssertNil(guidance.primaryActionTitle)
    }
}
