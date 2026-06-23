import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleasePackageIncludesFirstRunHelperAndGatekeeperWorkaround() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let helperURL = root.appendingPathComponent("scripts/first-run.command")
        let installerURL = root.appendingPathComponent("scripts/install.command")
        let buildScriptURL = root.appendingPathComponent("scripts/build-app-bundle.sh")
        let dmgScriptURL = root.appendingPathComponent("scripts/create-dmg.sh")

        let helperAttributes = try FileManager.default.attributesOfItem(atPath: helperURL.path)
        let helperMode = try XCTUnwrap(helperAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(helperMode & 0o111, 0)
        let installerAttributes = try FileManager.default.attributesOfItem(atPath: installerURL.path)
        let installerMode = try XCTUnwrap(installerAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertNotEqual(installerMode & 0o111, 0)

        let helper = try String(contentsOf: helperURL, encoding: .utf8)
        XCTAssertTrue(helper.contains("MyMacClean.app"))
        XCTAssertTrue(helper.contains("xattr -cr \"$SCRIPT_DIR\""))
        XCTAssertTrue(helper.contains("xattr -dr com.apple.quarantine \"$SCRIPT_DIR\""))
        XCTAssertTrue(helper.contains("open"))
        XCTAssertTrue(helper.contains("codesign --verify --deep --strict"))

        let installer = try String(contentsOf: installerURL, encoding: .utf8)
        XCTAssertTrue(installer.contains("MyMacClean.app"))
        XCTAssertTrue(installer.contains("MYMACCLEAN_INSTALL_DIR"))
        XCTAssertTrue(installer.contains("INSTALL_DIR=\"${MYMACCLEAN_INSTALL_DIR:-/Applications}\""))
        XCTAssertTrue(installer.contains("rm -rf \"$INSTALL_APP_PATH\""))
        XCTAssertTrue(installer.contains("cp -R \"$SOURCE_APP_PATH\" \"$INSTALL_APP_PATH\""))
        XCTAssertTrue(installer.contains("xattr -cr \"$SCRIPT_DIR\""))
        XCTAssertTrue(installer.contains("xattr -cr \"$INSTALL_APP_PATH\""))
        XCTAssertTrue(installer.contains("codesign --verify --deep --strict \"$INSTALL_APP_PATH\""))
        XCTAssertTrue(installer.contains("open \"$INSTALL_APP_PATH\""))

        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        XCTAssertTrue(buildScript.contains("MACOS_SIGN_IDENTITY"))
        XCTAssertTrue(buildScript.contains("Developer ID Application"))
        XCTAssertTrue(buildScript.contains("MACOS_NOTARY_PROFILE"))
        XCTAssertTrue(buildScript.contains("xcrun notarytool submit"))
        XCTAssertTrue(buildScript.contains("xcrun stapler staple"))
        XCTAssertTrue(buildScript.contains("spctl --assess --type execute"))
        XCTAssertTrue(buildScript.contains("--options runtime"))
        XCTAssertTrue(buildScript.contains("--timestamp"))
        XCTAssertTrue(buildScript.contains("xattr -cr"))
        XCTAssertTrue(buildScript.contains("Open MyMacClean.command"))
        XCTAssertTrue(buildScript.contains("Install MyMacClean.command"))
        XCTAssertTrue(buildScript.contains("READ ME FIRST.txt"))
        XCTAssertTrue(buildScript.contains("PACKAGE_DIR=\"$DIST_DIR/MyMacClean\""))
        XCTAssertTrue(buildScript.contains("APP_DIR=\"$PACKAGE_DIR/MyMacClean.app\""))
        XCTAssertTrue(buildScript.contains("ditto -c -k"))
        XCTAssertTrue(buildScript.contains("--keepParent"))

        let dmgScript = try String(contentsOf: dmgScriptURL, encoding: .utf8)
        XCTAssertTrue(dmgScript.contains("Install MyMacClean.command"))
    }
}
