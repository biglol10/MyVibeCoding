import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerUndoCommandTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderUndo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testUndoCreateFolderMovesCreatedFolderToTrash() async {
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        await store.perform(.newFolder)

        XCTAssertTrue(store.canUndo)
        await store.perform(.undo)

        XCTAssertFalse(store.activePane.entries.contains { $0.name == "Untitled Folder" })
    }

    @MainActor
    func testUndoRenameRestoresOriginalName() async throws {
        let file = tempDirectory.appendingPathComponent("old.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.renameSelected(to: "new.txt")
        await store.perform(.undo)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "old.txt" })
        XCTAssertFalse(store.activePane.entries.contains { $0.name == "new.txt" })
    }

    @MainActor
    func testUndoMoveRestoresMovedFile() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let file = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.cut)
        await store.navigate(to: destFolder)
        await store.perform(.paste)
        await store.perform(.undo)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("move.txt").path))
    }
}
