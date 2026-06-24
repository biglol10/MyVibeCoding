import XCTest

final class DistributionPackagingTests: XCTestCase {
    func testReleasePackagingScriptRequiresDeveloperIDAndNotarization() throws {
        let script = try String(contentsOf: releaseScriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Developer ID Application"))
        XCTAssertTrue(script.contains("CAPTURE_STUDIO_DEVELOPER_ID"))
        XCTAssertFalse(script.contains("Apple Development:"))
        XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
        XCTAssertTrue(script.contains("xcrun notarytool submit"))
        XCTAssertTrue(script.contains("xcrun stapler staple"))
        XCTAssertTrue(script.contains("xcrun stapler validate"))
    }

    func testReleasePackagingScriptUsesHardenedRuntimeTimestampEntitlementsAndGatekeeperAssessment() throws {
        let script = try String(contentsOf: releaseScriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("--options runtime"))
        XCTAssertTrue(script.contains("--timestamp"))
        XCTAssertTrue(script.contains("--entitlements"))
        XCTAssertTrue(script.contains("CaptureStudio.entitlements"))
        XCTAssertTrue(script.contains("spctl -a -vvv -t execute"))
        XCTAssertTrue(script.contains("ditto -c -k --sequesterRsrc --keepParent"))
    }

    func testReleaseEntitlementsPermitMicrophoneForHardenedRuntime() throws {
        let entitlements = try String(contentsOf: entitlementsURL, encoding: .utf8)

        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"))
        XCTAssertTrue(entitlements.contains("<true/>"))
    }

    func testReadmeDocumentsNotarizedReleasePackagingInsteadOfDevelopmentZip() throws {
        let readme = try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)

        XCTAssertTrue(readme.contains("scripts/package_release.sh"))
        XCTAssertTrue(readme.contains("scripts/package_personal.sh"))
        XCTAssertTrue(readme.contains("Developer ID Application"))
        XCTAssertTrue(readme.contains("notarization"))
        XCTAssertTrue(readme.contains("Do not upload"))
    }

    func testPersonalPackagingScriptCreatesInstallerThatClearsQuarantineAndInstallsToApplications() throws {
        let script = try String(contentsOf: personalScriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Install CaptureStudio.command"))
        XCTAssertTrue(script.contains("CAPTURE_STUDIO_CODE_SIGN_IDENTITY=\"-\""))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign -"))
        XCTAssertTrue(script.contains("/Applications/CaptureStudio.app"))
        XCTAssertTrue(script.contains("LaunchServices.framework"))
        XCTAssertTrue(script.contains("CaptureStudio-personal-mac.zip"))
    }

    private var releaseScriptURL: URL {
        repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("package_release.sh")
    }

    private var personalScriptURL: URL {
        repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("package_personal.sh")
    }

    private var entitlementsURL: URL {
        repositoryRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("CaptureStudio.entitlements")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
