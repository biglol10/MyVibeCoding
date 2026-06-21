import XCTest
@testable import CaptureStudio

final class AppSettingsTests: XCTestCase {
    func testDefaultFoldersUseDesktop() {
        let settings = AppSettings.defaults

        XCTAssertTrue(settings.screenshotFolderPath.hasSuffix("/Desktop"))
        XCTAssertTrue(settings.recordingFolderPath.hasSuffix("/Desktop"))
    }

    func testDefaultSaveBehaviorMatchesSpec() {
        let settings = AppSettings.defaults

        XCTAssertTrue(settings.automaticallySaveScreenshots)
        XCTAssertTrue(settings.automaticallySaveRecordings)
        XCTAssertTrue(settings.hideAppDuringCapture)
        XCTAssertTrue(settings.copyCapturedImageToClipboard)
        XCTAssertFalse(settings.askToSaveEditedScreenshots)
        XCTAssertEqual(settings.recordingDurationSeconds, 5)
    }

    func testRecordingQualityControlsVideoBitrate() {
        XCTAssertLessThan(
            AppSettings.RecordingQuality.standard.videoBitRate(width: 1920, height: 1080),
            AppSettings.RecordingQuality.high.videoBitRate(width: 1920, height: 1080)
        )
    }
}
