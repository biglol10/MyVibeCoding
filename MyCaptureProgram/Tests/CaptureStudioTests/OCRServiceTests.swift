import CoreGraphics
import XCTest
@testable import CaptureStudio

final class OCRServiceTests: XCTestCase {
    func testFakeOCRServiceReturnsDeterministicResult() async throws {
        let service = FakeOCRService(result: OCRResult(observations: [
            OCRObservation(text: "token-1234567890", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
        ]))

        let result = try await service.recognizeText(in: Data([0x89, 0x50, 0x4E, 0x47]))

        XCTAssertEqual(result.fullText, "token-1234567890")
    }
}

private struct FakeOCRService: OCRServicing {
    let result: OCRResult

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        result
    }
}
