import Foundation
import XCTest
@testable import MyMacFinder

private final class CapturingZipExtractor: ZipExtracting, @unchecked Sendable {
    var result: FileOperationResult
    private(set) var capturedURLs: [URL] = []
    private(set) var capturedDestination: URL?

    init(result: FileOperationResult) {
        self.result = result
    }

    func extract(
        _ zipURLs: [URL],
        to destinationFolder: URL,
        progress: FileOperationProgressReporter?
    ) async throws -> FileOperationResult {
        capturedURLs = zipURLs
        capturedDestination = destinationFolder
        return result
    }
}

@MainActor
final class ExplorerZipExtractionCommandTests: XCTestCase {
    func testExtractZipRequiresFileSystemZipSelection() {
        let zip = FileEntry(
            url: URL(fileURLWithPath: "/tmp/a.zip"),
            name: "a.zip",
            kind: .file,
            typeDescription: "ZIP Archive",
            fileExtension: "zip",
            size: 1,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
        let text = FileEntry(
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
            ExplorerCommand.extractZip.isEnabled(
                selectionCount: 1,
                canPaste: false,
                canUndo: false,
                selectedEntries: [zip],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.extractZip.isEnabled(
                selectionCount: 1,
                canPaste: false,
                canUndo: false,
                selectedEntries: [text],
                isArchiveLocation: false
            )
        )
        XCTAssertFalse(
            ExplorerCommand.extractZip.isEnabled(
                selectionCount: 1,
                canPaste: false,
                canUndo: false,
                selectedEntries: [zip],
                isArchiveLocation: true
            )
        )
    }

    func testStoreExtractsSelectedZipAndRecordsUndo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderExtractStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let zipURL = tempDirectory.appendingPathComponent("a.zip")
        try "zip data".write(to: zipURL, atomically: true, encoding: .utf8)
        let extracted = tempDirectory.appendingPathComponent("a", isDirectory: true)
        let extractor = CapturingZipExtractor(result: FileOperationResult(createdURLs: [extracted]))
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil, zipExtractor: extractor)
        await store.refresh()
        store.updateSelection([zipURL.standardizedFileURL])

        await store.perform(.extractZip)

        XCTAssertEqual(extractor.capturedURLs, [zipURL.standardizedFileURL])
        XCTAssertEqual(extractor.capturedDestination, tempDirectory.standardizedFileURL)
        XCTAssertTrue(store.canUndo)
    }
}
