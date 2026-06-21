import CoreGraphics
import Foundation

public struct OCRObservation: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
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
        imageSize: CGSize
    ) -> OCRObservation {
        let x = normalizedBoundingBox.minX * imageSize.width
        let y = (1 - normalizedBoundingBox.maxY) * imageSize.height
        let width = normalizedBoundingBox.width * imageSize.width
        let height = normalizedBoundingBox.height * imageSize.height
        return OCRObservation(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: height).integral
        )
    }
}
