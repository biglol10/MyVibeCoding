import Foundation
import XCTest
@testable import MyMacFinder

final class FileOperationServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderOps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCreatesUniquelyNamedFolder() async throws {
        let service = FileOperationService()
        let first = try await service.createFolder(in: tempDirectory).createdURLs[0]
        let second = try await service.createFolder(in: tempDirectory).createdURLs[0]

        XCTAssertEqual(first.lastPathComponent, "Untitled Folder")
        XCTAssertEqual(second.lastPathComponent, "Untitled Folder 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testRenamesItem() async throws {
        let file = tempDirectory.appendingPathComponent("old.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        let result = try await service.rename(file, to: "new.txt")
        let renamed = try XCTUnwrap(result.renamedItem?.destination)

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameRejectsPathSeparatorsInNewName() async throws {
        let file = tempDirectory.appendingPathComponent("old.txt")
        let nested = tempDirectory.appendingPathComponent("Nested", isDirectory: true)
        try "text".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let service = FileOperationService()

        do {
            _ = try await service.rename(file, to: "Nested/new.txt")
            XCTFail("Expected rename with path separator to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .invalidPath("Nested/new.txt"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.appendingPathComponent("new.txt").path))
    }

    func testDuplicateKeepsBothNames() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        let duplicate = try await service.duplicate(file).createdURLs[0]

        XCTAssertEqual(duplicate.lastPathComponent, "note copy.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicate.path))
    }

    func testCopyItemsUsesKeepBothCollisionName() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        try "one".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "two".write(to: existingDest, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.copyItems([sourceFile], to: destFolder)
        let copied = result.createdURLs

        XCTAssertEqual(copied.map(\.lastPathComponent), ["note copy.txt"])
        XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "two")
        XCTAssertEqual(try String(contentsOf: copied[0], encoding: .utf8), "one")
    }

    func testCopyItemsInSameFolderNeverReplacesSourceItself() async throws {
        let sourceFile = tempDirectory.appendingPathComponent("note.txt")
        try "original".write(to: sourceFile, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

        let result = try await service.copyItems([sourceFile], to: tempDirectory)
        let copied = try XCTUnwrap(result.createdURLs.first)

        XCTAssertEqual(copied.lastPathComponent, "note copy.txt")
        XCTAssertTrue(result.replacedItems.isEmpty)
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "original")
    }

    func testCopyItemsRejectsCopyingFolderIntoDescendant() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "source".write(to: folder.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        let service = FileOperationService()

        do {
            _ = try await service.copyItems([folder], to: child)
            XCTFail("Expected copying a folder into its descendant to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .readFailed("Cannot copy a folder into itself."))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: child.appendingPathComponent("Folder").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source.txt").path))
    }

    func testCopyItemsReportsProgressPerSource() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("a.txt")
        let second = sourceFolder.appendingPathComponent("b.txt")
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "b".write(to: second, atomically: true, encoding: .utf8)
        let recorder = FileOperationProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        _ = try await FileOperationService().copyItems([first, second], to: destFolder, progress: reporter)

        let snapshots = await recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 1 && $0.currentItemName == "a.txt" })
        XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 2 && $0.currentItemName == "b.txt" })
    }

    func testMoveItemsRemovesOriginal() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: sourceFile, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.moveItems([sourceFile], to: destFolder)
        let moved = result.movedItems.map(\.destination)

        XCTAssertEqual(moved.map(\.lastPathComponent), ["move.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved[0].path))
    }

    func testMoveItemsWithinSameFolderIsNoOp() async throws {
        let sourceFile = tempDirectory.appendingPathComponent("same-folder.txt")
        try "same".write(to: sourceFile, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.moveItems([sourceFile], to: tempDirectory)

        XCTAssertEqual(result.movedItems, [])
        XCTAssertEqual(result.skippedURLs, [sourceFile.standardizedFileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("same-folder copy.txt").path))
    }

    func testMoveItemsRejectsMovingFolderIntoDescendant() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let service = FileOperationService()

        do {
            _ = try await service.moveItems([folder], to: child)
            XCTFail("Expected moving a folder into its descendant to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .readFailed("Cannot move a folder into itself."))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
    }

    func testMoveToTrashRemovesOriginalAndReturnsTrashLocation() async throws {
        let sourceFile = tempDirectory.appendingPathComponent("trash-me.txt")
        try "trash".write(to: sourceFile, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let result = try await service.moveToTrash([sourceFile])
        let trashedURLs = result.trashedItems.map(\.trashed)
        defer {
            for url in trashedURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        XCTAssertEqual(trashedURLs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURLs[0].path))
    }

    func testCopyItemsReplacesExistingFileWhenResolverChoosesReplace() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "old".write(to: existingDest, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

        let result = try await service.copyItems([sourceFile], to: destFolder)
        defer {
            for item in result.replacedItems {
                try? FileManager.default.removeItem(at: item.trashed)
            }
        }

        XCTAssertEqual(result.createdURLs, [existingDest.standardizedFileURL])
        XCTAssertEqual(result.replacedItems.map(\.original), [existingDest.standardizedFileURL])
        XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: result.replacedItems[0].trashed, encoding: .utf8), "old")
    }

    func testCopyItemsSkipsExistingFileWhenResolverChoosesSkip() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "old".write(to: existingDest, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .skip))

        let result = try await service.copyItems([sourceFile], to: destFolder)

        XCTAssertEqual(result.createdURLs, [])
        XCTAssertEqual(result.skippedURLs, [sourceFile.standardizedFileURL])
        XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "old")
    }

    func testMoveItemsCanKeepBothOnCollision() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        try "moved".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "existing".write(to: existingDest, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .keepBoth))

        let result = try await service.moveItems([sourceFile], to: destFolder)

        XCTAssertEqual(result.movedItems.first?.source, sourceFile.standardizedFileURL)
        XCTAssertEqual(result.movedItems.first?.destination.lastPathComponent, "note copy.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "existing")
    }

    func testRenameCanReplaceExistingFile() async throws {
        let oldFile = tempDirectory.appendingPathComponent("old.txt")
        let existing = tempDirectory.appendingPathComponent("new.txt")
        try "old content".write(to: oldFile, atomically: true, encoding: .utf8)
        try "existing content".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

        let result = try await service.rename(oldFile, to: "new.txt")
        defer {
            for item in result.replacedItems {
                try? FileManager.default.removeItem(at: item.trashed)
            }
        }

        XCTAssertEqual(result.renamedItem?.source, oldFile.standardizedFileURL)
        XCTAssertEqual(result.renamedItem?.destination, existing.standardizedFileURL)
        XCTAssertEqual(result.replacedItems.map(\.original), [existing.standardizedFileURL])
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old content")
        XCTAssertEqual(try String(contentsOf: result.replacedItems[0].trashed, encoding: .utf8), "existing content")
    }
}

private actor FileOperationProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}
