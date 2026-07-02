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
        var acceptedRanges: [NSRange] = []
        appendMatches(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .email, observation: observation, acceptedRanges: &acceptedRanges, candidates: &candidates)
        appendMatches(pattern: "\\b\\d{8,}\\b", kind: .longNumber, observation: observation, acceptedRanges: &acceptedRanges, candidates: &candidates)
        appendMatches(pattern: "(\\+?\\d[\\d\\-\\s()]{7,}\\d)", kind: .phone, observation: observation, acceptedRanges: &acceptedRanges, candidates: &candidates)
        appendMatches(pattern: "https?://[^\\s]+|[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .url, observation: observation, acceptedRanges: &acceptedRanges, candidates: &candidates)
        appendMatches(pattern: "[A-Z0-9_-]{20,}", kind: .longToken, observation: observation, acceptedRanges: &acceptedRanges, candidates: &candidates)
        return candidates
    }

    private func appendMatches(
        pattern: String,
        kind: RedactionCandidate.Kind,
        observation: OCRObservation,
        acceptedRanges: inout [NSRange],
        candidates: inout [RedactionCandidate]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        let text = observation.text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard !acceptedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                continue
            }

            guard let swiftRange = Range(match.range, in: text) else {
                continue
            }

            acceptedRanges.append(match.range)
            candidates.append(
                RedactionCandidate(
                    text: String(text[swiftRange]),
                    kind: kind,
                    boundingBox: boundingBox(for: match.range, in: observation)
                )
            )
        }
    }

    private func boundingBox(for matchRange: NSRange, in observation: OCRObservation) -> CGRect {
        let textLength = max(1, (observation.text as NSString).length)
        let startRatio = CGFloat(matchRange.location) / CGFloat(textLength)
        let widthRatio = CGFloat(matchRange.length) / CGFloat(textLength)
        let horizontalPadding = min(4, observation.boundingBox.height * 0.15)
        let minX = observation.boundingBox.minX + observation.boundingBox.width * startRatio
        let width = observation.boundingBox.width * widthRatio
        let paddedMinX = max(observation.boundingBox.minX, minX - horizontalPadding)
        let paddedMaxX = min(observation.boundingBox.maxX, minX + width + horizontalPadding)

        return CGRect(
            x: paddedMinX,
            y: observation.boundingBox.minY,
            width: max(1, paddedMaxX - paddedMinX),
            height: observation.boundingBox.height
        ).integral
    }
}
