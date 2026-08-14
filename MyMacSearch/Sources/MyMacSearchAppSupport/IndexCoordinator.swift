import Foundation
import MyMacSearchCore

@MainActor
public final class IndexCoordinator {
    public private(set) var status: IndexStatus = .paused
    public private(set) var progress = IndexProgress()
    public private(set) var issues: [ScanIssue] = []

    private let scanner: any ScopeScanning
    private let writer: any IndexWriting
    private let metadataClient: any FileMetadataClient
    private let policy: IndexingPolicy
    private let watcher: any FileEventWatching
    private let generationProvider: @MainActor () -> Int64

    private var scopesByID: [String: IndexScope] = [:]
    private var scanTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var pendingEvents: [FileEvent] = []
    private var isPaused = true
    private var lastGeneration = Int64.min
    private var completedGenerationByScope: [String: Int64] = [:]

    public init(
        scanner: any ScopeScanning,
        writer: any IndexWriting,
        metadataClient: any FileMetadataClient,
        policy: IndexingPolicy,
        watcher: any FileEventWatching,
        generationProvider: @escaping @MainActor () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.scanner = scanner
        self.writer = writer
        self.metadataClient = metadataClient
        self.policy = policy
        self.watcher = watcher
        self.generationProvider = generationProvider
    }

    deinit {
        scanTask?.cancel()
        eventTask?.cancel()
        MainActor.assumeIsolated {
            watcher.stop()
        }
    }

    public func start(scopes: [IndexScope]) {
        pause()
        let enabledScopes = scopes.filter(\.isEnabled)
        guard !enabledScopes.isEmpty else {
            status = .paused
            return
        }

        isPaused = false
        issues = []
        progress = IndexProgress()
        scopesByID = Dictionary(uniqueKeysWithValues: enabledScopes.map { ($0.id, $0) })
        completedGenerationByScope = Dictionary(
            uniqueKeysWithValues: enabledScopes.map { ($0.id, $0.completedGeneration) }
        )
        status = .initialScan

        do {
            try watcher.start(
                paths: enabledScopes.map(\.rootPath),
                since: commonStartingEventID(for: enabledScopes),
                onEvents: { [weak self] events in
                    Task { @MainActor in
                        self?.receive(events)
                    }
                }
            )
        } catch {
            status = .error(message: error.localizedDescription)
            isPaused = true
            return
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.performFullScan(scopes: enabledScopes)
            self.scanTask = nil
            if self.status == .watching {
                self.startEventDrainIfNeeded()
            }
        }
    }

    public func pause() {
        isPaused = true
        scanTask?.cancel()
        eventTask?.cancel()
        scanTask = nil
        eventTask = nil
        pendingEvents.removeAll()
        watcher.stop()
        status = .paused
    }

    private func receive(_ events: [FileEvent]) {
        guard !isPaused else { return }
        pendingEvents.append(contentsOf: events)
        if status == .watching {
            startEventDrainIfNeeded()
        }
    }

    @discardableResult
    private func performFullScan(scopes: [IndexScope]) async -> Bool {
        status = .initialScan
        do {
            for scope in scopes {
                try Task.checkCancellation()
                let generation = nextGeneration()
                try await writer.beginScopeScan(scope, generation: generation)
                let errorBox = ScanWriteErrorBox()
                let summary = try await scanner.scan(
                    scope: scope,
                    generation: generation,
                    onBatch: { [writer] entries in
                        do {
                            try await writer.upsertBatch(
                                entries,
                                scopeID: scope.id,
                                generation: generation
                            )
                        } catch {
                            await errorBox.record(error)
                        }
                    },
                    onProgress: { [weak self] progress in
                        await MainActor.run {
                            self?.progress = progress
                        }
                    }
                )
                if let writeError = await errorBox.error {
                    throw writeError
                }
                issues.append(contentsOf: summary.issues)
                try await writer.completeScopeScan(scopeID: scope.id, generation: generation)
                completedGenerationByScope[scope.id] = generation
            }
            if !isPaused {
                status = .watching
            }
            return !isPaused
        } catch is CancellationError {
            if isPaused { status = .paused }
            return false
        } catch FileScanError.rootPermissionDenied {
            status = .permissionNeeded
            return false
        } catch {
            status = .error(message: error.localizedDescription)
            return false
        }
    }

