import Foundation

public struct CandidateMatch: Equatable, Sendable {
    public let matchReason: String
    public let confidence: MatchConfidence
    public let evidence: [MatchEvidence]
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
}

public struct CandidateMatcher: Sendable {
    public init() {}

    public func match(url: URL, app: InstalledApp, kind: RelatedFileKind) -> CandidateMatch? {
        let normalizedPath = url.lastPathComponent.lowercased()
        let fullPath = url.path.lowercased()

        if let bundleIdentifier = app.bundleIdentifier?.lowercased(), fullPath.contains(bundleIdentifier) {
            let evidence = MatchEvidence(
                type: .bundleIdentifier,
                matchedValue: bundleIdentifier,
                sourcePath: url.path,
                strength: .strong
            )
            return CandidateMatch(
                matchReason: "bundle identifier match",
                confidence: .high,
                evidence: [evidence],
                defaultSelected: true,
                requiresManualReview: false
            )
        }

        let candidateTokens = tokenSequence(from: normalizedPath)
        let candidateCompact = compactIdentifier(from: normalizedPath)
        let nameSequences = [app.displayName, app.executableName ?? ""]
            .map(tokenSequence(from:))
            .filter { !$0.isEmpty }

        if nameSequences.contains(where: { sequence in
            candidateTokens.containsContiguous(sequence) || compactNameMatch(sequence, in: candidateCompact)
        }) {
            let evidence = MatchEvidence(
                type: .exactAppName,
                matchedValue: app.displayName,
                sourcePath: url.path,
                strength: .medium
            )
            return CandidateMatch(
                matchReason: "full app name match",
                confidence: kind == .unknown ? .low : .medium,
                evidence: [evidence],
                defaultSelected: kind != .unknown,
                requiresManualReview: kind == .unknown
            )
        }

        return nil
    }

    private func tokenSequence(from value: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return value
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }

    private func compactNameMatch(_ sequence: [String], in candidateCompact: String) -> Bool {
        guard sequence.count > 1 else { return false }
        let compactName = sequence.joined()
        return compactName.count >= 6 && candidateCompact.contains(compactName)
    }

    private func compactIdentifier(from value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

private extension Array where Element == String {
    func containsContiguous(_ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= count else { return false }

        for startIndex in 0...(count - needle.count) {
            let range = startIndex..<(startIndex + needle.count)
            if Array(self[range]) == needle {
                return true
            }
        }

        return false
    }
}
