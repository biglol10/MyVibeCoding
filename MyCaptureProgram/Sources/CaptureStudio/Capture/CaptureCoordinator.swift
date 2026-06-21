import Foundation
import SwiftUI

@MainActor
public final class CaptureCoordinator: ObservableObject {
    private let appState: AppState
    private let settingsStore: SettingsStore
    private let screenshotService: ScreenshotServicing
    private let fileOutputService: FileOutputService
    private let recordingService: RecordingServicing
    private let selectionService: SelectionServicing
    private let delaySleeper: CaptureDelaySleeping
    private let clipboardService: ClipboardServicing
    private let fileRevealService: FileRevealServicing
    private let imageRenderService: ImageRenderServicing
    private let ocrService: OCRServicing
    private let redactionDetector: RedactionDetector

    public init(
        appState: AppState,
        settingsStore: SettingsStore,
        screenshotService: ScreenshotServicing = ScreenCaptureKitScreenshotService(),
        fileOutputService: FileOutputService = FileOutputService(),
        imageRenderService: ImageRenderServicing = AppKitImageRenderService(),
        ocrService: OCRServicing = VisionOCRService(),
        redactionDetector: RedactionDetector = RedactionDetector(),
        recordingService: RecordingServicing = ScreenCaptureKitRecordingService(),
        selectionService: SelectionServicing = AppKitSelectionService(),
        delaySleeper: CaptureDelaySleeping = TaskCaptureDelaySleeper(),
        clipboardService: ClipboardServicing = PasteboardClipboardService(),
        fileRevealService: FileRevealServicing = WorkspaceFileRevealService()
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        self.screenshotService = screenshotService
        self.fileOutputService = fileOutputService
        self.imageRenderService = imageRenderService
        self.ocrService = ocrService
        self.redactionDetector = redactionDetector
        self.recordingService = recordingService
        self.selectionService = selectionService
        self.delaySleeper = delaySleeper
        self.clipboardService = clipboardService
        self.fileRevealService = fileRevealService
    }

    public func startNewCapture() async {
        switch appState.captureMode {
        case .screenshot:
            await startScreenshotCapture()
        case .record:
            await startScreenRecording()
        }
    }

