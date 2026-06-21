import CoreGraphics
import XCTest
@testable import CaptureStudio

final class OCRResultTests: XCTestCase {
    func testVisionNormalizedBoxConvertsToImagePixels() {
        let observation = OCRObservation.fromVision(
            text: "hello@example.com",
            confidence: 0.95,
            normalizedBoundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(observation.boundingBox, CGRect(x: 250, y: 400, width: 500, height: 200))
    }

    func testFullTextJoinsObservationsByNewline() {
        let result = OCRResult(observations: [
            OCRObservation(text: "first", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10)),
            OCRObservation(text: "second", confidence: 0.8, boundingBox: CGRect(x: 0, y: 20, width: 10, height: 10))
        ])

        XCTAssertEqual(result.fullText, "first\nsecond")
    }
}
