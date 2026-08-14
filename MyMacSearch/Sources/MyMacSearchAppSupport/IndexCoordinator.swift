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
    private var unavailableScopeIDs: Set<String> = []
    private var runGeneration: UInt64 = 0

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

    public func start(scopes: [IndexScope], initiallyUnavailableScopeIDs: Set<String> = []) {
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
        unavailableScopeIDs = initiallyUnavailableScopeIDs.intersection(Set(enabledScopes.map(\.id)))
        scopeStates = Dictionary(uniqueKeysWithValues: enabledScopes.map {
            ($0.id, ScopeRuntimeState(
                state: unavailableScopeIDs.contains($0.id) ? .offline : .paused,
                message: unavailableScopeIDs.contains($0.id)
                    ? "Checking the indexed volume identity before indexing. Cached results are preserved."
                    : nil
            ))
        })
        completedGenerationByScope = Dictionary(
            uniqueKeysWithValues: enabledScopes.map { ($0.id, $0.completedGeneration) }
        )
        status = .initialScan

        do {
            try restartWatcher()
        } catch {
            status = .error(message: error.localizedDescription)
            isPaused = true
            return
        }

        let availableScopes = enabledScopes.filter { !unavailableScopeIDs.contains($0.id) }
        let canResumeFromCheckpoint = !availableScopes.isEmpty && availableScopes.allSatisfy {
            $0.completedGeneration > 0 && $0.lastEventID != nil
        }
        if canResumeFromCheckpoint {
            for scope in availableScopes {
                scopeStates[scope.id] = ScopeRuntimeState(state: .watching)
            }
            deriveGlobalStatus()
            startEventDrainIfNeeded()
            return
        }

        let runID = runGeneration
        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.performFullScan(scopes: availableScopes, runID: runID)
            guard self.runGeneration == runID else { return }
            self.scanTask = nil
            self.startNextScanIfNeeded()
            if self.status == .watching {
                self.startEventDrainIfNeeded()
            }
        }
    }

    public func pause() {
        runGeneration &+= 1
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
        guard !isPaused, scopesByID[scopeID]?.isEnabled == true,
              !unavailableScopeIDs.contains(scopeID) else { return }
        pendingRescanScopeIDs.insert(scopeID)
        startNextScanIfNeeded()
    }

    public func rescanAll() {
        guard !isPaused else { return }
        pendingRescanScopeIDs.formUnion(scopesByID.keys.filter { !unavailableScopeIDs.contains($0) })
        startNextScanIfNeeded()
    }

    public func updateAvailability(scopeID: String, availability: VolumeAvailability) {
        guard scopesByID[scopeID] != nil else { return }
        let wasUnavailable = unavailableScopeIDs.contains(scopeID)
        switch availability {
        case .available:
            unavailableScopeIDs.remove(scopeID)
            if scopeStates[scopeID]?.state == .offline {
                scopeStates[scopeID] = ScopeRuntimeState(state: .paused)
            }
        case .offline:
            unavailableScopeIDs.insert(scopeID)
            pendingRescanScopeIDs.remove(scopeID)
            scopeStates[scopeID] = ScopeRuntimeState(
                state: .offline,
                message: "The indexed volume is not currently available. Cached results are preserved."
            )
        case .identityMismatch(let actualUUID):
            unavailableScopeIDs.insert(scopeID)
            pendingRescanScopeIDs.remove(scopeID)
            let actual = actualUUID ?? "unknown"
            scopeStates[scopeID] = ScopeRuntimeState(
                state: .offline,
                message: "A different volume is mounted at this path (identity: \(actual)). Re-add it to index explicitly."
            )
        }
        let isUnavailable = unavailableScopeIDs.contains(scopeID)
        guard wasUnavailable != isUnavailable else {
            deriveGlobalStatus()
            return
        }
        if isUnavailable {
            runGeneration &+= 1
            scanTask?.cancel()
            eventTask?.cancel()
            scanTask = nil
            eventTask = nil
            activeScanScopeID = nil
            pendingEvents.removeAll { event in
                guard let scope = scopesByID[scopeID] else { return false }
                return Self.isSameOrDescendant(event.path, of: scope.rootPath)
            }
            for id in scopeStates.keys
            where id != scopeID && scopeStates[id]?.state == .scanning {
                scopeStates[id] = ScopeRuntimeState(state: .paused)
            }
            pendingRescanScopeIDs.formUnion(
                scopesByID.keys.filter { !unavailableScopeIDs.contains($0) && scopeStates[$0]?.state != .watching }
            )
        }
        do {
            try restartWatcher()
        } catch {
            status = .error(message: error.localizedDescription)
            return
        }
        if availability == .available {
            rescan(scopeID: scopeID)
        } else {
            startNextScanIfNeeded()
        }
        deriveGlobalStatus()
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

    public func isScopeUnavailable(_ scopeID: String) -> Bool {
        unavailableScopeIDs.contains(scopeID)
    }

    private func receive(_ events: [FileEvent]) {
        guard !isPaused else { return }
        if pendingEvents.count + events.count > maxBufferedEvents {
            let latestEventID = max(
                pendingEvents.map(\.eventID).max() ?? 0,
                events.map(\.eventID).max() ?? 0
            )
            pendingEvents = scopesByID.values.filter { !unavailableScopeIDs.contains($0.id) }.map {
                FileEvent(
                    path: $0.rootPath,
                    eventID: latestEventID,
                    flags: [.userDropped, .mustScanSubDirectories]
                )
            }
        } else {
            pendingEvents.append(contentsOf: events.filter { event in
                scopesByID.values.contains {
                    !unavailableScopeIDs.contains($0.id)
                        && Self.isSameOrDescendant(event.path, of: $0.rootPath)
                }
            })
        }
        if status == .watching {
            startEventDrainIfNeeded()
        }
    }

    @discardableResult
    private func performFullScan(scopes: [IndexScope], runID: UInt64) async -> Bool {
        for scope in scopes {
            if Task.isCancelled || isPaused || runGeneration != runID { return false }
            guard !unavailableScopeIDs.contains(scope.id) else { continue }
            guard await performScopeScan(scope, runID: runID) else { return false }
        }
        deriveGlobalStatus()
        return !isPaused
    }

    private func performScopeScan(_ scope: IndexScope, runID: UInt64) async -> Bool {
        guard runGeneration == runID, !unavailableScopeIDs.contains(scope.id) else { return false }
        activeScanScopeID = scope.id
        scopeStates[scope.id] = ScopeRuntimeState(state: .scanning)
        deriveGlobalStatus()
        let generation = nextGeneration()
        do {
            try Task.checkCancellation()
            try await writer.beginScopeScan(scope, generation: generation)
            guard runGeneration == runID, !unavailableScopeIDs.contains(scope.id) else { return false }
            let errorBox = ScanWriteErrorBox()
            let summary = try await scanner.scan(
                scope: scope,
                generation: generation,
                onBatch: { [weak self, writer] entries in
                    guard await self?.canMutate(scopeID: scope.id, runID: runID) == true else { return }
                    do {
                        try await writer.upsertBatch(entries, scopeID: scope.id, generation: generation)
                    } catch {
                        await errorBox.record(error)
                    }
                },
                onProgress: { [weak self] progress in
                    await MainActor.run {
                        guard let self, self.canMutate(scopeID: scope.id, runID: runID) else { return }
                        self.progress = progress
                        self.scopeStates[scope.id] = ScopeRuntimeState(state: .scanning, progress: progress)
                    }
                }
            )
            guard runGeneration == runID, !unavailableScopeIDs.contains(scope.id) else { return false }
            if let writeError = await errorBox.error { throw writeError }
            let completedAt = Date()
            try await writer.completeScopeScan(scopeID: scope.id, generation: generation, completedAt: completedAt)
            try await writer.updateScopeScanStatistics(
                scopeID: scope.id,
                skippedCount: summary.skippedCount,
                permissionDeniedCount: summary.permissionDeniedCount
            )
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
            guard runGeneration == runID else { return false }
            scopeStates[scope.id] = ScopeRuntimeState(state: .paused, progress: progress)
            activeScanScopeID = nil
            deriveGlobalStatus()
            return false
        } catch FileScanError.rootPermissionDenied(let path) {
            guard runGeneration == runID else { return false }
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
            guard runGeneration == runID else { return false }
            let message = "Indexing location is unavailable: \(path)"
            try? await writer.recordIssue(
                scopeID: scope.id,
                path: path,
                category: .unavailableRoot,
                message: message,
                occurredAt: Date()
            )
            unavailableScopeIDs.insert(scope.id)
            try? restartWatcher()
            scopeStates[scope.id] = ScopeRuntimeState(state: .offline, progress: progress, message: message)
        } catch {
            guard runGeneration == runID else { return false }
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
        startNextScanIfNeeded()
        return true
    }

    private func startNextScanIfNeeded() {
        guard scanTask == nil, activeScanScopeID == nil, !isPaused,
              let scopeID = pendingRescanScopeIDs.sorted().first,
              let scope = scopesByID[scopeID], !unavailableScopeIDs.contains(scopeID) else { return }
        pendingRescanScopeIDs.remove(scopeID)
        let runID = runGeneration
        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.performFullScan(scopes: [scope], runID: runID)
            guard self.runGeneration == runID else { return }
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
        let runID = runGeneration
        eventTask = Task { [weak self] in
            guard let self else { return }
            await self.drainPendingEvents(runID: runID)
            guard self.runGeneration == runID else { return }
            self.eventTask = nil
            if !self.pendingEvents.isEmpty, self.status == .watching {
                self.startEventDrainIfNeeded()
            }
        }
    }

    private func drainPendingEvents(runID: UInt64) async {
        while !pendingEvents.isEmpty, !Task.isCancelled, !isPaused, runGeneration == runID {
            let events = pendingEvents
            pendingEvents.removeAll(keepingCapacity: true)

            for scope in scopesByID.values.sorted(by: { $0.rootPath < $1.rootPath }) {
                guard !unavailableScopeIDs.contains(scope.id) else { continue }
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
                        guard await performFullScan(scopes: [scope], runID: runID) else { return }
                    } else {
                        try await apply(plan: plan, to: scope, runID: runID)
                    }
                    if let latestEventID = plan.latestEventID {
                            guard canMutate(scopeID: scope.id, runID: runID) else { continue }
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

    private func apply(plan: FileEventPlan, to scope: IndexScope, runID: UInt64) async throws {
        for path in plan.deletePaths.sorted() {
            guard canMutate(scopeID: scope.id, runID: runID) else { throw CancellationError() }
            try await writer.delete(path: path)
        }

        var entries: [IndexedEntry] = []
        for path in plan.upsertPaths.sorted() {
            guard canMutate(scopeID: scope.id, runID: runID) else { throw CancellationError() }
            do {
                let metadata = try await metadataClient.metadata(at: URL(fileURLWithPath: path))
                let decision = policy.decision(for: metadata)
                if decision == .indexAndDescend {
                    guard await performFullScan(scopes: [scope], runID: runID) else {
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
            guard canMutate(scopeID: scope.id, runID: runID) else { throw CancellationError() }
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

    private func canMutate(scopeID: String, runID: UInt64) -> Bool {
        !isPaused && runGeneration == runID && !unavailableScopeIDs.contains(scopeID)
    }

    private func restartWatcher() throws {
        watcher.stop()
        let scopes = scopesByID.values
            .filter { !unavailableScopeIDs.contains($0.id) }
            .sorted { $0.rootPath < $1.rootPath }
        guard !scopes.isEmpty else {
            watcherBaselineEventID = nil
            return
        }
        try watcher.start(
            paths: scopes.map(\.rootPath),
            since: commonStartingEventID(for: scopes),
            onEvents: { [weak self] events in
                Task { @MainActor in self?.receive(events) }
            }
        )
        watcherBaselineEventID = currentEventIDProvider()
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
