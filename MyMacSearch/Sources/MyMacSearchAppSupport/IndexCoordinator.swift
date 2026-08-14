import CoreServices
import Foundation
import MyMacSearchCore
import Observation

@MainActor
@Observable
public final class IndexCoordinator {
    public private(set) var status: IndexStatus = .paused
    public private(set) var progress = IndexProgress()
    public private(set) var issues: [ScanIssue] = []
    public private(set) var scopeStates: [String: ScopeRuntimeState] = [:]

    private let scanner: any ScopeScanning
    private let writer: any IndexWriting
    private let metadataClient: any FileMetadataClient
    private let policy: IndexingPolicy
    private let watcher: any FileEventWatching
    private let generationProvider: @MainActor () -> Int64
    private let currentEventIDProvider: @MainActor () -> UInt64
    private let maxBufferedEvents: Int

    private var scopesByID: [String: IndexScope] = [:]
    private var scanTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var pendingEvents: [FileEvent] = []
    private var isPaused = true
    private var lastGeneration = Int64.min
    private var completedGenerationByScope: [String: Int64] = [:]
    private var watcherBaselineEventID: UInt64?
    private var pendingRescanScopeIDs: Set<String> = []
    private var activeScanScopeID: String?

    public init(
        scanner: any ScopeScanning,
        writer: any IndexWriting,
        metadataClient: any FileMetadataClient,
        policy: IndexingPolicy,
        watcher: any FileEventWatching,
        generationProvider: @escaping @MainActor () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        currentEventIDProvider: @escaping @MainActor () -> UInt64 = {
            UInt64(FSEventsGetCurrentEventId())
        },
        maxBufferedEvents: Int = 50_000
    ) {
        self.scanner = scanner
        self.writer = writer
        self.metadataClient = metadataClient
        self.policy = policy
        self.watcher = watcher
        self.generationProvider = generationProvider
        self.currentEventIDProvider = currentEventIDProvider
        self.maxBufferedEvents = max(1, maxBufferedEvents)
    }

