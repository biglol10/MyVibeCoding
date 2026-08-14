import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class IndexCoordinatorTests: XCTestCase {
    @MainActor
    func testBuffersEventsDuringScanAndAppliesThemAfterGenerationCompletes() async throws {
        let scanner = BlockingScanner()
        let writer = RecordingIndexWriter()
        let watcher = RecordingWatcher()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: writer,
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: watcher,
            generationProvider: { 100 }
        )
        let scope = IndexScope(id: "scope", rootPath: "/scope")

        coordinator.start(scopes: [scope])
        try await eventually { await scanner.isWaiting }
        watcher.emit([
            FileEvent(path: "/scope/removed.txt", eventID: 9, flags: [.removed])
        ])
        await scanner.release()

        try await eventually {
            let wasDeleted = await writer.contains("delete:/scope/removed.txt")
            return coordinator.status == .watching && wasDeleted
        }
        let operations = await writer.operations
        XCTAssertLessThan(
            try XCTUnwrap(operations.firstIndex(of: "complete:scope:100")),
            try XCTUnwrap(operations.firstIndex(of: "delete:/scope/removed.txt"))
        )
    }

    @MainActor
    func testDroppedEventTriggersSafeFullScopeReconciliation() async throws {
        let scanner = CountingScanner()
        let writer = RecordingIndexWriter()
        let watcher = RecordingWatcher()
        var nextGeneration: Int64 = 200
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: writer,
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: watcher,
            generationProvider: {
                defer { nextGeneration += 1 }
                return nextGeneration
            }
        )

        coordinator.start(scopes: [IndexScope(id: "scope", rootPath: "/scope")])
        try await eventually { coordinator.status == .watching }
        watcher.emit([
            FileEvent(path: "/scope", eventID: 15, flags: [.kernelDropped])
        ])

        try await eventually {
            let count = await scanner.scanCount
            return count == 2 && coordinator.status == .watching
        }
        let finalScanCount = await scanner.scanCount
        XCTAssertEqual(finalScanCount, 2)
    }
}

private actor RecordingIndexWriter: IndexWriting {
    private(set) var operations: [String] = []

    func beginScopeScan(_ scope: IndexScope, generation: Int64) throws {
        operations.append("begin:\(scope.id):\(generation)")
    }

    func upsertBatch(_ entries: [IndexedEntry], scopeID: String, generation: Int64) throws {
        operations.append("upsert:\(scopeID):\(entries.count):\(generation)")
    }

    func delete(path: String) throws {
        operations.append("delete:\(path)")
    }

    func completeScopeScan(scopeID: String, generation: Int64) throws {
        operations.append("complete:\(scopeID):\(generation)")
    }

    func updateEventCheckpoint(scopeID: String, eventID: UInt64) throws {
        operations.append("checkpoint:\(scopeID):\(eventID)")
    }

    func contains(_ operation: String) -> Bool {
        operations.contains(operation)
    }
}

private actor BlockingScanner: ScopeScanning {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping FileScanner.BatchHandler,
        onProgress: @escaping FileScanner.ProgressHandler
    ) async throws -> ScanSummary {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
        isWaiting = false
        await onBatch([.coordinatorFixture(scopeID: scope.id, generation: generation)])
        return ScanSummary(
            scannedCount: 1,
            skippedCount: 0,
            permissionDeniedCount: 0,
            issues: [],
            completed: true
        )
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CountingScanner: ScopeScanning {
    private(set) var scanCount = 0

    func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping FileScanner.BatchHandler,
        onProgress: @escaping FileScanner.ProgressHandler
    ) async throws -> ScanSummary {
        scanCount += 1
        return ScanSummary(
            scannedCount: 0,
            skippedCount: 0,
            permissionDeniedCount: 0,
            issues: [],
            completed: true
        )
    }
}

@MainActor
private final class RecordingWatcher: FileEventWatching {
    private var handler: (@Sendable ([FileEvent]) -> Void)?

    func start(
        paths: [String],
        since eventID: UInt64?,
        onEvents: @escaping @Sendable ([FileEvent]) -> Void
    ) throws {
        handler = onEvents
    }

    func stop() {
        handler = nil
    }

    func emit(_ events: [FileEvent]) {
        handler?(events)
    }
}

private actor CoordinatorMetadataClient: FileMetadataClient {
    func metadata(at url: URL) async throws -> FileMetadata {
        throw FileMetadataClientError.missing(url.path)
    }

    func children(of directoryURL: URL) async throws -> [URL] {
        []
    }
}

private extension IndexedEntry {
    static func coordinatorFixture(scopeID: String, generation: Int64) -> IndexedEntry {
        IndexedEntry(
            scopeID: scopeID,
            path: "/scope/file.txt",
            parentPath: "/scope",
            name: "file.txt",
            fileExtension: "txt",
            kind: .document,
            sizeBytes: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isDirectory: false,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: generation
        )
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        if clock.now >= deadline {
            XCTFail("Condition did not become true before timeout")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
