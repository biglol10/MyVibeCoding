import Foundation
import XCTest
@testable import MyMacFinder

final class FolderSizeServiceTests: XCTestCase {
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
