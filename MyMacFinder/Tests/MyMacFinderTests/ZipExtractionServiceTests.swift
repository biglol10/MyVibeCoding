import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ZipExtractionServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderExtract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        }
    }

    func testExtractsZipIntoNamedFolder() async throws {
        let zipURL = try makeArchive(named: "sample.zip")
        let service = ZipExtractionService()

        let result = try await service.extract([zipURL], to: tempDirectory)

        let extractedFolder = tempDirectory.appendingPathComponent("sample", isDirectory: true)
        XCTAssertEqual(result.createdURLs, [extractedFolder.standardizedFileURL])
        XCTAssertEqual(
            try String(contentsOf: extractedFolder.appendingPathComponent("docs/readme.txt"), encoding: .utf8),
            "hello"
        )
    }

    func testExtractionUsesKeepBothForDestinationCollision() async throws {
        let zipURL = try makeArchive(named: "sample.zip")
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("sample", isDirectory: true),
            withIntermediateDirectories: true
        )
        let service = ZipExtractionService(conflictResolver: DefaultFileConflictResolver(decision: .keepBoth))

        let result = try await service.extract([zipURL], to: tempDirectory)

        XCTAssertEqual(result.createdURLs.first?.lastPathComponent, "sample copy")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("sample copy/docs/readme.txt").path
            )
        )
    }

    func testExtractionPreservesDanglingDestinationSymlinkAndKeepsBoth() async throws {
        let archiveName = "dangling-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let proposedFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: proposedFolder.path,
            withDestinationPath: "missing-extraction-target"
        )
        let service = ZipExtractionService(
            conflictResolver: DefaultFileConflictResolver(decision: .keepBoth)
        )

        let result = try await service.extract([zipURL], to: tempDirectory)

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: proposedFolder.path),
            "missing-extraction-target"
        )
        XCTAssertEqual(result.createdURLs.first?.lastPathComponent, "\(archiveName) copy")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("\(archiveName) copy/docs/readme.txt").path
            )
        )
    }

    func testExtractionFailurePreservesDestinationCreatedAfterConflictCheck() async throws {
        let archiveName = "late-extraction-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let destination = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let marker = destination.appendingPathComponent("unrelated.txt")
        let fileManager = LateExtractionDestinationFileManager(
            destination: destination,
            marker: marker
        )

        do {
            _ = try await ZipExtractionService(fileManager: fileManager).extract([zipURL], to: tempDirectory)
            XCTFail("Expected late extraction destination conflict")
        } catch {
            // The service must fail without deleting the unrelated late-created directory.
        }

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destination.appendingPathComponent("docs/readme.txt")))
    }

    func testExtractionPreservesUnverifiedStagingEntryCreatedBeforeIdentityCapture() async throws {
        let archiveName = "staging-preidentity-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let finalDestination = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let recorder = ExtractionStagingReplacementRecorder()
        let fileManager = PreIdentityExtractionStagingFileManager(recorder: recorder)

        do {
            _ = try await ZipExtractionService(fileManager: fileManager).extract([zipURL], to: tempDirectory)
            XCTFail("Expected extraction staging mutation to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("staging"))
        }

        let unverifiedStagingURL = try XCTUnwrap(recorder.url)
        XCTAssertEqual(try String(contentsOf: unverifiedStagingURL, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(finalDestination))
    }

    func testExtractionRollbackUsesStagedSnapshotWhenPublishedOutputChangesBeforeCommitReturns() async throws {
        let archiveName = "published-change-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let brokenZip = tempDirectory.appendingPathComponent("broken-after-publish-\(UUID().uuidString).zip")
        try "not a zip".write(to: brokenZip, atomically: true, encoding: .utf8)
        let extractionFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let extractedFile = extractionFolder.appendingPathComponent("docs/readme.txt")
        let fileManager = MutatingPublishedExtractionFileManager(
            destination: extractionFolder,
            publishedFile: extractedFile
        )

        do {
            _ = try await ZipExtractionService(fileManager: fileManager)
                .extract([zipURL, brokenZip], to: tempDirectory)
            XCTFail("Expected the broken second archive to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(extractionFolder.path))
        }

        XCTAssertEqual(try String(contentsOf: extractedFile, encoding: .utf8), "user modified")
    }

    func testExtractionRollbackDoesNotDeletePathReplacementInstalledAfterSnapshotCheck() async throws {
        let archiveName = "quarantine-race-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let brokenZip = tempDirectory.appendingPathComponent("broken-quarantine-\(UUID().uuidString).zip")
        try "not a zip".write(to: brokenZip, atomically: true, encoding: .utf8)
        let extractionFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let displaced = tempDirectory.appendingPathComponent("owned-\(archiveName)", isDirectory: true)
        let marker = extractionFolder.appendingPathComponent("unrelated.txt")
        let fileManager = SwappingExtractionRollbackOutputFileManager(
            destination: extractionFolder,
            displaced: displaced,
            marker: marker
        )

        do {
            _ = try await ZipExtractionService(fileManager: fileManager)
                .extract([zipURL, brokenZip], to: tempDirectory)
            XCTFail("Expected the broken second archive to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(extractionFolder.path))
        }

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "unrelated")
        XCTAssertEqual(
            try String(contentsOf: displaced.appendingPathComponent("docs/readme.txt"), encoding: .utf8),
            "hello"
        )
    }

    func testExtractionRejectsOutputReplacedBeforeCommitReturnsAndPreservesReplacement() async throws {
        let archiveName = "published-replacement-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let extractionFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let replacementMarker = extractionFolder.appendingPathComponent("unrelated.txt")
        let fileManager = ReplacingPublishedExtractionFileManager(
            destination: extractionFolder,
            marker: replacementMarker
        )

        do {
            _ = try await ZipExtractionService(fileManager: fileManager).extract([zipURL], to: tempDirectory)
            XCTFail("Expected destination identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(extractionFolder.path))
        }

        XCTAssertEqual(try String(contentsOf: replacementMarker, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(extractionFolder.appendingPathComponent("docs/readme.txt")))
    }

    func testExtractionReportsProgressForArchiveEntries() async throws {
        let zipURL = try makeArchive(named: "sample.zip")
        let recorder = ZipProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .extractZip, title: "Extracting"),
            onUpdate: { snapshot in await recorder.append(snapshot) }
        )

        _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory, progress: reporter)

        let snapshots = await recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.totalUnitCount == 1 })
        XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 1 })
    }

    func testInvalidZipDoesNotLeaveExtractionFolder() async throws {
        let zipURL = tempDirectory.appendingPathComponent("broken.zip")
        try "not a zip".write(to: zipURL, atomically: true, encoding: .utf8)

        do {
            _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory)
            XCTFail("Expected invalid ZIP extraction to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("ZIP archive could not be read"))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("broken", isDirectory: true).path
            )
        )
    }

    func testInvalidZipDoesNotReplaceExistingDestinationFolder() async throws {
        let zipURL = tempDirectory.appendingPathComponent("sample.zip")
        try "not a zip".write(to: zipURL, atomically: true, encoding: .utf8)
        let existingFolder = tempDirectory.appendingPathComponent("sample", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "keep".write(
            to: existingFolder.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = ZipExtractionService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

        do {
            _ = try await service.extract([zipURL], to: tempDirectory)
            XCTFail("Expected invalid ZIP extraction to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("ZIP archive could not be read"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFolder.path))
        XCTAssertEqual(
            try String(contentsOf: existingFolder.appendingPathComponent("keep.txt"), encoding: .utf8),
            "keep"
        )
    }

    func testUnsafeZipEntryDoesNotLeavePartialExtractionFolder() async throws {
        let zipURL = try makeArchive(
            named: "unsafe.zip",
            entries: [
                ("safe.txt", "safe"),
                ("../evil.txt", "evil")
            ]
        )

        do {
            _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory)
            XCTFail("Expected unsafe ZIP extraction to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("outside destination"))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("unsafe", isDirectory: true).path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("evil.txt").path))
    }

    func testExtractionRejectsEntryNestedBelowArchiveSymlinkWithoutTouchingExternalTarget() async throws {
        let externalFolder = tempDirectory.appendingPathComponent("External-\(UUID().uuidString)", isDirectory: true)
        let externalFile = externalFolder.appendingPathComponent("victim.txt")
        try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: false)
        try "original".write(to: externalFile, atomically: true, encoding: .utf8)

        let archiveURL = tempDirectory.appendingPathComponent("symlink-escape-\(UUID().uuidString).zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try addEntry(path: "pivot", type: .symlink, contents: externalFolder.path, to: archive)
        try addEntry(path: "pivot/victim.txt", type: .file, contents: "attacker", to: archive)

        do {
            _ = try await ZipExtractionService().extract([archiveURL], to: tempDirectory)
            XCTFail("Expected an archive entry below a symlink to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("symbolic link"),
                error.localizedDescription
            )
        }

        XCTAssertEqual(try String(contentsOf: externalFile, encoding: .utf8), "original")
        XCTAssertFalse(
            FileSystemPathIdentity.entryExists(
                tempDirectory.appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent)
            )
        )
    }

    func testExtractionRejectsFileEntryThatReusesArchiveSymlinkPath() async throws {
        let externalFile = tempDirectory.appendingPathComponent("external-file-\(UUID().uuidString).txt")
        try "original".write(to: externalFile, atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory.appendingPathComponent("symlink-reuse-\(UUID().uuidString).zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try addEntry(path: "pivot", type: .symlink, contents: externalFile.path, to: archive)
        try addEntry(path: "pivot", type: .file, contents: "attacker", to: archive)

        do {
            _ = try await ZipExtractionService().extract([archiveURL], to: tempDirectory)
            XCTFail("Expected a duplicate entry at a symlink path to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("symbolic link"),
                error.localizedDescription
            )
        }

        XCTAssertEqual(try String(contentsOf: externalFile, encoding: .utf8), "original")
    }

    func testUnsafeZipEntryFailureIsNotReportedAsReadFailure() async throws {
        let zipURL = try makeArchive(
            named: "unsafe-classification.zip",
            entries: [
                ("safe.txt", "safe"),
                ("../evil.txt", "evil")
            ]
        )

        do {
            _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory)
            XCTFail("Expected unsafe ZIP extraction to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(
                error,
                .archiveFailed("ZIP entry attempted to extract outside destination: ../evil.txt")
            )
        }
    }

    func testExtractionFailureRemovesPartialDestinationFolder() async throws {
        let zipURL = try makeArchive(
            named: "partial.zip",
            entries: [
                ("blocked", "file"),
                ("blocked/nested.txt", "nested")
            ]
        )

        do {
            _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory)
            XCTFail("Expected extraction to fail")
        } catch let error as ExplorerError {
            if case .archiveFailed = error {
                // Expected classification.
            } else {
                XCTFail("Expected archive failure, got \(error)")
            }
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: tempDirectory.appendingPathComponent("partial", isDirectory: true).path
                )
            )
        } catch {
            XCTFail("Expected archive failure, got \(error)")
        }
    }

    func testMultiArchiveExtractionRollsBackEarlierSuccessWhenLaterArchiveFails() async throws {
        let firstName = "first-\(UUID().uuidString)"
        let secondName = "second-\(UUID().uuidString)"
        let firstArchive = try makeArchive(named: "\(firstName).zip")
        let brokenArchive = tempDirectory.appendingPathComponent("\(secondName).zip")
        try "not a zip".write(to: brokenArchive, atomically: true, encoding: .utf8)

        do {
            _ = try await ZipExtractionService().extract(
                [firstArchive, brokenArchive],
                to: tempDirectory
            )
            XCTFail("Expected the second archive to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains(brokenArchive.path))
        }

        XCTAssertFalse(FileSystemPathIdentity.entryExists(tempDirectory.appendingPathComponent(firstName)))
        XCTAssertFalse(FileSystemPathIdentity.entryExists(tempDirectory.appendingPathComponent(secondName)))
    }

    func testBatchRollbackPreservesCompletedExtractionModifiedBeforeLaterCancellation() async throws {
        let firstName = "first-modified-\(UUID().uuidString)"
        let secondName = "second-cancelled-\(UUID().uuidString)"
        let firstArchive = try makeArchive(named: "\(firstName).zip")
        let secondArchive = try makeArchive(named: "\(secondName).zip")
        let firstOutput = tempDirectory.appendingPathComponent(firstName, isDirectory: true)
        let userMarker = firstOutput.appendingPathComponent("user-added.txt")
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent(secondName, isDirectory: true),
            withIntermediateDirectories: false
        )
        let resolver = MutatingExtractionCancellationResolver(marker: userMarker)

        do {
            _ = try await ZipExtractionService(conflictResolver: resolver).extract(
                [firstArchive, secondArchive],
                to: tempDirectory
            )
            XCTFail("Expected the second extraction to cancel")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(firstOutput.path))
        }

        XCTAssertEqual(try String(contentsOf: userMarker, encoding: .utf8), "user change")
        XCTAssertEqual(
            try String(contentsOf: firstOutput.appendingPathComponent("docs/readme.txt"), encoding: .utf8),
            "hello"
        )
    }

    func testBatchRollbackPreservesCompletedExtractionWithInPlaceFileModification() async throws {
        let firstName = "first-in-place-\(UUID().uuidString)"
        let secondName = "second-in-place-cancel-\(UUID().uuidString)"
        let firstArchive = try makeArchive(named: "\(firstName).zip")
        let secondArchive = try makeArchive(named: "\(secondName).zip")
        let firstOutput = tempDirectory.appendingPathComponent(firstName, isDirectory: true)
        let extractedFile = firstOutput.appendingPathComponent("docs/readme.txt")
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent(secondName, isDirectory: true),
            withIntermediateDirectories: false
        )
        let resolver = OverwritingExtractionCancellationResolver(file: extractedFile)

        do {
            _ = try await ZipExtractionService(conflictResolver: resolver).extract(
                [firstArchive, secondArchive],
                to: tempDirectory
            )
            XCTFail("Expected the second extraction to cancel")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(firstOutput.path))
        }

        XCTAssertEqual(try String(contentsOf: extractedFile, encoding: .utf8), "user modified in place")
    }

    func testUnsafeZipEntryDoesNotReplaceExistingDestinationFolder() async throws {
        let archiveName = "unsafe-\(UUID().uuidString)"
        let zipURL = try makeArchive(
            named: "\(archiveName).zip",
            entries: [
                ("safe.txt", "safe"),
                ("../evil.txt", "evil")
            ]
        )
        let existingFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-Unsafe", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "keep".write(
            to: existingFolder.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = ZipExtractionService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.extract([zipURL], to: tempDirectory)
            XCTFail("Expected unsafe ZIP extraction to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("outside destination"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFolder.path))
        XCTAssertEqual(
            try String(contentsOf: existingFolder.appendingPathComponent("keep.txt"), encoding: .utf8),
            "keep"
        )
    }

    func testReplaceRestoresExistingDestinationWhenExtractionIsCancelledAfterTrash() async throws {
        let archiveName = "cancel-after-replace-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let existingFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-Cancel", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "keep".write(
            to: existingFolder.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        let canceller = ZipProgressCanceller()
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .extractZip, title: "Extracting"),
            onUpdate: { snapshot in
                await canceller.cancelOnce(snapshot: snapshot)
            }
        )
        await canceller.setReporter(reporter)
        let service = ZipExtractionService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.extract([zipURL], to: tempDirectory, progress: reporter)
            XCTFail("Expected extraction cancellation")
        } catch is CancellationError {
            XCTAssertTrue(FileManager.default.fileExists(atPath: existingFolder.path))
            XCTAssertEqual(
                try String(contentsOf: existingFolder.appendingPathComponent("keep.txt"), encoding: .utf8),
                "keep"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: existingFolder.appendingPathComponent("docs/readme.txt").path
                )
            )
        }
    }

    func testReplaceRestoresExistingDestinationWhenStagingCreationFailsAfterTrash() async throws {
        let archiveName = "staging-create-failure-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let existingFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let keepFile = existingFolder.appendingPathComponent("keep.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-StagingFailure", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "keep".write(to: keepFile, atomically: true, encoding: .utf8)
        let service = ZipExtractionService(
            fileManager: FailingExtractionStagingCreationFileManager(),
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.extract([zipURL], to: tempDirectory)
            XCTFail("Expected staging creation to fail")
        } catch {
            // The original destination still must be restored.
        }

        XCTAssertEqual(try String(contentsOf: keepFile, encoding: .utf8), "keep")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testReplaceReportsRollbackFailureWhenTrashedDestinationCannotBeRestored() async throws {
        let archiveName = "rollback-failure-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let existingFolder = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-RollbackFailure", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "keep".write(
            to: existingFolder.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        let canceller = ZipProgressCanceller()
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .extractZip, title: "Extracting"),
            onUpdate: { snapshot in
                await canceller.cancelOnce(snapshot: snapshot)
            }
        )
        await canceller.setReporter(reporter)
        let service = ZipExtractionService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                try FileManager.default.removeItem(at: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.extract([zipURL], to: tempDirectory, progress: reporter)
            XCTFail("Expected extraction rollback to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(existingFolder.path))
        } catch {
            XCTFail("Expected an explicit rollback failure, got \(error)")
        }

        XCTAssertFalse(FileSystemPathIdentity.entryExists(existingFolder))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testReplaceDoesNotTrashFolderChangedWhileAwaitingConflictDecision() async throws {
        let archiveName = "replace-race-\(UUID().uuidString)"
        let zipURL = try makeArchive(named: "\(archiveName).zip")
        let destination = tempDirectory.appendingPathComponent(archiveName, isDirectory: true)
        let displacedDestination = tempDirectory.appendingPathComponent("folder-before-decision", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-ReplaceRace", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "original".write(
            to: destination.appendingPathComponent("original.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = ZipExtractionService(
            conflictResolver: ReplacingExtractionConflictResolver(
                destination: destination,
                displacedDestination: displacedDestination
            ),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.extract([zipURL], to: tempDirectory)
            XCTFail("Expected changed extraction destination identity to abort replace")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("late.txt"), encoding: .utf8),
            "late"
        )
        XCTAssertEqual(
            try String(contentsOf: displacedDestination.appendingPathComponent("original.txt"), encoding: .utf8),
            "original"
        )
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    private func makeArchive(named name: String) throws -> URL {
        try makeArchive(named: name, entries: [("docs/readme.txt", "hello")])
    }

    private func makeArchive(named name: String, entries: [(path: String, contents: String)]) throws -> URL {
        let source = tempDirectory.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for entry in entries {
            let data = Data(entry.contents.utf8)
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                bufferSize: max(data.count, 1)
            ) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        }
        return archiveURL
    }

    private func addEntry(path: String, type: Entry.EntryType, contents: String, to archive: Archive) throws {
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: type,
            uncompressedSize: Int64(data.count),
            compressionMethod: .none,
            bufferSize: max(data.count, 1)
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }
}

private actor ZipProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}

