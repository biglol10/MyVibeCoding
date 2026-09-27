import Foundation
import XCTest
@testable import MyMacFinder

final class FolderSizeServiceTests: XCTestCase {
    func testEnumerationFailureDoesNotReturnPartialSizeAsComplete() throws {
        let unreadable = tempDirectory.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 7).write(to: tempDirectory.appendingPathComponent("visible.bin"))
        try Data(repeating: 1, count: 11).write(to: unreadable.appendingPathComponent("restricted.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }
        guard !FileManager.default.isReadableFile(atPath: unreadable.path) else {
            throw XCTSkip("This account can bypass file permissions.")
        }

        XCTAssertThrowsError(try FolderSizeService().size(of: tempDirectory)) { error in
            XCTAssertTrue(error.localizedDescription.contains("fully calculated"))
        }
    }
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFolderSize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCalculatesNestedFolderSize() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 7).write(to: folder.appendingPathComponent("root.bin"))
        try Data(repeating: 2, count: 11).write(to: child.appendingPathComponent("nested.bin"))

        let service = FolderSizeService()

        XCTAssertEqual(try service.size(of: folder), 18)
    }

    func testRejectsFileInput() throws {
        let file = tempDirectory.appendingPathComponent("file.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)

        let service = FolderSizeService()

        XCTAssertThrowsError(try service.size(of: file)) { error in
            XCTAssertEqual(error as? ExplorerError, .notDirectory(file.path))
        }
    }
}
