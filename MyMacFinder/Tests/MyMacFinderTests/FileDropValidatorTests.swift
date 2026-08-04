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
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
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
            XCTAssertEqual(error as? ExplorerError, .operationFailed("Cannot copy a folder into itself."))
        }
    }

    func testRejectsAlternateCaseSourcePathIntoItsDescendant() throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let folder = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        let alternateCaseSource = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(
                urls: [alternateCaseSource],
                destinationFolder: child,
                operation: .copy
            )
        ) { error in
            XCTAssertEqual(error as? ExplorerError, .operationFailed("Cannot copy a folder into itself."))
        }
    }

    func testRejectsCopyingThroughDestinationSymlinkIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        let destinationAlias = tempDirectory.appendingPathComponent("DestinationAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destinationAlias, withDestinationURL: child)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: destinationAlias, operation: .copy)
        ) { error in
            XCTAssertEqual(error as? ExplorerError, .operationFailed("Cannot copy a folder into itself."))
        }
    }

    func testRejectsMovingThroughDestinationSymlinkIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        let destinationAlias = tempDirectory.appendingPathComponent("DestinationAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destinationAlias, withDestinationURL: child)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: destinationAlias, operation: .move)
        ) { error in
            XCTAssertEqual(error as? ExplorerError, .operationFailed("Cannot move a folder into itself."))
        }
    }

    func testAllowsSourceDirectorySymlinkEntryToBeDroppedIntoItsTarget() throws {
        let target = tempDirectory.appendingPathComponent("Target", isDirectory: true)
        let sourceLink = tempDirectory.appendingPathComponent("TargetLink", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)

        XCTAssertNoThrow(
            try FileDropValidator.validate(urls: [sourceLink], destinationFolder: target, operation: .copy)
        )
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
