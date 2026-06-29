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
            try? FileManager.default.removeItem(at: tempDirectory)
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

    func testReplaceRestoresExistingArchiveWhenCompressionFailsAfterTrash() async throws {
        let note = tempDirectory.appendingPathComponent("replace-compress-failure-\(UUID().uuidString).txt")
        try "note".write(to: note, atomically: true, encoding: .utf8)
        let existingArchive = tempDirectory
            .appendingPathComponent(note.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("zip")
        try "existing archive".write(to: existingArchive, atomically: true, encoding: .utf8)
        let trashCandidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(existingArchive.lastPathComponent)
        defer {
            if !FileManager.default.fileExists(atPath: existingArchive.path),
               FileManager.default.fileExists(atPath: trashCandidate.path) {
                try? FileManager.default.moveItem(at: trashCandidate, to: existingArchive)
            }
            try? FileManager.default.removeItem(at: trashCandidate)
        }
        let service = ZipCompressionService(
            conflictResolver: DeletingSourceConflictResolver(urlToDelete: note)
        )

        do {
            _ = try await service.compress([note], to: tempDirectory)
            XCTFail("Expected compression to fail after replacement trash step")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: existingArchive.path))
            XCTAssertEqual(try String(contentsOf: existingArchive, encoding: .utf8), "existing archive")
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

private struct DeletingSourceConflictResolver: FileConflictResolving {
    var urlToDelete: URL

    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try? FileManager.default.removeItem(at: urlToDelete)
        return .replace
    }
}
