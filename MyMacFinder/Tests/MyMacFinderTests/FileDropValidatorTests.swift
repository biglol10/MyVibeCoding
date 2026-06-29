import Foundation
import XCTest
@testable import MyMacFinder

final class FileDropValidatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderDropValidator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testRejectsEmptyDrop() {
        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [], destinationFolder: tempDirectory, operation: .copy)
        )
    }

    func testRejectsMovingItemOntoItself() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: folder, operation: .move)
        )
    }

    func testRejectsMovingFolderIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: child, operation: .move)
        )
    }

    func testRejectsCopyingFolderIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: child, operation: .copy)
        ) { error in
            XCTAssertEqual(error as? ExplorerError, .readFailed("Cannot copy a folder into itself."))
        }
    }

    func testRejectsNonDirectoryDestination() throws {
        let source = tempDirectory.appendingPathComponent("source.txt")
        let destination = tempDirectory.appendingPathComponent("destination.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "destination".write(to: destination, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [source], destinationFolder: destination, operation: .copy)
        )
    }
}
