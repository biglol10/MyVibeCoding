import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorPersonalWorkflowTests: XCTestCase {
    @MainActor
    func testAutoSavedScreenshotAddsHistoryItemWithSmartFilenameMetadata() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("historyScreenshot")
        let historyStore = CaptureHistoryStore(defaults: isolatedDefaults("historyScreenshot"))
        let metadataService = MockCaptureMetadataService(
            context: FileNamingContext(
                applicationName: "Google Chrome",
                windowTitle: "Naver News / Economy"
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockPersonalSelectionService(),
            historyStore: historyStore,
            metadataService: metadataService
        )

        await coordinator.startScreenshotCapture()

        let item = try XCTUnwrap(historyStore.items.first)
        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(item.fileURL, fileURL)
        XCTAssertEqual(item.kind, .screenshot)
        XCTAssertEqual(item.sourceApplication, "Google Chrome")
        XCTAssertEqual(item.windowTitle, "Naver News / Economy")
        XCTAssertTrue(fileURL.lastPathComponent.contains("Google Chrome"))
        XCTAssertTrue(fileURL.lastPathComponent.contains("Naver News Economy"))
    }

    @MainActor
    func testManualScreenshotSaveAddsHistoryAfterFileExists() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("manualHistoryScreenshot")
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = false
        }
        let historyStore = CaptureHistoryStore(defaults: isolatedDefaults("manualHistoryScreenshot"))
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockPersonalSelectionService(),
            historyStore: historyStore,
            metadataService: MockCaptureMetadataService(
                context: FileNamingContext(applicationName: "Safari", windowTitle: "Receipt")
            )
        )

        await coordinator.startScreenshotCapture()
        XCTAssertTrue(historyStore.items.isEmpty)

        await coordinator.saveCurrentDocument()

        let item = try XCTUnwrap(historyStore.items.first)
        XCTAssertEqual(item.fileURL, appState.currentDocument?.fileURL)
        XCTAssertEqual(item.sourceApplication, "Safari")
    }

    @MainActor
    func testPinCurrentScreenshotUsesRenderedScreenshotData() async {
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: URL(fileURLWithPath: "/tmp/pinned.png"),
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: false
            )
        )
        let pinService = MockFloatingPinService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("pin"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            floatingPinService: pinService
        )

        await coordinator.pinCurrentScreenshot()

        XCTAssertEqual(pinService.pinnedImages.map(\.data), [Data([0x89, 0x50, 0x4E, 0x47])])
        XCTAssertEqual(pinService.pinnedImages.first?.title, "pinned.png")
        XCTAssertEqual(appState.statusMessage, "Screenshot pinned.")
    }

    @MainActor
    func testTrimmingCurrentRecordingUsesExporterAndUpdatesCurrentDocument() async throws {
        let sourceURL = temporaryFile(name: "source.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = MockRecordingExportService()
        let settingsStore = makeSettingsStore("trim")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.trimCurrentRecording(startSeconds: 1, endSeconds: 3)

        let request = try XCTUnwrap(exporter.trimRequests.first)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.startSeconds, 1)
        XCTAssertEqual(request.endSeconds, 3)
        let finalURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertNotEqual(finalURL, request.outputURL)
        XCTAssertEqual(finalURL.deletingLastPathComponent().path, settingsStore.settings.recordingFolderPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.outputURL.path))
        XCTAssertEqual(appState.currentDocument?.isDirty, false)
        XCTAssertEqual(appState.statusMessage, "Recording trimmed.")
    }

    @MainActor
    func testTrimmingUnsavedTemporaryRecordingRemovesOwnedSource() async throws {
        let sourceURL = temporaryFile(name: "unsaved-source.mp4", data: Data("original".utf8))
        let sourceIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                fileURL: sourceURL,
                fileIdentity: sourceIdentity,
                isDirty: true
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("trimUnsavedSourceCleanup"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: MockRecordingExportService()
        )

        await coordinator.trimCurrentRecording(startSeconds: 0, endSeconds: 1)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(appState.currentDocument?.isDirty, false)
        XCTAssertEqual(appState.statusMessage, "Recording trimmed.")
    }

    @MainActor
    func testExportCurrentRecordingAsGIFUsesExporterAndLeavesRecordingOpen() async throws {
        let sourceURL = temporaryFile(name: "source-gif.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = MockRecordingExportService()
        let revealService = MockPersonalFileRevealService()
        let settingsStore = makeSettingsStore("gif")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileRevealService: revealService,
            recordingExportService: exporter
        )

        await coordinator.exportCurrentRecordingAsGIF()

        let request = try XCTUnwrap(exporter.gifRequests.first)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.outputURL.pathExtension, "gif")
        XCTAssertNil(request.maxDurationSeconds)
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        let finalURL = try XCTUnwrap(revealService.revealedURLs.first)
        XCTAssertNotEqual(finalURL, request.outputURL)
        XCTAssertEqual(finalURL.deletingLastPathComponent().path, settingsStore.settings.recordingFolderPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.outputURL.path))
        XCTAssertEqual(appState.statusMessage, "GIF exported.")
    }

    @MainActor
    func testSavingRecordingDoesNotMoveReplacementAtSamePath() async throws {
        let sourceURL = temporaryFile(name: "manual-save-source.mp4", data: Data("original".utf8))
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let movedOriginalURL = sourceURL.deletingLastPathComponent().appendingPathComponent("manual-save-original.mp4")
        let replacementData = Data("replacement".utf8)
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try replacementData.write(to: sourceURL)
        let settingsStore = makeSettingsStore("recordingSaveReplacement")
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                fileURL: sourceURL,
                fileIdentity: originalIdentity,
                isDirty: true
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService()
        )

        await coordinator.saveCurrentDocument()

        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.currentDocument?.isDirty, true)
        XCTAssertEqual(try Data(contentsOf: sourceURL), replacementData)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: settingsStore.settings.recordingFolderPath).isEmpty)
        XCTAssertEqual(appState.statusMessage, "Save stopped because the recording changed on disk.")
    }

    @MainActor
    func testTrimDoesNotStartWhenRecordingWasReplacedAtSamePath() async throws {
        let sourceURL = temporaryFile(name: "trim-replaced-source.mp4", data: Data("original".utf8))
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let movedOriginalURL = sourceURL.deletingLastPathComponent().appendingPathComponent("trim-replaced-original.mp4")
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: sourceURL)
        let exporter = MockRecordingExportService()
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                fileURL: sourceURL,
                fileIdentity: originalIdentity,
                isDirty: false
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("trimReplacedBeforeStart"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.trimCurrentRecording(startSeconds: 0, endSeconds: 1)

        XCTAssertTrue(exporter.trimRequests.isEmpty)
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.statusMessage, "Trim stopped because the recording changed on disk.")
    }

    @MainActor
    func testGIFExportDoesNotStartWhenRecordingWasReplacedAtSamePath() async throws {
        let sourceURL = temporaryFile(name: "gif-replaced-source.mp4", data: Data("original".utf8))
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let movedOriginalURL = sourceURL.deletingLastPathComponent().appendingPathComponent("gif-replaced-original.mp4")
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: sourceURL)
        let exporter = MockRecordingExportService()
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                fileURL: sourceURL,
                fileIdentity: originalIdentity,
                isDirty: false
            )
        )
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("gifReplacedBeforeStart"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.exportCurrentRecordingAsGIF()

        XCTAssertTrue(exporter.gifRequests.isEmpty)
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.statusMessage, "GIF export stopped because the recording changed on disk.")
    }

    @MainActor
    func testTrimFailureRemovesPartialOutputFile() async throws {
        let sourceURL = temporaryFile(name: "source-trim-failure.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = FailingRecordingExportService(operation: .trim)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("trimFailureCleanup"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.trimCurrentRecording(startSeconds: 1, endSeconds: 3)

        let outputURL = try XCTUnwrap(exporter.trimRequests.first?.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.statusMessage?.hasPrefix("Trim failed:"), true)
    }

    @MainActor
    func testGIFFailureRemovesPartialOutputFile() async throws {
        let sourceURL = temporaryFile(name: "source-gif-failure.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: sourceURL,
                isDirty: false
            )
        )
        let exporter = FailingRecordingExportService(operation: .gif)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("gifFailureCleanup"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        await coordinator.exportCurrentRecordingAsGIF()

        let outputURL = try XCTUnwrap(exporter.gifRequests.first?.outputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.statusMessage?.hasPrefix("GIF export failed:"), true)
    }

    @MainActor
    func testTrimCompletionDoesNotReplaceANewerDocumentOrPublishItsOutput() async throws {
        let sourceURL = temporaryFile(name: "source-stale-trim.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let original = EditorDocument(kind: .recording, fileURL: sourceURL, isDirty: false)
        let replacement = EditorDocument(
            kind: .recording,
            fileURL: temporaryFile(name: "replacement.mp4", data: Data([0x01])),
            isDirty: false
        )
        let appState = AppState(currentDocument: original)
        let exporter = SuspendingRecordingExportService()
        let settingsStore = makeSettingsStore("staleTrim")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        let task = Task { @MainActor in
            await coordinator.trimCurrentRecording(startSeconds: 1, endSeconds: 3)
        }
        await exporter.waitUntilTrimStarted()
        appState.currentDocument = replacement
        try exporter.finishTrim()
        await task.value

        XCTAssertEqual(appState.currentDocument?.id, replacement.id)
        XCTAssertEqual(appState.statusMessage, "Trim cancelled because the document changed.")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: settingsStore.settings.recordingFolderPath).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.trimOutputURL?.path ?? ""))
    }

    @MainActor
    func testTrimMarksFileOperationBusyAndBlocksNewCaptureUntilCompletion() async throws {
        let sourceURL = temporaryFile(name: "source-file-operation-busy.mp4", data: Data("original".utf8))
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .recording,
                fileURL: sourceURL,
                fileIdentity: try CaptureFileIdentity.existingFile(at: sourceURL),
                isDirty: false
            )
        )
        let exporter = SuspendingRecordingExportService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("fileOperationBusy"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        let trimTask = Task { @MainActor in
            await coordinator.trimCurrentRecording(startSeconds: 0, endSeconds: 1)
        }
        await exporter.waitUntilTrimStarted()
        XCTAssertTrue(appState.isFileOperationInProgress)

        await coordinator.startScreenshotCapture()
        XCTAssertEqual(appState.statusMessage, "A file operation is already in progress.")

        try exporter.finishTrim()
        await trimTask.value
        XCTAssertFalse(appState.isFileOperationInProgress)
    }

    @MainActor
    func testTrimCompletionDoesNotPublishAfterSourceFileIsReplaced() async throws {
        let sourceURL = temporaryFile(name: "source-replaced-during-trim.mp4", data: Data("original".utf8))
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let original = EditorDocument(
            kind: .recording,
            fileURL: sourceURL,
            fileIdentity: originalIdentity,
            isDirty: false
        )
        let appState = AppState(currentDocument: original)
        let exporter = SuspendingRecordingExportService()
        let settingsStore = makeSettingsStore("sourceReplacedDuringTrim")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            recordingExportService: exporter
        )

        let task = Task { @MainActor in
            await coordinator.trimCurrentRecording(startSeconds: 0, endSeconds: 1)
        }
        await exporter.waitUntilTrimStarted()
        let movedOriginalURL = sourceURL.deletingLastPathComponent().appendingPathComponent("source-before-trim-replacement.mp4")
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: sourceURL)
        try exporter.finishTrim()
        await task.value

        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.currentDocument?.fileIdentity, originalIdentity)
        XCTAssertEqual(appState.statusMessage, "Trim cancelled because the source recording changed.")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: settingsStore.settings.recordingFolderPath).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.trimOutputURL?.path ?? ""))
    }

    @MainActor
    func testGIFCompletionDoesNotPublishAfterTheDocumentChanges() async throws {
        let sourceURL = temporaryFile(name: "source-stale-gif.mp4", data: Data([0x00, 0x00, 0x00, 0x18]))
        let original = EditorDocument(kind: .recording, fileURL: sourceURL, isDirty: false)
        let replacement = EditorDocument(
            kind: .recording,
            fileURL: temporaryFile(name: "replacement-gif.mp4", data: Data([0x01])),
            isDirty: false
        )
        let appState = AppState(currentDocument: original)
        let exporter = SuspendingRecordingExportService()
        let revealService = MockPersonalFileRevealService()
        let settingsStore = makeSettingsStore("staleGIF")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileRevealService: revealService,
            recordingExportService: exporter
        )

        let task = Task { @MainActor in
            await coordinator.exportCurrentRecordingAsGIF()
        }
        await exporter.waitUntilGIFStarted()
        appState.currentDocument = replacement
        try exporter.finishGIF()
        await task.value

        XCTAssertEqual(appState.currentDocument?.id, replacement.id)
        XCTAssertEqual(appState.statusMessage, "GIF export cancelled because the document changed.")
        XCTAssertTrue(revealService.revealedURLs.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: settingsStore.settings.recordingFolderPath).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.gifOutputURL?.path ?? ""))
    }

    @MainActor
    func testGIFCompletionDoesNotPublishAfterSourceFileIsReplaced() async throws {
        let sourceURL = temporaryFile(name: "source-replaced-during-gif.mp4", data: Data("original".utf8))
        let originalIdentity = try CaptureFileIdentity.existingFile(at: sourceURL)
        let original = EditorDocument(
            kind: .recording,
            fileURL: sourceURL,
            fileIdentity: originalIdentity,
            isDirty: false
        )
        let appState = AppState(currentDocument: original)
        let exporter = SuspendingRecordingExportService()
        let revealService = MockPersonalFileRevealService()
        let settingsStore = makeSettingsStore("sourceReplacedDuringGIF")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileRevealService: revealService,
            recordingExportService: exporter
        )

        let task = Task { @MainActor in
            await coordinator.exportCurrentRecordingAsGIF()
        }
        await exporter.waitUntilGIFStarted()
        let movedOriginalURL = sourceURL.deletingLastPathComponent().appendingPathComponent("source-before-gif-replacement.mp4")
        try FileManager.default.moveItem(at: sourceURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: sourceURL)
        try exporter.finishGIF()
        await task.value

        XCTAssertEqual(appState.currentDocument?.fileURL, sourceURL)
        XCTAssertEqual(appState.currentDocument?.fileIdentity, originalIdentity)
        XCTAssertEqual(appState.statusMessage, "GIF export cancelled because the source recording changed.")
        XCTAssertTrue(revealService.revealedURLs.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: settingsStore.settings.recordingFolderPath).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exporter.gifOutputURL?.path ?? ""))
    }

    @MainActor
    func testDeletingHistoryDoesNotTrashAReplacementAtTheSamePath() throws {
        let fileURL = temporaryFile(name: "history-original.png", data: Data("original".utf8))
        let movedOriginalURL = fileURL.deletingLastPathComponent().appendingPathComponent("moved-original.png")
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: fileURL,
            title: "Original",
            detail: "Screenshot",
            fileIdentity: try CaptureFileIdentity.existingFile(at: fileURL)
        )
        let historyStore = CaptureHistoryStore(defaults: isolatedDefaults("historyReplacementDelete"))
        historyStore.add(item)
        try FileManager.default.moveItem(at: fileURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: fileURL)
        let trashService = MockPersonalFileTrashService()
        let appState = AppState()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("historyReplacementDelete"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileTrashService: trashService,
            historyStore: historyStore
        )

        coordinator.deleteHistoryItem(item)

        XCTAssertTrue(trashService.trashedURLs.isEmpty)
        XCTAssertTrue(historyStore.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("replacement".utf8))
        XCTAssertEqual(appState.statusMessage, "History entry removed. The file changed and was not deleted.")
    }

    @MainActor
    func testDeletingAnOpenedHistoryDocumentDoesNotTrashAReplacementAtTheSamePath() async throws {
        let fileURL = temporaryFile(name: "opened-history-original.png", data: Data("original".utf8))
        let movedOriginalURL = fileURL.deletingLastPathComponent().appendingPathComponent("opened-history-moved.png")
        let item = CaptureHistoryItem(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: fileURL,
            title: "Original",
            detail: "Screenshot",
            fileIdentity: try CaptureFileIdentity.existingFile(at: fileURL)
        )
        let trashService = MockPersonalFileTrashService()
        let appState = AppState()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("openedHistoryReplacementDelete"),
            screenshotService: MockPersonalScreenshotService(),
            selectionService: MockPersonalSelectionService(),
            fileTrashService: trashService
        )
        await coordinator.openHistoryItem(item)
        try FileManager.default.moveItem(at: fileURL, to: movedOriginalURL)
        try Data("replacement".utf8).write(to: fileURL)

        coordinator.deleteCurrentDocument()

        XCTAssertTrue(trashService.trashedURLs.isEmpty)
        XCTAssertNotNil(appState.currentDocument)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("replacement".utf8))
        XCTAssertEqual(appState.statusMessage, "Delete stopped because the file changed on disk.")
    }

    @MainActor
    private func makeSettingsStore(_ name: String) -> SettingsStore {
        let store = SettingsStore(defaults: isolatedDefaults("settings-\(name)"))
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorPersonalWorkflowTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        store.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.recordingFolderPath = temporaryDirectory.path
            settings.showInFinderAfterSave = false
            settings.copyCapturedImageToClipboard = false
            settings.countdownSeconds = 0
        }
        return store
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorPersonalWorkflowTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryFile(name: String, data: Data) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorPersonalWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}

