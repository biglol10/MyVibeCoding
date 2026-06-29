import Foundation
import XCTest
@testable import MyMacFinder

final class FileSearchServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testRecursiveSearchFindsNestedEntriesAndSkipsHiddenWhenDisabled() async throws {
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        let hidden = tempDirectory.appendingPathComponent(".Hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try "top".write(to: tempDirectory.appendingPathComponent("TopReport.txt"), atomically: true, encoding: .utf8)
        try "deep".write(to: nested.appendingPathComponent("DeepReport.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: hidden.appendingPathComponent("HiddenReport.txt"), atomically: true, encoding: .utf8)

        let results = try await FileSearchService().search(
            in: tempDirectory,
            criteria: FileEntrySearchCriteria(query: "report", kind: .files),
            options: DirectoryReadOptions(showHiddenFiles: false)
        )

        XCTAssertEqual(results.map(\.name), ["DeepReport.txt", "TopReport.txt"])
    }

    func testRecursiveSearchCanFilterFolders() async throws {
        let reportFolder = tempDirectory.appendingPathComponent("Report Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: reportFolder, withIntermediateDirectories: true)
        try "report".write(to: tempDirectory.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)

        let results = try await FileSearchService().search(
            in: tempDirectory,
            criteria: FileEntrySearchCriteria(query: "report", kind: .folders),
            options: DirectoryReadOptions(showHiddenFiles: true)
        )

        XCTAssertEqual(results.map(\.name), ["Report Folder"])
    }
}
