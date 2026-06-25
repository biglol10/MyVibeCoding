import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorTests: XCTestCase {
    @MainActor
    func testNewScreenshotAutoSavesWhenEnabled() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("screenshot")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.automaticallySaveScreenshots = true
        }
        let service = MockScreenshotService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service,
            fileOutputService: FileOutputService(),
            selectionService: selectionService
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(appState.currentDocument?.kind, .screenshot)
        XCTAssertNotNil(appState.currentDocument?.fileURL)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
        XCTAssertEqual(appState.statusMessage, "Screenshot captured.")
        XCTAssertEqual(service.captureCallCount, 1)
        XCTAssertEqual(selectionService.selectionCallCount, 1)
        XCTAssertEqual(service.lastSelection, selectionService.selection)
        if let fileURL = appState.currentDocument?.fileURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        }
    }

    @MainActor
    func testNewScreenshotStaysUnsavedWhenAutomaticSaveDisabled() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("manualScreenshot")
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = false
        }
        let service = MockScreenshotService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service,
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService()
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(appState.currentDocument?.kind, .screenshot)
        XCTAssertNil(appState.currentDocument?.fileURL)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
        XCTAssertEqual(appState.statusMessage, "Screenshot captured. Press Save to write the file.")
    }

    @MainActor
    func testScreenshotSelectionCancelReturnsToInitialState() async {
        let appState = AppState()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("screenshotSelectionCancel"),
            screenshotService: MockScreenshotService(),
            selectionService: FailingSelectionService(error: SelectionError.cancelled)
        )

        await coordinator.startScreenshotCapture()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(appState.statusMessage, "Screenshot cancelled.")
    }

    @MainActor
    func testScreenshotCopiesImageToClipboardWhenEnabled() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("clipboardEnabled")
        settingsStore.update { settings in
            settings.copyCapturedImageToClipboard = true
        }
        let service = MockScreenshotService()
        let clipboardService = MockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service,
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService(),
            clipboardService: clipboardService
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(clipboardService.copiedPNGData, service.pngData)
    }

    @MainActor
    func testScreenshotDoesNotCopyImageToClipboardWhenDisabled() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("clipboardDisabled")
        settingsStore.update { settings in
            settings.copyCapturedImageToClipboard = false
        }
        let clipboardService = MockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService(),
            clipboardService: clipboardService
        )

        await coordinator.startNewCapture()

        XCTAssertNil(clipboardService.copiedPNGData)
    }

    @MainActor
    func testCopyCurrentScreenshotCopiesStoredDataToClipboard() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("copyCurrent")
        settingsStore.update { settings in
            settings.copyCapturedImageToClipboard = false
        }
        let service = MockScreenshotService()
        let clipboardService = MockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service,
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService(),
            clipboardService: clipboardService
        )

        await coordinator.startNewCapture()
        coordinator.copyCurrentDocument()

        XCTAssertEqual(clipboardService.copiedPNGData, service.pngData)
        XCTAssertEqual(appState.statusMessage, "Screenshot copied.")
    }

    @MainActor
    func testSaveCurrentScreenshotWritesManualCaptureToConfiguredFolder() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("manualSave")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.automaticallySaveScreenshots = false
        }
        let service = MockScreenshotService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service,
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService()
        )

        await coordinator.startNewCapture()
        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), service.pngData)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
        XCTAssertEqual(appState.statusMessage, "Screenshot saved.")
    }

    @MainActor
    func testAutoSavedScreenshotRevealsFileWhenEnabled() async throws {
        let appState = AppState()
        let settingsStore = makeSettingsStore("revealScreenshot")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.showInFinderAfterSave = true
        }
        let fileRevealService = MockFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService(),
            fileRevealService: fileRevealService
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(fileRevealService.revealedURLs, [try XCTUnwrap(appState.currentDocument?.fileURL)])
    }

    @MainActor
    func testScreenshotUsesConfiguredDefaultDelayBeforeSelecting() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("screenshotDelay")
        settingsStore.update { settings in
            settings.defaultDelaySeconds = 4
        }
        let delaySleeper = MockDelaySleeper()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            fileOutputService: FileOutputService(),
            selectionService: MockSelectionService(),
            delaySleeper: delaySleeper
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(delaySleeper.requestedSeconds, [4])
    }

    @MainActor
    func testScreenshotHidesAppWindowWhileSelectingAndCapturingWhenEnabled() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState()
        let settingsStore = makeSettingsStore("hideDuringScreenshot")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = true
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EventLoggingScreenshotService(events: events),
            fileOutputService: FileOutputService(),
            selectionService: EventLoggingSelectionService(events: events),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(events.values, ["hide", "select", "capture", "restore"])
    }

    @MainActor
    func testScreenshotHidesAppWindowBeforeDelayWhenEnabled() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState()
        let settingsStore = makeSettingsStore("hideBeforeScreenshotDelay")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = true
            settings.defaultDelaySeconds = 4
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EventLoggingScreenshotService(events: events),
            fileOutputService: FileOutputService(),
            selectionService: EventLoggingSelectionService(events: events),
            delaySleeper: EventLoggingDelaySleeper(events: events),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(events.values, ["hide", "sleep:4", "select", "capture", "restore"])
    }

    @MainActor
    func testScreenshotDoesNotHideAppWindowWhenSettingIsDisabled() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState()
        let settingsStore = makeSettingsStore("doNotHideDuringScreenshot")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = false
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EventLoggingScreenshotService(events: events),
            fileOutputService: FileOutputService(),
            selectionService: EventLoggingSelectionService(events: events),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(events.values, ["select", "capture"])
    }

    @MainActor
    func testScreenshotPermissionFailureShowsActionableStatus() async {
        let appState = AppState()
        let settingsStore = makeSettingsStore("screenshotPermissionDenied")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: FailingScreenshotService(errorDescription: "사용자가 응용 프로그램, 윈도우, 디스플레이 캡처의 TCC를 거절함"),
            selectionService: MockSelectionService()
        )

        await coordinator.startScreenshotCapture()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(
            appState.statusMessage,
            "Screenshot failed: Screen access is off. Enable CaptureStudio in System Settings > Privacy & Security."
        )
    }

    @MainActor
    func testRecordModeReportsRecordingNotReady() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("record")
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: MockRecordingService(),
            selectionService: MockSelectionService(),
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(appState.currentDocument?.kind, .recording)
        XCTAssertNotNil(appState.currentDocument?.fileURL)
        XCTAssertEqual(appState.statusMessage, "Recording saved.")
    }

    @MainActor
    func testNewRecordingStaysUnsavedWhenAutomaticSaveDisabled() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("manualRecording")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.recordingFolderPath = temporaryDirectory.path
            settings.automaticallySaveRecordings = false
        }
        let recordingService = MockRecordingService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: recordingService,
            selectionService: MockSelectionService(),
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(appState.currentDocument?.kind, .recording)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
        XCTAssertEqual(appState.statusMessage, "Recording captured. Press Save to write the file.")
        XCTAssertNotEqual(recordingService.lastOutputURL?.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    @MainActor
    func testRecordingSelectionCancelReturnsToInitialState() async {
        let appState = AppState(captureMode: .record)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: makeSettingsStore("recordingSelectionCancel"),
            screenshotService: MockScreenshotService(),
            recordingService: MockRecordingService(),
            selectionService: FailingSelectionService(error: SelectionError.cancelled),
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startScreenRecording()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(appState.statusMessage, "Recording cancelled.")
    }

    @MainActor
    func testSaveCurrentRecordingMovesManualRecordingToConfiguredFolder() async throws {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("manualRecordingSave")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.recordingFolderPath = temporaryDirectory.path
            settings.automaticallySaveRecordings = false
        }
        let recordingService = MockRecordingService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: recordingService,
            selectionService: MockSelectionService(),
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startNewCapture()
        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), recordingService.recordingData)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
        XCTAssertEqual(appState.statusMessage, "Recording saved.")
    }

    @MainActor
    func testRecordingUsesConfiguredCountdownBeforeSelecting() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("recordCountdown")
        settingsStore.update { settings in
            settings.countdownSeconds = 2
        }
        let delaySleeper = MockDelaySleeper()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: MockRecordingService(),
            selectionService: MockSelectionService(),
            delaySleeper: delaySleeper
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(delaySleeper.requestedSeconds, [2])
    }

    @MainActor
    func testRecordingUsesConfiguredFolder() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("recordFolder")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.recordingFolderPath = temporaryDirectory.path
        }
        let recordingService = MockRecordingService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: recordingService,
            selectionService: selectionService,
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(recordingService.lastOutputURL?.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(appState.currentDocument?.fileURL?.lastPathComponent.hasSuffix(".mp4") ?? false)
        XCTAssertEqual(recordingService.lastSelection, selectionService.selection)
    }

    @MainActor
    func testRecordingRevealsFileWhenEnabled() async throws {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("revealRecording")
        settingsStore.update { settings in
            settings.showInFinderAfterSave = true
        }
        let fileRevealService = MockFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: MockRecordingService(),
            selectionService: MockSelectionService(),
            delaySleeper: MockDelaySleeper(),
            fileRevealService: fileRevealService
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(fileRevealService.revealedURLs, [try XCTUnwrap(appState.currentDocument?.fileURL)])
    }

    @MainActor
    func testStartScreenshotCaptureDoesNotDependOnSelectedMode() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("directScreenshot")
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
        }
        let screenshotService = MockScreenshotService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: screenshotService,
            fileOutputService: FileOutputService(),
            selectionService: selectionService
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(appState.captureMode, .record)
        XCTAssertEqual(appState.currentDocument?.kind, .screenshot)
        XCTAssertEqual(selectionService.selectionCallCount, 1)
        XCTAssertEqual(screenshotService.captureCallCount, 1)
        XCTAssertEqual(appState.statusMessage, "Screenshot captured. Press Save to write the file.")
    }

    @MainActor
    func testStartScreenRecordingDoesNotDependOnSelectedMode() async {
        let appState = AppState(captureMode: .screenshot)
        let settingsStore = makeSettingsStore("directRecording")
        settingsStore.update { settings in
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 0
        }
        let recordingService = MockRecordingService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: recordingService,
            selectionService: selectionService,
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startScreenRecording()

        XCTAssertEqual(appState.captureMode, .screenshot)
        XCTAssertEqual(appState.currentDocument?.kind, .recording)
        XCTAssertEqual(selectionService.selectionCallCount, 1)
        XCTAssertEqual(recordingService.recordCallCount, 1)
        XCTAssertEqual(appState.statusMessage, "Recording saved.")
    }

    @MainActor
    func testRecordingHidesAppWindowWhileSelectingAndRecordingWhenEnabled() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("hideDuringRecording")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = true
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 0
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: EventLoggingRecordingService(events: events),
            selectionService: EventLoggingSelectionService(events: events),
            delaySleeper: MockDelaySleeper(),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenRecording()

        XCTAssertEqual(events.values, ["hide", "select", "record", "restore"])
    }

    @MainActor
    func testRecordingStoppedByUserReturnsToInitialStateAndRestoresWindow() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("recordingStoppedByUser")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = true
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 0
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: EventLoggingStoppedRecordingService(events: events),
            selectionService: EventLoggingSelectionService(events: events),
            delaySleeper: MockDelaySleeper(),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenRecording()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(appState.statusMessage, "Recording stopped.")
        XCTAssertEqual(events.values, ["hide", "select", "record-stopped", "restore"])
    }

    @MainActor
    func testRecordingHidesAppWindowBeforeCountdownWhenEnabled() async {
        let events = CaptureVisibilityEventLog()
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("hideBeforeRecordingCountdown")
        settingsStore.update { settings in
            settings.hideAppDuringCapture = true
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 2
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: EventLoggingRecordingService(events: events),
            selectionService: EventLoggingSelectionService(events: events),
            delaySleeper: EventLoggingDelaySleeper(events: events),
            windowVisibilityController: EventLoggingWindowVisibilityController(events: events)
        )

        await coordinator.startScreenRecording()

        XCTAssertEqual(events.values, ["hide", "sleep:2", "select", "record", "restore"])
    }

    @MainActor
    func testRecordingPermissionFailureShowsActionableStatus() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("recordingPermissionDenied")
        settingsStore.update { settings in
            settings.countdownSeconds = 0
        }
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            recordingService: FailingRecordingService(errorDescription: "User declined TCC capture permission"),
            selectionService: MockSelectionService(),
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startScreenRecording()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(
            appState.statusMessage,
            "Recording failed: Screen access is off. Enable CaptureStudio in System Settings > Privacy & Security."
        )
    }

    @MainActor
    func testRevealCurrentDocumentUsesCurrentFileURL() {
        let fileURL = URL(fileURLWithPath: "/tmp/CaptureStudioTests/reveal.png")
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: fileURL,
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: false
            )
        )
        let settingsStore = makeSettingsStore("revealCurrent")
        let fileRevealService = MockFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            selectionService: MockSelectionService(),
            fileRevealService: fileRevealService
        )

        coordinator.revealCurrentDocument()

        XCTAssertEqual(fileRevealService.revealedURLs, [fileURL])
        XCTAssertEqual(appState.statusMessage, "Revealed in Finder.")
    }

    @MainActor
    func testRevealCurrentDocumentWithoutFileSetsStatus() {
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: nil,
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: true
            )
        )
        let settingsStore = makeSettingsStore("revealCurrentWithoutFile")
        let fileRevealService = MockFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            selectionService: MockSelectionService(),
            fileRevealService: fileRevealService
        )

        coordinator.revealCurrentDocument()

        XCTAssertTrue(fileRevealService.revealedURLs.isEmpty)
        XCTAssertEqual(appState.statusMessage, "No saved file to reveal.")
    }

    @MainActor
    func testDeleteCurrentSavedScreenshotMovesFileToTrashAndClearsDocument() {
        let fileURL = URL(fileURLWithPath: "/tmp/CaptureStudioTests/delete-saved.png")
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: fileURL,
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: false
            )
        )
        let settingsStore = makeSettingsStore("deleteSaved")
        let fileTrashService = MockFileTrashService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            selectionService: MockSelectionService(),
            fileTrashService: fileTrashService
        )

        coordinator.deleteCurrentDocument()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(fileTrashService.trashedURLs, [fileURL])
        XCTAssertEqual(appState.statusMessage, "Screenshot deleted.")
    }

    @MainActor
    func testDeleteCurrentUnsavedScreenshotClearsDocumentWithoutTrashingFile() {
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: true
            )
        )
        let settingsStore = makeSettingsStore("deleteUnsaved")
        let fileTrashService = MockFileTrashService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            selectionService: MockSelectionService(),
            fileTrashService: fileTrashService
        )

        coordinator.deleteCurrentDocument()

        XCTAssertNil(appState.currentDocument)
        XCTAssertTrue(fileTrashService.trashedURLs.isEmpty)
        XCTAssertEqual(appState.statusMessage, "Screenshot discarded.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeSettingsStore(_ name: String) -> SettingsStore {
        let store = SettingsStore(defaults: isolatedDefaults(name))
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCoordinatorTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        store.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.recordingFolderPath = temporaryDirectory.path
        }
        return store
    }
}

