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
    private static let patterns: [(String, RedactionCandidate.Kind)] = [
        ("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", .email),
        ("\\b\\d{8,}\\b", .longNumber),
        ("(\\+?\\d[\\d\\-\\s()]{7,}\\d)", .phone),
        ("https?://[^\\s]+|[A-Z0-9.-]+\\.[A-Z]{2,}", .url),
        ("[A-Z0-9_-]{20,}", .longToken)
    ]

    public init() {}

    public func detect(in result: OCRResult) -> [RedactionCandidate] {
        result.observations.flatMap { observation in
            candidates(for: observation)
        }
    }

    private func candidates(for observation: OCRObservation) -> [RedactionCandidate] {
        Self.textMatches(in: observation.text).compactMap { match in
            guard let swiftRange = Range(match.range, in: observation.text) else {
                return nil
            }
            return RedactionCandidate(
                text: String(observation.text[swiftRange]),
                kind: match.kind,
                boundingBox: boundingBox(for: match.range, in: observation)
            )
        }
    }

    static func textMatches(in text: String) -> [RedactionTextMatch] {
        var matches: [RedactionTextMatch] = []
        var acceptedRanges: [NSRange] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (pattern, kind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: text, range: range) {
                guard !acceptedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                    continue
                }
                acceptedRanges.append(match.range)
                matches.append(RedactionTextMatch(range: match.range, kind: kind))
            }
        }
        return matches
    }

    private func boundingBox(for matchRange: NSRange, in observation: OCRObservation) -> CGRect {
        if let exactRangeBox = observation.textRangeBoxes.first(where: { $0.range == matchRange }) {
            return exactRangeBox.boundingBox.integral
        }

        return observation.boundingBox.integral
    }
}

struct RedactionTextMatch: Equatable, Sendable {
    let range: NSRange
    let kind: RedactionCandidate.Kind
}
