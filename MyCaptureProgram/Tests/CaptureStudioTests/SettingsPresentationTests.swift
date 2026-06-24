import XCTest
@testable import CaptureStudio

final class SettingsPresentationTests: XCTestCase {
    func testTimeControlsExposeFastPresets() {
        XCTAssertEqual(SettingsTimeControl.captureDelay.presets, [0, 3, 5, 10])
        XCTAssertEqual(SettingsTimeControl.recordingCountdown.presets, [0, 3, 5, 10])
        XCTAssertEqual(SettingsTimeControl.recordingDuration.presets, [5, 10, 30, 60, 120])
    }

    func testTimeControlsClampDirectInputToSupportedRanges() {
        XCTAssertEqual(SettingsTimeControl.captureDelay.clampedValue(for: -4), 0)
        XCTAssertEqual(SettingsTimeControl.captureDelay.clampedValue(for: 99), 10)
        XCTAssertEqual(SettingsTimeControl.recordingCountdown.clampedValue(for: -1), 0)
        XCTAssertEqual(SettingsTimeControl.recordingCountdown.clampedValue(for: 30), 10)
        XCTAssertEqual(SettingsTimeControl.recordingDuration.clampedValue(for: 0), 1)
        XCTAssertEqual(SettingsTimeControl.recordingDuration.clampedValue(for: 300), 120)
    }

    func testGuideSectionsCoverPrimaryWorkflows() {
        let titles = CaptureStudioGuidePresentation.sections.map(\.title)

        XCTAssertEqual(titles, [
            "Capture",
            "Record",
            "Options",
            "Editor",
            "Settings",
            "Permissions"
        ])
        XCTAssertTrue(CaptureStudioGuidePresentation.sections.allSatisfy { !$0.items.isEmpty })
    }

    func testGuideLaunchPolicyShowsUntilUserHasSeenGuide() {
        XCTAssertTrue(CaptureStudioGuidePresentation.shouldPresentOnLaunch(hasSeenGuide: false))
        XCTAssertFalse(CaptureStudioGuidePresentation.shouldPresentOnLaunch(hasSeenGuide: true))
    }

    func testSettingsButtonOpensUsefulDefaultTab() {
        XCTAssertEqual(SettingsTab.defaultOpen, .output)
        XCTAssertEqual(SettingsTab.defaultOpen.title, "Output")
        XCTAssertEqual(SettingsTab.allCases.map(\.title), [
            "Output",
            "Capture",
            "Record",
            "Shortcuts",
            "Advanced"
        ])
    }

    func testAdvancedPermissionCopyUsesUserFacingLanguage() {
        XCTAssertEqual(
            AdvancedPermissionStatusPresentation.screenRecording,
            "Checked automatically when you start capture or recording."
        )
        XCTAssertEqual(
            AdvancedPermissionStatusPresentation.microphone,
            "Checked automatically when microphone recording is enabled."
        )
    }

    func testShortcutErrorPresentationDoesNotShiftRows() {
        XCTAssertGreaterThanOrEqual(ShortcutErrorPresentation.reservedMessageHeight, 18)
        XCTAssertEqual(ShortcutErrorPresentation.opacity(for: nil), 0)
        XCTAssertEqual(ShortcutErrorPresentation.opacity(for: "Shortcut already used."), 1)
        XCTAssertEqual(ShortcutErrorPresentation.displayMessage(for: nil), " ")
        XCTAssertEqual(
            ShortcutErrorPresentation.displayMessage(for: "Shortcut already used."),
            "Shortcut already used."
        )
    }
}
