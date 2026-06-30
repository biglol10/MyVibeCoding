import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleasePackageIncludesFirstRunHelperAndGatekeeperWorkaround() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperURL = packageRoot.appendingPathComponent("scripts/first-run.command")
        let installerURL = packageRoot.appendingPathComponent("scripts/install.command")
        let buildScriptURL = packageRoot.appendingPathComponent("scripts/build-app-bundle.sh")

        let helperAttributes = try FileManager.default.attributesOfItem(atPath: helperURL.path)
        let helperMode = try XCTUnwrap(helperAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(helperMode & 0o111, 0)
        let installerAttributes = try FileManager.default.attributesOfItem(atPath: installerURL.path)
        let installerMode = try XCTUnwrap(installerAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(installerMode & 0o111, 0)

        let helper = try String(contentsOf: helperURL, encoding: .utf8)
        XCTAssertTrue(helper.contains("MyMacStats.app"))
        XCTAssertTrue(helper.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(helper.contains("open \"$APP_PATH\""))
        XCTAssertFalse(helper.contains("osascript"))

        let installer = try String(contentsOf: installerURL, encoding: .utf8)
        XCTAssertTrue(installer.contains("MyMacStats.app"))
        XCTAssertTrue(installer.contains("MYMACSTATS_INSTALL_DIR:-/Applications"))
        XCTAssertTrue(installer.contains("ditto --rsrc --extattr"))
        XCTAssertTrue(installer.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(installer.contains("open \"$INSTALLED_APP_PATH\""))
        XCTAssertTrue(installer.contains("pkill -x MyMacStatsApp"))
        XCTAssertFalse(installer.contains("osascript"))

        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        XCTAssertTrue(buildScript.contains("MACOS_SIGN_IDENTITY"))
        XCTAssertTrue(buildScript.contains("--deploy-personal"))
        XCTAssertTrue(buildScript.contains("xattr -cr"))
        XCTAssertTrue(buildScript.contains("처음 실행하기.command"))
        XCTAssertTrue(buildScript.contains("Install MyMacStats.command"))
        XCTAssertTrue(buildScript.contains("PACKAGE_DIR=\"$DIST_DIR/MyMacStats\""))
        XCTAssertTrue(buildScript.contains("APP_DIR=\"$PACKAGE_DIR/MyMacStats.app\""))
        XCTAssertTrue(buildScript.contains("ditto -c -k"))
        XCTAssertTrue(buildScript.contains("--keepParent"))
    }

    func testReleaseBuildRequiresDeveloperIDNotarizationAndGatekeeperVerification() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScriptURL = packageRoot.appendingPathComponent("scripts/build-app-bundle.sh")
        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)

        XCTAssertTrue(buildScript.contains("--release"))
        XCTAssertTrue(buildScript.contains("Developer ID Application"))
        XCTAssertTrue(buildScript.contains("MACOS_NOTARY_PROFILE"))
        XCTAssertTrue(buildScript.contains("--options runtime"))
        XCTAssertTrue(buildScript.contains("--timestamp"))
        XCTAssertTrue(buildScript.contains("notarytool submit"))
        XCTAssertTrue(buildScript.contains("stapler staple"))
        XCTAssertTrue(buildScript.contains("stapler validate"))
        XCTAssertTrue(buildScript.contains("spctl --assess --type execute"))
    }

    func testDistributionCheckSimulatesDownloadedAppGatekeeperAssessment() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let checkScriptURL = packageRoot.appendingPathComponent("scripts/check-distribution.sh")
        let installerURL = packageRoot.appendingPathComponent("scripts/install.command")
        let checkScript = try String(contentsOf: checkScriptURL, encoding: .utf8)
        let installer = try String(contentsOf: installerURL, encoding: .utf8)

        XCTAssertTrue(checkScript.contains("com.apple.quarantine"))
        XCTAssertTrue(checkScript.contains("ditto -x -k"))
        XCTAssertTrue(checkScript.contains("MYMACSTATS_INSTALL_DIR"))
        XCTAssertTrue(checkScript.contains("MYMACSTATS_SKIP_OPEN=1"))
        XCTAssertTrue(checkScript.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(checkScript.contains("spctl --assess --type execute"))
        XCTAssertTrue(checkScript.contains("--release"))
        XCTAssertTrue(installer.contains("MYMACSTATS_SKIP_OPEN"))
    }
}
