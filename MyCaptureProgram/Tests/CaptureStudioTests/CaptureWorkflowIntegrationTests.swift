@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit
import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureWorkflowIntegrationTests: XCTestCase {
    func testActualScreenshotAutoSaveUsesConfiguredFolderAndCopiesToClipboard() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualScreenshotAuto"))
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.automaticallySaveScreenshots = true
            settings.copyCapturedImageToClipboard = true
            settings.defaultDelaySeconds = 0
            settings.showInFinderAfterSave = false
        }
        let clipboard = SpyClipboardService()
        let coordinator = try await Self.makeCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            clipboardService: clipboard
        )

        await coordinator.startNewCapture()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(clipboard.copiedPNGData, data)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }

    func testActualScreenshotManualSaveWritesOnlyAfterSave() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualScreenshotManual"))
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
            settings.defaultDelaySeconds = 0
        }
        let selection = try await Self.smallDisplaySelection()
        let coordinator = try await Self.makeCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            selection: selection
        )

        await coordinator.startNewCapture()

        XCTAssertNil(appState.currentDocument?.fileURL)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).isEmpty)

        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertGreaterThan(try Data(contentsOf: fileURL).count, 0)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }

    func testActualScreenshotWithRedactionLayerSavesFlattenedPNG() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualEditedScreenshot"))
        settingsStore.update { settings in
            settings.screenshotFolderPath = temporaryDirectory.path
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
            settings.defaultDelaySeconds = 0
        }
        let selection = try await Self.smallDisplaySelection()
        let coordinator = try await Self.makeCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            selection: selection
        )

        await coordinator.startNewCapture()

        var document = try XCTUnwrap(appState.currentDocument)
        document.layers = [
            EditorLayer.redaction(
                RedactionLayer(
                    frame: CGRect(x: 5, y: 5, width: 40, height: 30),
                    style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                )
            )
        ]
        appState.currentDocument = document
        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertGreaterThan(try Self.fileSize(at: fileURL), 0)
    }

    func testActualRecordingAutoSaveUsesConfiguredFolder() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let appState = AppState(captureMode: .record)
        let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualRecordingAuto"))
        settingsStore.update { settings in
            settings.recordingFolderPath = temporaryDirectory.path
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 0
            settings.recordingDurationSeconds = 1
            settings.includeSystemAudio = false
            settings.includeMicrophone = false
            settings.showCursorInRecordings = false
            settings.recordingQuality = .standard
            settings.showInFinderAfterSave = false
        }
        let selection = try await Self.smallDisplaySelection()
        let coordinator = try await Self.makeCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            selection: selection
        )

        await coordinator.startNewCapture()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(fileURL.pathExtension, "mp4")
        XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertGreaterThan(try Self.fileSize(at: fileURL), 0)
        try await Self.assertVideo(at: fileURL, matches: selection)
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }

    func testActualRecordingManualSaveMovesTemporaryFileToConfiguredFolder() async throws {
        try Self.skipUnlessIntegrationIsEnabled()
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let appState = AppState(captureMode: .record)
        let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualRecordingManual"))
        settingsStore.update { settings in
            settings.recordingFolderPath = temporaryDirectory.path
            settings.automaticallySaveRecordings = false
            settings.countdownSeconds = 0
            settings.recordingDurationSeconds = 1
            settings.includeSystemAudio = false
            settings.includeMicrophone = false
            settings.showCursorInRecordings = false
            settings.recordingQuality = .standard
        }
        let selection = try await Self.smallDisplaySelection()
        let coordinator = try await Self.makeCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            selection: selection
        )

        await coordinator.startNewCapture()

        let temporaryRecordingURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertNotEqual(
            temporaryRecordingURL.deletingLastPathComponent().standardizedFileURL,
            temporaryDirectory.standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRecordingURL.path))
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)

        coordinator.saveCurrentDocument()

        let savedURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(savedURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
        XCTAssertGreaterThan(try Self.fileSize(at: savedURL), 0)
        try await Self.assertVideo(at: savedURL, matches: selection)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRecordingURL.path))
        XCTAssertFalse(appState.currentDocument?.isDirty ?? true)
    }

    private static func makeCoordinator(
        appState: AppState,
        settingsStore: SettingsStore,
        clipboardService: ClipboardServicing = SpyClipboardService(),
        selection: CaptureSelection? = nil
    ) async throws -> CaptureCoordinator {
        let resolvedSelection: CaptureSelection
        if let selection {
            resolvedSelection = selection
        } else {
            resolvedSelection = try await smallDisplaySelection()
        }
        return CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: ScreenCaptureKitScreenshotService(),
            fileOutputService: FileOutputService(),
            recordingService: ScreenCaptureKitRecordingService(),
            selectionService: FixedSelectionService(selection: resolvedSelection),
            delaySleeper: NoOpDelaySleeper(),
            clipboardService: clipboardService,
            fileRevealService: NoOpFileRevealService()
        )
    }

    private static func smallDisplaySelection() async throws -> CaptureSelection {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = try XCTUnwrap(content.displays.first)
        let screenFrame = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let scale = NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == display.displayID
        }?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        return CaptureSelection(
            displayID: display.displayID,
            screenFrame: screenFrame,
            rect: CGRect(x: 0, y: 0, width: 160, height: 120),
            scale: scale
        )
    }

    private static func skipUnlessIntegrationIsEnabled() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_STUDIO_RUN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set CAPTURE_STUDIO_RUN_INTEGRATION=1 to run end-to-end capture workflow tests.")
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureWorkflowIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).intValue
    }

    private static func assertVideo(at url: URL, matches selection: CaptureSelection) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(tracks.first)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())

        XCTAssertEqual(width, selection.pixelWidth)
        XCTAssertEqual(height, selection.pixelHeight)
    }

    private static func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureWorkflowIntegrationTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FixedSelectionService: SelectionServicing {
    let selection: CaptureSelection

    init(selection: CaptureSelection) {
        self.selection = selection
    }

    func selectRectangle() async throws -> CaptureSelection {
        selection
    }
}

private struct NoOpDelaySleeper: CaptureDelaySleeping {
    func sleep(seconds: Int) async throws {}
}

private final class SpyClipboardService: ClipboardServicing {
    var copiedPNGData: Data?
    var copiedText: String?

    func copyPNGData(_ data: Data) {
        copiedPNGData = data
    }

    func copyText(_ text: String) {
        copiedText = text
    }
}

private struct NoOpFileRevealService: FileRevealServicing {
    func reveal(_ url: URL) {}
}