private final class MockScreenshotService: ScreenshotServicing {
    let pngData = Data([0x89, 0x50, 0x4E, 0x47])
    var captureCallCount = 0
    var lastSelection: CaptureSelection?

    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        captureCallCount += 1
        lastSelection = selection
        return ScreenshotResult(
            pngData: pngData,
            createdAt: Date(timeIntervalSince1970: 20)
        )
    }
}

private final class FailingScreenshotService: ScreenshotServicing {
    private let errorDescription: String

    init(errorDescription: String) {
        self.errorDescription = errorDescription
    }

    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        throw TestLocalizedError(errorDescription: errorDescription)
    }
}

private final class MockRecordingService: RecordingServicing {
    let recordingData = Data([0x00, 0x00, 0x00, 0x18])
    var lastOutputURL: URL?
    var lastSelection: CaptureSelection?
    var recordCallCount = 0

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        recordCallCount += 1
        lastOutputURL = outputURL
        lastSelection = selection
        try recordingData.write(to: outputURL, options: .atomic)
        return RecordingResult(fileURL: outputURL, createdAt: Date(timeIntervalSince1970: 30))
    }
}

private final class FailingRecordingService: RecordingServicing {
    private let errorDescription: String

    init(errorDescription: String) {
        self.errorDescription = errorDescription
    }

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        throw TestLocalizedError(errorDescription: errorDescription)
    }
}

