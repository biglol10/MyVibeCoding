import Foundation
import XCTest
@testable import MyMacSearchCore

final class FileScannerTests: XCTestCase {
    func testIndexesSymlinkAndPackageWithoutDescending() async throws {
        let client = TestMetadataClient(
            metadata: [
                "/scope": .directory("/scope"),
                "/scope/link": .symlink("/scope/link"),
                "/scope/Tool.app": .package("/scope/Tool.app")
            ],
            children: [
                "/scope": ["/scope/link", "/scope/Tool.app"],
                "/scope/link": ["/scope/link/secret.txt"],
                "/scope/Tool.app": ["/scope/Tool.app/Contents"]
            ]
        )
        let collector = EntryCollector()
        let scanner = FileScanner(
            metadataClient: client,
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            batchSize: 1
        )

        let summary = try await scanner.scan(
            scope: IndexScope(id: "scope", rootPath: "/scope"),
            generation: 7,
            onBatch: { await collector.append($0) },
            onProgress: { _ in }
        )

        let indexedPaths = await collector.paths()
        let enumeratedPaths = await client.enumeratedPaths()
        XCTAssertEqual(Set(indexedPaths), ["/scope/link", "/scope/Tool.app"])
        XCTAssertEqual(enumeratedPaths, ["/scope"])
        XCTAssertEqual(summary.scannedCount, 2)
        XCTAssertTrue(summary.completed)
    }

    func testDescendantPermissionFailureIsRecordedAndScanContinues() async throws {
        let denied = FileMetadataClientError.permissionDenied("/scope/blocked")
        let client = TestMetadataClient(
            metadata: [
                "/scope": .directory("/scope"),
                "/scope/blocked": .directory("/scope/blocked"),
                "/scope/visible.txt": .file("/scope/visible.txt")
            ],
            children: ["/scope": ["/scope/blocked", "/scope/visible.txt"]],
            childErrors: ["/scope/blocked": denied]
        )
        let collector = EntryCollector()

        let summary = try await FileScanner(
            metadataClient: client,
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false)
        ).scan(
            scope: IndexScope(id: "scope", rootPath: "/scope"),
            generation: 1,
            onBatch: { await collector.append($0) },
            onProgress: { _ in }
        )

        let indexedPaths = await collector.paths()
        XCTAssertEqual(Set(indexedPaths), ["/scope/blocked", "/scope/visible.txt"])
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.permissionDeniedCount, 1)
        XCTAssertEqual(summary.issues.first?.path, "/scope/blocked")
    }

    func testAlreadyCancelledScanThrowsBeforeReadingFilesystem() async {
        let client = TestMetadataClient(metadata: [:], children: [:])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileScanner(
                metadataClient: client,
                policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false)
            ).scan(
                scope: IndexScope(id: "scope", rootPath: "/scope"),
                generation: 1,
                onBatch: { _ in },
                onProgress: { _ in }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let readPaths = await client.metadataReadPaths()
            XCTAssertEqual(readPaths, [])
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}

private actor EntryCollector {
    private var entries: [IndexedEntry] = []

    func append(_ batch: [IndexedEntry]) {
        entries.append(contentsOf: batch)
    }

    func paths() -> [String] {
        entries.map(\.path)
    }
}

private actor TestMetadataClient: FileMetadataClient {
    private let metadataByPath: [String: FileMetadata]
    private let childrenByPath: [String: [String]]
    private let childErrors: [String: FileMetadataClientError]
    private var metadataReads: [String] = []
    private var enumerations: [String] = []

    init(
        metadata: [String: FileMetadata],
        children: [String: [String]],
        childErrors: [String: FileMetadataClientError] = [:]
    ) {
        metadataByPath = metadata
        childrenByPath = children
        self.childErrors = childErrors
    }

    func metadata(at url: URL) async throws -> FileMetadata {
        metadataReads.append(url.path)
        guard let value = metadataByPath[url.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return value
    }

    func children(of directoryURL: URL) async throws -> [URL] {
        enumerations.append(directoryURL.path)
        if let error = childErrors[directoryURL.path] {
            throw error
        }
        return childrenByPath[directoryURL.path, default: []].map { URL(fileURLWithPath: $0) }
    }

    func metadataReadPaths() -> [String] { metadataReads }
    func enumeratedPaths() -> [String] { enumerations }
}

private extension FileMetadata {
    static func file(_ path: String) -> FileMetadata { fixture(path: path) }
    static func directory(_ path: String) -> FileMetadata { fixture(path: path, isDirectory: true) }
    static func symlink(_ path: String) -> FileMetadata { fixture(path: path, isDirectory: true, isSymlink: true) }
    static func package(_ path: String) -> FileMetadata { fixture(path: path, isDirectory: true, isPackage: true) }

    static func fixture(
        path: String,
        isDirectory: Bool = false,
        isSymlink: Bool = false,
        isPackage: Bool = false
    ) -> FileMetadata {
        FileMetadata(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            isPackage: isPackage,
            isHidden: false,
            sizeBytes: 10,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceID: nil,
            inode: nil
        )
    }
}
