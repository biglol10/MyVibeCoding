import Foundation
import XCTest
@testable import MyMacFinder

private final class CapturingZipCompressor: ZipCompressing, @unchecked Sendable {
    var result: FileOperationResult
    private(set) var capturedURLs: [URL] = []
    private(set) var capturedDestination: URL?

    init(result: FileOperationResult) {
        self.result = result
    }

    func compress(
        _ urls: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult {
        capturedURLs = urls
        capturedDestination = destinationFolder
        return result
    }
}

@MainActor
final class ExplorerZipCompressionCommandTests: XCTestCase {
    func testCompressToZipRequiresFileSystemSelection() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/a.txt"),
            name: "a.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 1,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertTrue(
            ExplorerCommand.compressToZip.isEnabled(
                selectionCount: 1,
                canPaste: false,
                canUndo: false,
                selectedEntries: [entry],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.compressToZip.isEnabled(
                selectionCount: 1,
                canPaste: false,
                canUndo: false,
                selectedEntries: [entry],
                isArchiveLocation: true
            )
        )
    }

    func testStoreCompressesSelectedItemsAndRecordsUndo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderCompressStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("a.txt")
        try "a".write(to: fileURL, atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory.appendingPathComponent("a.zip")
        let compressor = CapturingZipCompressor(result: FileOperationResult(createdURLs: [archiveURL]))
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil, zipCompressor: compressor)
        await store.refresh()
        store.updateSelection([fileURL.standardizedFileURL])

        await store.perform(.compressToZip)

        XCTAssertEqual(compressor.capturedURLs, [fileURL.standardizedFileURL])
        XCTAssertEqual(compressor.capturedDestination, tempDirectory.standardizedFileURL)
        XCTAssertTrue(store.canUndo)
    }
}