private struct TestLocalizedError: LocalizedError {
    let errorDescription: String?
}

private final class MockSelectionService: SelectionServicing {
    let selection = CaptureSelection(
        displayID: 1,
        screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        rect: CGRect(x: 20, y: 30, width: 400, height: 240),
        scale: 1
    )
    var selectionCallCount = 0

    func selectRectangle() async throws -> CaptureSelection {
        selectionCallCount += 1
        return selection
    }
}

private final class FailingSelectionService: SelectionServicing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func selectRectangle() async throws -> CaptureSelection {
        throw error
    }
}

private final class MockDelaySleeper: CaptureDelaySleeping {
    var requestedSeconds: [Int] = []

    func sleep(seconds: Int) async throws {
        requestedSeconds.append(seconds)
    }
}

private final class EventLoggingDelaySleeper: CaptureDelaySleeping {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func sleep(seconds: Int) async throws {
        events.values.append("sleep:\(seconds)")
    }
}

private final class MockClipboardService: ClipboardServicing {
    var copiedPNGData: Data?
    var copiedText: String?

    func copyPNGData(_ data: Data) {
        copiedPNGData = data
    }

    func copyText(_ text: String) {
        copiedText = text
    }
}

private final class MockFileRevealService: FileRevealServicing {
    var revealedURLs: [URL] = []

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}

