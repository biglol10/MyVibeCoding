import XCTest
@testable import CaptureStudio

final class MainWindowPresentationTests: XCTestCase {
    func testOutputSummaryUsesScreenshotFolderDelayAndClipboard() {
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = "/Users/biglol/Desktop"
        settings.defaultDelaySeconds = 3
        settings.copyCapturedImageToClipboard = true

        let summary = MainWindowPresentation.outputSummary(settings: settings)

        XCTAssertEqual(summary, "Desktop · PNG · 3s · Clipboard")
    }

    func testOutputSummaryUsesFolderNameAndNoClipboardWhenDisabled() {
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = "/tmp/Capture Output"
        settings.defaultDelaySeconds = 0
        settings.copyCapturedImageToClipboard = false

        let summary = MainWindowPresentation.outputSummary(settings: settings)

        XCTAssertEqual(summary, "Capture Output · PNG · 0s")
    }

    func testRecordingSummaryShowsDurationDelayAndQuality() {
        var settings = AppSettings.defaults
        settings.recordingFolderPath = "/tmp/Recordings"
        settings.countdownSeconds = 5
        settings.recordingDurationSeconds = 12
        settings.recordingQuality = .high

        let summary = MainWindowPresentation.recordingSummary(settings: settings)

        XCTAssertEqual(summary, "MP4 · 12s · Delay 5s · High")
    }

    func testRecordingSummaryOmitsStandardQualityForCompactMainBar() {
        var settings = AppSettings.defaults
        settings.countdownSeconds = 3
        settings.recordingDurationSeconds = 5
        settings.recordingQuality = .standard

        let summary = MainWindowPresentation.recordingSummary(settings: settings)

        XCTAssertEqual(summary, "MP4 · 5s · Delay 3s")
    }

    func testQuickOptionsControlLeavesRoomForMenuIndicator() {
        let control = MainWindowPresentation.quickOptionsControl

        XCTAssertEqual(control.title, "Options")
        XCTAssertGreaterThanOrEqual(control.minimumWidth, 128)
    }

    func testMainWindowMinimumWidthFitsQuickBarControls() {
        let estimatedQuickBarWidth =
            104.0 + // Capture
            104.0 + // Record
            MainWindowPresentation.quickOptionsControl.minimumWidth +
            50.0 + // Settings
            150.0 + // Summary
            40.0 + // HStack spacing
            24.0 // Horizontal padding

        XCTAssertGreaterThanOrEqual(MainWindowPresentation.mainWindowMinimumWidth, estimatedQuickBarWidth)
    }

    func testRecentResultForSavedScreenshot() {
        let document = EditorDocument(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            isDirty: false
        )

        let result = MainWindowPresentation.recentResult(for: document, statusMessage: "Screenshot captured.")

        XCTAssertEqual(result.title, "Screenshot saved")
        XCTAssertEqual(result.detail, "Screenshot captured.")
        XCTAssertEqual(result.systemImage, "photo")
        XCTAssertTrue(result.canReveal)
        XCTAssertTrue(result.canCopy)
        XCTAssertTrue(result.canSave)
        XCTAssertTrue(result.canDelete)
        XCTAssertFalse(result.requiresSave)
    }

    func testRecentResultForUnsavedRecording() {
        let document = EditorDocument(
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/Recording.mp4"),
            isDirty: true
        )

        let result = MainWindowPresentation.recentResult(for: document, statusMessage: nil)

        XCTAssertEqual(result.title, "Unsaved recording")
        XCTAssertEqual(result.detail, "Press Save to write the file.")
        XCTAssertEqual(result.systemImage, "record.circle")
        XCTAssertFalse(result.canCopy)
        XCTAssertTrue(result.canSave)
        XCTAssertTrue(result.canDelete)
        XCTAssertTrue(result.requiresSave)
    }

    func testRecentResultForSavedRecordingDoesNotOfferUnavailableActions() {
        let document = EditorDocument(
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/Recording.mp4"),
            isDirty: false
        )

        let result = MainWindowPresentation.recentResult(for: document, statusMessage: nil)

        XCTAssertEqual(result.title, "Recording saved")
        XCTAssertEqual(result.detail, "Saved to tmp")
        XCTAssertEqual(result.systemImage, "record.circle")
        XCTAssertFalse(result.canCopy)
        XCTAssertFalse(result.canSave)
        XCTAssertTrue(result.canDelete)
        XCTAssertFalse(result.requiresSave)
    }

    func testRecordingPreviewForSavedRecordingUsesPlayableFileURL() {
        let fileURL = URL(fileURLWithPath: "/tmp/Recording.mp4")
        let document = EditorDocument(
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: fileURL,
            isDirty: false
        )

        let preview = MainWindowPresentation.recordingPreview(for: document, statusMessage: "Recording saved.")

        XCTAssertEqual(preview.fileURL, fileURL)
        XCTAssertEqual(preview.title, "Recording saved")
        XCTAssertEqual(preview.detail, "Recording saved.")
        XCTAssertTrue(preview.canPlay)
    }

    func testRecordingPreviewWithoutFileUsesFallbackMessage() {
        let document = EditorDocument(
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: nil,
            isDirty: true
        )

        let preview = MainWindowPresentation.recordingPreview(for: document, statusMessage: nil)

        XCTAssertNil(preview.fileURL)
        XCTAssertEqual(preview.title, "Recording captured")
        XCTAssertEqual(preview.detail, "Recording is ready.")
        XCTAssertFalse(preview.canPlay)
    }
}