private actor ZipProgressCanceller {
    private var didCancel = false
    private var reporter: FileOperationProgressReporter?

    func setReporter(_ reporter: FileOperationProgressReporter) {
        self.reporter = reporter
    }

    func cancelOnce(snapshot: FileOperationProgressSnapshot) async {
        guard !didCancel, snapshot.phase != .cancelled else {
            return
        }
        guard let reporter else {
            return
        }
        didCancel = true
        await reporter.cancel()
    }
}

private final class LateExtractionDestinationFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let marker: URL
    private let lock = NSLock()
    private var didInject = false

    init(destination: URL, marker: URL) {
        self.destination = destination.standardizedFileURL
        self.marker = marker.standardizedFileURL
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        guard url.standardizedFileURL == destination, injectIfNeeded() else {
            try super.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
            return
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "unrelated".write(to: marker, atomically: true, encoding: .utf8)
        throw CocoaError(.fileWriteFileExists)
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        guard destination.standardizedFileURL == self.destination, injectIfNeeded() else {
            try super.moveItem(at: source, to: destination)
            return
        }
        try FileManager.default.createDirectory(at: self.destination, withIntermediateDirectories: true)
        try "unrelated".write(to: marker, atomically: true, encoding: .utf8)
        throw CocoaError(.fileWriteFileExists)
    }

    private func injectIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didInject else {
            return false
        }
        didInject = true
        return true
    }
}

private final class SwappingExtractionRollbackOutputFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let displaced: URL
    private let marker: URL
    private let lock = NSLock()
    private var didSwap = false

    init(destination: URL, displaced: URL, marker: URL) {
        self.destination = destination.standardizedFileURL
        self.displaced = displaced.standardizedFileURL
        self.marker = marker.standardizedFileURL
        super.init()
    }

    override func removeItem(at url: URL) throws {
        if url.standardizedFileURL == destination, beginSwap() {
            try installReplacement()
            try FileManager.default.removeItem(at: destination)
            return
        }
        try super.removeItem(at: url)
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        if source.standardizedFileURL == self.destination,
           destination.deletingLastPathComponent().lastPathComponent.hasPrefix(".MyMacFinder-rollback-"),
           beginSwap() {
            try installReplacement()
            try super.moveItem(at: self.destination, to: destination)
            return
        }
        try super.moveItem(at: source, to: destination)
    }

    private func beginSwap() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didSwap else {
            return false
        }
        didSwap = true
        return true
    }

    private func installReplacement() throws {
        try FileManager.default.moveItem(at: destination, to: displaced)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "unrelated".write(to: marker, atomically: true, encoding: .utf8)
    }
}

private final class MutatingPublishedExtractionFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let publishedFile: URL

    init(destination: URL, publishedFile: URL) {
        self.destination = destination.standardizedFileURL
        self.publishedFile = publishedFile.standardizedFileURL
        super.init()
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        guard destination.standardizedFileURL == self.destination else {
            return
        }
        try "user modified".write(to: publishedFile, atomically: false, encoding: .utf8)
    }
}

private final class ReplacingPublishedExtractionFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let marker: URL

    init(destination: URL, marker: URL) {
        self.destination = destination.standardizedFileURL
        self.marker = marker.standardizedFileURL
        super.init()
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        guard destination.standardizedFileURL == self.destination else {
            return
        }
        try FileManager.default.removeItem(at: self.destination)
        try FileManager.default.createDirectory(at: self.destination, withIntermediateDirectories: true)
        try "unrelated".write(to: marker, atomically: true, encoding: .utf8)
    }
}

private final class ExtractionStagingReplacementRecorder: @unchecked Sendable {
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

private final class PreIdentityExtractionStagingFileManager: FileManager, @unchecked Sendable {
    private let recorder: ExtractionStagingReplacementRecorder

    init(recorder: ExtractionStagingReplacementRecorder) {
        self.recorder = recorder
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        let parentName = url.deletingLastPathComponent().lastPathComponent
        guard url.lastPathComponent == "docs", parentName.hasPrefix(".MyMacFinder-extract-") else {
            try super.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
            return
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
        let unrelated = url.appendingPathComponent("unrelated.txt")
        try "unrelated".write(to: unrelated, atomically: true, encoding: .utf8)
        recorder.record(unrelated)
        throw CocoaError(.fileWriteUnknown)
    }
}

private struct ReplacingExtractionConflictResolver: FileConflictResolving {
    var destination: URL
    var displacedDestination: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try FileManager.default.moveItem(at: destination, to: displacedDestination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "late".write(
            to: destination.appendingPathComponent("late.txt"),
            atomically: true,
            encoding: .utf8
        )
        return .replace
    }
}

private struct MutatingExtractionCancellationResolver: FileConflictResolving {
    var marker: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try "user change".write(to: marker, atomically: true, encoding: .utf8)
        return .cancel
    }
}

private struct OverwritingExtractionCancellationResolver: FileConflictResolving {
    var file: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try "user modified in place".write(to: file, atomically: false, encoding: .utf8)
        return .cancel
    }
}

private final class FailingExtractionStagingCreationFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        guard url.lastPathComponent.hasPrefix(".MyMacFinder-extract-") else {
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
