import Darwin
import Foundation
import XCTest
@testable import MyMacFinder

final class ArchiveTemporaryArtifactStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var userDefaultsSuiteNames: [String] = []

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
    }

    func testReleaseRejectsArtifactWhoseOwnerDirectoryWasReplaced() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(extractionRoot: root)
        let artifact = try await store.allocate(fileName: "readme.txt")

        try FileManager.default.removeItem(at: artifact.ownerDirectoryURL)
        try FileManager.default.createDirectory(at: artifact.ownerDirectoryURL, withIntermediateDirectories: false)
        let replacement = artifact.ownerDirectoryURL.appendingPathComponent("replacement.txt")
        try "unrelated".write(to: replacement, atomically: true, encoding: .utf8)

        do {
            try await store.release(artifact)
            XCTFail("Expected replaced artifact owner to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "unrelated")
    }

    func testReleaseDoesNotDeleteReplacementInstalledAfterOwnershipValidation() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let originalBackup = root.appendingPathComponent("original-owner-backup", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterReleaseValidation: { owner in
                try FileManager.default.moveItem(at: owner, to: originalBackup)
                try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: false)
                try "keep replacement".write(
                    to: owner.appendingPathComponent("replacement-sentinel.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            })
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the post-validation replacement to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        let replacement = artifact.ownerDirectoryURL.appendingPathComponent("replacement-sentinel.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalBackup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.path))
        if FileManager.default.fileExists(atPath: replacement.path) {
            XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "keep replacement")
        }
    }

    func testReleaseDoesNotDeleteReplacementInstalledAtQuarantinePath() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let originalBackup = root.appendingPathComponent("quarantined-original-backup", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOwnerQuarantine: { quarantine in
                try FileManager.default.moveItem(at: quarantine, to: originalBackup)
                try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
                try "keep quarantine replacement".write(
                    to: quarantine.appendingPathComponent("replacement-sentinel.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            })
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the quarantine replacement to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        let replacement = artifact.ownerDirectoryURL.appendingPathComponent("replacement-sentinel.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalBackup.path))
        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "keep quarantine replacement")
    }

    func testReleasePreservesUnexpectedDirectoryAndReportsItsRestoredPath() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(extractionRoot: root)
        let artifact = try await store.allocate(fileName: "readme.txt")
        let unexpected = artifact.ownerDirectoryURL.appendingPathComponent("unexpected", isDirectory: true)
        let sentinel = unexpected.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: unexpected, withIntermediateDirectories: false)
        try "keep unexpected".write(to: sentinel, atomically: true, encoding: .utf8)

        do {
            try await store.release(artifact)
            XCTFail("Expected an unexpected directory to prevent owner removal")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains(unexpected.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        if FileManager.default.fileExists(atPath: sentinel.path) {
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep unexpected")
        }
    }

    func testReleasePreservesOutputReplacementInsteadOfAuthorizingItsFirstSeenIdentity() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let expectedOutputBackup = tempDirectory.appendingPathComponent("expected-output-backup.txt")
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOwnerQuarantine: { quarantine in
                let output = quarantine.appendingPathComponent("readme.txt")
                try FileManager.default.moveItem(at: output, to: expectedOutputBackup)
                try "keep replacement".write(to: output, atomically: true, encoding: .utf8)
            })
        )
        var artifact = try await store.allocate(fileName: "readme.txt")
        let output = try await store.openOutputFile(for: artifact)
        try output.write(Data("expected output".utf8))
        try output.close()
        artifact = artifact.recordingOutputIdentity(output.identity)

        do {
            try await store.release(artifact)
            XCTFail("Expected a same-name output replacement to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains(artifact.url.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.url.path))
        if FileManager.default.fileExists(atPath: artifact.url.path) {
            XCTAssertEqual(try String(contentsOf: artifact.url, encoding: .utf8), "keep replacement")
        }
        XCTAssertEqual(try String(contentsOf: expectedOutputBackup, encoding: .utf8), "expected output")
    }

    func testReleasePreservesReplacementInstalledAfterOutputEnumerationBeforeQuarantine() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let expectedOutputBackup = tempDirectory.appendingPathComponent("enumerated-output-backup.txt")
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOutputEnumeration: { output in
                try FileManager.default.moveItem(at: output, to: expectedOutputBackup)
                try "keep enumerated replacement".write(to: output, atomically: true, encoding: .utf8)
            })
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the post-enumeration replacement to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains(artifact.url.path))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.url.path))
        if FileManager.default.fileExists(atPath: artifact.url.path) {
            XCTAssertEqual(try String(contentsOf: artifact.url, encoding: .utf8), "keep enumerated replacement")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOutputBackup.path))
    }

    func testReleasePreservesReplacementInstalledAfterOutputQuarantineBeforeUnlink() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let expectedOutputBackup = tempDirectory.appendingPathComponent("quarantined-output-backup.txt")
        let quarantinedPath = URLRecorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOutputQuarantine: { quarantine in
                quarantinedPath.record(quarantine)
                try FileManager.default.moveItem(at: quarantine, to: expectedOutputBackup)
                try "keep quarantined replacement".write(to: quarantine, atomically: true, encoding: .utf8)
            })
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the post-quarantine replacement to be rejected")
        } catch let error as ExplorerError {
            if let capturedPath = quarantinedPath.value {
                let restoredPath = artifact.ownerDirectoryURL.appendingPathComponent(capturedPath.lastPathComponent)
                XCTAssertTrue(error.localizedDescription.contains(restoredPath.path))
            } else {
                XCTFail("Expected the output quarantine hook to run")
            }
        }

        if let capturedPath = quarantinedPath.value {
            let restoredPath = artifact.ownerDirectoryURL.appendingPathComponent(capturedPath.lastPathComponent)
            XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath.path))
            if FileManager.default.fileExists(atPath: restoredPath.path) {
                XCTAssertEqual(
                    try String(contentsOf: restoredPath, encoding: .utf8),
                    "keep quarantined replacement"
                )
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOutputBackup.path))
    }

    func testReleasePreservesReplacementInstalledBeforeFinalOwnerUnlink() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let expectedOwnerBackup = tempDirectory.appendingPathComponent("expected-owner-backup", isDirectory: true)
        let replacementOwnerPath = URLRecorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(beforeOwnerUnlink: { quarantine in
                replacementOwnerPath.record(quarantine)
                try FileManager.default.moveItem(at: quarantine, to: expectedOwnerBackup)
                try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
                try "keep owner replacement".write(
                    to: quarantine.appendingPathComponent("replacement-sentinel.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            })
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the final owner replacement to be rejected")
        } catch let error as ExplorerError {
            if let replacementOwnerPath = replacementOwnerPath.value {
                XCTAssertTrue(error.localizedDescription.contains(replacementOwnerPath.path))
            } else {
                XCTFail("Expected the final owner unlink hook to run")
            }
        }

        if let replacementOwnerPath = replacementOwnerPath.value {
            let sentinel = replacementOwnerPath.appendingPathComponent("replacement-sentinel.txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOwnerBackup.path))
    }

    func testReleaseRebasesFinalOwnerUnlinkFailureToRestoredOwnerPath() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let quarantinedOwner = URLRecorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(beforeOwnerUnlink: { quarantine in
                quarantinedOwner.record(quarantine)
                try "keep late child".write(
                    to: quarantine.appendingPathComponent("late-sentinel.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            })
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the late child to prevent owner removal")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains(artifact.ownerDirectoryURL.path))
            if let quarantinedOwner = quarantinedOwner.value {
                XCTAssertFalse(error.localizedDescription.contains(quarantinedOwner.path))
            } else {
                XCTFail("Expected the final owner unlink hook to run")
            }
        }

        let restoredSentinel = artifact.ownerDirectoryURL.appendingPathComponent("late-sentinel.txt")
        XCTAssertEqual(try String(contentsOf: restoredSentinel, encoding: .utf8), "keep late child")
    }

    func testDirectoryEnumerationDuplicateIsCloseOnExec() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let descriptorFlags = Int32Recorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterDirectoryDescriptorDuplicate: { descriptor in
                descriptorFlags.record(Darwin.fcntl(descriptor, F_GETFD))
            })
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        try await store.release(artifact)

        XCTAssertNotNil(descriptorFlags.value)
        if let flags = descriptorFlags.value {
            XCTAssertEqual(flags & FD_CLOEXEC, FD_CLOEXEC)
        }
    }

    func testDirectoryStreamCloseFailureIsReportedAndOwnerIsRestored() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let quarantinedOwner = URLRecorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(
                afterOwnerQuarantine: { quarantinedOwner.record($0) },
                closeDirectoryStream: { directory in
                    _ = Darwin.closedir(directory)
                    errno = EIO
                    return -1
                }
            )
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected directory stream close failure")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("close archive preview directory stream"))
            XCTAssertTrue(error.localizedDescription.contains(artifact.ownerDirectoryURL.path))
            if let quarantinedOwner = quarantinedOwner.value {
                XCTAssertFalse(error.localizedDescription.contains(quarantinedOwner.path))
            } else {
                XCTFail("Expected the owner quarantine hook to run")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(try String(contentsOf: artifact.url, encoding: .utf8), "expected output")
    }

    func testDirectoryEnumerationErrorWinsWhenDirectoryStreamCloseAlsoFails() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(
                beforeDirectoryEntryRead: {
                    throw InjectedDirectoryEnumerationFailure()
                },
                closeDirectoryStream: { directory in
                    _ = Darwin.closedir(directory)
                    errno = EIO
                    return -1
                }
            )
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected the injected enumeration failure")
        } catch is InjectedDirectoryEnumerationFailure {
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
    }

    func testReleaseRestoreDoesNotOverwriteReplacementInstalledAfterAbsenceCheck() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let originalBackup = root.appendingPathComponent("original-owner-backup", isDirectory: true)
        let replacementIdentity = EntryIdentityRecorder()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(
                afterReleaseValidation: { owner in
                    try FileManager.default.moveItem(at: owner, to: originalBackup)
                    try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: false)
                    try "first replacement".write(
                        to: owner.appendingPathComponent("first-sentinel.txt"),
                        atomically: true,
                        encoding: .utf8
                    )
                },
                beforeQuarantineRestore: { owner in
                    try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: false)
                    guard let identity = FileSystemPathIdentity.entryIdentity(owner) else {
                        throw ExplorerError.operationFailed("Replacement owner identity is unavailable")
                    }
                    replacementIdentity.record(identity)
                }
            )
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        do {
            try await store.release(artifact)
            XCTFail("Expected exclusive restore to reject the new owner")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("preserved"))
        }

        XCTAssertEqual(
            FileSystemPathIdentity.entryIdentity(artifact.ownerDirectoryURL),
            replacementIdentity.value
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalBackup.path))
        let quarantineURLs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".MyMacFinderArchivePreview-") }
        XCTAssertEqual(quarantineURLs.count, 1)
        let firstSentinel = try XCTUnwrap(quarantineURLs.first)
            .appendingPathComponent("first-sentinel.txt")
        XCTAssertEqual(try String(contentsOf: firstSentinel, encoding: .utf8), "first replacement")
    }

    func testAllocationAndOutputUsePrivatePermissions() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(extractionRoot: root)
        let artifact = try await store.allocate(fileName: "readme.txt")
        let output = try await store.openOutputFile(for: artifact)
        try output.write(Data("preview".utf8))
        try output.close()

        let rootMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        ).uint16Value
        let ownerMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: artifact.ownerDirectoryURL.path)[.posixPermissions] as? NSNumber
        ).uint16Value
        let outputMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: artifact.url.path)[.posixPermissions] as? NSNumber
        ).uint16Value

        XCTAssertEqual(rootMode & 0o777, 0o700)
        XCTAssertEqual(ownerMode & 0o777, 0o700)
        XCTAssertEqual(outputMode & 0o777, 0o600)
    }

    func testReleaseRejectsOwnerSymlinkEscapingExtractionRoot() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let outside = tempDirectory.appendingPathComponent("outside", isDirectory: true)
        let sentinel = outside.appendingPathComponent("unrelated.txt")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        let store = ArchiveTemporaryArtifactStore(extractionRoot: root)
        let artifact = try await store.allocate(fileName: "readme.txt")
        try FileManager.default.removeItem(at: artifact.ownerDirectoryURL)
        try FileManager.default.createSymbolicLink(atPath: artifact.ownerDirectoryURL.path, withDestinationPath: outside.path)

        do {
            try await store.release(artifact)
            XCTFail("Expected symlinked artifact owner to be rejected")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("not a directory"))
        }

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testPendingCleanupRetrySurvivesStoreRecreation() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let suiteName = "MyMacFinderArchiveArtifactRegistry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = ArchiveTemporaryArtifactCleanupRegistry(userDefaults: defaults)
        let failingStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOwnerQuarantine: { _ in
                throw InjectedArtifactCleanupFailure()
            })
        )
        let artifact = try await failingStore.allocate(fileName: "readme.txt")

        do {
            try await failingStore.release(artifact)
            XCTFail("Expected cleanup to fail")
        } catch is InjectedArtifactCleanupFailure {
        }
        try await failingStore.scheduleCleanupRetry(artifact)

        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry
        )
        try await restartedStore.retryPendingCleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertTrue(try registry.load().isEmpty)
    }

    func testReleaseRemovesCompletedEmptyOwnerAndClearsPersistedRecords() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let registry = try makeRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )
        let artifact = try await makeCompletedArtifact(in: store, fileName: "readme.txt")
        try await store.scheduleCleanupRetry(artifact)
        try await store.registerExternalOpen(
            artifact,
            openedAt: Date(timeIntervalSinceReferenceDate: 15_000)
        )
        try FileManager.default.removeItem(at: artifact.url)

        try await store.release(artifact)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertTrue(try registry.cleanup.load().isEmpty)
        XCTAssertTrue(try registry.retention.load().isEmpty)
    }

    func testExternalOpenRetentionKeepsArtifactBeforeTwentyFourHours() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let registry = try makeRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )
        let artifact = try await store.allocate(fileName: "readme.txt")
        let openedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        try await store.registerExternalOpen(artifact, openedAt: openedAt)

        try await store.cleanupExpired(now: openedAt.addingTimeInterval(24 * 60 * 60 - 1), retentionInterval: 24 * 60 * 60)

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
    }

    func testExternalOpenRetentionExpiresAtTwentyFourHourBoundaryAfterRestart() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let openedAt = Date(timeIntervalSinceReferenceDate: 20_000)
        let registry = try makeRegistry()
        let firstStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )
        let artifact = try await firstStore.allocate(fileName: "readme.txt")
        try await firstStore.registerExternalOpen(artifact, openedAt: openedAt)
        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )

        try await restartedStore.cleanupExpired(now: openedAt.addingTimeInterval(24 * 60 * 60), retentionInterval: 24 * 60 * 60)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
    }

    func testExpiredRetentionIgnoresMissingArtifact() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let registry = try makeRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )
        let artifact = try await store.allocate(fileName: "readme.txt")
        let openedAt = Date(timeIntervalSinceReferenceDate: 30_000)
        try await store.registerExternalOpen(artifact, openedAt: openedAt)
        try FileManager.default.removeItem(at: artifact.ownerDirectoryURL)

        try await store.cleanupExpired(now: openedAt.addingTimeInterval(24 * 60 * 60), retentionInterval: 24 * 60 * 60)
    }

    func testPendingCleanupRetryIgnoresMissingArtifact() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let registry = try makeRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: registry.cleanup,
            retentionRegistry: registry.retention
        )
        let artifact = try await store.allocate(fileName: "readme.txt")
        try await store.scheduleCleanupRetry(artifact)
        try FileManager.default.removeItem(at: artifact.ownerDirectoryURL)

        try await store.retryPendingCleanup()

        XCTAssertTrue(try registry.cleanup.load().isEmpty)
    }

    func testCorruptPendingCleanupRegistryIsPreservedWhenSchedulingRetry() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let cleanupRegistry = CorruptCleanupRegistry()
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry()
        )
        let artifact = try await seedStore.allocate(fileName: "readme.txt")
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await store.scheduleCleanupRetry(artifact),
            containing: "cleanup registry is unavailable"
        )

        XCTAssertEqual(cleanupRegistry.saveCallCount, 0)
    }

    func testCorruptPendingCleanupRegistryIsPreservedWhenRetryingAtStartup() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let cleanupRegistry = CorruptCleanupRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await store.retryPendingCleanup(),
            containing: "cleanup registry is unavailable"
        )

        XCTAssertEqual(cleanupRegistry.saveCallCount, 0)
    }

    func testDuplicatePendingCleanupIdentifiersArePreservedAndDisableSchedulingAndRetry() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry()
        )
        let artifact = try await seedStore.allocate(fileName: "readme.txt")
        let record = PendingArchiveTemporaryArtifactCleanup(artifact)
        let cleanupRegistry = DuplicateCleanupRegistry(records: [record, record])
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await store.scheduleCleanupRetry(artifact),
            containing: "cleanup registry is unavailable"
        )
        await XCTAssertThrowsOperationFailedAsync(
            try await store.retryPendingCleanup(),
            containing: "cleanup registry is unavailable"
        )

        XCTAssertEqual(cleanupRegistry.saveCallCount, 0)
    }

    func testCorruptRetentionRegistryIsPreservedWhenRegisteringExternalOpen() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let retentionRegistry = CorruptRetentionRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry(),
            retentionRegistry: retentionRegistry
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        await XCTAssertThrowsErrorAsync(
            try await store.registerExternalOpen(
                artifact,
                openedAt: Date(timeIntervalSinceReferenceDate: 40_000)
            )
        )

        XCTAssertEqual(retentionRegistry.saveCallCount, 0)
    }

    func testDuplicateRetentionIdentifiersArePreservedWhenRegisteringExternalOpen() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry()
        )
        let artifact = try await seedStore.allocate(fileName: "readme.txt")
        let record = RetainedArchiveTemporaryArtifact(
            artifact,
            openedAt: Date(timeIntervalSinceReferenceDate: 45_000)
        )
        let retentionRegistry = DuplicateRetentionRegistry(records: [record, record])
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry(),
            retentionRegistry: retentionRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await store.registerExternalOpen(
                artifact,
                openedAt: Date(timeIntervalSinceReferenceDate: 45_001)
            ),
            containing: "retention registry is unavailable"
        )

        XCTAssertEqual(retentionRegistry.saveCallCount, 0)
    }

    func testExternalOpenRegistrationFailsWhenRetentionCannotPersist() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: InMemoryCleanupRegistry(),
            retentionRegistry: FailingRetentionRegistry()
        )
        let artifact = try await store.allocate(fileName: "readme.txt")

        await XCTAssertThrowsErrorAsync(
            try await store.registerExternalOpen(
                artifact,
                openedAt: Date(timeIntervalSinceReferenceDate: 50_000)
            )
        )
    }

    func testCorruptCleanupRegistryDoesNotBlockValidExpiredRetentionCleanup() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let retentionRegistry = RecordingRetentionRegistry()
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: RecordingCleanupRegistry(),
            retentionRegistry: retentionRegistry
        )
        let artifact = try await seedStore.allocate(fileName: "expired.txt")
        let openedAt = Date(timeIntervalSinceReferenceDate: 60_000)
        try await seedStore.registerExternalOpen(artifact, openedAt: openedAt)
        let corruptCleanup = CorruptCleanupRegistry()
        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: corruptCleanup,
            retentionRegistry: retentionRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await restartedStore.cleanupExpired(
                now: openedAt.addingTimeInterval(24 * 60 * 60),
                retentionInterval: 24 * 60 * 60
            ),
            containing: "cleanup registry is unavailable"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(corruptCleanup.saveCallCount, 0)
    }

    func testDuplicateCleanupRegistryDoesNotBlockValidExpiredRetentionCleanup() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let retentionRegistry = RecordingRetentionRegistry()
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: RecordingCleanupRegistry(),
            retentionRegistry: retentionRegistry
        )
        let artifact = try await seedStore.allocate(fileName: "expired.txt")
        let openedAt = Date(timeIntervalSinceReferenceDate: 70_000)
        try await seedStore.registerExternalOpen(artifact, openedAt: openedAt)
        let record = PendingArchiveTemporaryArtifactCleanup(artifact)
        let duplicateCleanup = DuplicateCleanupRegistry(records: [record, record])
        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: duplicateCleanup,
            retentionRegistry: retentionRegistry
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await restartedStore.cleanupExpired(
                now: openedAt.addingTimeInterval(24 * 60 * 60),
                retentionInterval: 24 * 60 * 60
            ),
            containing: "cleanup registry is unavailable"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(duplicateCleanup.saveCallCount, 0)
    }

    func testCorruptRetentionRegistryDoesNotBlockValidPendingCleanup() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let cleanupRegistry = RecordingCleanupRegistry()
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: RecordingRetentionRegistry()
        )
        let artifact = try await seedStore.allocate(fileName: "pending.txt")
        try await seedStore.scheduleCleanupRetry(artifact)
        let corruptRetention = CorruptRetentionRegistry()
        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: corruptRetention
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await restartedStore.cleanupExpired(now: Date(), retentionInterval: 24 * 60 * 60),
            containing: "retention registry is unavailable"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(corruptRetention.saveCallCount, 0)
    }

    func testDuplicateRetentionRegistryDoesNotBlockValidPendingCleanup() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let cleanupRegistry = RecordingCleanupRegistry()
        let seedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: RecordingRetentionRegistry()
        )
        let artifact = try await seedStore.allocate(fileName: "pending.txt")
        try await seedStore.scheduleCleanupRetry(artifact)
        let retainedRecord = RetainedArchiveTemporaryArtifact(
            artifact,
            openedAt: Date(timeIntervalSinceReferenceDate: 80_000)
        )
        let duplicateRetention = DuplicateRetentionRegistry(records: [retainedRecord, retainedRecord])
        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: duplicateRetention
        )

        await XCTAssertThrowsOperationFailedAsync(
            try await restartedStore.cleanupExpired(now: Date(), retentionInterval: 24 * 60 * 60),
            containing: "retention registry is unavailable"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(duplicateRetention.saveCallCount, 0)
    }

    func testCleanupExpiredReportsBothUnavailableRegistryPhasesWithoutWritingEither() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let corruptCleanup = CorruptCleanupRegistry()
        let corruptRetention = CorruptRetentionRegistry()
        let store = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: corruptCleanup,
            retentionRegistry: corruptRetention
        )

        do {
            try await store.cleanupExpired(now: Date(), retentionInterval: 24 * 60 * 60)
            XCTFail("Expected both unusable cleanup phases to be reported")
        } catch ExplorerError.operationFailed(let message) {
            XCTAssertTrue(message.contains("cleanup registry is unavailable"))
            XCTAssertTrue(message.contains("retention registry is unavailable"))
        }

        XCTAssertEqual(corruptCleanup.saveCallCount, 0)
        XCTAssertEqual(corruptRetention.saveCallCount, 0)
    }

    func testPersistedQuickLookCleanupOwnershipSurvivesStoreRecreationAndRemovesOnlyRecordedOwner() async throws {
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let sentinel = root.appendingPathComponent("unrelated-sentinel.txt")
        let cleanupRegistry = RecordingCleanupRegistry()
        let firstStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: RecordingRetentionRegistry()
        )
        var artifact = try await firstStore.allocate(fileName: "quick-look.txt")
        let output = try await firstStore.openOutputFile(for: artifact)
        try output.write(Data("preview".utf8))
        try output.close()
        artifact = artifact.recordingOutputIdentity(output.identity)
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
        try await firstStore.scheduleCleanupRetry(artifact)

        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            retentionRegistry: RecordingRetentionRegistry()
        )
        try await restartedStore.retryPendingCleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
        XCTAssertTrue(cleanupRegistry.records.isEmpty)
    }

    private func makeRegistry() throws -> (
        cleanup: ArchiveTemporaryArtifactCleanupRegistry,
        retention: ArchiveTemporaryArtifactRetentionRegistry
    ) {
        let suiteName = "MyMacFinderArchiveArtifactRegistry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        userDefaultsSuiteNames.append(suiteName)
        return (
            ArchiveTemporaryArtifactCleanupRegistry(userDefaults: defaults),
            ArchiveTemporaryArtifactRetentionRegistry(userDefaults: defaults)
        )
    }

    private func makeCompletedArtifact(
        in store: ArchiveTemporaryArtifactStore,
        fileName: String,
        contents: String = "expected output"
    ) async throws -> TemporaryArchiveArtifact {
        let artifact = try await store.allocate(fileName: fileName)
        let output = try await store.openOutputFile(for: artifact)
        try output.write(Data(contents.utf8))
        try output.close()
        return artifact.recordingOutputIdentity(output.identity)
    }
}

