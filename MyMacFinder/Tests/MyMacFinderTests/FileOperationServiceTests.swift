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
            try FileManager.default.removeItem(at: tempDirectory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
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

    func testCreateFolderRejectsReplacementInstalledBeforeOperationReturns() async throws {
        let destination = tempDirectory.appendingPathComponent("Untitled Folder", isDirectory: true)
        let displaced = tempDirectory.appendingPathComponent("owned-created-folder", isDirectory: true)
        let fileManager = ReplacingCreatedFolderBeforeReturnFileManager(
            destination: destination,
            displaced: displaced
        )

        do {
            _ = try await FileOperationService(fileManager: fileManager).createFolder(in: tempDirectory)
            XCTFail("Expected created-folder identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(destination.path))
        }

        XCTAssertTrue(FileSystemPathIdentity.entryExists(displaced))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
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

    func testRenameRejectsReplacementInstalledBeforeOperationReturns() async throws {
        let source = tempDirectory.appendingPathComponent("rename-owned.txt")
        let destination = tempDirectory.appendingPathComponent("renamed-owned.txt")
        let displaced = tempDirectory.appendingPathComponent("displaced-renamed-owned.txt")
        try "owned".write(to: source, atomically: true, encoding: .utf8)
        let sequence = ReplacingCommittedMoveBeforeReturn(
            destination: destination,
            displaced: displaced
        )

        do {
            _ = try await FileOperationService(moveItemAction: sequence.move)
                .rename(source, to: destination.lastPathComponent)
            XCTFail("Expected renamed-item identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(destination.path))
        }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: displaced, encoding: .utf8), "owned")
    }

    func testCaseOnlyRenameChangesDirectoryEntryNameOnCaseInsensitiveVolume() async throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let source = tempDirectory.appendingPathComponent("report.txt")
        try "report".write(to: source, atomically: true, encoding: .utf8)

        let result = try await FileOperationService().rename(source, to: "REPORT.txt")
        let renamed = try XCTUnwrap(result.renamedItem?.destination)
        let directoryNames = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)

        XCTAssertEqual(renamed.lastPathComponent, "REPORT.txt")
        XCTAssertTrue(directoryNames.contains("REPORT.txt"))
        XCTAssertFalse(directoryNames.contains("report.txt"))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "report")
    }

    func testFailedCaseOnlyRenameDoesNotDeleteOriginalAsPartialDestination() async throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let source = tempDirectory.appendingPathComponent("report.txt")
        try "report".write(to: source, atomically: true, encoding: .utf8)
        let service = FileOperationService(moveItemAction: { _, _ in
            throw InjectedMoveFailure()
        })

        do {
            _ = try await service.rename(source, to: "REPORT.txt")
            XCTFail("Expected injected rename failure")
        } catch let error as ExplorerError {
            guard case .operationFailed = error else {
                return XCTFail("Expected operationFailed, got \(error)")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "report")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path), ["report.txt"])
    }

    func testFailedRenameDoesNotDeleteDestinationCreatedAfterConflictCheck() async throws {
        let source = tempDirectory.appendingPathComponent("late-source.txt")
        let destination = tempDirectory.appendingPathComponent("late-destination.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let fileManager = LateDestinationRaceFileManager(
            target: destination,
            injectedContents: Data("unrelated".utf8)
        )
        let service = FileOperationService(fileManager: fileManager)

        do {
            _ = try await service.rename(source, to: destination.lastPathComponent)
            XCTFail("Expected late destination conflict")
        } catch {
            // The operation must fail without treating the late entry as its own partial output.
        }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
    }

    func testHardLinkIdentityAloneIsNotAcceptedAsCaseOnlyRename() throws {
        let original = tempDirectory.appendingPathComponent("report.txt")
        let hardLink = tempDirectory.appendingPathComponent("report-copy.txt")
        try "report".write(to: original, atomically: true, encoding: .utf8)
        try FileManager.default.linkItem(at: original, to: hardLink)

        XCTAssertFalse(
            try FileSystemPathIdentity.isCaseOnlyRenameOfSameItem(
                source: original,
                destination: hardLink
            )
        )
    }

    func testCaseSensitiveVolumeDoesNotReadCaseVariantDestinationIdentity() throws {
        let source = tempDirectory.appendingPathComponent("report.txt")
        let destination = tempDirectory.appendingPathComponent("REPORT.txt")
        var requestedURLs: [URL] = []

        let isCaseOnlyRename = try FileSystemPathIdentity.isCaseOnlyRenameOfSameItem(
            source: source,
            destination: destination,
            resourceValuesLoader: { url in
                requestedURLs.append(url.standardizedFileURL)
                guard url.standardizedFileURL == source.standardizedFileURL else {
                    throw InjectedIdentityReadFailure()
                }
                return FileSystemPathIdentity.EntryIdentityValues(
                    fileResourceIdentifier: "source-identifier",
                    volumeSupportsCaseSensitiveNames: true
                )
            }
        )

        XCTAssertFalse(isCaseOnlyRename)
        XCTAssertEqual(requestedURLs, [source.standardizedFileURL])
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

    func testDuplicateRejectsReplacementInstalledBeforeOperationReturns() async throws {
        let source = tempDirectory.appendingPathComponent("duplicate-owned", isDirectory: true)
        let sourceFile = source.appendingPathComponent("owned.txt")
        let destination = tempDirectory.appendingPathComponent("duplicate-owned copy", isDirectory: true)
        let displaced = tempDirectory.appendingPathComponent("displaced-duplicate-owned", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "owned".write(to: sourceFile, atomically: true, encoding: .utf8)
        let fileManager = ReplacingDuplicateBeforeReturnFileManager(
            destination: destination,
            displaced: displaced
        )

        do {
            _ = try await FileOperationService(fileManager: fileManager).duplicate(source)
            XCTFail("Expected duplicate identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(destination.path))
        }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
        XCTAssertEqual(
            try String(contentsOf: displaced.appendingPathComponent("owned.txt"), encoding: .utf8),
            "owned"
        )
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
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                XCTFail("Same-folder copy must not trash its source: \(url.path)")
                throw InjectedMoveFailure()
            }
        )

        let result = try await service.copyItems([sourceFile], to: tempDirectory)
        let copied = try XCTUnwrap(result.createdURLs.first)

        XCTAssertEqual(copied.lastPathComponent, "note copy.txt")
        XCTAssertTrue(result.replacedItems.isEmpty)
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "original")
    }

    func testCopyDoesNotOverwriteOrDeleteDestinationCreatedBeforeCommit() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("late-copy-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("late-copy-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let destination = destinationFolder.appendingPathComponent("report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let fileManager = LateDestinationRaceFileManager(
            target: destination,
            injectedContents: Data("unrelated".utf8)
        )
        let service = FileOperationService(fileManager: fileManager)

        do {
            _ = try await service.copyItems([source], to: destinationFolder)
            XCTFail("Expected late copy destination conflict")
        } catch {
            // The staged copy must be discarded without touching the late destination.
        }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path)
                .contains(where: { $0.hasPrefix(".MyMacFinder-copy-") })
        )
    }

    func testCopyPreservesStagingEntryReplacedBeforeFailedCommit() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("staging-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("staging-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let destination = destinationFolder.appendingPathComponent("report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let replacement = StagingReplacementRecorder()
        let service = FileOperationService(moveItemAction: { stagingURL, commitURL in
            guard commitURL.standardizedFileURL == destination.standardizedFileURL else {
                try FileManager.default.moveItem(at: stagingURL, to: commitURL)
                return
            }
            try FileManager.default.removeItem(at: stagingURL)
            try "unrelated".write(to: stagingURL, atomically: true, encoding: .utf8)
            replacement.record(stagingURL)
            throw InjectedMoveFailure()
        })

        do {
            _ = try await service.copyItems([source], to: destinationFolder)
            XCTFail("Expected staged copy commit to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("staging"))
        }

        let replacedStagingURL = try XCTUnwrap(replacement.url)
        XCTAssertEqual(try String(contentsOf: replacedStagingURL, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destination))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
    }

    func testCopyPreservesUnverifiedStagingEntryCreatedBeforeIdentityCapture() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("preidentity-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("preidentity-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        let recorder = StagingReplacementRecorder()
        let fileManager = PreIdentityCopyStagingFileManager(recorder: recorder)

        do {
            _ = try await FileOperationService(fileManager: fileManager).copyItems([source], to: destinationFolder)
            XCTFail("Expected staging creation to fail before identity capture")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("staging"))
        }

        let unverifiedStagingURL = try XCTUnwrap(recorder.url)
        XCTAssertEqual(try String(contentsOf: unverifiedStagingURL, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
    }

    func testReplaceDoesNotTrashDestinationChangedWhileAwaitingConflictDecision() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("replace-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("replace-destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-ConflictRace", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let destination = destinationFolder.appendingPathComponent("report.txt")
        let displacedDestination = destinationFolder.appendingPathComponent("report-before-decision.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "original destination".write(to: destination, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            conflictResolver: ReplacingFileConflictResolver(
                destination: destination,
                displacedDestination: displacedDestination,
                replacementContents: "late destination"
            ),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.copyItems([source], to: destinationFolder)
            XCTFail("Expected changed destination identity to abort replace")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "late destination")
        XCTAssertEqual(try String(contentsOf: displacedDestination, encoding: .utf8), "original destination")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testReplaceRestoresDestinationSwappedDuringTrashMove() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("trash-gap-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("trash-gap-destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-IdentityGap", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let destination = destinationFolder.appendingPathComponent("report.txt")
        let displacedDestination = destinationFolder.appendingPathComponent("report-before-trash.txt")
        let trashed = simulatedTrash.appendingPathComponent("report.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "original destination".write(to: destination, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                try FileManager.default.moveItem(at: url, to: displacedDestination)
                try "late destination".write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.copyItems([source], to: destinationFolder)
            XCTFail("Expected identity change during Trash move to abort replace")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed during Trash"))
        }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "late destination")
        XCTAssertEqual(try String(contentsOf: displacedDestination, encoding: .utf8), "original destination")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testCopyThroughAliasToSameFolderKeepsBothEvenWhenResolverWouldReplace() async throws {
        let realFolder = tempDirectory.appendingPathComponent("Real", isDirectory: true)
        let aliasFolder = tempDirectory.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasFolder, withDestinationURL: realFolder)
        let source = realFolder.appendingPathComponent("report.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                XCTFail("Same-item copy must not replace the source: \(url.path)")
                throw InjectedMoveFailure()
            }
        )

        let result = try await service.copyItems([source], to: aliasFolder)
        let copied = try XCTUnwrap(result.createdURLs.first)

        XCTAssertEqual(copied.lastPathComponent, "report copy.txt")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "original")
        XCTAssertTrue(result.replacedItems.isEmpty)
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
            XCTAssertEqual(error, .operationFailed("Cannot copy a folder into itself."))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: child.appendingPathComponent("Folder").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source.txt").path))
    }

    func testCopyItemsPreflightsEveryCanonicalRelationshipBeforeFirstMutation() async throws {
        let firstSource = tempDirectory.appendingPathComponent("first.txt")
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let destination = folder.appendingPathComponent("Child", isDirectory: true)
        try "first".write(to: firstSource, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await FileOperationService().copyItems([firstSource, folder], to: destination)
            XCTFail("Expected canonical batch preflight to reject the descendant destination")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot copy a folder into itself."))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("first.txt").path))
    }

    func testCopyRejectsDestinationSymlinkIntoSourceDescendant() async throws {
        let source = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let destinationAlias = tempDirectory.appendingPathComponent("DestinationAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destinationAlias, withDestinationURL: child)

        do {
            _ = try await FileOperationService().copyItems([source], to: destinationAlias)
            XCTFail("Expected canonical descendant copy rejection")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot copy a folder into itself."))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: child.appendingPathComponent("Source").path))
    }

    func testMoveRejectsDestinationSymlinkIntoSourceDescendant() async throws {
        let source = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let destinationAlias = tempDirectory.appendingPathComponent("DestinationAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destinationAlias, withDestinationURL: child)

        do {
            _ = try await FileOperationService().moveItems([source], to: destinationAlias)
            XCTFail("Expected canonical descendant move rejection")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot move a folder into itself."))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyAllowsSourceDirectorySymlinkEntryIntoItsTarget() async throws {
        let target = tempDirectory.appendingPathComponent("Target", isDirectory: true)
        let sourceLink = tempDirectory.appendingPathComponent("TargetLink", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "inside".write(
            to: target.appendingPathComponent("inside.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)

        let result = try await FileOperationService().copyItems([sourceLink], to: target)
        let copiedLink = try XCTUnwrap(result.createdURLs.first)
        let values = try copiedLink.resourceValues(forKeys: [.isSymbolicLinkKey])

        XCTAssertEqual(
            copiedLink.standardizedFileURL.path,
            target.appendingPathComponent("TargetLink").standardizedFileURL.path
        )
        XCTAssertEqual(values.isSymbolicLink, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceLink.path))
    }

    func testMoveAllowsSourceDirectorySymlinkEntryIntoItsTarget() async throws {
        let target = tempDirectory.appendingPathComponent("Target", isDirectory: true)
        let sourceLink = tempDirectory.appendingPathComponent("TargetLink", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)

        let result = try await FileOperationService().moveItems([sourceLink], to: target)
        let movedLink = try XCTUnwrap(result.movedItems.first?.destination)
        let values = try movedLink.resourceValues(forKeys: [.isSymbolicLinkKey])

        XCTAssertEqual(
            movedLink.standardizedFileURL.path,
            target.appendingPathComponent("TargetLink").standardizedFileURL.path
        )
        XCTAssertEqual(values.isSymbolicLink, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceLink.path))
    }

    func testCopyItemsDescendantFailureIsNotReportedAsReadFailure() async throws {
        let folder = tempDirectory.appendingPathComponent("OperationFolder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let service = FileOperationService()

        do {
            _ = try await service.copyItems([folder], to: child)
            XCTFail("Expected copying a folder into its descendant to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot copy a folder into itself."))
        }
    }

    func testCopyRejectsAlternateCaseSourcePathIntoItsDescendant() async throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let source = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let alternateCaseSource = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        do {
            _ = try await FileOperationService().copyItems([alternateCaseSource], to: child)
            XCTFail("Expected descendant copy rejection")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot copy a folder into itself."))
        }
    }

    func testMoveRejectsAlternateCaseSourcePathIntoItsDescendant() async throws {
        let supportsCaseSensitiveNames = try tempDirectory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames
        XCTAssertEqual(supportsCaseSensitiveNames, false, "This regression requires a case-insensitive test volume.")
        guard supportsCaseSensitiveNames == false else { return }
        let source = tempDirectory.appendingPathComponent("Source", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        let alternateCaseSource = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        do {
            _ = try await FileOperationService().moveItems([alternateCaseSource], to: child)
            XCTFail("Expected descendant move rejection")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot move a folder into itself."))
        }
    }

    func testDuplicateSystemFailureIsReportedAsOperationFailure() async throws {
        let missing = tempDirectory.appendingPathComponent("missing.txt")
        let service = FileOperationService()

        do {
            _ = try await service.duplicate(missing)
            XCTFail("Expected duplicate of a missing item to fail")
        } catch let error as ExplorerError {
            if case .operationFailed(let message) = error {
                XCTAssertTrue(message.contains("missing.txt"))
            } else {
                XCTFail("Expected operation failure, got \(error)")
            }
        } catch {
            XCTFail("Expected operation failure, got \(error)")
        }
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

    func testCopySingleFilePreservesExtendedAttributesDuringStreamingCopy() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("tagged.bin")
        try Data(repeating: 1, count: 10).write(to: source)
        let attributeName = "com.mymacfinder.test.metadata"
        let attributeValue = Data("finder-tag-metadata".utf8)
        try setExtendedAttribute(attributeName, value: attributeValue, for: source)

        _ = try await FileOperationService(copyChunkSize: 4).copyItems([source], to: destFolder)

        let destination = destFolder.appendingPathComponent(source.lastPathComponent)
        XCTAssertEqual(try extendedAttribute(attributeName, for: destination), attributeValue)
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

    func testCopyItemsRollBackEarlierReplacementWhenLaterCopyFails() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("copy-transaction-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("copy-transaction-destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("copy-transaction-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let second = sourceFolder.appendingPathComponent("second.txt")
        let firstDestination = destinationFolder.appendingPathComponent("first.txt")
        try "new first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        try "old first".write(to: firstDestination, atomically: true, encoding: .utf8)
        let moveSequence = FailingMoveSequence(failAtCall: 2)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent("trashed-\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            },
            moveItemAction: moveSequence.move
        )

        do {
            _ = try await service.copyItems([first, second], to: destinationFolder)
            XCTFail("Expected the second copy commit to fail")
        } catch {
            // The first completed copy and its replacement must roll back transactionally.
        }

        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "old first")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destinationFolder.appendingPathComponent("second.txt")))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "new first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testCopyRollbackPreservesEarlierOutputChangedBeforeLaterFailure() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("copy-changed-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("copy-changed-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let second = sourceFolder.appendingPathComponent("second.txt")
        let firstDestination = destinationFolder.appendingPathComponent("first.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let sequence = ReplacingCopyOutputBeforeLaterFailure(firstDestination: firstDestination)
        let service = FileOperationService(moveItemAction: sequence.move)

        do {
            _ = try await service.copyItems([first, second], to: destinationFolder)
            XCTFail("Expected the second copy commit to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(firstDestination.path))
        }

        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "unrelated")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destinationFolder.appendingPathComponent("second.txt")))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testCopyRollbackUsesStagedSnapshotWhenPublishedDirectoryChangesBeforeCommitReturns() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("copy-publish-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("copy-publish-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first", isDirectory: true)
        let second = sourceFolder.appendingPathComponent("second.txt")
        let firstFile = first.appendingPathComponent("nested.txt")
        let publishedFirstFile = destinationFolder.appendingPathComponent("first/nested.txt")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try "original".write(to: firstFile, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let sequence = MutatingPublishedCopyBeforeLaterFailure(
            publishedFile: publishedFirstFile
        )
        let service = FileOperationService(moveItemAction: sequence.move)

        do {
            _ = try await service.copyItems([first, second], to: destinationFolder)
            XCTFail("Expected the second copy commit to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(publishedFirstFile.deletingLastPathComponent().path))
        }

        XCTAssertEqual(try String(contentsOf: publishedFirstFile, encoding: .utf8), "user modified")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destinationFolder.appendingPathComponent("second.txt")))
        XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testCopyRollbackDoesNotDeletePathReplacementInstalledAfterSnapshotCheck() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("copy-quarantine-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("copy-quarantine-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let second = sourceFolder.appendingPathComponent("second.txt")
        let firstDestination = destinationFolder.appendingPathComponent("first.txt")
        let displaced = destinationFolder.appendingPathComponent("app-owned-first.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let fileManager = SwappingCopyRollbackOutputFileManager(
            destination: firstDestination,
            displaced: displaced
        )
        let moveSequence = FailingMoveSequence(failAtCall: 2)
        let service = FileOperationService(
            fileManager: fileManager,
            moveItemAction: moveSequence.move
        )

        do {
            _ = try await service.copyItems([first, second], to: destinationFolder)
            XCTFail("Expected the second copy commit to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(firstDestination.path))
        }

        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: displaced, encoding: .utf8), "first")
        XCTAssertFalse(FileSystemPathIdentity.entryExists(destinationFolder.appendingPathComponent("second.txt")))
    }

    func testCopyRejectsDestinationReplacedBeforeCommitReturnsAndPreservesReplacement() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("copy-replaced-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("copy-replaced-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("report.txt")
        let destination = destinationFolder.appendingPathComponent("report.txt")
        try "owned".write(to: source, atomically: true, encoding: .utf8)
        let sequence = ReplacingPublishedCopyBeforeCommitReturns(destination: destination)
        let service = FileOperationService(moveItemAction: sequence.move)

        do {
            _ = try await service.copyItems([source], to: destinationFolder)
            XCTFail("Expected destination identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(destination.path))
        }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "owned")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
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

    func testMoveRejectsReplacementInstalledBeforeOperationReturns() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("move-owned-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("move-owned-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("owned.txt")
        let destination = destinationFolder.appendingPathComponent("owned.txt")
        let displaced = destinationFolder.appendingPathComponent("displaced-owned.txt")
        try "owned".write(to: source, atomically: true, encoding: .utf8)
        let sequence = ReplacingCommittedMoveBeforeReturn(
            destination: destination,
            displaced: displaced
        )

        do {
            _ = try await FileOperationService(moveItemAction: sequence.move)
                .moveItems([source], to: destinationFolder)
            XCTFail("Expected moved-item identity verification to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
            XCTAssertTrue(error.localizedDescription.contains(destination.path))
        }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: displaced, encoding: .utf8), "owned")
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
            XCTAssertEqual(error, .operationFailed("Cannot move a folder into itself."))
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

    func testMoveItemsPreflightsEveryCanonicalRelationshipBeforeFirstMutation() async throws {
        let firstSource = tempDirectory.appendingPathComponent("first.txt")
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let destination = folder.appendingPathComponent("Child", isDirectory: true)
        try "first".write(to: firstSource, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await FileOperationService().moveItems([firstSource, folder], to: destination)
            XCTFail("Expected canonical batch preflight to reject the descendant destination")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .operationFailed("Cannot move a folder into itself."))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("first.txt").path))
    }

    func testMoveItemsRollsBackEarlierMovesWhenLaterMoveFails() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("transaction-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("transaction-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let second = sourceFolder.appendingPathComponent("second.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let moveInjector = FailingMoveSequence(failAtCall: 2)
        let service = FileOperationService(moveItemAction: { source, destination in
            try moveInjector.move(source, to: destination)
        })

        do {
            _ = try await service.moveItems([first, second], to: destinationFolder)
            XCTFail("Expected the second move to fail")
        } catch {
            // The first completed move must be rolled back before the error escapes.
        }

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path).isEmpty)
    }

    func testMoveRollbackReplaysMovesAndReplacementsInReverseTransactionOrder() async throws {
        let destinationFolder = tempDirectory.appendingPathComponent("ordered-rollback-destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("ordered-rollback-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)

        var sources: [URL] = []
        for index in 1...3 {
            let sourceFolder = tempDirectory.appendingPathComponent("ordered-source-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            let source = sourceFolder.appendingPathComponent("shared.txt")
            try "source-\(index)".write(to: source, atomically: true, encoding: .utf8)
            sources.append(source)
        }

        let canceller = CompletedUnitProgressCanceller(cancelAtCompletedUnitCount: 2)
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .move, title: "Moving"),
            onUpdate: { snapshot in await canceller.cancelIfNeeded(snapshot: snapshot) }
        )
        await canceller.setReporter(reporter)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(
                    "trashed-\(UUID().uuidString)-\(url.lastPathComponent)"
                )
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        do {
            _ = try await service.moveItems(sources, to: destinationFolder, progress: reporter)
            XCTFail("Expected cancellation after two completed moves")
        } catch is CancellationError {
            // Expected after the interleaved move/replace journal is rolled back.
        }

        for (index, source) in sources.enumerated() {
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source-\(index + 1)")
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveRollbackDoesNotMoveDestinationReplacedAfterCompletion() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("move-identity-source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("move-identity-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = sourceFolder.appendingPathComponent("first.txt")
        let second = sourceFolder.appendingPathComponent("second.txt")
        let firstDestination = destinationFolder.appendingPathComponent("first.txt")
        let displacedFirstDestination = destinationFolder.appendingPathComponent("first-before-rollback.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let sequence = ReplacingMoveRollbackSequence(
            firstDestination: firstDestination,
            displacedFirstDestination: displacedFirstDestination
        )
        let service = FileOperationService(moveItemAction: sequence.move)

        do {
            _ = try await service.moveItems([first, second], to: destinationFolder)
            XCTFail("Expected the second move to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        XCTAssertFalse(FileSystemPathIdentity.entryExists(first))
        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: displacedFirstDestination, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testMoveToTrashRemovesOriginalAndReturnsTrashLocation() async throws {
        let sourceFile = tempDirectory.appendingPathComponent("trash-me.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "trash".write(to: sourceFile, atomically: true, encoding: .utf8)

        let service = FileOperationService(trashItem: { url in
            let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        let result = try await service.moveToTrash([sourceFile])
        let trashedURLs = result.trashedItems.map(\.trashed)

        XCTAssertEqual(trashedURLs.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURLs[0].path))
    }

    func testMoveToTrashWithRecordedIdentityDoesNotTouchReplacementSource() async throws {
        let source = tempDirectory.appendingPathComponent("owned-trash-source.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-Owned", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "owned".write(to: source, atomically: true, encoding: .utf8)
        let expectedIdentity = try XCTUnwrap(FileSystemPathIdentity.entryIdentity(source))
        try FileManager.default.removeItem(at: source)
        try "unrelated".write(to: source, atomically: true, encoding: .utf8)
        let recorder = TrashInvocationRecorder(root: simulatedTrash)
        let service = FileOperationService(trashItem: recorder.moveToTrash)

        do {
            _ = try await service.moveToTrash(
                [source],
                expectedIdentities: [source.standardizedFileURL: expectedIdentity]
            )
            XCTFail("Expected the changed source identity to abort Trash")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }

        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "unrelated")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveToTrashPreflightsSourcesBeforeTrashingAnyItem() async throws {
        let first = tempDirectory.appendingPathComponent("trash-preflight-\(UUID().uuidString).txt")
        let missing = tempDirectory.appendingPathComponent("missing-trash.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        let service = FileOperationService(trashItem: { url in
            let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })

        do {
            _ = try await service.moveToTrash([first, missing])
            XCTFail("Expected trash to fail before moving any item")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .pathDoesNotExist(missing.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveToTrashCancellationRestoresCompletedItemsAndEmptiesSimulatedTrash() async throws {
        let first = tempDirectory.appendingPathComponent("first.txt")
        let second = tempDirectory.appendingPathComponent("second.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let canceller = CompletedUnitProgressCanceller(cancelAtCompletedUnitCount: 1)
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .trash, title: "Moving to Trash"),
            onUpdate: { snapshot in await canceller.cancelIfNeeded(snapshot: snapshot) }
        )
        await canceller.setReporter(reporter)
        let service = FileOperationService(trashItem: { url in
            let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })

        do {
            _ = try await service.moveToTrash([first, second], progress: reporter)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected after the completed item has been restored.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveToTrashCancellationReportsRollbackFailure() async throws {
        let first = tempDirectory.appendingPathComponent("first.txt")
        let second = tempDirectory.appendingPathComponent("second.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let canceller = CompletedUnitProgressCanceller(cancelAtCompletedUnitCount: 1)
        var reporter: FileOperationProgressReporter!
        reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .trash, title: "Moving to Trash"),
            onUpdate: { snapshot in await canceller.cancelIfNeeded(snapshot: snapshot) }
        )
        await canceller.setReporter(reporter)
        let service = FileOperationService(trashItem: { url in
            let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            if url == first {
                try "external replacement".write(to: first, atomically: true, encoding: .utf8)
            }
            return destination
        })

        do {
            _ = try await service.moveToTrash([first, second], progress: reporter)
            XCTFail("Expected rollback failure")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(first.path))
            XCTAssertTrue(error.localizedDescription.contains("Trash failed"))
        }

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "external replacement")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: simulatedTrash.appendingPathComponent("first.txt").path))
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

    func testTrashRollbackDoesNotRestoreTrashedPathReplacedAfterCompletion() async throws {
        let first = tempDirectory.appendingPathComponent("trash-identity-first.txt")
        let second = tempDirectory.appendingPathComponent("trash-identity-second.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-IdentityRollback", isDirectory: true)
        let displacedFirst = simulatedTrash.appendingPathComponent("first-before-rollback.txt")
        let firstTrash = simulatedTrash.appendingPathComponent(first.lastPathComponent)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let sequence = ReplacingTrashRollbackSequence(
            firstSource: first,
            firstTrash: firstTrash,
            displacedFirstTrash: displacedFirst
        )
        let service = FileOperationService(trashItem: sequence.trash)

        do {
            _ = try await service.moveToTrash([first, second])
            XCTFail("Expected the second Trash move to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        XCTAssertFalse(FileSystemPathIdentity.entryExists(first))
        XCTAssertEqual(try String(contentsOf: firstTrash, encoding: .utf8), "unrelated")
        XCTAssertEqual(try String(contentsOf: displacedFirst, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testMoveToTrashRollbackRestoresRelativeSymlinkEntryAfterItBecomesDangling() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("RelativeSymlinkSource", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-RelativeSymlink", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let target = sourceFolder.appendingPathComponent("target.txt")
        let link = sourceFolder.appendingPathComponent("target-link")
        let laterFailure = sourceFolder.appendingPathComponent("later.txt")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        try "later".write(to: laterFailure, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "target.txt")
        let service = FileOperationService(trashItem: { url in
            if url == laterFailure {
                throw ExplorerError.readFailed("later trash failed")
            }
            let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })

        do {
            _ = try await service.moveToTrash([link, laterFailure])
            XCTFail("Expected the later Trash operation to fail")
        } catch let error as ExplorerError {
            XCTAssertEqual(error, .readFailed("later trash failed"))
        }

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "target.txt")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target")
        XCTAssertTrue(FileManager.default.fileExists(atPath: laterFailure.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveToTrashReportsRollbackFailureWhenTrashedItemCannotBeRestored() async throws {
        let first = tempDirectory.appendingPathComponent("first.txt")
        let second = tempDirectory.appendingPathComponent("second.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let service = FileOperationService(trashItem: { url in
            if url == second {
                try "blocking replacement".write(to: first, atomically: true, encoding: .utf8)
                throw ExplorerError.readFailed("trash failed")
            }
            let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trashed)
            return trashed
        })

        do {
            _ = try await service.moveToTrash([first, second])
            XCTFail("Expected trash rollback failure")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("first.txt"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: simulatedTrash.appendingPathComponent("first.txt").path))
    }

    func testCopyItemsReplacesExistingFileWhenResolverChoosesReplace() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-CopyReplace", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "old".write(to: existingDest, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = try await service.copyItems([sourceFile], to: destFolder)

        XCTAssertEqual(result.createdURLs, [existingDest.standardizedFileURL])
        XCTAssertEqual(result.replacedItems.map(\.original), [existingDest.standardizedFileURL])
        XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: result.replacedItems[0].trashed, encoding: .utf8), "old")
    }

    func testCopyCancellationAfterReplaceRestoresExistingDestination() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-CopyCancel", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("replace.txt")
        let destination = destinationFolder.appendingPathComponent("replace.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { _ in }
        )
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                cancelSynchronously(reporter)
                return trashed
            }
        )

        do {
            _ = try await service.copyItems([source], to: destinationFolder, progress: reporter)
            XCTFail("Expected cancellation after replacement was moved to simulated Trash")
        } catch is CancellationError {
            // Expected after rollback restores the replaced destination.
        }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
    }

    func testMoveCancellationAfterReplaceRestoresExistingDestinationAndSource() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = tempDirectory.appendingPathComponent("destination", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-MoveCancel", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("replace.txt")
        let destination = destinationFolder.appendingPathComponent("replace.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .move, title: "Moving"),
            onUpdate: { _ in }
        )
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                cancelSynchronously(reporter)
                return trashed
            }
        )

        do {
            _ = try await service.moveItems([source], to: destinationFolder, progress: reporter)
            XCTFail("Expected cancellation after replacement was moved to simulated Trash")
        } catch is CancellationError {
            // Expected after rollback restores the replaced destination.
        }

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: simulatedTrash.path).isEmpty)
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
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-CopyFailure", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        defer {
            _ = chmod(unreadableFile.path, S_IRUSR | S_IWUSR)
        }
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

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

    func testCopyReplaceReportsRollbackFailureWhenTrashedDestinationCannotBeRestored() async throws {
        let itemName = "replace-copy-rollback-failure-\(UUID().uuidString)"
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        let sourceDir = sourceFolder.appendingPathComponent(itemName, isDirectory: true)
        let unreadableFile = sourceDir.appendingPathComponent("unreadable.txt")
        let existingDest = destFolder.appendingPathComponent(itemName, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "new".write(to: unreadableFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(unreadableFile.path, 0), 0)
        try FileManager.default.createDirectory(at: existingDest, withIntermediateDirectories: true)
        try "old".write(to: existingDest.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        defer {
            _ = chmod(unreadableFile.path, S_IRUSR | S_IWUSR)
        }
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let trashed = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: trashed)
                try FileManager.default.removeItem(at: trashed)
                return trashed
            }
        )

        do {
            _ = try await service.copyItems([sourceDir], to: destFolder)
            XCTFail("Expected copy rollback failure")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("rollback was incomplete"))
            XCTAssertTrue(error.localizedDescription.contains(itemName))
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
        let simulatedTrash = tempDirectory.appendingPathComponent("SimulatedTrash-RenameReplace", isDirectory: true)
        try FileManager.default.createDirectory(at: simulatedTrash, withIntermediateDirectories: true)
        try "old content".write(to: oldFile, atomically: true, encoding: .utf8)
        try "existing content".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(
            conflictResolver: DefaultFileConflictResolver(decision: .replace),
            trashItem: { url in
                let destination = simulatedTrash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )

        let result = try await service.rename(oldFile, to: "new.txt")

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

private func setExtendedAttribute(_ name: String, value: Data, for url: URL) throws {
    let result = value.withUnsafeBytes { buffer in
        setxattr(url.path, name, buffer.baseAddress, buffer.count, 0, 0)
    }
    guard result == 0 else {
        if errno == ENOTSUP || errno == ENODATA {
            throw XCTSkip("Extended attributes are not supported on this filesystem")
        }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func extendedAttribute(_ name: String, for url: URL) throws -> Data {
    let length = getxattr(url.path, name, nil, 0, 0, 0)
    guard length >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var data = Data(count: length)
    let result = data.withUnsafeMutableBytes { buffer in
        getxattr(url.path, name, buffer.baseAddress, length, 0, 0)
    }
    guard result >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return data
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

private actor CompletedUnitProgressCanceller {
    private let cancelAtCompletedUnitCount: Int
    private var didCancel = false
    private var reporter: FileOperationProgressReporter?

    init(cancelAtCompletedUnitCount: Int) {
        self.cancelAtCompletedUnitCount = cancelAtCompletedUnitCount
    }

    func setReporter(_ reporter: FileOperationProgressReporter) {
        self.reporter = reporter
    }

    func cancelIfNeeded(snapshot: FileOperationProgressSnapshot) async {
        guard !didCancel,
              snapshot.phase == .running,
              snapshot.completedUnitCount >= cancelAtCompletedUnitCount,
              let reporter else {
            return
        }
        didCancel = true
        await reporter.cancel()
    }
}

private func cancelSynchronously(_ reporter: FileOperationProgressReporter) {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await reporter.cancel()
        semaphore.signal()
    }
    XCTAssertEqual(semaphore.wait(timeout: .now() + 2), .success)
}

private struct InjectedMoveFailure: Error {}
private struct InjectedIdentityReadFailure: Error {}

private final class TrashInvocationRecorder: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var invocationCount = 0

    init(root: URL) {
        self.root = root
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCount
    }

    func moveToTrash(_ source: URL) throws -> URL {
        lock.lock()
        invocationCount += 1
        let index = invocationCount
        lock.unlock()
        let destination = root.appendingPathComponent("\(index)-\(source.lastPathComponent)")
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }
}

private final class ReplacingCreatedFolderBeforeReturnFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let displaced: URL
    private let lock = NSLock()
    private var didReplace = false

    init(destination: URL, displaced: URL) {
        self.destination = destination.standardizedFileURL
        self.displaced = displaced.standardizedFileURL
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
        if url.standardizedFileURL == destination {
            try replaceDestinationIfNeeded()
        }
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        if destination.standardizedFileURL == self.destination {
            try replaceDestinationIfNeeded()
        }
    }

    private func replaceDestinationIfNeeded() throws {
        lock.lock()
        guard !didReplace else {
            lock.unlock()
            return
        }
        didReplace = true
        lock.unlock()
        try FileManager.default.moveItem(at: destination, to: displaced)
        try "unrelated".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private final class ReplacingDuplicateBeforeReturnFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let displaced: URL
    private let lock = NSLock()
    private var didReplace = false

    init(destination: URL, displaced: URL) {
        self.destination = destination.standardizedFileURL
        self.displaced = displaced.standardizedFileURL
        super.init()
    }

    override func copyItem(at source: URL, to destination: URL) throws {
        try super.copyItem(at: source, to: destination)
        if destination.standardizedFileURL == self.destination {
            try replaceDestinationIfNeeded()
        }
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        if destination.standardizedFileURL == self.destination {
            try replaceDestinationIfNeeded()
        }
    }

    private func replaceDestinationIfNeeded() throws {
        lock.lock()
        guard !didReplace else {
            lock.unlock()
            return
        }
        didReplace = true
        lock.unlock()
        try FileManager.default.moveItem(at: destination, to: displaced)
        try "unrelated".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private final class ReplacingCommittedMoveBeforeReturn: @unchecked Sendable {
    private let destination: URL
    private let displaced: URL

    init(destination: URL, displaced: URL) {
        self.destination = destination.standardizedFileURL
        self.displaced = displaced.standardizedFileURL
    }

    func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
        try FileManager.default.moveItem(at: self.destination, to: displaced)
        try "unrelated".write(to: self.destination, atomically: true, encoding: .utf8)
    }
}

private final class SwappingCopyRollbackOutputFileManager: FileManager, @unchecked Sendable {
    private let destination: URL
    private let displaced: URL
    private let lock = NSLock()
    private var didSwap = false

    init(destination: URL, displaced: URL) {
        self.destination = destination.standardizedFileURL
        self.displaced = displaced.standardizedFileURL
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
        try "unrelated".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private final class ReplacingCopyOutputBeforeLaterFailure: @unchecked Sendable {
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
        guard call == 1 else {
            try FileManager.default.removeItem(at: firstDestination)
            try "unrelated".write(to: firstDestination, atomically: true, encoding: .utf8)
            throw InjectedMoveFailure()
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

private final class MutatingPublishedCopyBeforeLaterFailure: @unchecked Sendable {
    private let publishedFile: URL
    private let lock = NSLock()
    private var callCount = 0

    init(publishedFile: URL) {
        self.publishedFile = publishedFile
    }

    func move(_ source: URL, to destination: URL) throws {
        lock.lock()
        callCount += 1
        let call = callCount
        lock.unlock()

        guard call == 1 else {
            throw InjectedMoveFailure()
        }
        try FileManager.default.moveItem(at: source, to: destination)
        try "user modified".write(to: publishedFile, atomically: false, encoding: .utf8)
    }
}

private final class ReplacingPublishedCopyBeforeCommitReturns: @unchecked Sendable {
    private let destination: URL

    init(destination: URL) {
        self.destination = destination.standardizedFileURL
    }

    func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
        try FileManager.default.removeItem(at: self.destination)
        try "unrelated".write(to: self.destination, atomically: true, encoding: .utf8)
    }
}

private final class StagingReplacementRecorder: @unchecked Sendable {
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

private struct ReplacingFileConflictResolver: FileConflictResolving {
    var destination: URL
    var displacedDestination: URL
    var replacementContents: String

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try FileManager.default.moveItem(at: destination, to: displacedDestination)
        try replacementContents.write(to: destination, atomically: true, encoding: .utf8)
        return .replace
    }
}

private final class LateDestinationRaceFileManager: FileManager, @unchecked Sendable {
    private let target: URL
    private let injectedContents: Data
    private let lock = NSLock()
    private var didInject = false

    init(target: URL, injectedContents: Data) {
        self.target = target.standardizedFileURL
        self.injectedContents = injectedContents
        super.init()
    }

    override func createFile(
        atPath path: String,
        contents data: Data? = nil,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard shouldInject(at: url) else {
            return super.createFile(atPath: path, contents: data, attributes: attr)
        }
        _ = super.createFile(atPath: path, contents: injectedContents, attributes: attr)
        return false
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        guard shouldInject(at: destination.standardizedFileURL) else {
            try super.moveItem(at: source, to: destination)
            return
        }
        guard super.createFile(atPath: target.path, contents: injectedContents) else {
            throw InjectedMoveFailure()
        }
        throw InjectedMoveFailure()
    }

    private func shouldInject(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didInject, url == target else {
            return false
        }
        didInject = true
        return true
    }
}

private final class PreIdentityCopyStagingFileManager: FileManager, @unchecked Sendable {
    private let recorder: StagingReplacementRecorder

    init(recorder: StagingReplacementRecorder) {
        self.recorder = recorder
        super.init()
    }

    override func createFile(
        atPath path: String,
        contents data: Data? = nil,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().lastPathComponent.hasPrefix(".MyMacFinder-copy-") else {
            return super.createFile(atPath: path, contents: data, attributes: attr)
        }
        _ = super.createFile(atPath: path, contents: Data("unrelated".utf8), attributes: attr)
        recorder.record(url)
        return false
    }
}

private final class FailingMoveSequence: @unchecked Sendable {
    private let failAtCall: Int
    private let lock = NSLock()
    private var callCount = 0

    init(failAtCall: Int) {
        self.failAtCall = failAtCall
    }

    func move(_ source: URL, to destination: URL) throws {
        lock.lock()
        callCount += 1
        let shouldFail = callCount == failAtCall
        lock.unlock()
        if shouldFail {
            throw InjectedMoveFailure()
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

private final class ReplacingMoveRollbackSequence: @unchecked Sendable {
    private let firstDestination: URL
    private let displacedFirstDestination: URL
    private let lock = NSLock()
    private var callCount = 0

    init(firstDestination: URL, displacedFirstDestination: URL) {
        self.firstDestination = firstDestination
        self.displacedFirstDestination = displacedFirstDestination
    }

    func move(_ source: URL, to destination: URL) throws {
        lock.lock()
        callCount += 1
        let call = callCount
        lock.unlock()
        if call == 2 {
            try FileManager.default.moveItem(at: firstDestination, to: displacedFirstDestination)
            try "unrelated".write(to: firstDestination, atomically: true, encoding: .utf8)
            throw InjectedMoveFailure()
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

private final class ReplacingTrashRollbackSequence: @unchecked Sendable {
    private let firstSource: URL
    private let firstTrash: URL
    private let displacedFirstTrash: URL

    init(firstSource: URL, firstTrash: URL, displacedFirstTrash: URL) {
        self.firstSource = firstSource
        self.firstTrash = firstTrash
        self.displacedFirstTrash = displacedFirstTrash
    }

    func trash(_ source: URL) throws -> URL {
        if source.standardizedFileURL == firstSource.standardizedFileURL {
            try FileManager.default.moveItem(at: source, to: firstTrash)
            return firstTrash
        }
        try FileManager.default.moveItem(at: firstTrash, to: displacedFirstTrash)
        try "unrelated".write(to: firstTrash, atomically: true, encoding: .utf8)
        throw InjectedMoveFailure()
    }
}