    private func startEventDrainIfNeeded() {
        guard eventTask == nil, !pendingEvents.isEmpty, !isPaused else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            await self.drainPendingEvents()
            self.eventTask = nil
            if !self.pendingEvents.isEmpty, self.status == .watching {
                self.startEventDrainIfNeeded()
            }
        }
    }

    private func drainPendingEvents() async {
        while !pendingEvents.isEmpty, !Task.isCancelled, !isPaused {
            let events = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)

            for scope in scopesByID.values.sorted(by: { $0.rootPath < $1.rootPath }) {
                let relevant = events.filter { Self.isSameOrDescendant($0.path, of: scope.rootPath) }
                guard !relevant.isEmpty else { continue }
                let plan = FileEventPlanner.plan(events: relevant, scopeRoot: scope.rootPath)
                do {
                    if plan.requiresFullReconciliation || !plan.reconcileRoots.isEmpty {
                        guard await performFullScan(scopes: [scope]) else { return }
                    } else {
                        try await apply(plan: plan, to: scope)
                    }
                    if let latestEventID = plan.latestEventID {
                        try await writer.updateEventCheckpoint(
                            scopeID: scope.id,
                            eventID: latestEventID
                        )
                    }
                } catch is CancellationError {
                    return
                } catch FileMetadataClientError.permissionDenied(let path) {
                    issues.append(
                        ScanIssue(
                            path: path,
                            category: .permissionDenied,
                            message: "Permission denied: \(path)"
                        )
                    )
                } catch {
                    status = .error(message: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func apply(plan: FileEventPlan, to scope: IndexScope) async throws {
        for path in plan.deletePaths.sorted() {
            try Task.checkCancellation()
            try await writer.delete(path: path)
        }

        var entries: [IndexedEntry] = []
        for path in plan.upsertPaths.sorted() {
            try Task.checkCancellation()
            do {
                let metadata = try await metadataClient.metadata(at: URL(fileURLWithPath: path))
                let decision = policy.decision(for: metadata)
                if decision == .indexAndDescend {
                    guard await performFullScan(scopes: [scope]) else {
                        throw CancellationError()
                    }
                    return
                }
                if decision == .indexOnly {
                    entries.append(Self.makeEntry(metadata, scopeID: scope.id))
                } else {
                    try await writer.delete(path: path)
                }
            } catch FileMetadataClientError.missing {
                try await writer.delete(path: path)
            }
        }
        if !entries.isEmpty {
            try await writer.upsertBatch(
                entries,
                scopeID: scope.id,
                generation: completedGenerationByScope[scope.id] ?? scope.completedGeneration
            )
        }
    }

    private func commonStartingEventID(for scopes: [IndexScope]) -> UInt64? {
        let checkpoints = scopes.compactMap(\.lastEventID)
        guard checkpoints.count == scopes.count else { return nil }
        return checkpoints.min()
    }

    private func nextGeneration() -> Int64 {
        let proposed = generationProvider()
        let generation = max(proposed, lastGeneration == Int64.max ? Int64.max : lastGeneration + 1)
        lastGeneration = generation
        return generation
    }

    private static func isSameOrDescendant(_ path: String, of rootPath: String) -> Bool {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private static func makeEntry(_ metadata: FileMetadata, scopeID: String) -> IndexedEntry {
        let url = URL(fileURLWithPath: metadata.path)
        return IndexedEntry(
            scopeID: scopeID,
            path: metadata.path,
            parentPath: url.deletingLastPathComponent().path,
            name: metadata.name,
            fileExtension: url.pathExtension,
            kind: FileKindClassifier.kind(
                name: metadata.name,
                isDirectory: metadata.isDirectory,
                isPackage: metadata.isPackage
            ),
            sizeBytes: metadata.sizeBytes,
            modifiedAt: metadata.modifiedAt,
            isDirectory: metadata.isDirectory,
            isSymlink: metadata.isSymlink,
            isPackage: metadata.isPackage,
            isHidden: metadata.isHidden,
            deviceID: metadata.deviceID,
            inode: metadata.inode,
            scanGeneration: 0
        )
    }
}

private actor ScanWriteErrorBox {
    private(set) var error: Error?

    func record(_ error: Error) {
        if self.error == nil {
            self.error = error
        }
    }
}
