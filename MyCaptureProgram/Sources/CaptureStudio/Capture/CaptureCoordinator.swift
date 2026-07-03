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
    private let fileTrashService: FileTrashServicing
    private let windowVisibilityController: CaptureWindowVisibilityControlling
    private let imageRenderService: ImageRenderServicing
    private let ocrService: OCRServicing
    private let redactionDetector: RedactionDetector
    private let screenCapturePermissionChecker: ScreenCapturePermissionChecking
    private let historyStore: CaptureHistoryStore?
    private let metadataService: CaptureMetadataServicing
    private let floatingPinService: FloatingPinServicing
    private let recordingExportService: RecordingExportServicing

    public init(
        appState: AppState,
        settingsStore: SettingsStore,
        screenshotService: ScreenshotServicing = ScreenCaptureKitScreenshotService(),
        fileOutputService: FileOutputService = FileOutputService(),
        imageRenderService: ImageRenderServicing = AppKitImageRenderService(),
        ocrService: OCRServicing = VisionOCRService(),
        redactionDetector: RedactionDetector = RedactionDetector(),
        recordingService: RecordingServicing = ScreenCaptureKitRecordingService.shared,
        selectionService: SelectionServicing? = nil,
        delaySleeper: CaptureDelaySleeping = TaskCaptureDelaySleeper(),
        clipboardService: ClipboardServicing = PasteboardClipboardService(),
        fileRevealService: FileRevealServicing = WorkspaceFileRevealService(),
        fileTrashService: FileTrashServicing = WorkspaceFileTrashService(),
        windowVisibilityController: CaptureWindowVisibilityControlling = AppKitCaptureWindowVisibilityController(),
        screenCapturePermissionChecker: ScreenCapturePermissionChecking = CoreGraphicsScreenCapturePermissionChecker(),
        historyStore: CaptureHistoryStore? = nil,
        metadataService: CaptureMetadataServicing = CoreGraphicsCaptureMetadataService(),
        floatingPinService: FloatingPinServicing = AppKitFloatingPinService(),
        recordingExportService: RecordingExportServicing = AVFoundationRecordingExportService()
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        self.screenshotService = screenshotService
        self.fileOutputService = fileOutputService
        self.imageRenderService = imageRenderService
        self.ocrService = ocrService
        self.redactionDetector = redactionDetector
        self.recordingService = recordingService
        self.selectionService = selectionService ?? AppKitSelectionService(windowVisibilityController: windowVisibilityController)
        self.delaySleeper = delaySleeper
        self.clipboardService = clipboardService
        self.fileRevealService = fileRevealService
        self.fileTrashService = fileTrashService
        self.windowVisibilityController = windowVisibilityController
        self.screenCapturePermissionChecker = screenCapturePermissionChecker
        self.historyStore = historyStore
        self.metadataService = metadataService
        self.floatingPinService = floatingPinService
        self.recordingExportService = recordingExportService
    }

    public func startNewCapture() async {
        switch appState.captureMode {
        case .screenshot:
            await startScreenshotCapture()
        case .record:
            await startScreenRecording()
        }
    }

    public func startScreenshotCapture() async {
        do {
            try ensureScreenCaptureAccess()
            let settings = settingsStore.settings
            let didHideCaptureWindows = hideCaptureWindowsIfNeeded(settings: settings)
            defer { restoreCaptureWindowsIfNeeded(didHideCaptureWindows) }
            try await waitIfNeeded(seconds: settings.defaultDelaySeconds)
            let selection = try await selectCaptureArea()
            let namingContext = metadataService.namingContext(for: selection)
            let result = try await screenshotService.captureImage(selection: selection)
            copyToClipboardIfNeeded(result.pngData, settings: settings)
            if settings.automaticallySaveScreenshots {
                let fileURL = try fileOutputService.writeScreenshotData(
                    result.pngData,
                    settings: settings,
                    date: result.createdAt,
                    context: namingContext
                )
                revealIfNeeded(fileURL, settings: settings)
                let document = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    fileURL: fileURL,
                    data: result.pngData,
                    namingContext: namingContext,
                    isDirty: false
                )
                appState.currentDocument = document
                addHistoryItem(for: document)
                appState.statusMessage = "Screenshot captured."
            } else {
                appState.currentDocument = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    data: result.pngData,
                    namingContext: namingContext
                )
                appState.statusMessage = "Screenshot captured. Press Save to write the file."
            }
        } catch {
            appState.currentDocument = nil
            if isSelectionCancelled(error) {
                appState.statusMessage = "Screenshot cancelled."
            } else {
                appState.statusMessage = "Screenshot failed: \(userMessage(for: error))"
            }
        }
    }

    public func startScreenRecording() async {
        do {
            try ensureScreenCaptureAccess()
            let settings = settingsStore.settings
            let didHideCaptureWindows = hideCaptureWindowsIfNeeded(settings: settings)
            defer { restoreCaptureWindowsIfNeeded(didHideCaptureWindows) }
            let selection = try await selectCaptureArea()
            let namingContext = metadataService.namingContext(for: selection)
            try await waitIfNeeded(seconds: settings.countdownSeconds)
            let outputURL = settings.automaticallySaveRecordings
                ? fileOutputService.availableRecordingURL(settings: settings, context: namingContext)
                : fileOutputService.temporaryRecordingURL()
            appState.isRecordingInProgress = true
            defer { appState.isRecordingInProgress = false }
            let result = try await recordingService.recordScreen(selection: selection, to: outputURL, settings: settings)
            let document = EditorDocument(
                kind: .recording,
                createdAt: result.createdAt,
                fileURL: result.fileURL,
                namingContext: namingContext,
                isDirty: !settings.automaticallySaveRecordings
            )
            appState.currentDocument = document
            if settings.automaticallySaveRecordings {
                addHistoryItem(for: document)
                revealIfNeeded(result.fileURL, settings: settings)
                appState.statusMessage = "Recording saved."
            } else {
                appState.statusMessage = "Recording captured. Press Save to write the file."
            }
        } catch {
            appState.currentDocument = nil
            if isSelectionCancelled(error) {
                appState.statusMessage = "Recording cancelled."
            } else if isRecordingStoppedByUser(error) {
                appState.statusMessage = "Recording stopped."
            } else {
                appState.statusMessage = "Recording failed: \(userMessage(for: error))"
            }
        }
    }

    public func stopActiveRecording() async {
        guard appState.isRecordingInProgress else {
            appState.statusMessage = "No recording in progress."
            return
        }

        appState.statusMessage = "Stopping recording..."
        await recordingService.stopRecording()
    }

    public func saveCurrentDocument() async {
        guard var document = appState.currentDocument else {
            appState.statusMessage = "Nothing to save."
            return
        }

        switch document.kind {
        case .screenshot:
            do {
                let outputData = try await screenshotDataForOutput(document)
                let fileURL = try fileOutputService.writeScreenshotData(
                    outputData,
                    settings: settingsStore.settings,
                    date: document.createdAt,
                    context: document.namingContext
                )
                revealIfNeeded(fileURL, settings: settingsStore.settings)
                document.data = outputData
                document.renderedImageData = outputData
                document.fileURL = fileURL
                document.savedSnapshot = document.currentSnapshot
                document.isDirty = false
                appState.currentDocument = document
                addHistoryItem(for: document)
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
                    date: document.createdAt,
                    context: document.namingContext
                )
                revealIfNeeded(fileURL, settings: settings)
                document.fileURL = fileURL
                document.isDirty = false
                appState.currentDocument = document
                addHistoryItem(for: document)
                appState.statusMessage = "Recording saved."
            } catch {
                appState.statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    public func copyCurrentDocument() async {
        guard let document = appState.currentDocument else {
            appState.statusMessage = "Nothing to copy."
            return
        }

        switch document.kind {
        case .screenshot:
            do {
                let outputData = try await screenshotDataForOutput(document)
                clipboardService.copyPNGData(outputData)
                appState.statusMessage = "Screenshot copied."
            } catch {
                appState.statusMessage = "Image render failed: \(error.localizedDescription)"
            }
        case .recording:
            appState.statusMessage = "Recording copy is not available."
        }
    }

    public func revealCurrentDocument() {
        guard let fileURL = appState.currentDocument?.fileURL else {
            appState.statusMessage = "No saved file to reveal."
            return
        }

        fileRevealService.reveal(fileURL)
        appState.statusMessage = "Revealed in Finder."
    }

    public func deleteCurrentDocument() {
        guard let document = appState.currentDocument else {
            appState.statusMessage = "Nothing to delete."
            return
        }

        let deletedMessage = document.kind == .recording ? "Recording deleted." : "Screenshot deleted."
        let discardedMessage = document.kind == .recording ? "Recording discarded." : "Screenshot discarded."

        guard let fileURL = document.fileURL else {
            appState.currentDocument = nil
            appState.statusMessage = discardedMessage
            return
        }

        do {
            try fileTrashService.trash(fileURL)
            historyStore?.remove(fileURL: fileURL)
            appState.currentDocument = nil
            appState.statusMessage = deletedMessage
        } catch {
            appState.statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    public func openHistoryItem(_ item: CaptureHistoryItem) {
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            historyStore?.remove(id: item.id)
            appState.statusMessage = "History file is missing."
            return
        }

        switch item.kind {
        case .screenshot:
            do {
                let data = try Data(contentsOf: item.fileURL)
                appState.currentDocument = EditorDocument(
                    kind: .screenshot,
                    createdAt: item.createdAt,
                    fileURL: item.fileURL,
                    data: data,
                    namingContext: FileNamingContext(
                        applicationName: item.sourceApplication ?? item.detail,
                        windowTitle: item.windowTitle
                    ),
                    isDirty: false
                )
                appState.statusMessage = "History item opened."
            } catch {
                appState.statusMessage = "History item could not be opened."
            }
        case .recording:
            appState.currentDocument = EditorDocument(
                kind: .recording,
                createdAt: item.createdAt,
                fileURL: item.fileURL,
                namingContext: FileNamingContext(
                    applicationName: item.sourceApplication ?? item.detail,
                    windowTitle: item.windowTitle
                ),
                isDirty: false
            )
            appState.statusMessage = "History item opened."
        }
    }

    public func deleteHistoryItem(_ item: CaptureHistoryItem) {
        do {
            if FileManager.default.fileExists(atPath: item.fileURL.path) {
                try fileTrashService.trash(item.fileURL)
            }
            historyStore?.remove(id: item.id)
            if appState.currentDocument?.fileURL?.standardizedFileURL == item.fileURL.standardizedFileURL {
                appState.currentDocument = nil
            }
            appState.statusMessage = item.kind == .recording ? "Recording deleted." : "Screenshot deleted."
        } catch {
            appState.statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    public func pinCurrentScreenshot() async {
        guard let document = appState.currentDocument, document.kind == .screenshot else {
            appState.statusMessage = "No screenshot to pin."
            return
        }

        do {
            let data = try await screenshotDataForOutput(document)
            let title = document.fileURL?.lastPathComponent ?? "Screenshot"
            try floatingPinService.pinImage(data: data, title: title)
            appState.statusMessage = "Screenshot pinned."
        } catch {
            appState.statusMessage = "Pin failed: \(error.localizedDescription)"
        }
    }

    public func trimCurrentRecording(startSeconds: Double, endSeconds: Double) async {
        guard var document = appState.currentDocument, document.kind == .recording else {
            appState.statusMessage = "No recording to trim."
            return
        }
        guard let sourceURL = document.fileURL else {
            appState.statusMessage = "No recording file to trim."
            return
        }

        do {
            let outputURL = fileOutputService.trimmedRecordingURL(
                settings: settingsStore.settings,
                date: Date(),
                context: document.namingContext
            )
            let trimmedURL = try await recordingExportService.trimRecording(
                sourceURL: sourceURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                outputURL: outputURL
            )
            document.fileURL = trimmedURL
            document.createdAt = Date()
            document.isDirty = false
            appState.currentDocument = document
            addHistoryItem(for: document)
            revealIfNeeded(trimmedURL, settings: settingsStore.settings)
            appState.statusMessage = "Recording trimmed."
        } catch {
            appState.statusMessage = "Trim failed: \(error.localizedDescription)"
        }
    }

    public func exportCurrentRecordingAsGIF() async {
        guard let document = appState.currentDocument, document.kind == .recording else {
            appState.statusMessage = "No recording to export."
            return
        }
        guard let sourceURL = document.fileURL else {
            appState.statusMessage = "No recording file to export."
            return
        }

        do {
            let outputURL = fileOutputService.gifRecordingURL(
                settings: settingsStore.settings,
                date: Date(),
                context: document.namingContext
            )
            let gifURL = try await recordingExportService.exportGIF(
                sourceURL: sourceURL,
                outputURL: outputURL,
                maxDurationSeconds: Double(settingsStore.settings.recordingDurationSeconds)
            )
            fileRevealService.reveal(gifURL)
            appState.statusMessage = "GIF exported."
        } catch {
            appState.statusMessage = "GIF export failed: \(error.localizedDescription)"
        }
    }

    public func runOCR() async {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            appState.statusMessage = "No screenshot to scan."
            return
        }

        do {
            let data = try await screenshotDataForOutput(document)
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

    public func dismissOCRResult() {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            return
        }

        document.ocrResult = nil
        appState.currentDocument = document
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
                let data = try await screenshotDataForOutput(document)
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

    private func screenshotDataForOutput(_ document: EditorDocument) async throws -> Data {
        guard let baseData = document.baseImageData ?? document.data else {
            throw ImageRenderError.imageDecodeFailed
        }

        guard document.hasEdits else {
            return document.renderedImageData ?? document.data ?? baseData
        }

        let imageRenderService = imageRenderService
        let layers = document.layers
        return try await Task.detached(priority: .userInitiated) {
            try imageRenderService.renderPNG(basePNGData: baseData, layers: layers)
        }.value
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

    private func addHistoryItem(for document: EditorDocument) {
        guard let fileURL = document.fileURL else {
            return
        }

        let context = document.namingContext
        let title = context?.displayTitle.isEmpty == false
            ? context?.displayTitle ?? fileURL.lastPathComponent
            : fileURL.lastPathComponent
        let detail = document.kind == .recording ? "Recording" : "Screenshot"
        historyStore?.add(
            CaptureHistoryItem(
                kind: document.kind,
                createdAt: document.createdAt,
                fileURL: fileURL,
                title: title,
                detail: detail,
                thumbnailData: document.kind == .screenshot ? document.currentImageData : nil,
                sourceApplication: context?.applicationName,
                windowTitle: context?.windowTitle
            )
        )
    }

    private func waitIfNeeded(seconds: Int) async throws {
        let clampedSeconds = max(0, seconds)
        guard clampedSeconds > 0 else {
            return
        }

        appState.statusMessage = "Starting in \(clampedSeconds)s..."
        try await delaySleeper.sleep(seconds: clampedSeconds)
    }

    private func ensureScreenCaptureAccess() throws {
        guard screenCapturePermissionChecker.hasScreenCaptureAccess() else {
            throw ScreenCapturePermissionError.accessDenied
        }
    }

    private func selectCaptureArea() async throws -> CaptureSelection {
        switch appState.areaType {
        case .rectangle:
            return try await selectionService.selectRectangle()
        case .window:
            return try await selectionService.selectWindow()
        case .fullScreen:
            return try await selectionService.selectFullScreen()
        }
    }

    private func hideCaptureWindowsIfNeeded(settings: AppSettings) -> Bool {
        guard settings.hideAppDuringCapture else {
            return false
        }

        windowVisibilityController.hideCaptureWindows()
        return true
    }

    private func restoreCaptureWindowsIfNeeded(_ shouldRestore: Bool) {
        guard shouldRestore else {
            return
        }

        windowVisibilityController.restoreCaptureWindows()
    }

    private func userMessage(for error: Error) -> String {
        if let permissionError = error as? ScreenCapturePermissionError {
            return permissionError.localizedDescription
        }

        return error.localizedDescription
    }

    private func isRecordingStoppedByUser(_ error: Error) -> Bool {
        guard let recordingError = error as? RecordingError else {
            return false
        }

        return recordingError == .stoppedByUser
    }

    private func isSelectionCancelled(_ error: Error) -> Bool {
        guard let selectionError = error as? SelectionError else {
            return false
        }

        return selectionError == .cancelled
    }
}