private final class MockFileTrashService: FileTrashServicing {
    var trashedURLs: [URL] = []

    func trash(_ url: URL) throws {
        trashedURLs.append(url)
    }
}

@MainActor
private final class CaptureVisibilityEventLog {
    var values: [String] = []
}

private final class EventLoggingWindowVisibilityController: CaptureWindowVisibilityControlling {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func hideCaptureWindows() {
        events.values.append("hide")
    }

    func restoreCaptureWindows() {
        events.values.append("restore")
    }
}

private final class EventLoggingSelectionService: SelectionServicing {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func selectRectangle() async throws -> CaptureSelection {
        events.values.append("select")
        return CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            rect: CGRect(x: 20, y: 30, width: 400, height: 240),
            scale: 1
        )
    }
}

private final class EventLoggingScreenshotService: ScreenshotServicing {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        events.values.append("capture")
        return ScreenshotResult(
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            createdAt: Date(timeIntervalSince1970: 20)
        )
    }
}

private final class EventLoggingRecordingService: RecordingServicing {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        events.values.append("record")
        try Data([0x00, 0x00, 0x00, 0x18]).write(to: outputURL, options: .atomic)
        return RecordingResult(fileURL: outputURL, createdAt: Date(timeIntervalSince1970: 30))
    }
}

private final class EventLoggingStoppedRecordingService: RecordingServicing {
    private let events: CaptureVisibilityEventLog

    init(events: CaptureVisibilityEventLog) {
        self.events = events
    }

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        events.values.append("record-stopped")
        throw RecordingError.stoppedByUser
    }
}
