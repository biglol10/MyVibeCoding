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
        XCTAssertTrue(settings.smartFilenamesEnabled)
        XCTAssertEqual(settings.recordingDurationSeconds, 5)
    }

    func testRecordingQualityControlsVideoBitrate() {
        XCTAssertLessThan(
            AppSettings.RecordingQuality.standard.videoBitRate(width: 1920, height: 1080),
            AppSettings.RecordingQuality.high.videoBitRate(width: 1920, height: 1080)
        )
    }

    func testDecodingClampsNegativePersistedTimingValues() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any]
        )
        object["defaultDelaySeconds"] = -10
        object["countdownSeconds"] = -20
        object["recordingDurationSeconds"] = -30

        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(settings.defaultDelaySeconds, 0)
        XCTAssertEqual(settings.countdownSeconds, 0)
        XCTAssertEqual(settings.recordingDurationSeconds, 1)
    }

    func testDecodingClampsExtremePersistedTimingValues() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any]
        )
        object["defaultDelaySeconds"] = Int.max
        object["countdownSeconds"] = Int.max
        object["recordingDurationSeconds"] = Int.max

        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(settings.defaultDelaySeconds, 10)
        XCTAssertEqual(settings.countdownSeconds, 10)
        XCTAssertEqual(settings.recordingDurationSeconds, 120)
    }
}
