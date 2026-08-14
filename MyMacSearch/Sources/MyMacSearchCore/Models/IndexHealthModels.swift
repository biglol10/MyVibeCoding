import Foundation

public enum ScopeIndexState: String, Codable, Sendable {
    case scanning
    case watching
    case paused
    case offline
    case permissionNeeded
    case error
    case disabled
}

public struct ScopeRuntimeState: Equatable, Sendable {
    public var state: ScopeIndexState
    public var progress: IndexProgress
    public var message: String?

    public init(state: ScopeIndexState, progress: IndexProgress = IndexProgress(), message: String? = nil) {
        self.state = state
        self.progress = progress
        self.message = message
    }
}

public enum IndexIssueCategory: String, Codable, Sendable {
    case permissionDenied
    case unavailableRoot
    case metadataRead
    case scanFailure
    case droppedEvents
    case databaseMaintenance
}

public struct IndexIssueRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let scopeID: String
    public let path: String
    public let category: IndexIssueCategory
    public let message: String
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let occurrenceCount: Int
    public let resolvedAt: Date?

    public init(
        id: Int64,
        scopeID: String,
        path: String,
        category: IndexIssueCategory,
        message: String,
        firstSeenAt: Date,
        lastSeenAt: Date,
        occurrenceCount: Int,
        resolvedAt: Date?
    ) {
        self.id = id
        self.scopeID = scopeID
        self.path = path
        self.category = category
        self.message = message
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.occurrenceCount = occurrenceCount
        self.resolvedAt = resolvedAt
    }
}

public struct IndexScopeHealth: Identifiable, Equatable, Sendable {
    public var id: String { scopeID }
    public let scopeID: String
    public let rootPath: String
    public let volumeType: IndexedVolumeType
    public let isEnabled: Bool
    public let state: ScopeIndexState
    public let entryCount: Int
    public let lastCompletedScanAt: Date?
    public let lastEventAt: Date?
    public let lastEventID: UInt64?
    public let progress: IndexProgress
    public let unresolvedIssueCount: Int
    public let lastError: String?

    public init(
        scopeID: String,
        rootPath: String,
        volumeType: IndexedVolumeType,
        isEnabled: Bool,
        state: ScopeIndexState,
        entryCount: Int,
        lastCompletedScanAt: Date?,
        lastEventAt: Date?,
        lastEventID: UInt64?,
        progress: IndexProgress = IndexProgress(),
        unresolvedIssueCount: Int,
        lastError: String?
    ) {
        self.scopeID = scopeID
        self.rootPath = rootPath
        self.volumeType = volumeType
        self.isEnabled = isEnabled
        self.state = state
        self.entryCount = entryCount
        self.lastCompletedScanAt = lastCompletedScanAt
        self.lastEventAt = lastEventAt
        self.lastEventID = lastEventID
        self.progress = progress
        self.unresolvedIssueCount = unresolvedIssueCount
        self.lastError = lastError
    }
}

public struct IndexHealthSnapshot: Equatable, Sendable {
    public let scopes: [IndexScopeHealth]
    public let totalEntryCount: Int
    public let databaseBytes: Int64
    public let auxiliaryBytes: Int64
    public let capturedAt: Date

    public init(
        scopes: [IndexScopeHealth],
        totalEntryCount: Int,
        databaseBytes: Int64,
        auxiliaryBytes: Int64,
        capturedAt: Date = Date()
    ) {
        self.scopes = scopes
        self.totalEntryCount = totalEntryCount
        self.databaseBytes = databaseBytes
        self.auxiliaryBytes = auxiliaryBytes
        self.capturedAt = capturedAt
    }
}
