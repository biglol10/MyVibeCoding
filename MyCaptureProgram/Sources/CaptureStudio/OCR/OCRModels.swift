import CoreGraphics
import Foundation

public struct OCRTextRangeBox: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var boundingBox: CGRect

    public init(range: NSRange, boundingBox: CGRect) {
        self.location = range.location
        self.length = range.length
        self.boundingBox = boundingBox
    }

    public var range: NSRange {
        NSRange(location: location, length: length)
    }
}

public struct OCRObservation: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect
    public var textRangeBoxes: [OCRTextRangeBox]

    public init(
        text: String,
        confidence: Float,
        boundingBox: CGRect,
        textRangeBoxes: [OCRTextRangeBox] = []
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.textRangeBoxes = textRangeBoxes
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case confidence
        case boundingBox
        case textRangeBoxes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        confidence = try container.decode(Float.self, forKey: .confidence)
        boundingBox = try container.decode(CGRect.self, forKey: .boundingBox)
        textRangeBoxes = try container.decodeIfPresent([OCRTextRangeBox].self, forKey: .textRangeBoxes) ?? []
    }
}

public struct OCRResult: Codable, Equatable, Sendable {
    public var fullText: String
    public var observations: [OCRObservation]

    public init(fullText: String, observations: [OCRObservation]) {
        self.fullText = fullText
        self.observations = observations
    }

    public init(observations: [OCRObservation]) {
        self.observations = observations
        self.fullText = observations.map(\.text).joined(separator: "\n")
    }
}

public extension OCRObservation {
    static func fromVision(
        text: String,
        confidence: Float,
        normalizedBoundingBox: CGRect,
        imageSize: CGSize,
        textRangeBoxes: [OCRTextRangeBox] = []
    ) -> OCRObservation {
        return OCRObservation(
            text: text,
            confidence: confidence,
            boundingBox: imageBoundingBox(
                fromVision: normalizedBoundingBox,
                imageSize: imageSize
            ),
            textRangeBoxes: textRangeBoxes
        )
    }

    static func imageBoundingBox(fromVision normalizedBoundingBox: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalizedBoundingBox.minX * imageSize.width
        let y = (1 - normalizedBoundingBox.maxY) * imageSize.height
        let width = normalizedBoundingBox.width * imageSize.width
        let height = normalizedBoundingBox.height * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
