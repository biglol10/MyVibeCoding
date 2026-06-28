import XCTest
@testable import FlowPilotNativeCore

final class MacPermissionSettingsTests: XCTestCase {
    func testAccessibilitySettingsURLTargetsPrivacyAccessibilityPane() {
        XCTAssertEqual(
            MacPermissionSettings.accessibility.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testScreenRecordingSettingsURLTargetsPrivacyScreenCapturePane() {
        XCTAssertEqual(
            MacPermissionSettings.screenRecording.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }
}