private final class MockPersonalScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}

private final class MockPersonalSelectionService: SelectionServicing {
    func selectRectangle() async throws -> CaptureSelection {
        CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            rect: CGRect(x: 10, y: 20, width: 300, height: 200),
            scale: 1
        )
    }

    func selectWindow() async throws -> CaptureSelection {
        try await selectRectangle()
    }

    func selectFullScreen() async throws -> CaptureSelection {
        try await selectRectangle()
    }
}

private struct MockCaptureMetadataService: CaptureMetadataServicing {
    let context: FileNamingContext?

    func namingContext(for selection: CaptureSelection) -> FileNamingContext? {
        context
    }
}

private final class MockFloatingPinService: FloatingPinServicing {
    struct PinnedImage: Equatable {
        let data: Data
        let title: String
    }

    var pinnedImages: [PinnedImage] = []

    func pinImage(data: Data, title: String) throws {
        pinnedImages.append(PinnedImage(data: data, title: title))
    }
}

private final class MockRecordingExportService: RecordingExportServicing {
    struct TrimRequest: Equatable {
        let sourceURL: URL
        let startSeconds: Double
        let endSeconds: Double?
        let outputURL: URL
    }

    struct GIFRequest: Equatable {
        let sourceURL: URL
        let outputURL: URL
        let maxDurationSeconds: Double?
    }