private struct CorruptRegistryError: Error {}
private struct InjectedDirectoryEnumerationFailure: Error {}

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: URL?

    var value: URL? {
        lock.withLock { recordedValue }
    }

    func record(_ value: URL) {
        lock.withLock {
            recordedValue = value
        }
    }
}

private final class Int32Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: Int32?

    var value: Int32? {
        lock.withLock { recordedValue }
    }

    func record(_ value: Int32) {
        lock.withLock {
            recordedValue = value
        }
    }
}

private final class CorruptCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    var saveCallCount = 0

    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] {
        throw CorruptRegistryError()
    }

    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws {
        saveCallCount += 1
    }
}

private final class DuplicateCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    let records: [PendingArchiveTemporaryArtifactCleanup]
    var saveCallCount = 0

    init(records: [PendingArchiveTemporaryArtifactCleanup]) {
        self.records = records
    }

    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] {
        records
    }

    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws {
        saveCallCount += 1
    }
}

private final class CorruptRetentionRegistry: ArchiveTemporaryArtifactRetentionPersisting, @unchecked Sendable {
    var saveCallCount = 0

    func load() throws -> [RetainedArchiveTemporaryArtifact] {
        throw CorruptRegistryError()
    }

    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws {
        saveCallCount += 1
    }
}

