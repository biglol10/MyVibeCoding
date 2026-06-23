import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleasePackageIncludesFirstRunHelperForExecutableBuild() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let helperURL = root.appendingPathComponent("scripts/first-run.command")
        let buildScriptURL = root.appendingPathComponent("scripts/build-release-zip.sh")

        let helperAttributes = try FileManager.default.attributesOfItem(atPath: helperURL.path)
        let helperMode = try XCTUnwrap(helperAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(helperMode & 0o111, 0)

        let helper = try String(contentsOf: helperURL, encoding: .utf8)
        XCTAssertTrue(helper.contains("CaptureStudio"))
        XCTAssertTrue(helper.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(helper.contains("\"$EXECUTABLE_PATH\""))

        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        XCTAssertTrue(buildScript.contains("MACOS_SIGN_IDENTITY"))
        XCTAssertTrue(buildScript.contains("xattr -cr"))
        XCTAssertTrue(buildScript.contains("처음 실행하기.command"))
        XCTAssertTrue(buildScript.contains("PACKAGE_DIR=\"$DIST_DIR/CaptureStudio\""))
        XCTAssertTrue(buildScript.contains("ditto -c -k"))
        XCTAssertTrue(buildScript.contains("--keepParent"))
    }
}