    var trimRequests: [TrimRequest] = []
    var gifRequests: [GIFRequest] = []

    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double?, outputURL: URL) async throws -> RecordingExportResult {
        trimRequests.append(
            TrimRequest(sourceURL: sourceURL, startSeconds: startSeconds, endSeconds: endSeconds, outputURL: outputURL)
        )
        try Data([0x00, 0x00, 0x00, 0x18, 0x54]).write(to: outputURL, options: .atomic)
        return RecordingExportResult(fileURL: outputURL)
    }

    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> RecordingExportResult {
        gifRequests.append(
            GIFRequest(sourceURL: sourceURL, outputURL: outputURL, maxDurationSeconds: maxDurationSeconds)
        )
        try Data("GIF89a".utf8).write(to: outputURL, options: .atomic)
        return RecordingExportResult(fileURL: outputURL)
    }
}

private final class FailingRecordingExportService: RecordingExportServicing {
    enum Operation {
        case trim
        case gif
    }

    let operation: Operation
    var trimRequests: [MockRecordingExportService.TrimRequest] = []
    var gifRequests: [MockRecordingExportService.GIFRequest] = []

    init(operation: Operation) {
        self.operation = operation
    }

    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double?, outputURL: URL) async throws -> RecordingExportResult {
        trimRequests.append(
            MockRecordingExportService.TrimRequest(
                sourceURL: sourceURL,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                outputURL: outputURL
            )
        )
        throw RecordingExportError.exportFailed("forced trim failure")
    }

    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> RecordingExportResult {
        gifRequests.append(
            MockRecordingExportService.GIFRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                maxDurationSeconds: maxDurationSeconds
            )
        )
        throw RecordingExportError.gifDestinationFailed
    }
}