private final class DuplicateRetentionRegistry: ArchiveTemporaryArtifactRetentionPersisting, @unchecked Sendable {
    let records: [RetainedArchiveTemporaryArtifact]
    var saveCallCount = 0

    init(records: [RetainedArchiveTemporaryArtifact]) {
        self.records = records
    }

    func load() throws -> [RetainedArchiveTemporaryArtifact] {
        records
    }

    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws {
        saveCallCount += 1
    }
}

private final class InMemoryCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] { [] }
    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws {}
}

private final class RecordingCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    var records: [PendingArchiveTemporaryArtifactCleanup] = []

    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] { records }
    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws { self.records = records }
}

private final class RecordingRetentionRegistry: ArchiveTemporaryArtifactRetentionPersisting, @unchecked Sendable {
    var records: [RetainedArchiveTemporaryArtifact] = []

    func load() throws -> [RetainedArchiveTemporaryArtifact] { records }
    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws { self.records = records }
}

private final class FailingRetentionRegistry: ArchiveTemporaryArtifactRetentionPersisting, @unchecked Sendable {
    func load() throws -> [RetainedArchiveTemporaryArtifact] { [] }
    func save(_ records: [RetainedArchiveTemporaryArtifact]) throws {
        throw CorruptRegistryError()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}

private func XCTAssertThrowsOperationFailedAsync(
    _ expression: @autoclosure () async throws -> Void,
    containing expectedMessage: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected ExplorerError.operationFailed", file: file, line: line)
    } catch ExplorerError.operationFailed(let message) {
        XCTAssertTrue(message.contains(expectedMessage), file: file, line: line)
    } catch {
        XCTFail("Expected ExplorerError.operationFailed, got \(error)", file: file, line: line)
    }
}

private struct InjectedArtifactCleanupFailure: Error {}

private final class EntryIdentityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: FileSystemPathIdentity.FileSystemEntryIdentity?

    var value: FileSystemPathIdentity.FileSystemEntryIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return recordedValue
    }

    func record(_ value: FileSystemPathIdentity.FileSystemEntryIdentity) {
        lock.lock()
        recordedValue = value
        lock.unlock()
    }
}
