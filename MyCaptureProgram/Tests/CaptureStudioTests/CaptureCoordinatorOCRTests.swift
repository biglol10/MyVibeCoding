import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureCoordinatorOCRTests: XCTestCase {
    func testRunOCRStoresResultOnScreenshotDocument() async {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let result = OCRResult(observations: [
            OCRObservation(text: "hello@example.com", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
        ])
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("ocr")),
            screenshotService: OCRMockScreenshotService(),
            ocrService: MockOCRService(result: result)
        )

        await coordinator.runOCR()

        XCTAssertEqual(appState.currentDocument?.ocrResult, result)
        XCTAssertEqual(appState.statusMessage, "OCR complete.")
    }

    func testCopyOCRTextCopiesRecognizedTextToClipboard() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            ocrResult: OCRResult(observations: [
                OCRObservation(text: "first", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4)),
                OCRObservation(text: "second", confidence: 1, boundingBox: CGRect(x: 1, y: 8, width: 3, height: 4))
            ])
        )
        let clipboard = OCRMockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("copyOCR")),
            screenshotService: OCRMockScreenshotService(),
            clipboardService: clipboard
        )

        coordinator.copyOCRText()

        XCTAssertEqual(clipboard.copiedText, "first\nsecond")
        XCTAssertEqual(appState.statusMessage, "OCR text copied.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorOCRTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct MockOCRService: OCRServicing {
    let result: OCRResult

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        result
    }
}

private final class OCRMockScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}

private final class OCRMockClipboardService: ClipboardServicing {
    var copiedPNGData: Data?
    var copiedText: String?

    func copyPNGData(_ data: Data) {
        copiedPNGData = data
    }

    func copyText(_ text: String) {
        copiedText = text
    }
}
