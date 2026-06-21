import Foundation

public enum DeletionAction: String, Codable, Equatable, Sendable {
    case uninstall
    case orphanCleanup
}

public struct DeletionReceiptCandidate: Codable, Equatable, Sendable {
    public let path: String
    public let kind: RelatedFileKind
    public let size: Int64
    public let safety: CandidateSafetyLevel
    public let evidence: [MatchEvidence]

    public init(path: String, kind: RelatedFileKind, size: Int64, safety: CandidateSafetyLevel, evidence: [MatchEvidence]) {
        self.path = path
        self.kind = kind
        self.size = size
        self.safety = safety
        self.evidence = evidence
    }
}

public struct DeletionReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let bundleIdentifier: String?
    public let bundlePath: String
    public let action: DeletionAction
    public let completedAt: Date
    public let selectedCandidates: [DeletionReceiptCandidate]
    public let executionResults: [DeletionItemResult]
    public let verificationResults: [DeletionVerificationResult]
    public let confirmationMatched: Bool

    public init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String?,
        bundlePath: String,
        action: DeletionAction,
        completedAt: Date = Date(),
        selectedCandidates: [DeletionReceiptCandidate],
        executionResults: [DeletionItemResult],
        verificationResults: [DeletionVerificationResult],
        confirmationMatched: Bool
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.action = action
        self.completedAt = completedAt
        self.selectedCandidates = selectedCandidates
        self.executionResults = executionResults
        self.verificationResults = verificationResults
        self.confirmationMatched = confirmationMatched
    }
}

public struct DeletionReceiptStore: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ receipt: DeletionReceipt) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try encoder.encode(receipt)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }

    public func readReceipts() throws -> [DeletionReceipt] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try decoder.decode(DeletionReceipt.self, from: Data(line.utf8))
        }
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
