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
    private let documentReplacementAuthorizer: DocumentReplacementAuthorizing
    private let pendingRecordingStore: PendingRecordingStore
    private let pendingRecordingValidator: PendingRecordingMediaValidator
    private let historyThumbnailService: CaptureHistoryThumbnailService
    private let historyFileLoader: CaptureHistoryFileLoader
    private var screenshotSaveGenerationByDocumentID: [UUID: UInt64] = [:]
    private var isTerminationPreparationInProgress = false
    private var didAttemptPendingRecordingRecovery = false

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
        recordingExportService: RecordingExportServicing = AVFoundationRecordingExportService(),
        pendingRecordingStore: PendingRecordingStore = PendingRecordingStore(),
        pendingRecordingValidator: PendingRecordingMediaValidator = PendingRecordingMediaValidator(),
        historyThumbnailService: CaptureHistoryThumbnailService = CaptureHistoryThumbnailService(),
        historyFileLoader: CaptureHistoryFileLoader = CaptureHistoryFileLoader(),
        documentReplacementAuthorizer: DocumentReplacementAuthorizing = AppKitDocumentReplacementAuthorizer()
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
        self.pendingRecordingStore = pendingRecordingStore
        self.pendingRecordingValidator = pendingRecordingValidator
        self.historyThumbnailService = historyThumbnailService
        self.historyFileLoader = historyFileLoader
        self.documentReplacementAuthorizer = documentReplacementAuthorizer
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
        guard beginCaptureOperation() else {
            return
        }
        defer { endCaptureOperation() }

        do {
            appState.permissionPrompt = nil
            try ensureScreenCaptureAccess()
            guard var replacement = await authorizeDocumentReplacementIfNeeded() else {
                return
            }
            let settings = settingsStore.settings
            let didHideCaptureWindows = hideCaptureWindowsIfNeeded(settings: settings)
            defer { restoreCaptureWindowsIfNeeded(didHideCaptureWindows) }
            try await waitIfNeeded(seconds: settings.defaultDelaySeconds)
            let selection = try await selectCaptureArea()
            let namingContext = metadataService.namingContext(for: selection)
            let result = try await screenshotService.captureImage(selection: selection)
            guard let refreshedReplacement = await refreshReplacementAuthorizationIfDocumentChanged(replacement) else {
                return
            }
            replacement = refreshedReplacement
            copyToClipboardIfNeeded(result.pngData, settings: settings)
            if settings.automaticallySaveScreenshots {
                let fileURL: URL
                do {
                    fileURL = try fileOutputService.writeScreenshotData(
                        result.pngData,
                        settings: settings,
                        date: result.createdAt,
                        context: namingContext
                    )
                } catch {
                    let document = EditorDocument(
                        kind: .screenshot,
                        createdAt: result.createdAt,
                        data: result.pngData,
                        namingContext: namingContext
                    )
                    appState.currentDocument = document
                    discardSupersededTemporaryRecordingIfNeeded(replacement)
                    appState.statusMessage = "Screenshot captured but could not be saved: \(error.localizedDescription)"
                    return
                }
                revealIfNeeded(fileURL, settings: settings)
                let document = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    fileURL: fileURL,
                    fileIdentity: try? CaptureFileIdentity.existingFile(at: fileURL),
                    data: result.pngData,
                    namingContext: namingContext,
                    isDirty: false
                )
                appState.currentDocument = document
                discardSupersededTemporaryRecordingIfNeeded(replacement)
                await addHistoryItem(for: document)
                appState.statusMessage = "Screenshot captured."
            } else {
                let document = EditorDocument(
                    kind: .screenshot,
                    createdAt: result.createdAt,
                    data: result.pngData,
                    namingContext: namingContext
                )
                appState.currentDocument = document
                discardSupersededTemporaryRecordingIfNeeded(replacement)
                appState.statusMessage = "Screenshot captured. Press Save to write the file."
            }
        } catch {
            if isSelectionCancelled(error) {
                appState.statusMessage = "Screenshot cancelled."
            } else {
                appState.statusMessage = "Screenshot failed: \(userMessage(for: error))"
                presentPermissionPromptIfNeeded(for: error)
            }
        }
    }

    public func startScreenRecording() async {
        guard beginCaptureOperation() else {
            return
        }
        defer { endCaptureOperation() }

        do {
            appState.permissionPrompt = nil
            try ensureScreenCaptureAccess()
            guard var replacement = await authorizeDocumentReplacementIfNeeded() else {
                return
            }
            let settings = settingsStore.settings
            var captureWindowsAreHidden = hideCaptureWindowsIfNeeded(settings: settings)
            defer { restoreCaptureWindowsIfNeeded(captureWindowsAreHidden) }
            let selection = try await selectCaptureArea()
            restoreCaptureWindowsIfNeeded(captureWindowsAreHidden)
            captureWindowsAreHidden = false
            let namingContext = metadataService.namingContext(for: selection)
            try await waitIfNeeded(seconds: settings.countdownSeconds)
            let outputURL = try pendingRecordingStore.allocateRecordingURL()
            appState.isRecordingInProgress = true
            defer { appState.isRecordingInProgress = false }
            let result = try await recordingService.recordScreen(selection: selection, to: outputURL, settings: settings)
            guard let refreshedReplacement = await refreshReplacementAuthorizationIfDocumentChanged(replacement) else {
                discardRecordingResultIfOwned(result)
                return
            }
            replacement = refreshedReplacement
            let finalURL: URL
            if settings.automaticallySaveRecordings {
                do {
                    finalURL = try await fileOutputService.moveRecordingFileAsync(
                        from: result.fileURL,
                        expectedSourceIdentity: result.fileIdentity,
                        settings: settings,
                        date: result.createdAt,
                        context: namingContext
                    )
                } catch {
                    let document = EditorDocument(
                        kind: .recording,
                        createdAt: result.createdAt,
                        fileURL: result.fileURL,
                        fileIdentity: result.fileIdentity,
                        namingContext: namingContext,
                        isDirty: true
                    )
                    appState.currentDocument = document
                    discardSupersededTemporaryRecordingIfNeeded(replacement)
                    appState.statusMessage = "Recording captured but could not be saved: \(error.localizedDescription)"
                    return
                }
            } else {
                finalURL = result.fileURL
            }
            let document = EditorDocument(
                kind: .recording,
                createdAt: result.createdAt,
                fileURL: finalURL,
                fileIdentity: try? CaptureFileIdentity.existingFile(at: finalURL),
                namingContext: namingContext,
                isDirty: !settings.automaticallySaveRecordings
            )
            appState.currentDocument = document
            discardSupersededTemporaryRecordingIfNeeded(replacement)
            if settings.automaticallySaveRecordings {
                await addHistoryItem(for: document)
                revealIfNeeded(finalURL, settings: settings)
                appState.statusMessage = "Recording saved."
            } else {
                appState.statusMessage = "Recording captured. Press Save to write the file."
            }
        } catch {
            if isSelectionCancelled(error) {
                appState.statusMessage = "Recording cancelled."
            } else if isRecordingStoppedByUser(error) {
                appState.statusMessage = "Recording stopped."
            } else {
                appState.statusMessage = "Recording failed: \(userMessage(for: error))"
                presentPermissionPromptIfNeeded(for: error)
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

    public func recoverPendingRecordingIfAvailable() async {
        guard !didAttemptPendingRecordingRecovery,
              appState.currentDocument == nil,
              !appState.isInteractionBlocked,
              !appState.isRecordingInProgress
        else {
            return
        }
        didAttemptPendingRecordingRecovery = true

        let pendingRecordingStore = self.pendingRecordingStore
        do {
            let recordings = try await Task.detached(priority: .utility) {
                try pendingRecordingStore.recoverableRecordings()
            }.value
            var recoverableRecording: PendingRecording?
            for candidate in recordings {
                if await pendingRecordingValidator.isRecoverableRecording(at: candidate.fileURL) {
                    recoverableRecording = candidate
                    break
                }
            }
            guard appState.currentDocument == nil,
                  !appState.isInteractionBlocked,
                  !appState.isRecordingInProgress
            else {
                didAttemptPendingRecordingRecovery = false
                return
            }
            guard let recording = recoverableRecording,
                  recording.fileIdentity.matchesExistingFile(at: recording.fileURL)
            else {
                if !recordings.isEmpty {
                    appState.statusMessage = "An unsaved recording was found but could not be recovered."
                }
                return
            }

            appState.currentDocument = EditorDocument(
                kind: .recording,
                createdAt: recording.createdAt,
                fileURL: recording.fileURL,
                fileIdentity: recording.fileIdentity,
                namingContext: FileNamingContext(applicationName: "Recovered Recording", windowTitle: nil),
                isDirty: true
            )
            appState.statusMessage = "Recovered an unsaved recording. Save or delete it before starting another capture."
        } catch {
            appState.statusMessage = "Unsaved recordings could not be checked: \(error.localizedDescription)"
        }
    }

    public var needsTerminationPreparation: Bool {
        appState.isInteractionBlocked
            || appState.isRecordingInProgress
            || appState.currentDocument?.isDirty == true
    }

    public func prepareForTermination() async -> Bool {
        guard !isTerminationPreparationInProgress else {
            return false
        }
        guard !appState.isInteractionBlocked, !appState.isRecordingInProgress else {
            appState.statusMessage = "Finish or cancel the active operation before quitting."
            return false
        }
        isTerminationPreparationInProgress = true
        defer { isTerminationPreparationInProgress = false }

        guard let replacement = await authorizeDocumentReplacementIfNeeded(
            cancelStatusMessage: "Quit cancelled. Current document was preserved.",
            forTermination: true
        ) else {
            return false
        }
        guard !appState.isInteractionBlocked, !appState.isRecordingInProgress else {
            appState.statusMessage = "Finish or cancel the active operation before quitting."
            return false
        }

        if replacement.shouldDiscardUnsavedRecording {
            discardSupersededTemporaryRecordingIfNeeded(replacement)
            appState.currentDocument = nil
        }
        return true
    }

    public func saveCurrentDocument() async {
        guard var document = appState.currentDocument else {
            appState.statusMessage = "Nothing to save."
            return
        }

        switch document.kind {
        case .screenshot:
            let saveGeneration = nextScreenshotSaveGeneration(for: document.id)
            let expectedRevision = ScreenshotContentRevision(document)
            do {
                let outputData = try await screenshotDataForOutput(document)
                guard isCurrentScreenshotSave(
                    saveGeneration,
                    expectedRevision: expectedRevision
                ) else {
                    return
                }
                let fileURL = try fileOutputService.writeScreenshotData(
                    outputData,
                    settings: settingsStore.settings,
                    date: document.createdAt,
                    context: document.namingContext
                )
                revealIfNeeded(fileURL, settings: settingsStore.settings)
                document.fileURL = fileURL
                document.fileIdentity = try? CaptureFileIdentity.existingFile(at: fileURL)
                document.savedSnapshot = document.currentSnapshot
                document.isDirty = false
                if var currentDocument = appState.currentDocument,
                   ScreenshotContentRevision(currentDocument) == expectedRevision {
                    currentDocument.fileURL = fileURL
                    currentDocument.fileIdentity = document.fileIdentity
                    currentDocument.renderedImageData = nil
                    currentDocument.savedSnapshot = document.currentSnapshot
                    currentDocument.refreshDirtyState()
                    appState.currentDocument = currentDocument
                }
                var historyDocument = document
                historyDocument.renderedImageData = outputData
                await addHistoryItem(for: historyDocument)
                appState.statusMessage = "Screenshot saved."
            } catch let error as ImageRenderError {
                if isCurrentScreenshotSave(saveGeneration, expectedRevision: expectedRevision) {
                    appState.statusMessage = "Image render failed: \(error.localizedDescription)"
                }
            } catch {
                if isCurrentScreenshotSave(saveGeneration, expectedRevision: expectedRevision) {
                    appState.statusMessage = "Save failed: \(error.localizedDescription)"
                }
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
            guard let sourceIdentity = validatedRecordingIdentity(for: document, at: sourceURL) else {
                appState.statusMessage = "Save stopped because the recording changed on disk."
                return
            }
            guard beginFileOperation(allowDuringCapture: true) else {
                return
            }
            defer { endFileOperation() }

            do {
                let settings = settingsStore.settings
                let fileURL = try await fileOutputService.moveRecordingFileAsync(
                    from: sourceURL,
                    expectedSourceIdentity: sourceIdentity,
                    settings: settings,
                    date: document.createdAt,
                    context: document.namingContext
                )
                revealIfNeeded(fileURL, settings: settings)
                document.fileURL = fileURL
                document.fileIdentity = try? CaptureFileIdentity.existingFile(at: fileURL)
                document.isDirty = false
                appState.currentDocument = document
                await addHistoryItem(for: document)
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

        if let fileIdentity = document.fileIdentity,
           !fileIdentity.matchesExistingFile(at: fileURL) {
            appState.statusMessage = "Delete stopped because the file changed on disk."
            return
        }

        do {
            try fileTrashService.trash(fileURL, expectedIdentity: document.fileIdentity)
            historyStore?.remove(fileURL: fileURL)
            appState.currentDocument = nil
            appState.statusMessage = deletedMessage
        } catch {
            appState.statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    public func openHistoryItem(_ item: CaptureHistoryItem) async {
        guard validateHistoryItemForOpening(item) else {
            return
        }
        guard var replacement = await authorizeDocumentReplacementIfNeeded(
            cancelStatusMessage: "History item was not opened. Current document was preserved."
        ) else {
            return
        }
        guard let refreshedReplacement = await refreshReplacementAuthorizationIfDocumentChanged(
            replacement,
            cancelStatusMessage: "History item was not opened. Current document was preserved."
        ) else {
            return
        }
        replacement = refreshedReplacement
        guard validateHistoryItemForOpening(item),
              let historyDocument = await historyDocument(for: item)
        else {
            return
        }
        guard let refreshedReplacement = await refreshReplacementAuthorizationIfDocumentChanged(
            replacement,
            cancelStatusMessage: "History item was not opened. Current document was preserved."
        ) else {
            return
        }
        replacement = refreshedReplacement

        discardSupersededTemporaryRecordingIfNeeded(replacement)
        appState.currentDocument = historyDocument
        appState.statusMessage = "History item opened."
    }

    public func deleteHistoryItem(_ item: CaptureHistoryItem) {
        do {
            if FileManager.default.fileExists(atPath: item.fileURL.path) {
                guard let fileIdentity = item.fileIdentity,
                      fileIdentity.matchesExistingFile(at: item.fileURL)
                else {
                    historyStore?.remove(id: item.id)
                    appState.statusMessage = "History entry removed. The file changed and was not deleted."
                    return
                }
                try fileTrashService.trash(item.fileURL, expectedIdentity: fileIdentity)
            }
            let thumbnailCleanupSucceeded = historyStore?.remove(id: item.id) ?? true
            if appState.currentDocument?.fileURL?.standardizedFileURL == item.fileURL.standardizedFileURL {
                appState.currentDocument = nil
            }
            if thumbnailCleanupSucceeded {
                appState.statusMessage = item.kind == .recording ? "Recording deleted." : "Screenshot deleted."
            } else {
                appState.statusMessage = "Capture deleted, but its history thumbnail could not be removed."
            }
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

    public func trimCurrentRecording(startSeconds: Double, endSeconds: Double?) async {
        guard beginFileOperation() else {
            return
        }
        defer { endFileOperation() }
        guard let document = appState.currentDocument, document.kind == .recording else {
            appState.statusMessage = "No recording to trim."
            return
        }
        guard let sourceURL = document.fileURL else {
            appState.statusMessage = "No recording file to trim."
            return
        }
        guard let sourceIdentity = validatedRecordingIdentity(for: document, at: sourceURL) else {
            appState.statusMessage = "Trim stopped because the recording changed on disk."
            return
        }

        let exportDate = Date()
        let temporaryOutputURL = fileOutputService.temporaryRecordingURL()
        var producedResult: RecordingExportResult?
        do {
            let exportResult = try await recordingExportService.trimRecording(
                sourceURL: sourceURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                outputURL: temporaryOutputURL
            )
            producedResult = exportResult
            let temporaryTrimmedURL = exportResult.fileURL
            guard var currentDocument = appState.currentDocument,
                  currentDocument.id == document.id,
                  currentDocument.fileURL?.standardizedFileURL == sourceURL.standardizedFileURL
            else {
                discardExportResultIfOwned(exportResult)
                appState.statusMessage = "Trim cancelled because the document changed."
                return
            }
            guard sourceIdentity.matchesExistingFile(at: sourceURL),
                  currentDocument.fileIdentity == nil || currentDocument.fileIdentity == sourceIdentity
            else {
                discardExportResultIfOwned(exportResult)
                appState.statusMessage = "Trim cancelled because the source recording changed."
                return
            }
            let trimmedURL = try await fileOutputService.moveTrimmedRecordingFileAsync(
                from: temporaryTrimmedURL,
                expectedSourceIdentity: exportResult.fileIdentity,
                settings: settingsStore.settings,
                date: exportDate,
                context: document.namingContext
            )
            currentDocument.fileURL = trimmedURL
            currentDocument.fileIdentity = try? CaptureFileIdentity.existingFile(at: trimmedURL)
            currentDocument.createdAt = Date()
            currentDocument.isDirty = false
            let removedTemporarySource = discardTemporaryRecordingIfOwned(
                document,
                identity: sourceIdentity
            )
            appState.currentDocument = currentDocument
            await addHistoryItem(for: currentDocument)
            revealIfNeeded(trimmedURL, settings: settingsStore.settings)
            appState.statusMessage = removedTemporarySource
                ? "Recording trimmed."
                : "Recording trimmed, but the temporary original could not be removed."
        } catch {
            if let producedResult {
                discardExportResultIfOwned(producedResult)
            }
            appState.statusMessage = "Trim failed: \(error.localizedDescription)"
        }
    }

    public func exportCurrentRecordingAsGIF() async {
        guard beginFileOperation() else {
            return
        }
        defer { endFileOperation() }
        guard let document = appState.currentDocument, document.kind == .recording else {
            appState.statusMessage = "No recording to export."
            return
        }
        guard let sourceURL = document.fileURL else {
            appState.statusMessage = "No recording file to export."
            return
        }
        guard let sourceIdentity = validatedRecordingIdentity(for: document, at: sourceURL) else {
            appState.statusMessage = "GIF export stopped because the recording changed on disk."
            return
        }

        let exportDate = Date()
        let temporaryOutputURL = fileOutputService.temporaryGIFURL()
        var producedResult: RecordingExportResult?
        do {
            let exportResult = try await recordingExportService.exportGIF(
                sourceURL: sourceURL,
                outputURL: temporaryOutputURL,
                maxDurationSeconds: nil
            )
            producedResult = exportResult
            let temporaryGIFURL = exportResult.fileURL
            guard let currentDocument = appState.currentDocument,
                  currentDocument.id == document.id,
                  currentDocument.fileURL?.standardizedFileURL == sourceURL.standardizedFileURL
            else {
                discardExportResultIfOwned(exportResult)
                appState.statusMessage = "GIF export cancelled because the document changed."
                return
            }
            guard sourceIdentity.matchesExistingFile(at: sourceURL),
                  currentDocument.fileIdentity == nil || currentDocument.fileIdentity == sourceIdentity
            else {
                discardExportResultIfOwned(exportResult)
                appState.statusMessage = "GIF export cancelled because the source recording changed."
                return
            }
            let gifURL = try await fileOutputService.moveGIFFileAsync(
                from: temporaryGIFURL,
                expectedSourceIdentity: exportResult.fileIdentity,
                settings: settingsStore.settings,
                date: exportDate,
                context: document.namingContext
            )
            fileRevealService.reveal(gifURL)
            appState.statusMessage = "GIF exported."
        } catch {
            if let producedResult {
                discardExportResultIfOwned(producedResult)
            }
            appState.statusMessage = "GIF export failed: \(error.localizedDescription)"
        }
    }

    public func runOCR() async {
        guard let document = appState.currentDocument, document.kind == .screenshot else {
            appState.statusMessage = "No screenshot to scan."
            return
        }
        let expectedRevision = ScreenshotContentRevision(document)

        do {
            let data = try await screenshotDataForOutput(document)
            let result = try await ocrService.recognizeText(in: data)
            guard var currentDocument = appState.currentDocument,
                  ScreenshotContentRevision(currentDocument) == expectedRevision
            else {
                appState.statusMessage = "OCR cancelled because the document changed."
                return
            }
            currentDocument.ocrResult = result
            appState.currentDocument = currentDocument
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
        let expectedRevision = ScreenshotContentRevision(document)

        do {
            let result: OCRResult
            if let existing = document.ocrResult {
                result = existing
            } else {
                let data = try await screenshotDataForOutput(document)
                result = try await ocrService.recognizeText(in: data)
                guard let currentDocument = appState.currentDocument,
                      ScreenshotContentRevision(currentDocument) == expectedRevision
                else {
                    appState.statusMessage = "Redaction cancelled because the document changed."
                    return
                }
                document = currentDocument
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
            document.ocrResult = nil
            document.isDirty = true
            appState.currentDocument = document
            let resultSummary = newLayers.count == 1 ? "Redaction added." : "\(newLayers.count) redactions added."
            appState.statusMessage = "\(resultSummary) Save or Copy creates a redacted version; the original file and clipboard are unchanged."
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

    private func addHistoryItem(for document: EditorDocument) async {
        guard let fileURL = document.fileURL,
              let expectedFileIdentity = document.fileIdentity
                ?? (try? CaptureFileIdentity.existingFile(at: fileURL))
        else {
            return
        }

        let context = document.namingContext
        let title = context?.displayTitle.isEmpty == false
            ? context?.displayTitle ?? fileURL.lastPathComponent
            : fileURL.lastPathComponent
        let detail = document.kind == .recording ? "Recording" : "Screenshot"
        let thumbnailData: Data?
        if document.kind == .screenshot, let imageData = document.currentImageData {
            thumbnailData = await historyThumbnailService.thumbnailData(from: imageData)
        } else {
            thumbnailData = nil
        }
        guard expectedFileIdentity.matchesExistingFile(at: fileURL) else {
            return
        }
        historyStore?.addPrepared(
            CaptureHistoryItem(
                kind: document.kind,
                createdAt: document.createdAt,
                fileURL: fileURL,
                title: title,
                detail: detail,
                fileIdentity: expectedFileIdentity,
                thumbnailData: thumbnailData,
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

    private struct ReplacementAuthorization {
        let document: EditorDocument?
        let shouldDiscardUnsavedRecording: Bool
    }

    private func beginCaptureOperation() -> Bool {
        guard !isTerminationPreparationInProgress else {
            appState.statusMessage = "Quit confirmation is in progress."
            return false
        }
        guard !appState.isFileOperationInProgress else {
            appState.statusMessage = "A file operation is already in progress."
            return false
        }
        guard !appState.isCaptureOperationInProgress else {
            appState.statusMessage = "Another capture operation is already in progress."
            return false
        }

        appState.isCaptureOperationInProgress = true
        return true
    }

    private func endCaptureOperation() {
        appState.isCaptureOperationInProgress = false
    }

    private func beginFileOperation(allowDuringCapture: Bool = false) -> Bool {
        guard !appState.isFileOperationInProgress else {
            appState.statusMessage = "A file operation is already in progress."
            return false
        }
        guard allowDuringCapture || !appState.isCaptureOperationInProgress else {
            appState.statusMessage = "A capture operation is already in progress."
            return false
        }
        appState.isFileOperationInProgress = true
        return true
    }

    private func endFileOperation() {
        appState.isFileOperationInProgress = false
    }

    private func nextScreenshotSaveGeneration(for documentID: UUID) -> UInt64 {
        let nextGeneration = (screenshotSaveGenerationByDocumentID[documentID] ?? 0) &+ 1
        screenshotSaveGenerationByDocumentID[documentID] = nextGeneration
        return nextGeneration
    }

    private func isLatestScreenshotSave(_ generation: UInt64, for documentID: UUID) -> Bool {
        screenshotSaveGenerationByDocumentID[documentID] == generation
    }

    private func isCurrentScreenshotSave(
        _ generation: UInt64,
        expectedRevision: ScreenshotContentRevision
    ) -> Bool {
        guard isLatestScreenshotSave(generation, for: expectedRevision.documentID),
              let currentDocument = appState.currentDocument
        else {
            return false
        }
        return ScreenshotContentRevision(currentDocument) == expectedRevision
    }

    private func validatedRecordingIdentity(
        for document: EditorDocument,
        at fileURL: URL
    ) -> CaptureFileIdentity? {
        let identity = document.fileIdentity ?? (try? CaptureFileIdentity.existingFile(at: fileURL))
        guard let identity, identity.matchesExistingFile(at: fileURL) else {
            return nil
        }
        return identity
    }

    private func authorizeDocumentReplacementIfNeeded(
        cancelStatusMessage: String = "Capture cancelled. Current document was preserved.",
        forTermination: Bool = false
    ) async -> ReplacementAuthorization? {
        while true {
            guard let document = appState.currentDocument, document.isDirty else {
                return ReplacementAuthorization(
                    document: appState.currentDocument,
                    shouldDiscardUnsavedRecording: false
                )
            }

            let decision = forTermination
                ? await documentReplacementAuthorizer.terminationDecision(for: document)
                : await documentReplacementAuthorizer.replacementDecision(for: document)
            guard appState.currentDocument == document else {
                continue
            }

            switch decision {
            case .save:
                await saveCurrentDocument()
                guard let savedDocument = appState.currentDocument else {
                    continue
                }
                guard savedDocument.id == document.id else {
                    continue
                }
                guard !savedDocument.isDirty else {
                    return nil
                }
                return ReplacementAuthorization(
                    document: savedDocument,
                    shouldDiscardUnsavedRecording: false
                )
            case .discard:
                return ReplacementAuthorization(
                    document: document,
                    shouldDiscardUnsavedRecording: true
                )
            case .cancel:
                appState.statusMessage = cancelStatusMessage
                return nil
            }
        }
    }

    private func refreshReplacementAuthorizationIfDocumentChanged(
        _ authorization: ReplacementAuthorization,
        cancelStatusMessage: String = "Capture cancelled. Current document was preserved."
    ) async -> ReplacementAuthorization? {
        guard appState.currentDocument != authorization.document else {
            return authorization
        }
        return await authorizeDocumentReplacementIfNeeded(cancelStatusMessage: cancelStatusMessage)
    }

    private func validateHistoryItemForOpening(_ item: CaptureHistoryItem) -> Bool {
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            historyStore?.remove(id: item.id)
            appState.statusMessage = "History file is missing."
            return false
        }
        if let fileIdentity = item.fileIdentity,
           !fileIdentity.matchesExistingFile(at: item.fileURL) {
            historyStore?.remove(id: item.id)
            appState.statusMessage = "History file changed and was not opened."
            return false
        }
        return true
    }

    private func historyDocument(for item: CaptureHistoryItem) async -> EditorDocument? {
        do {
            let fileIdentity = try item.fileIdentity ?? CaptureFileIdentity.existingFile(at: item.fileURL)
            let namingContext = FileNamingContext(
                applicationName: item.sourceApplication ?? item.detail,
                windowTitle: item.windowTitle
            )
            switch item.kind {
            case .screenshot:
                let data = try await historyFileLoader.load(item.fileURL)
                guard fileIdentity.matchesExistingFile(at: item.fileURL) else {
                    appState.statusMessage = "History file changed and was not opened."
                    return nil
                }
                return EditorDocument(
                    kind: .screenshot,
                    createdAt: item.createdAt,
                    fileURL: item.fileURL,
                    fileIdentity: fileIdentity,
                    data: data,
                    namingContext: namingContext,
                    isDirty: false
                )
            case .recording:
                return EditorDocument(
                    kind: .recording,
                    createdAt: item.createdAt,
                    fileURL: item.fileURL,
                    fileIdentity: fileIdentity,
                    namingContext: namingContext,
                    isDirty: false
                )
            }
        } catch {
            appState.statusMessage = "History item could not be opened."
            return nil
        }
    }

    private func discardSupersededTemporaryRecordingIfNeeded(_ replacement: ReplacementAuthorization) {
        guard replacement.shouldDiscardUnsavedRecording,
              let document = replacement.document,
              document.kind == .recording,
              document.isDirty,
              let fileURL = document.fileURL,
              let fileIdentity = document.fileIdentity,
              fileIdentity.matchesExistingFile(at: fileURL),
              pendingRecordingStore.owns(fileURL)
        else {
            return
        }

        _ = try? ExclusiveFilePublisher.discardFileIfStillOwned(fileURL, identity: fileIdentity)
    }

    private func discardRecordingResultIfOwned(_ result: RecordingResult) {
        guard let fileIdentity = result.fileIdentity else {
            return
        }
        _ = try? ExclusiveFilePublisher.discardFileIfStillOwned(result.fileURL, identity: fileIdentity)
    }

    private func discardExportResultIfOwned(_ result: RecordingExportResult) {
        guard let fileIdentity = result.fileIdentity else {
            return
        }
        _ = try? ExclusiveFilePublisher.discardFileIfStillOwned(result.fileURL, identity: fileIdentity)
    }

    private func discardTemporaryRecordingIfOwned(
        _ document: EditorDocument,
        identity: CaptureFileIdentity
    ) -> Bool {
        guard document.kind == .recording,
              document.isDirty,
              let fileURL = document.fileURL,
              pendingRecordingStore.owns(fileURL)
        else {
            return true
        }

        return (try? ExclusiveFilePublisher.discardFileIfStillOwned(fileURL, identity: identity)) == true
    }

    private func userMessage(for error: Error) -> String {
        if let permissionError = error as? ScreenCapturePermissionError {
            return permissionError.localizedDescription
        }

        return error.localizedDescription
    }

    private func presentPermissionPromptIfNeeded(for error: Error) {
        guard error is ScreenCapturePermissionError else {
            return
        }

        appState.permissionPrompt = .screenRecording
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

private struct ScreenshotContentRevision: Equatable {
    let documentID: UUID
    let data: Data?
    let baseImageData: Data?
    let renderedImageData: Data?
    let layers: [EditorLayer]

    init(_ document: EditorDocument) {
        documentID = document.id
        data = document.data
        baseImageData = document.baseImageData
        renderedImageData = document.renderedImageData
        layers = document.layers
    }
}
