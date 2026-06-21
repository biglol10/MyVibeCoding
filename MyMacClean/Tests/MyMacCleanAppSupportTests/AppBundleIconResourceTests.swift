import XCTest

final class AppBundleIconResourceTests: XCTestCase {
    func testAppInfoPlistDeclaresBundledIconResource() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plistURL = root.appendingPathComponent("Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist")
        let iconURL = root.appendingPathComponent("Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns")

        let plistData = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            XCTFail("MyMacCleanInfo.plist should be a dictionary")
            return
        }

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "MyMacCleanIcon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "MyMacCleanIcon.icns should exist in app resources")
    }
}
