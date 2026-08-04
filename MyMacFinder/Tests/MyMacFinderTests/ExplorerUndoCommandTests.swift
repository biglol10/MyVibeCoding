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
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    @MainActor
    func testUndoCreateFolderMovesCreatedFolderToTrash() async throws {
        let trash = try UndoTrashHarness(root: tempDirectory.appendingPathComponent("Trash-Create", isDirectory: true))
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileOperationService: FileOperationService(trashItem: { try trash.moveToTrash($0) }),
            directoryWatcher: nil
        )
        await store.refresh()
        await store.perform(.newFolder)

        XCTAssertTrue(store.canUndo)
        await store.perform(.undo)

        XCTAssertFalse(store.activePane.entries.contains { $0.name == "Untitled Folder" })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).count, 1)
    }

    @MainActor
    func testUndoCreateRefusesToTrashUnrelatedReplacementAtRecordedPath() async throws {
        let trash = try UndoTrashHarness(root: tempDirectory.appendingPathComponent("Trash-Create-Identity", isDirectory: true))
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileOperationService: FileOperationService(trashItem: { try trash.moveToTrash($0) }),
            directoryWatcher: nil
        )
        await store.refresh()
        await store.perform(.newFolder)
        let createdFolder = tempDirectory.appendingPathComponent("Untitled Folder", isDirectory: true)
        XCTAssertTrue(FileSystemPathIdentity.entryExists(createdFolder))

        try FileManager.default.removeItem(at: createdFolder)
        try "unrelated".write(to: createdFolder, atomically: true, encoding: .utf8)
        await store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: createdFolder, encoding: .utf8), "unrelated")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).isEmpty)
        XCTAssertEqual(trash.moveCount, 0)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.visibleError?.localizedDescription.contains("changed") == true)
    }

    @MainActor
    func testUndoDoesNotClaimLiveOutputWhenExtractorOmitsOwnership() async throws {
        let zipURL = tempDirectory.appendingPathComponent("missing-ownership.zip")
        let extracted = tempDirectory.appendingPathComponent("missing-ownership", isDirectory: true)
        let extractedFile = extracted.appendingPathComponent("output.txt")
        try "zip data".write(to: zipURL, atomically: true, encoding: .utf8)
        let extractor = MissingOwnershipZipExtractor(output: extracted, file: extractedFile)
        let trash = try UndoTrashHarness(
            root: tempDirectory.appendingPathComponent("Trash-MissingOwnership", isDirectory: true)
        )
        let store = ExplorerStore(
            initialURL: tempDirectory,
            fileOperationService: FileOperationService(trashItem: { try trash.moveToTrash($0) }),
            directoryWatcher: nil,
            zipExtractor: extractor
        )
        await store.refresh()
        store.updateSelection([zipURL.standardizedFileURL])

        await store.perform(.extractZip)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(try String(contentsOf: extractedFile, encoding: .utf8), "created without ownership")

        await store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: extractedFile, encoding: .utf8), "created without ownership")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).isEmpty)
        XCTAssertEqual(trash.moveCount, 0)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.visibleError?.localizedDescription.contains("ownership is unavailable") == true)
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
    func testUndoRenameRefusesToMoveUnrelatedReplacementAtRenamedPath() async throws {
        let original = tempDirectory.appendingPathComponent("owned-old.txt")
        let renamed = tempDirectory.appendingPathComponent("owned-new.txt")
        try "owned".write(to: original, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([original.standardizedFileURL])
        await store.renameSelected(to: renamed.lastPathComponent)

        try FileManager.default.removeItem(at: renamed)
        try "unrelated".write(to: renamed, atomically: true, encoding: .utf8)
        await store.perform(.undo)

        XCTAssertFalse(FileSystemPathIdentity.entryExists(original))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "unrelated")
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.visibleError?.localizedDescription.contains("changed") == true)
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

    @MainActor
    func testUndoCopyReplaceRemovesCopiedItemBeforeRestoringReplacedDestination() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let destinationFile = destFolder.appendingPathComponent("note.txt")
        try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "old".write(to: destinationFile, atomically: true, encoding: .utf8)
        let trash = try UndoTrashHarness(root: tempDirectory.appendingPathComponent("Trash-CopyReplace", isDirectory: true))
        let store = ExplorerStore(
            initialURL: sourceFolder,
            fileOperationService: FileOperationService(
                conflictResolver: DefaultFileConflictResolver(decision: .replace),
                trashItem: { try trash.moveToTrash($0) }
            ),
            directoryWatcher: nil
        )
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        await store.perform(.paste)
        XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "new")

        await store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "old")
    }

    @MainActor
    func testUndoCopyUsesCreationTimeIdentityWhenEarlierBatchOutputIsReplacedBeforeCompletion() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("Source-BatchOwnership", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("Destination-BatchOwnership", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let firstSource = sourceFolder.appendingPathComponent("first.txt")
        let secondSource = sourceFolder.appendingPathComponent("second.txt")
        let firstDestination = destinationFolder.appendingPathComponent("first.txt")
        let secondDestination = destinationFolder.appendingPathComponent("second.txt")
        try "first".write(to: firstSource, atomically: true, encoding: .utf8)
        try "second".write(to: secondSource, atomically: true, encoding: .utf8)
        let trash = try UndoTrashHarness(
            root: tempDirectory.appendingPathComponent("Trash-BatchOwnership", isDirectory: true)
        )
        let commitSequence = ReplacingFirstCopyDuringSecondCommit(firstDestination: firstDestination)
        let store = ExplorerStore(
            initialURL: sourceFolder,
            fileOperationService: FileOperationService(
                trashItem: { try trash.moveToTrash($0) },
                moveItemAction: commitSequence.move
            ),
            directoryWatcher: nil
        )
        await store.refresh()
        store.updateSelection([firstSource.standardizedFileURL, secondSource.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destinationFolder)
        await store.perform(.paste)
        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: secondDestination, encoding: .utf8), "second")

        await store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: secondDestination, encoding: .utf8), "second")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).isEmpty)
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.visibleError?.localizedDescription.contains("changed") == true)
    }

    @MainActor
    func testCompoundUndoPreflightStopsBeforeFirstChangeWhenLaterSourceIsMissing() async throws {
        let setup = try await makeCopyReplacementScenario(named: "Preflight")
        let replacement = try XCTUnwrap(replacementRecord(in: setup.store.undoStack.last))
        try FileManager.default.removeItem(at: replacement.trashed)

        await setup.store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: setup.destinationFile, encoding: .utf8), "new")
        XCTAssertTrue(setup.store.canUndo)
        XCTAssertTrue(setup.store.visibleError?.localizedDescription.contains(replacement.trashed.path) == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: setup.trash.root.path).isEmpty)
    }

    @MainActor
    func testCompoundUndoRollsBackCompletedStepAfterTOCTOUSourceDisappears() async throws {
        let setup = try await makeCopyReplacementScenario(named: "TOCTOU")
        let replacement = try XCTUnwrap(replacementRecord(in: setup.store.undoStack.last))
        setup.trash.onNextMove = { _, _ in
            try FileManager.default.removeItem(at: replacement.trashed)
        }

        await setup.store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: setup.destinationFile, encoding: .utf8), "new")
        XCTAssertTrue(setup.store.canUndo)
        XCTAssertTrue(setup.store.visibleError?.localizedDescription.contains(replacement.trashed.path) == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: setup.trash.root.path).isEmpty)
    }

    @MainActor
    func testCompoundUndoReportsRollbackIncompleteAndRestoresUndoStack() async throws {
        let setup = try await makeCopyReplacementScenario(named: "RollbackFailure")
        let replacement = try XCTUnwrap(replacementRecord(in: setup.store.undoStack.last))
        setup.trash.onNextMove = { _, _ in
            try FileManager.default.removeItem(at: replacement.trashed)
            try "blocking replacement".write(
                to: setup.destinationFile,
                atomically: true,
                encoding: .utf8
            )
        }

        await setup.store.perform(.undo)

        XCTAssertEqual(try String(contentsOf: setup.destinationFile, encoding: .utf8), "blocking replacement")
        XCTAssertTrue(setup.store.canUndo)
        XCTAssertTrue(setup.store.visibleError?.localizedDescription.contains("rollback was incomplete") == true)
        XCTAssertTrue(setup.store.visibleError?.localizedDescription.contains(setup.destinationFile.path) == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: setup.trash.root.path).count, 1)
    }

    @MainActor
    func testUndoCaseOnlyRenameRestoresOriginalDirectoryEntryCasing() async throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let original = tempDirectory.appendingPathComponent("report.txt")
        try "report".write(to: original, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([original.standardizedFileURL])

        await store.renameSelected(to: "REPORT.txt")
        await store.perform(.undo)

        let directoryNames = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertTrue(directoryNames.contains("report.txt"))
        XCTAssertFalse(directoryNames.contains("REPORT.txt"))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "report")
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    func testUndoTrashRestoresRelativeSymlinkThatIsDanglingInSimulatedTrash() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("RelativeSymlinkUndo", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let target = sourceFolder.appendingPathComponent("target.txt")
        let link = sourceFolder.appendingPathComponent("target-link")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target.txt")
        let trash = try UndoTrashHarness(
            root: tempDirectory.appendingPathComponent("Trash-RelativeSymlink", isDirectory: true)
        )
        let store = ExplorerStore(
            initialURL: sourceFolder,
            fileOperationService: FileOperationService(trashItem: { try trash.moveToTrash($0) }),
            directoryWatcher: nil
        )
        await store.refresh()
        store.updateSelection([link.standardizedFileURL])

        await store.perform(.moveToTrash)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).count, 1)

        await store.perform(.undo)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "target.txt")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.root.path).isEmpty)
        XCTAssertNil(store.visibleError)
    }

    @MainActor
    private func makeCopyReplacementScenario(named name: String) async throws -> CopyReplacementScenario {
        let sourceFolder = tempDirectory.appendingPathComponent("Source-\(name)", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("Destination-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let destinationFile = destinationFolder.appendingPathComponent("note.txt")
        try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "old".write(to: destinationFile, atomically: true, encoding: .utf8)
        let trash = try UndoTrashHarness(
            root: tempDirectory.appendingPathComponent("Trash-\(name)", isDirectory: true)
        )
        let store = ExplorerStore(
            initialURL: sourceFolder,
            fileOperationService: FileOperationService(
                conflictResolver: DefaultFileConflictResolver(decision: .replace),
                trashItem: { try trash.moveToTrash($0) }
            ),
            directoryWatcher: nil
        )
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])
        await store.perform(.copy)
        await store.navigate(to: destinationFolder)
        await store.perform(.paste)
        XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "new")

        return CopyReplacementScenario(
            store: store,
            destinationFile: destinationFile,
            trash: trash
        )
    }

    private func replacementRecord(in action: FileUndoAction?) -> FileTrashRecord? {
        guard case .compound(_, let actions) = action else { return nil }
        for action in actions {
            if case .restoreReplacements(let records) = action {
                return records.first
            }
        }
        return nil
    }
}