    deinit {
        MainActor.assumeIsolated {
            scanTask?.cancel()
            eventTask?.cancel()
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
        scopeStates = Dictionary(uniqueKeysWithValues: enabledScopes.map {
            ($0.id, ScopeRuntimeState(state: .paused))
        })
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
            watcherBaselineEventID = currentEventIDProvider()
        } catch {
            status = .error(message: error.localizedDescription)
            isPaused = true
            return
        }

        let canResumeFromCheckpoint = enabledScopes.allSatisfy {
            $0.completedGeneration > 0 && $0.lastEventID != nil
        }
        if canResumeFromCheckpoint {
            for scope in enabledScopes {
                scopeStates[scope.id] = ScopeRuntimeState(state: .watching)
            }
            deriveGlobalStatus()
            startEventDrainIfNeeded()
            return
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.performFullScan(scopes: enabledScopes)
            self.scanTask = nil
            self.startNextScanIfNeeded()
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
        pendingRescanScopeIDs.removeAll()
        activeScanScopeID = nil
        watcher.stop()
        for id in scopeStates.keys {
            scopeStates[id] = ScopeRuntimeState(state: .paused)
        }
        status = .paused
    }

    public func rescan(scopeID: String) {
        guard !isPaused, scopesByID[scopeID]?.isEnabled == true else { return }
        pendingRescanScopeIDs.insert(scopeID)
        startNextScanIfNeeded()
    }

    public func rescanAll() {
        guard !isPaused else { return }
        pendingRescanScopeIDs.formUnion(scopesByID.keys)
        startNextScanIfNeeded()
    }

    public func removeMissingPath(_ path: String) {
        Task { [weak self, writer] in
            do {
                try await writer.delete(path: path)
            } catch {
                guard let self else { return }
                self.status = .error(message: error.localizedDescription)
            }
        }
    }

    private func receive(_ events: [FileEvent]) {
        guard !isPaused else { return }
        if pendingEvents.count + events.count > maxBufferedEvents {
            let latestEventID = max(
                pendingEvents.map(\.eventID).max() ?? 0,
                events.map(\.eventID).max() ?? 0
            )
            pendingEvents = scopesByID.values.map {
                FileEvent(
                    path: $0.rootPath,
                    eventID: latestEventID,
                    flags: [.userDropped, .mustScanSubDirectories]
                )
            }
        } else {
            pendingEvents.append(contentsOf: events)
        }
        if status == .watching {
            startEventDrainIfNeeded()
        }
    }

    @discardableResult
    private func performFullScan(scopes: [IndexScope]) async -> Bool {
        for scope in scopes {
            if Task.isCancelled || isPaused { return false }
            guard await performScopeScan(scope) else { return false }
        }
        deriveGlobalStatus()
        return !isPaused
    }

    private func performScopeScan(_ scope: IndexScope) async -> Bool {
        activeScanScopeID = scope.id
        scopeStates[scope.id] = ScopeRuntimeState(state: .scanning)
        deriveGlobalStatus()
        let generation = nextGeneration()
        do {
            try Task.checkCancellation()
            try await writer.beginScopeScan(scope, generation: generation)
            let errorBox = ScanWriteErrorBox()
            let summary = try await scanner.scan(
                scope: scope,
                generation: generation,
                onBatch: { [writer] entries in
                    do {
                        try await writer.upsertBatch(entries, scopeID: scope.id, generation: generation)
                    } catch {
                        await errorBox.record(error)
                    }
                },
                onProgress: { [weak self] progress in
                    await MainActor.run {
                        self?.progress = progress
                        self?.scopeStates[scope.id] = ScopeRuntimeState(state: .scanning, progress: progress)
                    }
                }
            )
            if let writeError = await errorBox.error { throw writeError }
            let completedAt = Date()
            try await writer.completeScopeScan(scopeID: scope.id, generation: generation, completedAt: completedAt)
            try await writer.resolveIssues(scopeID: scope.id, resolvedAt: completedAt)
            for issue in summary.issues {
                issues.append(issue)
                try await writer.recordIssue(
                    scopeID: scope.id,
                    path: issue.path,
                    category: Self.indexIssueCategory(for: issue.category),
                    message: issue.message,
                    occurredAt: completedAt
                )
            }
            completedGenerationByScope[scope.id] = generation
            if let watcherBaselineEventID {
                try await writer.updateEventCheckpoint(
                    scopeID: scope.id,
                    eventID: watcherBaselineEventID,
                    occurredAt: completedAt
                )
            }
            scopeStates[scope.id] = ScopeRuntimeState(state: .watching, progress: progress)
        } catch is CancellationError {
            scopeStates[scope.id] = ScopeRuntimeState(state: .paused, progress: progress)
            activeScanScopeID = nil
            deriveGlobalStatus()
            return false
        } catch FileScanError.rootPermissionDenied(let path) {
            let message = "Permission denied: \(path)"
            let issue = ScanIssue(path: path, category: .permissionDenied, message: message)
            issues.append(issue)
            try? await writer.recordIssue(
                scopeID: scope.id,
                path: path,
                category: .permissionDenied,
                message: message,
                occurredAt: Date()
            )
            scopeStates[scope.id] = ScopeRuntimeState(state: .permissionNeeded, progress: progress, message: message)
        } catch FileScanError.rootUnavailable(let path) {
            let message = "Indexing location is unavailable: \(path)"
            try? await writer.recordIssue(
                scopeID: scope.id,
                path: path,
                category: .unavailableRoot,
                message: message,
                occurredAt: Date()
            )
            scopeStates[scope.id] = ScopeRuntimeState(state: .offline, progress: progress, message: message)
        } catch {
            let message = error.localizedDescription
            try? await writer.recordIssue(
                scopeID: scope.id,
                path: scope.rootPath,
                category: .scanFailure,
                message: message,
                occurredAt: Date()
            )
            scopeStates[scope.id] = ScopeRuntimeState(state: .error, progress: progress, message: message)
            activeScanScopeID = nil
            status = .error(message: message)
            return false
        }
        activeScanScopeID = nil
        deriveGlobalStatus()
        return true
    }

    private func startNextScanIfNeeded() {
        guard scanTask == nil, !isPaused, let scopeID = pendingRescanScopeIDs.sorted().first,
              let scope = scopesByID[scopeID] else { return }
        pendingRescanScopeIDs.remove(scopeID)
        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.performFullScan(scopes: [scope])
            self.scanTask = nil
            self.startNextScanIfNeeded()
        }
    }

    private func deriveGlobalStatus() {
        if isPaused {
            status = .paused
        } else if scopeStates.values.contains(where: { $0.state == .scanning }) {
            status = .initialScan
        } else if scopeStates.values.contains(where: { $0.state == .watching }) {
            status = .watching
        } else if scopeStates.values.contains(where: { $0.state == .permissionNeeded }) {
            status = .permissionNeeded
        } else if let error = scopeStates.values.first(where: { $0.state == .error })?.message {
            status = .error(message: error)
        } else {
            status = .paused
        }
    }

    private static func indexIssueCategory(for category: ScanIssueCategory) -> IndexIssueCategory {
        switch category {
        case .permissionDenied: .permissionDenied
        case .missing: .unavailableRoot
        case .metadata: .metadataRead
        case .enumeration: .scanFailure
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
                        if plan.requiresFullReconciliation {
                            try await writer.recordIssue(
                                scopeID: scope.id,
                                path: scope.rootPath,
                                category: .droppedEvents,
                                message: "File system events were dropped; a safe reconciliation was scheduled.",
                                occurredAt: Date()
                            )
                        }
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
                    let message = "Permission denied: \(path)"
                    issues.append(ScanIssue(path: path, category: .permissionDenied, message: message))
                    try? await writer.recordIssue(
                        scopeID: scope.id,
                        path: path,
                        category: .permissionDenied,
                        message: message,
                        occurredAt: Date()
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
