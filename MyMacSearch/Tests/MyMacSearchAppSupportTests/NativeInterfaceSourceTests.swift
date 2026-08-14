import Foundation
import XCTest

final class NativeInterfaceSourceTests: XCTestCase {
    func testPackageDeclaresNativeExecutableAndUtilityViews() throws {
        let root = packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"))
        XCTAssertTrue(manifest.contains(".executable(name: \"MyMacSearchApp\""))

        let searchRoot = try source("Views/SearchRootView.swift")
        XCTAssertTrue(searchRoot.contains("TextField(\"Search files and folders\""))
        XCTAssertTrue(searchRoot.contains("SearchResultsTable"))
        XCTAssertTrue(searchRoot.contains("IndexStatusBar"))

        let resultsTable = try source("Views/SearchResultsTable.swift")
        for column in ["Name", "Path", "Kind", "Size", "Modified"] {
            XCTAssertTrue(resultsTable.contains("TableColumn(\"\(column)\""))
        }
    }

    func testV1InterfaceDoesNotOfferContentSearchOrDestructiveActions() throws {
        let appSource = try allAppSource()
        XCTAssertFalse(appSource.localizedCaseInsensitiveContains("OCR"))
        XCTAssertFalse(appSource.localizedCaseInsensitiveContains("search file contents"))
        XCTAssertFalse(appSource.contains("Move to Trash"))
        XCTAssertFalse(appSource.contains("Delete File"))
    }

    func testIndexCenterExposesHealthWithoutReplacingSearchTool() throws {
        let appSource = try allAppSource()
        XCTAssertTrue(appSource.contains("IndexCenterView"))
        XCTAssertTrue(appSource.contains("Verify Index"))
        XCTAssertTrue(appSource.contains("Rescan"))
        XCTAssertTrue(appSource.contains("Indexed Entries"))
        XCTAssertTrue(appSource.contains("Last Completed Scan"))
        XCTAssertTrue(try source("Views/SearchRootView.swift").contains("SearchResultsTable"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/MyMacSearchApp")
                .appendingPathComponent(relativePath)
        )
    }

    private func allAppSource() throws -> String {
        let root = packageRoot().appendingPathComponent("Sources/MyMacSearchApp")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        return try files.map { try String(contentsOf: root.appendingPathComponent($0)) }
            .joined(separator: "\n")
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
