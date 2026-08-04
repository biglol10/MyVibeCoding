import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ZipCompressionServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderZipCompress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    func testCompressesMultipleItemsIntoArchive() async throws {
        let note = tempDirectory.appendingPathComponent("note.txt")
        let image = tempDirectory.appendingPathComponent("image.png")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        try "png".write(to: image, atomically: true, encoding: .utf8)

        let result = try await ZipCompressionService().compress([note, image], to: tempDirectory)

        let archiveURL = try XCTUnwrap(result.createdURLs.first)
        XCTAssertEqual(archiveURL.lastPathComponent, "Archive.zip")
        XCTAssertEqual(archiveEntries(at: archiveURL), ["image.png", "note.txt"])
    }

    func testSingleFolderCompressionKeepsFolderRoot() async throws {
        let folder = tempDirectory.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "readme".write(to: folder.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)

        let result = try await ZipCompressionService().compress([folder], to: tempDirectory)

        let archiveURL = try XCTUnwrap(result.createdURLs.first)
        XCTAssertEqual(archiveURL.lastPathComponent, "Docs.zip")
        XCTAssertTrue(archiveEntries(at: archiveURL).contains("Docs/readme.md"))
    }

    func testCompressionUsesKeepBothForDestinationCollision() async throws {
        let note = tempDirectory.appendingPathComponent("note.txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let existingArchive = tempDirectory.appendingPathComponent("note.zip")
        try "existing".write(to: existingArchive, atomically: true, encoding: .utf8)
        let service = ZipCompressionService(conflictResolver: DefaultFileConflictResolver(decision: .keepBoth))

        let result = try await service.compress([note], to: tempDirectory)

        let archiveURL = try XCTUnwrap(result.createdURLs.first)
        XCTAssertEqual(archiveURL.lastPathComponent, "note copy.zip")
        XCTAssertEqual(try String(contentsOf: existingArchive, encoding: .utf8), "existing")
    }

    func testCompressionPreservesDanglingDestinationSymlinkAndKeepsBoth() async throws {
        let source = tempDirectory.appendingPathComponent("dangling-\(UUID().uuidString).txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let proposedArchive = tempDirectory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        try FileManager.default.createSymbolicLink(
            atPath: proposedArchive.path,
            withDestinationPath: "missing-archive-target.zip"
        )
        let service = ZipCompressionService(
            conflictResolver: DefaultFileConflictResolver(decision: .keepBoth)
        )

        let result = try await service.compress([source], to: tempDirectory)

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: proposedArchive.path),
            "missing-archive-target.zip"
        )
        XCTAssertEqual(result.createdURLs.first?.lastPathComponent, "\(source.deletingPathExtension().lastPathComponent) copy.zip")
        XCTAssertTrue(FileSystemPathIdentity.entryExists(try XCTUnwrap(result.createdURLs.first)))
    }

    func testReplaceRestoresExistingArchiveWhenCompressionFailsAfterTrash() async throws {
        let note = tempDirectory.appendingPathComponent("replace-compress-failure-\(UUID().uuidString).txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let existingArchive = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "existing archive".write(to: existingArchive, atomically: true, encoding: .utf8)
        let service = ZipCompressionService(
            conflictResolver: DeletingSourceConflictResolver(urlToDelete: note),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.compress([note], to: tempDirectory)
            XCTFail("Expected compression to fail after replacement trash step")
        } catch let error as ExplorerError {
            if case .archiveFailed = error {
                // Expected classification.
            } else {
                XCTFail("Expected archive failure, got \(error)")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: existingArchive.path))
            XCTAssertEqual(try String(contentsOf: existingArchive, encoding: .utf8), "existing archive")
        } catch {
            XCTFail("Expected archive failure, got \(error)")
        }
    }

    func testReplaceRestoresExistingArchiveWhenStagingCreationFailsAfterTrash() async throws {
        let source = tempDirectory.appendingPathComponent("staging-create-failure-\(UUID().uuidString).txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let existingArchive = tempDirectory
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-StagingFailure", isDirectory: true)
        try "existing archive".write(to: existingArchive, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let service = ZipCompressionService(
            fileManager: FailingCompressionStagingCreationFileManager(),
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.compress([source], to: tempDirectory)
            XCTFail("Expected staging creation to fail")
        } catch {
            // The original archive still must be restored.
        }

        XCTAssertEqual(try String(contentsOf: existingArchive, encoding: .utf8), "existing archive")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testReplaceReportsRollbackFailureWhenTrashedArchiveCannotBeRestored() async throws {
        let note = tempDirectory.appendingPathComponent("replace-compress-rollback-\(UUID().uuidString).txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let existingArchive = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-RollbackFailure", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "existing archive".write(to: existingArchive, atomically: true, encoding: .utf8)
        let service = ZipCompressionService(
            conflictResolver: DeletingSourceConflictResolver(urlToDelete: note),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                try FileManager.default.removeItem(at: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.compress([note], to: tempDirectory)
            XCTFail("Expected compression rollback to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(existingArchive.path))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: existingArchive.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testReplaceDoesNotTrashArchiveChangedWhileAwaitingConflictDecision() async throws {
        let note = tempDirectory.appendingPathComponent("replace-race-\(UUID().uuidString).txt")
        try "source".write(to: note, atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let displacedArchive = tempDirectory.appendingPathComponent("archive-before-decision.zip")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-ReplaceRace", isDirectory: true)
        try "original archive".write(to: archiveURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let service = ZipCompressionService(
            conflictResolver: ReplacingCompressionConflictResolver(
                destination: archiveURL,
                displacedDestination: displacedArchive
            ),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.compress([note], to: tempDirectory)
            XCTFail("Expected changed archive identity to abort replace")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }

        XCTAssertEqual(try String(contentsOf: archiveURL, encoding: .utf8), "late archive")
        XCTAssertEqual(try String(contentsOf: displacedArchive, encoding: .utf8), "original archive")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testCompressionFailurePreservesDestinationCreatedAfterConflictCheck() async throws {
        let note = tempDirectory.appendingPathComponent("partial-compress-\(UUID().uuidString).txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let injector = ZipCompressionFailureInjector(source: note, partialArchive: archiveURL)
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .compressZip, title: "Compressing"),
            onUpdate: { snapshot in await injector.injectIfNeeded(snapshot) }
        )

        do {
            _ = try await ZipCompressionService().compress([note], to: tempDirectory, progress: reporter)
            XCTFail("Expected injected compression failure")
        } catch {
            // The injected source removal must fail archive creation.
        }

        let injectionFailure = await injector.failureMessage
        XCTAssertNil(injectionFailure)
        XCTAssertEqual(try String(contentsOf: archiveURL, encoding: .utf8), "partial")
    }

    func testCompressionPreservesStagingArchiveReplacedBeforeFailedCommit() async throws {
        let note = tempDirectory.appendingPathComponent("staging-race-\(UUID().uuidString).txt")
        try "source".write(to: note, atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        let recorder = CompressionStagingReplacementRecorder()
        let fileManager = ReplacingCompressionStagingFileManager(
            finalDestination: archiveURL,
            recorder: recorder
        )

        do {
            _ = try await ZipCompressionService(fileManager: fileManager).compress([note], to: tempDirectory)
            XCTFail("Expected staged archive commit to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("staging"))
        }

        let replacedStagingURL = try XCTUnwrap(recorder.url)
        XCTAssertEqual(try String(contentsOf: replacedStagingURL, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(archiveURL))
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "source")
    }

    func testCompressionWriteFailureIsNotReportedAsReadFailure() async throws {
        let missing = tempDirectory.appendingPathComponent("missing-source.txt")

        do {
            _ = try await ZipCompressionService().compress([missing], to: tempDirectory)
            XCTFail("Expected compression to fail for a missing source")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .pathDoesNotExist(missing.path))
        }
    }

    func testCompressionReportsArchiveWritingPhase() async throws {
        let source = tempDirectory.appendingPathComponent("source.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let recorder = ZipCompressionProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .compressZip, title: "Compressing"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        _ = try await ZipCompressionService().compress([source], to: tempDirectory, progress: reporter)

        let snapshots = await recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.phase == .writingArchive })
    }

    private func archiveEntries(at url: URL) -> [String] {
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
            return []
        }
        return archive.map(\.path).sorted()
    }
}

private actor ZipCompressionProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}

private actor ZipCompressionFailureInjector {
    private let source: URL
    private let partialArchive: URL
    private(set) var failureMessage: String?
    private var didInject = false

    init(source: URL, partialArchive: URL) {
        self.source = source
        self.partialArchive = partialArchive
    }

    func injectIfNeeded(_ snapshot: FileOperationProgressSnapshot) {
        guard !didInject, snapshot.phase == .writingArchive else {
            return
        }
        didInject = true
        do {
            try Data("partial".utf8).write(to: partialArchive)
            try FileManager.default.removeItem(at: source)
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}

private struct DeletingSourceConflictResolver: FileConflictResolving {
    var urlToDelete: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try? FileManager.default.removeItem(at: urlToDelete)
        return .replace
    }
}

private struct ReplacingCompressionConflictResolver: FileConflictResolving {
    var destination: URL
    var displacedDestination: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try FileManager.default.moveItem(at: destination, to: displacedDestination)
        try "late archive".write(to: destination, atomically: true, encoding: .utf8)
        return .replace
    }
}

private final class CompressionStagingReplacementRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedURL: URL?

    var url: URL? {
        lock.lock()
        defer { lock.unlock() }
        return recordedURL
    }

    func record(_ url: URL) {
        lock.lock()
        recordedURL = url
        lock.unlock()
    }
}

private final class ReplacingCompressionStagingFileManager: FileManager, @unchecked Sendable {
    private let finalDestination: URL
    private let recorder: CompressionStagingReplacementRecorder

    init(finalDestination: URL, recorder: CompressionStagingReplacementRecorder) {
        self.finalDestination = finalDestination.standardizedFileURL
        self.recorder = recorder
        super.init()
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        guard destination.standardizedFileURL == finalDestination else {
            try super.moveItem(at: source, to: destination)
            return
        }
        try super.removeItem(at: source)
        try "unrelated".write(to: source, atomically: true, encoding: .utf8)
        recorder.record(source)
        throw CocoaError(.fileWriteFileExists)
    }
}

private final class FailingCompressionStagingCreationFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        guard url.lastPathComponent.hasPrefix(".MyMacFinder-compress-") else {
            try super.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
            return
        }
        throw CocoaError(.fileWriteNoPermission)
    }
}
