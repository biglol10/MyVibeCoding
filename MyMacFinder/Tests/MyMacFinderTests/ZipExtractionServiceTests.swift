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

    private func makeArchive(named name: String) throws -> URL {
        let source = tempDirectory.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "hello".write(to: source.appendingPathComponent("docs/readme.txt"), atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory.appendingPathComponent(name)
        try FileManager.default.zipItem(at: source, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        return archiveURL
    }
}

private actor ZipProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}
