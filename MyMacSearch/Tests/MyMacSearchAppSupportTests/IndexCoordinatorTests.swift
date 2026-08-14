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

    @MainActor
    func testPersistedCheckpointStartsWatchingWithoutRepeatingFullScan() async throws {
        let scanner = CountingScanner()
        let watcher = RecordingWatcher()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: RecordingIndexWriter(),
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: watcher
        )

        coordinator.start(scopes: [
            IndexScope(
                id: "scope",
                rootPath: "/scope",
                completedGeneration: 9,
                lastEventID: 77
            )
        ])

        try await eventually { coordinator.status == .watching }
        let scanCount = await scanner.scanCount
        XCTAssertEqual(scanCount, 0)
        XCTAssertEqual(watcher.startingEventID, 77)
    }

    @MainActor
    func testEventBufferOverflowFallsBackToFullReconciliation() async throws {
        let scanner = CountingScanner()
        let watcher = RecordingWatcher()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: RecordingIndexWriter(),
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: watcher,
            maxBufferedEvents: 1
        )
        coordinator.start(scopes: [IndexScope(id: "scope", rootPath: "/scope")])
        try await eventually { coordinator.status == .watching }

        watcher.emit([
            FileEvent(path: "/scope/a", eventID: 80, flags: [.modified]),
            FileEvent(path: "/scope/b", eventID: 81, flags: [.modified])
        ])

        try await eventually { await scanner.scanCount == 2 }
        let finalScanCount = await scanner.scanCountValue()
        XCTAssertEqual(finalScanCount, 2)
    }

    @MainActor
    func testTargetedRescanTouchesOnlyRequestedScope() async throws {
        let scanner = PerScopeCountingScanner()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: RecordingIndexWriter(),
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: RecordingWatcher(),
            generationProvider: { 500 }
        )
        let home = IndexScope(id: "home", rootPath: "/home", completedGeneration: 1, lastEventID: 10)
        let downloads = IndexScope(id: "downloads", rootPath: "/downloads", completedGeneration: 1, lastEventID: 10)

        coordinator.start(scopes: [home, downloads])
        try await eventually { coordinator.status == .watching }
        coordinator.rescan(scopeID: downloads.id)
        try await eventually { await scanner.count(for: downloads.id) == 1 }

        let homeCount = await scanner.count(for: home.id)
        XCTAssertEqual(homeCount, 0)
        XCTAssertEqual(coordinator.scopeStates[home.id]?.state, .watching)
        XCTAssertEqual(coordinator.scopeStates[downloads.id]?.state, .watching)
    }

    @MainActor
    func testPermissionFailureDoesNotHideHealthyScope() async throws {
        let coordinator = IndexCoordinator(
            scanner: SelectivePermissionScanner(deniedScopeID: "private"),
            writer: RecordingIndexWriter(),
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: RecordingWatcher()
        )

        coordinator.start(scopes: [
            IndexScope(id: "private", rootPath: "/private"),
            IndexScope(id: "downloads", rootPath: "/downloads")
        ])

        try await eventually { coordinator.scopeStates["downloads"]?.state == .watching }
        XCTAssertEqual(coordinator.scopeStates["private"]?.state, .permissionNeeded)
        XCTAssertEqual(coordinator.status, .watching)
    }

    @MainActor
    func testMatchingRemountReconcilesOfflineScopeWithoutDeletingCachedRows() async throws {
        let scanner = PerScopeCountingScanner()
        let writer = RecordingIndexWriter()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: writer,
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: RecordingWatcher()
        )
        let scope = IndexScope(
            id: "external",
            rootPath: "/Volumes/Work",
            volumeType: .external,
            completedGeneration: 1,
            lastEventID: 10
        )
        coordinator.start(scopes: [scope])
        try await eventually { coordinator.status == .watching }

        coordinator.updateAvailability(scopeID: scope.id, availability: .offline)
        XCTAssertEqual(coordinator.scopeStates[scope.id]?.state, .offline)
        let offlineOperations = await writer.operations
        XCTAssertFalse(offlineOperations.contains(where: { $0.hasPrefix("delete:") }))

        coordinator.updateAvailability(scopeID: scope.id, availability: .available)
        try await eventually { await scanner.count(for: scope.id) == 1 }
        XCTAssertEqual(coordinator.scopeStates[scope.id]?.state, .watching)
    }

    @MainActor
    func testUnmountDuringScanKeepsLastCompleteGeneration() async throws {
        let scanner = BlockingScanner()
        let writer = RecordingIndexWriter()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: writer,
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: RecordingWatcher()
        )
        let scope = IndexScope(id: "external", rootPath: "/Volumes/Work", volumeType: .external)
        coordinator.start(scopes: [scope])
        try await eventually { await scanner.isWaiting }

        coordinator.updateAvailability(scopeID: scope.id, availability: .offline)
        await scanner.release()
        try await eventually { coordinator.scopeStates[scope.id]?.state == .offline }

        let operations = await writer.operations
        XCTAssertFalse(operations.contains(where: { $0.hasPrefix("complete:external:") }))
    }

    @MainActor
    func testOfflineScopeIsRemovedFromWatcherAndIgnoresQueuedEvents() async throws {
        let writer = RecordingIndexWriter()
        let watcher = RecordingWatcher()
        let coordinator = IndexCoordinator(
            scanner: CountingScanner(),
            writer: writer,
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: watcher
        )
        let scope = IndexScope(
            id: "external",
            rootPath: "/Volumes/Work",
            volumeType: .external,
            completedGeneration: 1,
            lastEventID: 10
        )
        coordinator.start(scopes: [scope])
        try await eventually { coordinator.status == .watching }

        coordinator.updateAvailability(scopeID: scope.id, availability: .identityMismatch(actualUUID: "other"))
        watcher.emit([FileEvent(path: "/Volumes/Work/gone.txt", eventID: 11, flags: [.removed])])
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(watcher.watchedPaths, [])
        let deletedOfflinePath = await writer.contains("delete:/Volumes/Work/gone.txt")
        XCTAssertFalse(deletedOfflinePath)
        XCTAssertTrue(coordinator.isScopeUnavailable(scope.id))
    }

    @MainActor
    func testCancellationInsensitiveOldScanCannotClobberResumedRun() async throws {
        let scanner = MultiBlockingScanner()
        let coordinator = IndexCoordinator(
            scanner: scanner,
            writer: RecordingIndexWriter(),
            metadataClient: CoordinatorMetadataClient(),
            policy: IndexingPolicy(homePath: "/Users/test", includeHidden: false),
            watcher: RecordingWatcher()
        )
        let scope = IndexScope(id: "scope", rootPath: "/scope")

        coordinator.start(scopes: [scope])
        try await eventually { await scanner.waitingCount == 1 }
        coordinator.pause()
        coordinator.start(scopes: [scope])
        try await eventually { await scanner.waitingCount == 2 }

        await scanner.release(call: 0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.scopeStates[scope.id]?.state, .scanning)

        await scanner.release(call: 1)
        try await eventually { coordinator.status == .watching }
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

    func completeScopeScan(scopeID: String, generation: Int64, completedAt: Date) throws {
        operations.append("complete:\(scopeID):\(generation)")
    }

    func updateEventCheckpoint(scopeID: String, eventID: UInt64, occurredAt: Date) throws {
        operations.append("checkpoint:\(scopeID):\(eventID)")
    }

    func recordIssue(
        scopeID: String,
        path: String,
        category: IndexIssueCategory,
        message: String,
        occurredAt: Date
    ) throws {
        operations.append("issue:\(scopeID):\(category.rawValue):\(path)")
    }

    func resolveIssues(scopeID: String, resolvedAt: Date) throws {
        operations.append("resolve:\(scopeID)")
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

private actor MultiBlockingScanner: ScopeScanning {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextCall = 0
    var waitingCount: Int { continuations.count }

    func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping FileScanner.BatchHandler,
        onProgress: @escaping FileScanner.ProgressHandler
    ) async throws -> ScanSummary {
        let call = nextCall
        nextCall += 1
        await withCheckedContinuation { continuations[call] = $0 }
        return ScanSummary(scannedCount: 0, skippedCount: 0, permissionDeniedCount: 0, issues: [], completed: true)
    }

    func release(call: Int) {
        continuations.removeValue(forKey: call)?.resume()
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

    func scanCountValue() -> Int { scanCount }
}

private actor PerScopeCountingScanner: ScopeScanning {
    private var counts: [String: Int] = [:]

    func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping FileScanner.BatchHandler,
        onProgress: @escaping FileScanner.ProgressHandler
    ) async throws -> ScanSummary {
        counts[scope.id, default: 0] += 1
        return ScanSummary(scannedCount: 0, skippedCount: 0, permissionDeniedCount: 0, issues: [], completed: true)
    }

    func count(for scopeID: String) -> Int { counts[scopeID, default: 0] }
}

private actor SelectivePermissionScanner: ScopeScanning {
    let deniedScopeID: String

    init(deniedScopeID: String) {
        self.deniedScopeID = deniedScopeID
    }

    func scan(
        scope: IndexScope,
        generation: Int64,
        onBatch: @escaping FileScanner.BatchHandler,
        onProgress: @escaping FileScanner.ProgressHandler
    ) async throws -> ScanSummary {
        if scope.id == deniedScopeID {
            throw FileScanError.rootPermissionDenied(scope.rootPath)
        }
        return ScanSummary(scannedCount: 0, skippedCount: 0, permissionDeniedCount: 0, issues: [], completed: true)
    }
}

@MainActor
private final class RecordingWatcher: FileEventWatching {
    private var handler: (@Sendable ([FileEvent]) -> Void)?
    private(set) var startingEventID: UInt64?
    private(set) var watchedPaths: [String] = []

    func start(
        paths: [String],
        since eventID: UInt64?,
        onEvents: @escaping @Sendable ([FileEvent]) -> Void
    ) throws {
        startingEventID = eventID
        watchedPaths = paths
        handler = onEvents
    }

    func stop() {
        handler = nil
        watchedPaths = []
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
