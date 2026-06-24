import AppKit
import XCTest

final class AppBundleIconTests: XCTestCase {
    func testMacAppIconAssetsExistAtRequiredSizes() throws {
        let root = repositoryRoot
        let resourcesURL = root.appendingPathComponent("Resources")
        let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset")

        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("AppIcon.icns").path))

        let expectedImages: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1_024)
        ]

        for expectedImage in expectedImages {
            let imageURL = iconsetURL.appendingPathComponent(expectedImage.name)
            let imageData = try Data(contentsOf: imageURL)
            let image = try XCTUnwrap(NSBitmapImageRep(data: imageData))

            XCTAssertEqual(image.pixelsWide, expectedImage.pixels, expectedImage.name)
            XCTAssertEqual(image.pixelsHigh, expectedImage.pixels, expectedImage.name)
        }
    }

    func testInstallScriptCopiesAndRegistersBundleIcon() throws {
        let scriptURL = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("install_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("Contents/Resources"))
        XCTAssertTrue(script.contains("AppIcon.icns"))
        XCTAssertTrue(script.contains("CFBundleIconFile"))
        XCTAssertTrue(script.contains("<string>AppIcon.icns</string>"))
        XCTAssertTrue(script.contains("CFBundleIconName"))
        XCTAssertTrue(script.contains("lsregister"))
        XCTAssertTrue(script.contains("touch \"$APP_BUNDLE\""))
    }

    func testInstallScriptUsesStableCodeSigningIdentityForTCC() throws {
        let scriptURL = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("install_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("CAPTURE_STUDIO_CODE_SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("security find-identity -v -p codesigning"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign \"$SIGN_IDENTITY\" \"$APP_BUNDLE\""))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
