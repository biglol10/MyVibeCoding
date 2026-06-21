import XCTest
@testable import CaptureStudio

@MainActor
final class QuickRedactIntegrationTests: XCTestCase {
    func testQuickRedactCreatesRedactionLayersFromOCRCandidates() async {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let ocr = OCRResult(observations: [
            OCRObservation(text: "Email user@example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 20, width: 200, height: 24))
        ])
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("quickRedact")),
            screenshotService: QuickRedactMockScreenshotService(),
            ocrService: QuickRedactMockOCRService(result: ocr),
            redactionDetector: RedactionDetector()
        )

        await coordinator.quickRedact()

        XCTAssertEqual(appState.currentDocument?.layers.count, 1)
        XCTAssertEqual(appState.currentDocument?.layers.first?.frame, CGRect(x: 10, y: 20, width: 200, height: 24))
        XCTAssertEqual(appState.statusMessage, "Redaction added.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "QuickRedactIntegrationTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct QuickRedactMockOCRService: OCRServicing {
    let result: OCRResult

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        result
    }
}

private final class QuickRedactMockScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}
