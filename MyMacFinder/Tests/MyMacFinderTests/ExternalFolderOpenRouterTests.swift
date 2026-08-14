import Foundation
import XCTest
@testable import MyMacFinder

final class ExternalFolderOpenRouterTests: XCTestCase {
    func testAcceptsExistingDirectoryAndStandardizesURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = try ExternalFolderOpenRouter().validate(
            directory.appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent(directory.lastPathComponent, isDirectory: true)
        )

        XCTAssertEqual(result, directory.standardizedFileURL)
    }

    func testRejectsRegularFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)

        XCTAssertThrowsError(try ExternalFolderOpenRouter().validate(file)) { error in
            XCTAssertEqual(error as? ExternalFolderOpenError, .notDirectory(file.path))
        }
    }

    func testRejectsNonFileURL() {
        let url = URL(string: "https://example.com/folder")!
        XCTAssertThrowsError(try ExternalFolderOpenRouter().validate(url)) { error in
            XCTAssertEqual(error as? ExternalFolderOpenError, .notFileURL)
        }
    }
}
