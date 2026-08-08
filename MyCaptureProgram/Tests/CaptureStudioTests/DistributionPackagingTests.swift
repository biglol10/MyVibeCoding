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
        XCTAssertTrue(script.contains("--keychain-profile"))
        XCTAssertFalse(script.contains("--password"))
        XCTAssertFalse(script.contains("CAPTURE_STUDIO_APP_SPECIFIC_PASSWORD"))
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
        XCTAssertFalse(readme.contains("sudo scripts/install_app.sh"))
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
        XCTAssertFalse(script.contains("xattr -dr com.apple.quarantine \"$SCRIPT_DIR\""))
        XCTAssertFalse(script.contains("rm -rf \"$APP_DEST\""))
        XCTAssertTrue(script.contains("APP_BACKUP"))
        XCTAssertTrue(script.contains("APP_INSTALLING"))
        XCTAssertTrue(script.contains("Save any open capture or recording"))
        XCTAssertFalse(script.contains("tell application \"CaptureStudio\" to quit"))
        XCTAssertFalse(script.contains("pkill -x CaptureStudio"))
    }

    func testPersonalPackagingDoesNotRegisterItsStagingBundleWithLaunchServices() throws {
        let installScript = try String(contentsOf: installScriptURL, encoding: .utf8)
        let personalScript = try String(contentsOf: personalScriptURL, encoding: .utf8)

        XCTAssertTrue(installScript.contains("CAPTURE_STUDIO_SKIP_LSREGISTER"))
        XCTAssertTrue(personalScript.contains("CAPTURE_STUDIO_SKIP_LSREGISTER=1"))
    }

    func testLocalInstallBuildsWithoutRootAndReplacesTheAppTransactionally() throws {
        let script = try String(contentsOf: installScriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("EUID"))
        XCTAssertTrue(script.contains("Do not run this entire script with sudo"))
        XCTAssertFalse(script.contains("rm -rf \"$APP_BUNDLE\""))
        XCTAssertTrue(script.contains("APP_BACKUP"))
        XCTAssertTrue(script.contains("APP_INSTALLING"))
        XCTAssertTrue(script.contains("trap cleanup_staging EXIT"))
    }

    func testInstallScriptsAvoidEmptyPrivilegeArraysUnderMacOSBashNounset() throws {
        for scriptURL in [installScriptURL, personalScriptURL] {
            let script = try String(contentsOf: scriptURL, encoding: .utf8)

            XCTAssertTrue(script.contains("run_install_command()"), scriptURL.lastPathComponent)
            XCTAssertTrue(script.contains("USE_SUDO="), scriptURL.lastPathComponent)
            XCTAssertFalse(script.contains("PRIVILEGED=("), scriptURL.lastPathComponent)
            XCTAssertFalse(script.contains("${PRIVILEGED[@]}"), scriptURL.lastPathComponent)
        }
    }

    func testRepositoryDefinesSwiftPackageCIWorkflow() throws {
        let workflowURL = repositoryRoot
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("swift test"))
        XCTAssertTrue(workflow.contains("macos-"))
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

    private var installScriptURL: URL {
        repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("install_app.sh")
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
