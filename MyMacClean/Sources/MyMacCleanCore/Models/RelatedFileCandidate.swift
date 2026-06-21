import Foundation

public enum RelatedFileKind: String, Codable, Equatable, Sendable {
    case appBundle
    case applicationSupport
    case cache
    case preferences
    case savedState
    case container
    case groupContainer
    case log
    case httpStorage
    case webKit
    case launchAgent
    case launchDaemon
    case script
    case unknown
}

public enum MatchConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct RelatedFileCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: RelatedFileKind
    public let size: Int64
    public let matchReason: String
    public let confidence: MatchConfidence
    public let evidence: [MatchEvidence]
    public let safety: CandidateSafetyLevel
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
    public let isProtected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: RelatedFileKind,
        size: Int64,
        matchReason: String,
        confidence: MatchConfidence,
        evidence: [MatchEvidence] = [],
        safety: CandidateSafetyLevel = .review,
        defaultSelected: Bool,
        requiresManualReview: Bool,
        isProtected: Bool
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.size = size
        self.matchReason = matchReason
        self.confidence = confidence
        self.evidence = evidence
        self.safety = safety
        self.defaultSelected = defaultSelected
        self.requiresManualReview = requiresManualReview
        self.isProtected = isProtected
    }
}

public struct DeletionPlan: Equatable, Sendable {
    public let app: InstalledApp
    public let candidates: [RelatedFileCandidate]
    public let totalSize: Int64
    public let createdAt: Date

    public init(app: InstalledApp, candidates: [RelatedFileCandidate], createdAt: Date = Date()) {
        self.app = app
        self.candidates = candidates
        self.totalSize = candidates.reduce(0) { $0 + $1.size }
        self.createdAt = createdAt
    }
}

public struct DeletionItemResult: Codable, Equatable, Sendable {
    public let path: String
    public let success: Bool
    public let errorMessage: String?

    public init(path: String, success: Bool, errorMessage: String?) {
        self.path = path
        self.success = success
        self.errorMessage = errorMessage
    }
}
