import Foundation

public enum MatchEvidenceType: String, Codable, Equatable, Sendable {
    case selectedAppBundle
    case bundleIdentifier
    case exactAppName
    case executableName
    case knownUpdaterName
    case receiptHistory
    case weakName
}

public enum MatchEvidenceStrength: String, Codable, Equatable, Sendable {
    case strong
    case medium
    case weak
}

public struct MatchEvidence: Codable, Equatable, Sendable {
    public let type: MatchEvidenceType
    public let matchedValue: String
    public let sourcePath: String
    public let strength: MatchEvidenceStrength

    public init(type: MatchEvidenceType, matchedValue: String, sourcePath: String, strength: MatchEvidenceStrength) {
        self.type = type
        self.matchedValue = matchedValue
        self.sourcePath = sourcePath
        self.strength = strength
    }
}

public enum CandidateSafetyLevel: String, Codable, Equatable, Sendable {
    case safe
    case review
    case risky
}

public struct SafetyScore: Codable, Equatable, Sendable {
    public let level: CandidateSafetyLevel
    public let defaultSelected: Bool
    public let requiresManualReview: Bool

    public init(level: CandidateSafetyLevel, defaultSelected: Bool, requiresManualReview: Bool) {
        self.level = level
        self.defaultSelected = defaultSelected
        self.requiresManualReview = requiresManualReview
    }
}

public struct SafetyScorer: Sendable {
    public init() {}

    public func score(
        evidence: [MatchEvidence],
        kind: RelatedFileKind,
        isProtected: Bool,
        isKnownCleanupRoot: Bool
    ) -> SafetyScore {
        if isProtected {
            return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
        }

        if evidence.contains(where: { $0.type == .weakName || $0.strength == .weak }) {
            return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
        }

        if evidence.contains(where: { $0.type == .bundleIdentifier || $0.type == .selectedAppBundle }) && isKnownCleanupRoot {
            return SafetyScore(level: .safe, defaultSelected: true, requiresManualReview: false)
        }

        if evidence.contains(where: { $0.type == .exactAppName || $0.type == .executableName || $0.type == .knownUpdaterName }) && isKnownCleanupRoot {
            return SafetyScore(level: .review, defaultSelected: true, requiresManualReview: true)
        }

        return SafetyScore(level: .risky, defaultSelected: false, requiresManualReview: true)
    }
}

public enum DeletionVerificationStatus: String, Codable, Equatable, Sendable {
    case deleted
    case stillExists
    case notFoundBeforeDelete
    case permissionDenied
    case skipped
}

public struct DeletionVerificationResult: Codable, Equatable, Sendable {
    public let path: String
    public let status: DeletionVerificationStatus
    public let errorMessage: String?

    public init(path: String, status: DeletionVerificationStatus, errorMessage: String?) {
        self.path = path
        self.status = status
        self.errorMessage = errorMessage
    }
}