private final class MockPersonalFileRevealService: FileRevealServicing {
    var revealedURLs: [URL] = []

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}

private final class MockPersonalFileTrashService: FileTrashServicing {
    private(set) var trashedURLs: [URL] = []

    func trash(_ url: URL, expectedIdentity: CaptureFileIdentity?) throws {
        trashedURLs.append(url)
    }
}

@MainActor
private final class SuspendingRecordingExportService: RecordingExportServicing {
    private var trimContinuation: CheckedContinuation<RecordingExportResult, Error>?
    private var gifContinuation: CheckedContinuation<RecordingExportResult, Error>?
    private var trimWaiters: [CheckedContinuation<Void, Never>] = []
    private var gifWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var trimOutputURL: URL?
    private(set) var gifOutputURL: URL?

    func trimRecording(sourceURL: URL, startSeconds: Double, endSeconds: Double?, outputURL: URL) async throws -> RecordingExportResult {
        trimOutputURL = outputURL
        trimWaiters.forEach { $0.resume() }
        trimWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            trimContinuation = continuation
        }
    }

    func exportGIF(sourceURL: URL, outputURL: URL, maxDurationSeconds: Double?) async throws -> RecordingExportResult {
        gifOutputURL = outputURL
        gifWaiters.forEach { $0.resume() }
        gifWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            gifContinuation = continuation
        }
    }

    func waitUntilTrimStarted() async {
        if trimOutputURL != nil {
            return
        }
        await withCheckedContinuation { continuation in
            trimWaiters.append(continuation)
        }
    }

    func waitUntilGIFStarted() async {
        if gifOutputURL != nil {
            return
        }
        await withCheckedContinuation { continuation in
            gifWaiters.append(continuation)
        }
    }

    func finishTrim() throws {
        guard let trimOutputURL else {
            throw RecordingExportError.exportFailed("trim was not started")
        }
        try Data([0x00, 0x00, 0x00, 0x18, 0x54]).write(to: trimOutputURL, options: .atomic)
        trimContinuation?.resume(returning: RecordingExportResult(fileURL: trimOutputURL))
        trimContinuation = nil
    }

    func finishGIF() throws {
        guard let gifOutputURL else {
            throw RecordingExportError.exportFailed("GIF was not started")
        }
        try Data("GIF89a".utf8).write(to: gifOutputURL, options: .atomic)
        gifContinuation?.resume(returning: RecordingExportResult(fileURL: gifOutputURL))
        gifContinuation = nil
    }
}
