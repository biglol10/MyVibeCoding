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
        XCTAssertTrue(helper.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(helper.contains("open"))

        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        XCTAssertTrue(buildScript.contains("MACOS_SIGN_IDENTITY"))
        XCTAssertTrue(buildScript.contains("xattr -cr"))
        XCTAssertTrue(buildScript.contains("처음 실행하기.command"))
        XCTAssertTrue(buildScript.contains("PACKAGE_DIR=\"$DIST_DIR/MyMacStats\""))
        XCTAssertTrue(buildScript.contains("APP_DIR=\"$PACKAGE_DIR/MyMacStats.app\""))
        XCTAssertTrue(buildScript.contains("ditto -c -k"))
        XCTAssertTrue(buildScript.contains("--keepParent"))
    }
}
