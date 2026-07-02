import Darwin
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

    func testCopyItemsPreflightsSourcesBeforeCopyingAnyItem() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let missing = sourceFolder.appendingPathComponent("missing.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        do {
            _ = try await service.copyItems([first, missing], to: destFolder)
            XCTFail("Expected copy to fail before copying any item")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .pathDoesNotExist(missing.path))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("first.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
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

    func testCopyItemsReportsByteProgressFromManifest() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("a.bin")
        let second = sourceFolder.appendingPathComponent("b.bin")
        try Data(repeating: 1, count: 4).write(to: first)
        try Data(repeating: 1, count: 6).write(to: second)
        let recorder = FileOperationProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        _ = try await FileOperationService().copyItems([first, second], to: destFolder, progress: reporter)

        let snapshots = await recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 0 && $0.totalBytes == 10 })
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 4 && $0.totalBytes == 10 })
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 10 && $0.totalBytes == 10 })
    }

    func testCopySingleFileReportsIntermediateByteProgress() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("large.bin")
        try Data(repeating: 1, count: 10).write(to: source)
        let recorder = FileOperationProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        _ = try await FileOperationService(copyChunkSize: 4).copyItems([source], to: destFolder, progress: reporter)

        let snapshots = await recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 4 && $0.totalBytes == 10 && $0.completedUnitCount == 0 })
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 8 && $0.totalBytes == 10 && $0.completedUnitCount == 0 })
        XCTAssertTrue(snapshots.contains { $0.completedBytes == 10 && $0.totalBytes == 10 && $0.completedUnitCount == 1 })
    }

    func testCopyItemsStopsBeforeCopyingWhenProgressIsCancelledAfterStartUpdate() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("cancel.txt")
        try "cancel".write(to: source, atomically: true, encoding: .utf8)
        let canceller = ProgressCanceller()
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await canceller.cancelOnce(snapshot: snapshot) }
        )
        await canceller.setReporter(reporter)

        do {
            _ = try await FileOperationService().copyItems([source], to: destFolder, progress: reporter)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("cancel.txt").path))
        }
    }

    func testCopySingleFileCanBeCancelledDuringStreamingCopy() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("cancel-during-copy.bin")
        try Data(repeating: 1, count: 10).write(to: source)
        let destination = destFolder.appendingPathComponent(source.lastPathComponent)
        let canceller = ByteThresholdProgressCanceller(cancelAtCompletedBytes: 4)
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in await canceller.cancelIfNeeded(snapshot: snapshot) }
        )
        await canceller.setReporter(reporter)

        do {
            _ = try await FileOperationService(copyChunkSize: 4).copyItems([source], to: destFolder, progress: reporter)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
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

    func testMoveItemsPreflightsSourcesBeforeMovingAnyItem() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let missing = sourceFolder.appendingPathComponent("missing.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        do {
            _ = try await service.moveItems([first, missing], to: destFolder)
            XCTFail("Expected move to fail before moving any item")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .pathDoesNotExist(missing.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("first.txt").path))
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

    func testMoveToTrashPreflightsSourcesBeforeTrashingAnyItem() async throws {
        let first = tempDirectory.appendingPathComponent("trash-preflight-\(UUID().uuidString).txt")
        let missing = tempDirectory.appendingPathComponent("missing-trash.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        let trashCandidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(first.lastPathComponent)
        defer {
            if !FileManager.default.fileExists(atPath: first.path),
               FileManager.default.fileExists(atPath: trashCandidate.path) {
                try? FileManager.default.moveItem(at: trashCandidate, to: first)
            }
        }
        let service = FileOperationService()

        do {
            _ = try await service.moveToTrash([first, missing])
            XCTFail("Expected trash to fail before moving any item")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .pathDoesNotExist(missing.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testMoveToTrashRestoresAlreadyTrashedItemsWhenLaterTrashFails() async throws {
        let first = tempDirectory.appendingPathComponent("first.txt")
        let second = tempDirectory.appendingPathComponent("second.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let service = FileOperationService(trashItem: { url in
            if url == second {
                throw ExplorerError.readFailed("trash failed")
            }
            let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })

        do {
            _ = try await service.moveToTrash([first, second])
            XCTFail("Expected trash failure")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .readFailed("trash failed"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: simulatedTrash.appendingPathComponent("first.txt").path))
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

    func testCopyReplaceRestoresExistingDestinationWhenCopyFailsAfterTrash() async throws {
        let itemName = "replace-copy-failure-\(UUID().uuidString)"
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceDir = sourceFolder.appendingPathComponent(itemName, isDirectory: true)
        let unreadableFile = sourceDir.appendingPathComponent("unreadable.txt")
        let existingDest = destFolder.appendingPathComponent(itemName, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "new".write(to: unreadableFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(unreadableFile.path, 0), 0)
        try FileManager.default.createDirectory(at: existingDest, withIntermediateDirectories: true)
        try "old".write(to: existingDest.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        let trashCandidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(itemName, isDirectory: true)
        defer {
            _ = chmod(unreadableFile.path, S_IRUSR | S_IWUSR)
            if !FileManager.default.fileExists(atPath: existingDest.path),
               FileManager.default.fileExists(atPath: trashCandidate.path) {
                try? FileManager.default.moveItem(at: trashCandidate, to: existingDest)
            }
            try? FileManager.default.removeItem(at: trashCandidate)
        }
        let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

        do {
            _ = try await service.copyItems([sourceDir], to: destFolder)
            XCTFail("Expected copy to fail after replacement trash step")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: existingDest.path))
            XCTAssertEqual(
                try String(contentsOf: existingDest.appendingPathComponent("old.txt"), encoding: .utf8),
                "old"
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: existingDest.appendingPathComponent("unreadable.txt").path))
        }
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

private actor ProgressCanceller {
    private var didCancel = false
    private var reporter: FileOperationProgressReporter?

    func setReporter(_ reporter: FileOperationProgressReporter) {
        self.reporter = reporter
    }

    func cancelOnce(snapshot: FileOperationProgressSnapshot) async {
        guard !didCancel, snapshot.phase == .running else {
            return
        }
        guard let reporter else {
            return
        }
        didCancel = true
        await reporter.cancel()
    }
}

private actor ByteThresholdProgressCanceller {
    private let cancelAtCompletedBytes: Int64
    private var didCancel = false
    private var reporter: FileOperationProgressReporter?

    init(cancelAtCompletedBytes: Int64) {
        self.cancelAtCompletedBytes = cancelAtCompletedBytes
    }

    func setReporter(_ reporter: FileOperationProgressReporter) {
        self.reporter = reporter
    }

    func cancelIfNeeded(snapshot: FileOperationProgressSnapshot) async {
        guard !didCancel,
              snapshot.phase == .running,
              let completedBytes = snapshot.completedBytes,
              completedBytes >= cancelAtCompletedBytes,
              completedBytes < (snapshot.totalBytes ?? completedBytes) else {
            return
        }
        guard let reporter else {
            return
        }
        didCancel = true
        await reporter.cancel()
    }
}
