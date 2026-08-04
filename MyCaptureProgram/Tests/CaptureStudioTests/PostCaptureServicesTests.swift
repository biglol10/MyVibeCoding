import XCTest
@testable import CaptureStudio

final class PostCaptureServicesTests: XCTestCase {
    @MainActor
    func testTrashDoesNotMoveReplacementCreatedAfterIdentityCheck() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("capture.png")
        let originalURL = directory.appendingPathComponent("original.png")
        try Data("original".utf8).write(to: fileURL)
        let expectedIdentity = try CaptureFileIdentity.existingFile(at: fileURL)
        var trashedURLs: [URL] = []
        let service = WorkspaceFileTrashService(
            identityWasCheckedBeforeQuarantine: {
                try FileManager.default.moveItem(at: fileURL, to: originalURL)
                try Data("replacement".utf8).write(to: fileURL)
            },
            trashOperation: { url in
                trashedURLs.append(url)
                try FileManager.default.removeItem(at: url)
            }
        )

        XCTAssertThrowsError(
            try service.trash(fileURL, expectedIdentity: expectedIdentity)
        ) { error in
            XCTAssertEqual(error as? FileTrashError, .fileChanged)
        }
        XCTAssertTrue(trashedURLs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original".utf8))
    }

    @MainActor
    func testTrashMovesVerifiedFileThroughPrivateQuarantine() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("capture.png")
        try Data("original".utf8).write(to: fileURL)
        let expectedIdentity = try CaptureFileIdentity.existingFile(at: fileURL)
        var trashedURLs: [URL] = []
        let service = WorkspaceFileTrashService(
            trashOperation: { url in
                trashedURLs.append(url)
                XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
                try FileManager.default.removeItem(at: url)
            }
        )

        try service.trash(fileURL, expectedIdentity: expectedIdentity)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(trashedURLs.count, 1)
        XCTAssertNotEqual(trashedURLs.first, fileURL)
    }

    @MainActor
    func testTrashFailureRecoversOwnedFileWhenOriginalPathIsOccupied() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("capture.png")
        try Data("original".utf8).write(to: fileURL)
        let expectedIdentity = try CaptureFileIdentity.existingFile(at: fileURL)
        let service = WorkspaceFileTrashService(
            trashOperation: { _ in
                try Data("replacement".utf8).write(to: fileURL)
                throw POSIXError(.EIO)
            }
        )
        var recoveredURL: URL?

        XCTAssertThrowsError(
            try service.trash(fileURL, expectedIdentity: expectedIdentity)
        ) { error in
            guard case let FileTrashError.fileRecovered(url) = error else {
                return XCTFail("Expected a visible recovery file, got \(error)")
            }
            recoveredURL = url
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(recoveredURL)), Data("original".utf8))
        XCTAssertTrue(recoveredURL?.lastPathComponent.hasPrefix("CaptureStudio Recovered - ") == true)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".CaptureStudio-Trash-") }
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostCaptureServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