private struct CopyReplacementScenario {
    var store: ExplorerStore
    var destinationFile: URL
    var trash: UndoTrashHarness
}

private final class UndoTrashHarness: @unchecked Sendable {
    let root: URL
    var onNextMove: ((URL, URL) throws -> Void)?
    private let lock = NSLock()
    private var nextIndex = 0

    var moveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextIndex
    }

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func moveToTrash(_ source: URL) throws -> URL {
        lock.lock()
        let index = nextIndex
        nextIndex += 1
        let callback = onNextMove
        onNextMove = nil
        lock.unlock()

        let destination = root.appendingPathComponent("\(index)-\(source.lastPathComponent)")
        try FileManager.default.moveItem(at: source, to: destination)
        try callback?(source, destination)
        return destination
    }
}

private final class ReplacingFirstCopyDuringSecondCommit: @unchecked Sendable {
    private let firstDestination: URL
    private let lock = NSLock()
    private var callCount = 0

    init(firstDestination: URL) {
        self.firstDestination = firstDestination
    }

    func move(_ source: URL, to destination: URL) throws {
        lock.lock()
        callCount += 1
        let call = callCount
        lock.unlock()

        if call == 2 {
            try FileManager.default.removeItem(at: firstDestination)
            try "unrelated".write(to: firstDestination, atomically: true, encoding: .utf8)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

private final class MissingOwnershipZipExtractor: ZipExtracting, @unchecked Sendable {
    private let output: URL
    private let file: URL

    init(output: URL, file: URL) {
        self.output = output
        self.file = file
    }

    func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "created without ownership".write(to: file, atomically: true, encoding: .utf8)
        return FileOperationResult(createdURLs: [output])
    }
}
