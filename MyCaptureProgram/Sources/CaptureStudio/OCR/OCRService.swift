import AppKit
import Foundation
import Vision

@MainActor
public protocol OCRServicing {
    func recognizeText(in imageData: Data) async throws -> OCRResult
}

public enum OCRError: LocalizedError, Equatable {
    case imageDecodeFailed
    case cgImageUnavailable
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "image could not be decoded."
        case .cgImageUnavailable:
            return "image could not be prepared for OCR."
        case .noTextFound:
            return "No text found."
        }
    }
}

public struct VisionOCRService: OCRServicing {
    public init() {}

    public func recognizeText(in imageData: Data) async throws -> OCRResult {
        guard let image = NSImage(data: imageData) else {
            throw OCRError.imageDecodeFailed
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageUnavailable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let observations = request.results?.compactMap { observation -> OCRObservation? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            return OCRObservation.fromVision(
                text: candidate.string,
                confidence: candidate.confidence,
                normalizedBoundingBox: observation.boundingBox,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height)
            )
        } ?? []

        guard !observations.isEmpty else {
            throw OCRError.noTextFound
        }

        return OCRResult(observations: observations)
    }
}
