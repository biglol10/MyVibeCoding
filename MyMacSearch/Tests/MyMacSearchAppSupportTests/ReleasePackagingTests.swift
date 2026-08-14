import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testInfoPlistDeclaresReleaseBundleMetadata() throws {
        let plistURL = packageRoot()
            .appendingPathComponent("Sources/MyMacSearchApp/Resources/MyMacSearchInfo.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.biglol.MyMacSearch")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "MyMacSearchApp")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["LSApplicationCategoryType"] as? String, "public.app-category.utilities")
    }

    func testBundleBuilderSignsAndStrictlyVerifiesACompleteApp() throws {
        let script = try file("scripts/build-app-bundle.sh")

        XCTAssertTrue(script.contains("--configuration release"))
        XCTAssertTrue(script.contains("MyMacSearchInfo.plist"))
        XCTAssertTrue(script.contains("AppIcon.icns"))
        XCTAssertTrue(script.contains("codesign --force --deep --sign -"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains(".MyMacSearch.app.building"))
    }

    func testPersonalInstallerUsesRollbackSafeStaging() throws {
        let packageScript = try file("scripts/package-personal.sh")
        let installer = try file("scripts/install-personal.sh")

        XCTAssertTrue(packageScript.contains("MyMacSearch-personal-mac.zip"))
        XCTAssertTrue(packageScript.contains("unzip -tq"))
        XCTAssertTrue(packageScript.contains("check-distribution.sh"))

        XCTAssertTrue(installer.contains("MYMACSEARCH_INSTALL_DIR"))
        XCTAssertTrue(installer.contains("MYMACSEARCH_SKIP_OPEN"))
        XCTAssertTrue(installer.contains(".MyMacSearch.installing"))
        XCTAssertTrue(installer.contains(".MyMacSearch.backup"))
        XCTAssertTrue(installer.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(installer.contains("rollback"))
    }

    func testDistributionCheckComparesPackagedAndInstalledExecutableHashes() throws {
        let script = try file("scripts/check-distribution.sh")

        XCTAssertTrue(script.contains("unzip -tq"))
        XCTAssertTrue(script.contains("MYMACSEARCH_INSTALL_DIR"))
        XCTAssertTrue(script.contains("MYMACSEARCH_SKIP_OPEN=1"))
        XCTAssertTrue(script.contains("shasum -a 256"))
        XCTAssertTrue(script.contains("LC_ALL=C LANG=C shasum -a 256"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
    }

    func testReadmeDocumentsV1ScopePermissionsFiltersAndPackaging() throws {
        let readme = try file("README.md")

        for text in [
            "ext:swift", "kind:pdf", "path:Downloads", "name:report",
            "modified:today", "modified:7d", "Full Disk Access",
            "node_modules", "DerivedData", "symlink", "package bundle",
            "파일 내용", "OCR", "PDF 본문", "package-personal.sh"
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(text), "README is missing: \(text)")
        }
    }

    private func file(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
