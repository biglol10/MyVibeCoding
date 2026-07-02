import XCTest
@testable import CaptureStudio

final class RedactionDetectorTests: XCTestCase {
    func testDetectsEmailPhoneURLTokenAndLongNumber() {
        let observations = [
            OCRObservation(text: "Email me at user@example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 10, width: 200, height: 20)),
            OCRObservation(text: "Call 010-1234-5678", confidence: 1, boundingBox: CGRect(x: 10, y: 40, width: 200, height: 20)),
            OCRObservation(text: "Visit https://example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 70, width: 200, height: 20)),
            OCRObservation(text: "key sk-abcdefghijklmnopqrstuvwxyz123456", confidence: 1, boundingBox: CGRect(x: 10, y: 100, width: 260, height: 20)),
            OCRObservation(text: "card 1234567890123456", confidence: 1, boundingBox: CGRect(x: 10, y: 130, width: 220, height: 20))
        ]

        let candidates = RedactionDetector().detect(in: OCRResult(observations: observations))

        XCTAssertEqual(Set(candidates.map(\.kind)), [.email, .phone, .url, .longToken, .longNumber])
    }

    func testRedactionCandidateBoundsOnlyMatchedTextWithinObservation() throws {
        let observationBox = CGRect(x: 10, y: 20, width: 240, height: 24)
        let result = OCRResult(observations: [
            OCRObservation(text: "Email user@example.com now", confidence: 1, boundingBox: observationBox)
        ])

        let candidate = try XCTUnwrap(RedactionDetector().detect(in: result).first { $0.kind == .email })

        XCTAssertGreaterThan(candidate.boundingBox.minX, observationBox.minX)
        XCTAssertLessThan(candidate.boundingBox.width, observationBox.width)
        XCTAssertEqual(candidate.text, "user@example.com")
    }
}
