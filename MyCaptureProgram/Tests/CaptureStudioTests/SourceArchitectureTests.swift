import XCTest

final class SourceArchitectureTests: XCTestCase {
    func testMainWindowContainerKeepsCoordinatorAsStateObject() throws {
        let source = try String(contentsOf: sourceURL("CaptureStudioApp.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@StateObject private var captureCoordinator"))
        XCTAssertFalse(source.contains("captureCoordinator: CaptureCoordinator("))
        XCTAssertFalse(source.contains("await CaptureCoordinator("))
    }

    func testRecordingServiceChecksStartWritingResult() throws {
        let source = try String(contentsOf: sourceURL("Capture/RecordingService.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("guard writer.startWriting() else"))
        XCTAssertFalse(source.contains("writer.startWriting()\n            writer.startSession"))
    }

    func testRecordingServiceDoesNotProcessSampleBuffersOnMainQueue() throws {
        let source = try String(contentsOf: sourceURL("Capture/RecordingService.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("sampleHandlerQueue: .main"))
        XCTAssertTrue(source.contains("sampleOutputQueue"))
        XCTAssertFalse(source.contains("@MainActor\nprivate final class ScreenRecorder"))
        XCTAssertTrue(source.contains("finishIfNeededOnSampleOutputQueue"))
    }

    func testCaptureCoordinatorRendersEditedScreenshotsOffMainActor() throws {
        let source = try String(contentsOf: sourceURL("Capture/CaptureCoordinator.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("Task.detached"))
        XCTAssertTrue(source.contains("imageRenderService.renderPNG"))
    }

    func testUnusedSettingsAreNotKeptInAppSettings() throws {
        let source = try String(contentsOf: sourceURL("Settings/AppSettings.swift"), encoding: .utf8)
        let removedSettings = [
            "askToSaveEditedScreenshots",
            "copyEditsToClipboard",
            "multipleEditorWindows",
            "captureBorderEnabled",
            "microphoneDeviceName"
        ]

        for setting in removedSettings {
            XCTAssertFalse(source.contains(setting), "\(setting) should not be retained without product wiring")
        }
    }

    func testCaptureMenuDoesNotDuplicateGlobalHotkeyBindings() throws {
        let source = try String(contentsOf: sourceURL("CaptureStudioApp.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("shortcutBinding(for: .newScreenshot).keyEquivalent"))
        XCTAssertFalse(source.contains("shortcutBinding(for: .newRecording).keyEquivalent"))
    }

    func testQuickOptionsExposeUserPresetDeletion() throws {
        let source = try String(contentsOf: sourceURL("Views/MainWindowView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("presetStore.remove"))
    }

    private func sourceURL(_ relativePath: String) -> URL {
        repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("CaptureStudio")
            .appendingPathComponent(relativePath)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
