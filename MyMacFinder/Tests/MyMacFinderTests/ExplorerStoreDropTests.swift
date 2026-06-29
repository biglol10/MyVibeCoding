import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerStoreDropTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderStoreDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testPerformDropCopiesFilesIntoCurrentFolder() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        try "note".write(to: sourceFile, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: destFolder)
        await store.refresh()

        await store.performDrop(urls: [sourceFile], destinationFolder: destFolder, operation: .copy)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "note.txt" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    @MainActor
    func testPerformDropMovesFilesIntoFolderDestination() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: sourceFile, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()

        await store.performDrop(urls: [sourceFile], destinationFolder: destFolder, operation: .move)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("move.txt").path))
    }

    @MainActor
    func testPerformDropRejectsInvalidDescendantMove() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()

        await store.performDrop(urls: [folder], destinationFolder: child, operation: .move)

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Cannot move"))
    }

    @MainActor
    func testPerformDropRejectsInvalidDescendantCopy() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()

        await store.performDrop(urls: [folder], destinationFolder: child, operation: .copy)

        XCTAssertFalse(FileManager.default.fileExists(atPath: child.appendingPathComponent("Folder").path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Cannot copy"))
    }
}
