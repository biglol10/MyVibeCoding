import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorTests: XCTestCase {
    @MainActor
    func testNewScreenshotAutoSavesWhenEnabled() async {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("screenshot"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("manualScreenshot"))
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
    func testScreenshotCopiesImageToClipboardWhenEnabled() async {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("clipboardEnabled"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("clipboardDisabled"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("copyCurrent"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("manualSave"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("revealScreenshot"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("screenshotDelay"))
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
    func testRecordModeReportsRecordingNotReady() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = SettingsStore(defaults: isolatedDefaults("record"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("manualRecording"))
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
    func testSaveCurrentRecordingMovesManualRecordingToConfiguredFolder() async throws {
        let appState = AppState(captureMode: .record)
        let settingsStore = SettingsStore(defaults: isolatedDefaults("manualRecordingSave"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("recordCountdown"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("recordFolder"))
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
        let settingsStore = SettingsStore(defaults: isolatedDefaults("revealRecording"))
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

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

private final class MockRecordingService: RecordingServicing {
    let recordingData = Data([0x00, 0x00, 0x00, 0x18])
    var lastOutputURL: URL?
    var lastSelection: CaptureSelection?

    func recordScreen(selection: CaptureSelection, to outputURL: URL, settings: AppSettings) async throws -> RecordingResult {
        lastOutputURL = outputURL
        lastSelection = selection
        try recordingData.write(to: outputURL, options: .atomic)
        return RecordingResult(fileURL: outputURL, createdAt: Date(timeIntervalSince1970: 30))
    }
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

private final class MockDelaySleeper: CaptureDelaySleeping {
    var requestedSeconds: [Int] = []

    func sleep(seconds: Int) async throws {
        requestedSeconds.append(seconds)
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
