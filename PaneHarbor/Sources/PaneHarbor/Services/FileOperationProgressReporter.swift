import Foundation

public actor FileOperationProgressReporter {
    public typealias UpdateHandler = @Sendable (FileOperationProgressSnapshot) async -> Void

    private var snapshot: FileOperationProgressSnapshot
    private let onUpdate: UpdateHandler
    private var isCancelled = false
    private let minimumUpdateInterval: Duration
    private let clock = ContinuousClock()
    private var lastPublishedAt: ContinuousClock.Instant?

    public init(
        initialSnapshot: FileOperationProgressSnapshot,
        minimumUpdateInterval: Duration = .zero,
        onUpdate: @escaping UpdateHandler
    ) {
        self.snapshot = initialSnapshot
        self.onUpdate = onUpdate
        self.minimumUpdateInterval = max(.zero, minimumUpdateInterval)
    }

    public var currentSnapshot: FileOperationProgressSnapshot {
        snapshot
    }

    public func update(
        phase: FileOperationPhase? = nil,
        currentItemName: String? = nil,
        completedUnitCount: Int? = nil,
        totalUnitCount: Int? = nil,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil
    ) async {
        guard !isCancelled else {
            return
        }
        let previous = snapshot
        if let phase {
            snapshot.phase = phase
        }
        if let currentItemName {
            snapshot.currentItemName = currentItemName
        }
        if let completedUnitCount {
            snapshot.completedUnitCount = completedUnitCount
        }
        if let totalUnitCount {
            snapshot.totalUnitCount = totalUnitCount
        }
        if let completedBytes {
            snapshot.completedBytes = completedBytes
        }
        if let totalBytes {
            snapshot.totalBytes = totalBytes
        }
        let now = clock.now
        let contextChanged = previous.phase != snapshot.phase ||
            previous.totalUnitCount != snapshot.totalUnitCount ||
            previous.totalBytes != snapshot.totalBytes
        if let lastPublishedAt, !contextChanged,
           lastPublishedAt.duration(to: now) < minimumUpdateInterval {
            return
        }
        lastPublishedAt = now
        await onUpdate(snapshot)
    }

    public func complete() async {
        guard !isCancelled else {
            return
        }
        snapshot.phase = .completed
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func fail(_ message: String) async {
        guard !isCancelled else {
            return
        }
        snapshot.phase = .failed
        snapshot.errorMessage = message
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func cancel() async {
        isCancelled = true
        snapshot.phase = .cancelled
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}
