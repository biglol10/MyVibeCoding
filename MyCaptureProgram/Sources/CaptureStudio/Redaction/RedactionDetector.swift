import CoreGraphics
import Foundation

public struct RedactionCandidate: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case email
        case phone
        case url
        case longToken
        case longNumber
    }

    public var id = UUID()
    public var text: String
    public var kind: Kind
    public var boundingBox: CGRect

    public init(id: UUID = UUID(), text: String, kind: Kind, boundingBox: CGRect) {
        self.id = id
        self.text = text
        self.kind = kind
        self.boundingBox = boundingBox
    }
}

public struct RedactionDetector {
    public init() {}

    public func detect(in result: OCRResult) -> [RedactionCandidate] {
        result.observations.flatMap { observation in
            candidates(for: observation)
        }
    }

    private func candidates(for observation: OCRObservation) -> [RedactionCandidate] {
        var candidates: [RedactionCandidate] = []
        appendMatches(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .email, observation: observation, candidates: &candidates)
        appendMatches(pattern: "(\\+?\\d[\\d\\-\\s()]{7,}\\d)", kind: .phone, observation: observation, candidates: &candidates)
        appendMatches(pattern: "https?://[^\\s]+|[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .url, observation: observation, candidates: &candidates)
        appendMatches(pattern: "[A-Z0-9_-]{20,}", kind: .longToken, observation: observation, candidates: &candidates)
        appendMatches(pattern: "\\b\\d{8,}\\b", kind: .longNumber, observation: observation, candidates: &candidates)
        return candidates
    }

    private func appendMatches(
        pattern: String,
        kind: RedactionCandidate.Kind,
        observation: OCRObservation,
        candidates: inout [RedactionCandidate]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        let text = observation.text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else {
                continue
            }

            candidates.append(
                RedactionCandidate(
                    text: String(text[swiftRange]),
                    kind: kind,
                    boundingBox: observation.boundingBox
                )
            )
        }
    }
}
