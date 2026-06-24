import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleasePackageIncludesFirstRunHelperAndGatekeeperWorkaround() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperURL = packageRoot.appendingPathComponent("scripts/first-run.command")
        let buildScriptURL = packageRoot.appendingPathComponent("scripts/build-app-bundle.sh")

        let helperAttributes = try FileManager.default.attributesOfItem(atPath: helperURL.path)
        let helperMode = try XCTUnwrap(helperAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(helperMode & 0o111, 0)

        let helper = try String(contentsOf: helperURL, encoding: .utf8)
        XCTAssertTrue(helper.contains("MyMacStats.app"))
        XCTAssertTrue(helper.contains("MYMACSTATS_INSTALL_DIR:-/Applications"))
        XCTAssertTrue(helper.contains("ditto --rsrc --extattr"))
        XCTAssertTrue(helper.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(helper.contains("open \"$INSTALLED_APP_PATH\""))
        XCTAssertTrue(helper.contains("pkill -x MyMacStatsApp"))
        XCTAssertFalse(helper.contains("osascript"))

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
        let checkScript = try String(contentsOf: checkScriptURL, encoding: .utf8)

        XCTAssertTrue(checkScript.contains("com.apple.quarantine"))
        XCTAssertTrue(checkScript.contains("ditto -x -k"))
        XCTAssertTrue(checkScript.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(checkScript.contains("spctl --assess --type execute"))
    }
}
