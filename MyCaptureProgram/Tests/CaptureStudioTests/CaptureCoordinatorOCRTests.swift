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

    func testDismissOCRResultClearsPanelContent() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(
            kind: .screenshot,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            ocrResult: OCRResult(observations: [
                OCRObservation(text: "first", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
            ])
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("dismissOCR")),
            screenshotService: OCRMockScreenshotService()
        )

        coordinator.dismissOCRResult()

        XCTAssertNil(appState.currentDocument?.ocrResult)
        XCTAssertNil(appState.statusMessage)
    }

    func testOCRCompletionDoesNotReplaceANewerDocument() async {
        let original = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let replacement = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47, 0x01]))
        let appState = AppState(currentDocument: original)
        let service = SuspendingOCRService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("ocrReplacement")),
            screenshotService: OCRMockScreenshotService(),
            ocrService: service
        )

        let task = Task { @MainActor in
            await coordinator.runOCR()
        }
        await service.waitUntilStarted()
        appState.currentDocument = replacement
        service.finish(with: OCRResult(observations: [
            OCRObservation(text: "old", confidence: 1, boundingBox: CGRect(x: 1, y: 1, width: 4, height: 4))
        ]))
        await task.value

        XCTAssertEqual(appState.currentDocument?.id, replacement.id)
        XCTAssertNil(appState.currentDocument?.ocrResult)
        XCTAssertEqual(appState.statusMessage, "OCR cancelled because the document changed.")
    }

    func testOCRCompletionDoesNotAttachAStaleResultAfterTheSameDocumentWasEdited() async {
        let appState = AppState(
            currentDocument: EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        )
        let service = SuspendingOCRService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("ocrConcurrentEdit")),
            screenshotService: OCRMockScreenshotService(),
            ocrService: service
        )
        let concurrentLayer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 4, y: 4, width: 8, height: 8),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )

        let task = Task { @MainActor in
            await coordinator.runOCR()
        }
        await service.waitUntilStarted()
        appState.currentDocument?.layers.append(concurrentLayer)
        appState.currentDocument?.isDirty = true
        service.finish(with: OCRResult(observations: [
            OCRObservation(text: "stale", confidence: 1, boundingBox: CGRect(x: 1, y: 1, width: 4, height: 4))
        ]))
        await task.value

        XCTAssertEqual(appState.currentDocument?.layers, [concurrentLayer])
        XCTAssertNil(appState.currentDocument?.ocrResult)
        XCTAssertEqual(appState.statusMessage, "OCR cancelled because the document changed.")
    }

    func testQuickRedactCancelsWhenEditsAreAddedWhileOCRIsRunning() async {
        let appState = AppState(
            currentDocument: EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        )
        let service = SuspendingOCRService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("redactConcurrentEdit")),
            screenshotService: OCRMockScreenshotService(),
            ocrService: service
        )
        let concurrentLayer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 20, y: 20, width: 8, height: 8),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )

        let task = Task { @MainActor in
            await coordinator.quickRedact()
        }
        await service.waitUntilStarted()
        appState.currentDocument?.layers.append(concurrentLayer)
        appState.currentDocument?.isDirty = true
        service.finish(with: OCRResult(observations: [
            OCRObservation(
                text: "person@example.com",
                confidence: 1,
                boundingBox: CGRect(x: 1, y: 1, width: 16, height: 5)
            )
        ]))
        await task.value

        XCTAssertTrue(appState.currentDocument?.layers.contains(concurrentLayer) ?? false)
        XCTAssertEqual(
            appState.currentDocument?.layers.filter {
                if case .redaction = $0 { return true }
                return false
            }.count,
            0
        )
        XCTAssertNil(appState.currentDocument?.ocrResult)
        XCTAssertEqual(appState.statusMessage, "Redaction cancelled because the document changed.")
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

@MainActor
private final class SuspendingOCRService: OCRServicing {
    private var continuation: CheckedContinuation<OCRResult, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(with result: OCRResult) {
        continuation?.resume(returning: result)
        continuation = nil
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
