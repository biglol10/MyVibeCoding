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
            try? FileManager.default.removeItem(at: tempDirectory)
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
        let possibleTrashFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(existingFolder.lastPathComponent, isDirectory: true)
        defer {
            if !FileManager.default.fileExists(atPath: existingFolder.path),
               FileManager.default.fileExists(atPath: possibleTrashFolder.path) {
                try? FileManager.default.moveItem(at: possibleTrashFolder, to: existingFolder)
            }
        }
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "keep".write(
            to: existingFolder.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = ZipExtractionService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

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
        let possibleTrashFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(existingFolder.lastPathComponent, isDirectory: true)
        defer {
            if !FileManager.default.fileExists(atPath: existingFolder.appendingPathComponent("keep.txt").path),
               FileManager.default.fileExists(atPath: possibleTrashFolder.path) {
                try? FileManager.default.removeItem(at: existingFolder)
                try? FileManager.default.moveItem(at: possibleTrashFolder, to: existingFolder)
            }
            try? FileManager.default.removeItem(at: possibleTrashFolder)
        }
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
        let service = ZipExtractionService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

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
