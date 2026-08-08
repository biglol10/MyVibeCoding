import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ArchiveBrowsingServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCanOpenOnlyZipFiles() {
        let service = ArchiveBrowsingService()

        XCTAssertTrue(service.canOpen(URL(fileURLWithPath: "/tmp/archive.zip")))
        XCTAssertFalse(service.canOpen(URL(fileURLWithPath: "/tmp/archive.txt")))
    }

    func testListsRootAndNestedFolders() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()

        let rootEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: ""),
            showHiddenFiles: false
        )
        XCTAssertEqual(rootEntries.map(\.name).sorted(), ["docs", "hidden", "image.png"])
        XCTAssertTrue(rootEntries.first { $0.name == "docs" }?.isDirectory == true)

        let nestedEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"),
            showHiddenFiles: false
        )
        XCTAssertEqual(nestedEntries.map(\.name).sorted(), ["readme.txt"])
        XCTAssertEqual(nestedEntries.first?.size, 5)
    }

    func testFiltersHiddenEntries() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "hidden")

        let hiddenOff = try await service.list(location, showHiddenFiles: false)
        let hiddenOn = try await service.list(location, showHiddenFiles: true)

        XCTAssertEqual(hiddenOff.map(\.name), [])
        XCTAssertEqual(hiddenOn.map(\.name), [".secret"])
    }

    func testTemporaryExtractReturnsOwnedArtifactAndReleaseRemovesOnlyOwnerDirectory() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let sentinel = root.appendingPathComponent("unrelated.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: sentinel)
        let service = ArchiveBrowsingService(extractionRoot: root)

        let artifact = try await service.temporaryExtract(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
        )
        XCTAssertEqual(try String(contentsOf: artifact.url, encoding: .utf8), "hello")
        try await service.releaseTemporaryArtifact(artifact)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testTemporaryExtractDoesNotFollowOwnerSymlinkInstalledBeforeDestinationOpen() async throws {
        let archiveURL = try makeArchive()
        let originalArchiveData = try Data(contentsOf: archiveURL)
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let outside = tempDirectory.appendingPathComponent("outside", isDirectory: true)
        let outsideSentinel = outside.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try "keep".write(to: outsideSentinel, atomically: true, encoding: .utf8)
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(beforeOutputOwnerOpen: { artifact in
                let owner = artifact.ownerDirectoryURL
                let originalOwner = root.appendingPathComponent("original-owner", isDirectory: true)
                try FileManager.default.moveItem(at: owner, to: originalOwner)
                try FileManager.default.createSymbolicLink(atPath: owner.path, withDestinationPath: outside.path)
            })
        )

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
            XCTFail("Expected the owner symlink swap to prevent extraction")
        } catch {
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("readme.txt").path))
        XCTAssertEqual(try String(contentsOf: outsideSentinel, encoding: .utf8), "keep")
        XCTAssertEqual(try Data(contentsOf: archiveURL), originalArchiveData)
    }

    func testTemporaryExtractDoesNotFollowLeafSymlinkInstalledBeforeDestinationOpen() async throws {
        let archiveURL = try makeArchive()
        let originalArchiveData = try Data(contentsOf: archiveURL)
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let outside = tempDirectory.appendingPathComponent("outside.txt")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(beforeOutputLeafOpen: { artifact in
                try FileManager.default.createSymbolicLink(
                    atPath: artifact.url.path,
                    withDestinationPath: outside.path
                )
            })
        )

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
            XCTFail("Expected the leaf symlink swap to prevent extraction")
        } catch {
        }

        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep")
        XCTAssertEqual(try Data(contentsOf: archiveURL), originalArchiveData)
        let preservedEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(preservedEntries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testTemporaryExtractRejectsOwnerReplacementAfterPublicationDescriptorOpen() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let originalOwnerBackup = tempDirectory.appendingPathComponent("publication-owner-backup", isDirectory: true)
        let replacementOutput = BrowsingURLRecorder()
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterPublishedOutputOwnerOpen: { artifact in
                replacementOutput.record(artifact.url)
                try FileManager.default.moveItem(at: artifact.ownerDirectoryURL, to: originalOwnerBackup)
                try FileManager.default.createDirectory(at: artifact.ownerDirectoryURL, withIntermediateDirectories: false)
                try "keep publication replacement".write(
                    to: artifact.url,
                    atomically: true,
                    encoding: .utf8
                )
            })
        )

        do {
            let artifact = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
            try? await service.releaseTemporaryArtifact(artifact)
            XCTFail("Expected publication owner replacement to fail extraction")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalOwnerBackup.path))
        XCTAssertNotNil(replacementOutput.value)
        if let replacementOutput = replacementOutput.value {
            XCTAssertTrue(FileManager.default.fileExists(atPath: replacementOutput.path))
            XCTAssertEqual(
                try String(contentsOf: replacementOutput, encoding: .utf8),
                "keep publication replacement"
            )
        }
    }

    func testExtractionFailureRemovesPartialOwnerDirectory() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            extractionHandler: { _, _, _, consumer in
                try consumer(Data("partial".utf8))
                throw InjectedExtractionFailure()
            }
        )

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
            XCTFail("Expected extraction to fail")
        } catch is InjectedExtractionFailure {
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testTemporaryExtractUsesInjectedFileManagerForArtifactAllocation() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let service = ArchiveBrowsingService(
            fileManager: FailingArtifactAllocationFileManager(),
            extractionRoot: root
        )

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
            XCTFail("Expected injected file manager to reject artifact allocation")
        } catch is InjectedArtifactAllocationFailure {
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCancelledExtractionRethrowsCancellationErrorAndRemovesPartialOwnerDirectory() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let probe = ExtractionCancellationProbe()
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            extractionHandler: { _, _, progress, consumer in
                try consumer(Data("partial".utf8))
                probe.markStarted()
                while !progress.isCancelled {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                throw InjectedExtractionFailure()
            }
        )

        let task = Task {
            try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
        }
        try await waitForExtractionToStart(probe)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected extraction cancellation")
        } catch is CancellationError {
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCancelledExtractionPersistsPartialOutputIdentityForCleanupRetryAfterRestart() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sentinel = root.appendingPathComponent("unrelated-sentinel.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
        let probe = ExtractionCancellationProbe()
        let suiteName = "MyMacFinderArchiveArtifactRegistry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cleanupRegistry = ArchiveTemporaryArtifactCleanupRegistry(userDefaults: defaults)
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry,
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOwnerQuarantine: { _ in
                throw InjectedArtifactCleanupFailure()
            }),
            extractionHandler: { _, _, progress, consumer in
                try consumer(Data("partial".utf8))
                probe.markStarted()
                while !progress.isCancelled {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                throw InjectedExtractionFailure()
            }
        )

        let task = Task {
            try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
        }
        try await waitForExtractionToStart(probe)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected extraction cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let records = try cleanupRegistry.load()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        let outputIdentity = try XCTUnwrap(
            FileSystemPathIdentity.entryIdentity(URL(fileURLWithPath: record.urlPath))
        )
        XCTAssertEqual(record.expectedOutputDevice, outputIdentity.device)
        XCTAssertEqual(record.expectedOutputInode, outputIdentity.inode)
        XCTAssertEqual(record.expectedOutputGeneration, outputIdentity.generation)
        XCTAssertEqual(record.expectedOutputMode, outputIdentity.mode)

        let restartedStore = ArchiveTemporaryArtifactStore(
            extractionRoot: root,
            cleanupRegistry: cleanupRegistry
        )
        try await restartedStore.retryPendingCleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: record.ownerDirectoryPath))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
        XCTAssertTrue(try cleanupRegistry.load().isEmpty)
    }

    func testCancelledExtractionRethrowsCancellationErrorWhenCleanupRetryCannotBeScheduled() async throws {
        let archiveURL = try makeArchive()
        let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
        let probe = ExtractionCancellationProbe()
        let service = ArchiveBrowsingService(
            extractionRoot: root,
            cleanupRegistry: FailingArtifactCleanupRegistry(),
            fileSystemHooks: ArchiveTemporaryFileSystemHooks(afterOwnerQuarantine: { _ in
                throw InjectedArtifactCleanupFailure()
            }),
            extractionHandler: { _, _, progress, consumer in
                try consumer(Data("partial".utf8))
                probe.markStarted()
                while !progress.isCancelled {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                throw InjectedExtractionFailure()
            }
        )

        let task = Task {
            try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
            )
        }
        try await waitForExtractionToStart(probe)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected extraction cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testInvalidZipThrowsReadableExplorerError() async throws {
        let invalid = tempDirectory.appendingPathComponent("broken.zip")
        try "not a zip".write(to: invalid, atomically: true, encoding: .utf8)
        let service = ArchiveBrowsingService()

        do {
            _ = try await service.list(
                ArchiveLocation(archiveURL: invalid, internalPath: ""),
                showHiddenFiles: false
            )
            XCTFail("Expected invalid archive to throw")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("ZIP"))
        }
    }

    func testListSkipsUnsafeArchiveEntryPaths() async throws {
        let archiveURL = try makeArchive(
            entries: [
                ("safe.txt", "safe"),
                ("../evil.txt", "evil"),
                ("/absolute.txt", "absolute"),
                ("C:/windows.txt", "windows")
            ]
        )
        let service = ArchiveBrowsingService()

        let entries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: ""),
            showHiddenFiles: true
        )

        XCTAssertEqual(entries.map(\.name), ["safe.txt"])
    }

    func testTemporaryExtractRejectsUnsafeArchiveEntryPaths() async throws {
        let archiveURL = try makeArchive(entries: [("../evil.txt", "evil")])
        let service = ArchiveBrowsingService()

        do {
            _ = try await service.temporaryExtract(
                ArchiveLocation(archiveURL: archiveURL, internalPath: "../evil.txt")
            )
            XCTFail("Expected unsafe archive entry preview to fail")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("outside destination"))
        }
    }

    private func makeArchive() throws -> URL {
        try makeArchive(
            entries: [
                ("docs/readme.txt", "hello"),
                ("image.png", String(decoding: Data([0x89, 0x50, 0x4E, 0x47]), as: UTF8.self)),
                ("hidden/.secret", "secret")
            ]
        )
    }

    private func makeArchive(entries: [(path: String, contents: String)]) throws -> URL {
        let source = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let archiveURL = tempDirectory.appendingPathComponent("fixture.zip")
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

    private func waitForExtractionToStart(_ probe: ExtractionCancellationProbe) async throws {
        for _ in 0..<100 {
            if probe.hasStarted {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for extraction to start")
    }
}

private struct InjectedExtractionFailure: Error {}
private struct InjectedArtifactAllocationFailure: Error {}

private final class BrowsingURLRecorder: @unchecked Sendable {
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

private final class FailingArtifactAllocationFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        throw InjectedArtifactAllocationFailure()
    }
}

private struct InjectedArtifactCleanupFailure: Error {}

private final class FailingArtifactCleanupRegistry: ArchiveTemporaryArtifactCleanupPersisting, @unchecked Sendable {
    func load() throws -> [PendingArchiveTemporaryArtifactCleanup] {
        []
    }

    func save(_ records: [PendingArchiveTemporaryArtifactCleanup]) throws {
        throw InjectedArtifactCleanupFailure()
    }
}

private final class ExtractionCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func markStarted() {
        lock.lock()
        started = true
        lock.unlock()
    }
}
