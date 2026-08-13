import Foundation

public struct CandidateMatch: Equatable, Sendable {
    public let matchReason: String
    public let confidence: MatchConfidence
    public let evidence: [MatchEvidence]
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
}

public struct CandidateMatcher: Sendable {
    private static let sharedVendorFolderNames: Set<String> = [
        "adobe",
        "autodesk",
        "google",
        "jetbrains",
        "microsoft",
        "oracle"
    ]

    public init() {}

    public func match(url: URL, app: InstalledApp, kind: RelatedFileKind) -> CandidateMatch? {
        let normalizedPath = url.lastPathComponent.lowercased()
        let fullPath = url.path.lowercased()

        if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
           containsBoundedIdentifier(bundleIdentifier, in: fullPath) {
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
            .map { (name: $0, tokens: tokenSequence(from: $0)) }
            .filter { !$0.tokens.isEmpty }

        if let matchedName = nameSequences.first(where: { sequence in
            fullNameMatch(sequence.tokens, candidateTokens: candidateTokens, candidateCompact: candidateCompact)
        }) {
            if isKnownSharedVendorFolder(normalizedPath, matchedNameTokens: matchedName.tokens) {
                let evidence = MatchEvidence(
                    type: .weakName,
                    matchedValue: matchedName.name,
                    sourcePath: url.path,
                    strength: .weak
                )
                return CandidateMatch(
                    matchReason: "known shared vendor folder name",
                    confidence: .low,
                    evidence: [evidence],
                    defaultSelected: false,
                    requiresManualReview: true
                )
            }

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

    private func containsBoundedIdentifier(_ identifier: String, in value: String) -> Bool {
        var searchStart = value.startIndex
        while searchStart < value.endIndex,
              let range = value.range(of: identifier, range: searchStart..<value.endIndex) {
            let beforeIsBoundary = range.lowerBound == value.startIndex
                || isIdentifierBoundary(value[value.index(before: range.lowerBound)])
            let afterIsBoundary = range.upperBound == value.endIndex
                || isIdentifierBoundary(value[range.upperBound])
            if beforeIsBoundary && afterIsBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private func isIdentifierBoundary(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber && character != "-" && character != "_"
    }

    private func fullNameMatch(_ sequence: [String], candidateTokens: [String], candidateCompact: String) -> Bool {
        if sequence.count == 1 {
            return candidateTokens == sequence
        }
        return candidateTokens.containsContiguous(sequence) || compactNameMatch(sequence, in: candidateCompact)
    }

    private func isKnownSharedVendorFolder(_ normalizedPath: String, matchedNameTokens: [String]) -> Bool {
        matchedNameTokens.count == 1
            && CandidateMatcher.sharedVendorFolderNames.contains(matchedNameTokens[0])
            && tokenSequence(from: normalizedPath) == matchedNameTokens
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