    private func startScreenshotCapture() async {
        do {
            let settings = settingsStore.settings
            try await waitIfNeeded(seconds: settings.defaultDelaySeconds)
            let selection = try await selectionService.selectRectangle()
            let result = try await screenshotService.captureImage(selection: selection)
            copyToClipboardIfNeeded(result.pngData, settings: settings)
            if settings.automaticallySaveScreenshots {
                let fileURL = try fileOutputService.writeScreenshotData(
                    result.pngData,
                    settings: settings,
                    date: result.createdAt
                )
                revealIfNeeded(fileURL, settings: settings)
                appState.currentDocument = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    fileURL: fileURL,
                    data: result.pngData,
                    isDirty: false
                )
                appState.statusMessage = "Screenshot captured."
            } else {
                appState.currentDocument = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    data: result.pngData
                )
                appState.statusMessage = "Screenshot captured. Press Save to write the file."
            }
        } catch {
            appState.currentDocument = nil
            appState.statusMessage = "Screenshot failed: \(error.localizedDescription)"
        }
    }

    private func startScreenRecording() async {
        do {
            let settings = settingsStore.settings
            try await waitIfNeeded(seconds: settings.countdownSeconds)
            let selection = try await selectionService.selectRectangle()
            let outputURL = settings.automaticallySaveRecordings
                ? fileOutputService.recordingURL(settings: settings)
                : fileOutputService.temporaryRecordingURL()
            let result = try await recordingService.recordScreen(selection: selection, to: outputURL, settings: settings)
            appState.currentDocument = EditorDocument(
                kind: .recording,
                createdAt: result.createdAt,
                fileURL: result.fileURL,
                isDirty: !settings.automaticallySaveRecordings
            )
            if settings.automaticallySaveRecordings {
                revealIfNeeded(result.fileURL, settings: settings)
                appState.statusMessage = "Recording saved."
            } else {
                appState.statusMessage = "Recording captured. Press Save to write the file."
            }
        } catch {
            appState.currentDocument = nil
            appState.statusMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    public func saveCurrentDocument() {
        guard var document = appState.currentDocument else {
            appState.statusMessage = "Nothing to save."
            return
        }

        switch document.kind {
        case .screenshot:
            do {
                let outputData = try screenshotDataForOutput(document)
                let fileURL = try fileOutputService.writeScreenshotData(
                    outputData,
                    settings: settingsStore.settings,
                    date: document.createdAt
                )
                revealIfNeeded(fileURL, settings: settingsStore.settings)
                document.data = outputData
                document.renderedImageData = outputData
                document.fileURL = fileURL
                document.isDirty = false
                appState.currentDocument = document
                appState.statusMessage = "Screenshot saved."
            } catch let error as ImageRenderError {
                appState.statusMessage = "Image render failed: \(error.localizedDescription)"
            } catch {
                appState.statusMessage = "Save failed: \(error.localizedDescription)"
            }
        case .recording:
            guard document.isDirty else {
                appState.statusMessage = document.fileURL == nil ? "No recording file to save." : "Recording already saved."
                return
            }

            guard let sourceURL = document.fileURL else {
                appState.statusMessage = "No recording file to save."
                return
            }

            do {
                let settings = settingsStore.settings
                let fileURL = try fileOutputService.moveRecordingFile(
                    from: sourceURL,
                    settings: settings,
                    date: document.createdAt
                )
                revealIfNeeded(fileURL, settings: settings)
                document.fileURL = fileURL
                document.isDirty = false
                appState.currentDocument = document
                appState.statusMessage = "Recording saved."
            } catch {
                appState.statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    public func copyCurrentDocument() {
        guard let document = appState.currentDocument else {
            appState.statusMessage = "Nothing to copy."
            return
        }

        switch document.kind {
        case .screenshot:
            do {
                let outputData = try screenshotDataForOutput(document)
                clipboardService.copyPNGData(outputData)
                appState.statusMessage = "Screenshot copied."
            } catch {
                appState.statusMessage = "Image render failed: \(error.localizedDescription)"
            }
        case .recording:
            appState.statusMessage = "Recording copy is not available."
        }
    }

    public func runOCR() async {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            appState.statusMessage = "No screenshot to scan."
            return
        }

        do {
            let data = try screenshotDataForOutput(document)
            let result = try await ocrService.recognizeText(in: data)
            document.ocrResult = result
            appState.currentDocument = document
            appState.statusMessage = "OCR complete."
        } catch {
            appState.statusMessage = "OCR failed: \(error.localizedDescription)"
        }
    }

    public func copyOCRText() {
        guard let text = appState.currentDocument?.ocrResult?.fullText, !text.isEmpty else {
            appState.statusMessage = "No OCR text to copy."
            return
        }

        clipboardService.copyText(text)
        appState.statusMessage = "OCR text copied."
    }

    public func quickRedact() async {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            appState.statusMessage = "No screenshot to redact."
            return
        }

        do {
            let result: OCRResult
            if let existing = document.ocrResult {
                result = existing
            } else {
                let data = try screenshotDataForOutput(document)
                result = try await ocrService.recognizeText(in: data)
                document.ocrResult = result
            }

            let candidates = uniqueRedactionCandidates(from: redactionDetector.detect(in: result))
            guard !candidates.isEmpty else {
                appState.currentDocument = document
                appState.statusMessage = "No sensitive text found."
                return
            }

            let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            let newLayers = candidates.map { candidate in
                EditorLayer.redaction(
                    RedactionLayer(
                        frame: candidate.boundingBox,
                        style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                    )
                )
            }
            document.layers.append(contentsOf: newLayers)
            document.selectedLayerID = newLayers.last?.id
            document.renderedImageData = nil
            document.isDirty = true
            appState.currentDocument = document
            appState.statusMessage = newLayers.count == 1 ? "Redaction added." : "\(newLayers.count) redactions added."
        } catch {
            appState.statusMessage = "Redaction failed: \(error.localizedDescription)"
        }
    }

    private func screenshotDataForOutput(_ document: EditorDocument) throws -> Data {
        guard let baseData = document.baseImageData ?? document.data else {
            throw ImageRenderError.imageDecodeFailed
        }

        guard document.hasEdits else {
            return document.renderedImageData ?? document.data ?? baseData
        }

        return try imageRenderService.renderPNG(basePNGData: baseData, layers: document.layers)
    }

    private func uniqueRedactionCandidates(from candidates: [RedactionCandidate]) -> [RedactionCandidate] {
        var frames: [CGRect] = []
        return candidates.filter { candidate in
            guard !frames.contains(candidate.boundingBox) else {
                return false
            }

            frames.append(candidate.boundingBox)
            return true
        }
    }

    private func copyToClipboardIfNeeded(_ data: Data, settings: AppSettings) {
        guard settings.copyCapturedImageToClipboard else {
            return
        }

        clipboardService.copyPNGData(data)
    }

    private func revealIfNeeded(_ url: URL, settings: AppSettings) {
        guard settings.showInFinderAfterSave else {
            return
        }

        fileRevealService.reveal(url)
    }

    private func waitIfNeeded(seconds: Int) async throws {
        let clampedSeconds = max(0, seconds)
        guard clampedSeconds > 0 else {
            return
        }

        appState.statusMessage = "Starting in \(clampedSeconds)s..."
        try await delaySleeper.sleep(seconds: clampedSeconds)
    }
}
