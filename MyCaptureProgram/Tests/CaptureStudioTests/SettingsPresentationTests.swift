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
        let editorItems = CaptureStudioGuidePresentation.sections.first { $0.id == "editor" }?.items ?? []

        XCTAssertEqual(titles, [
            "Capture",
            "Record",
            "Options",
            "Editor",
            "Settings",
            "Permissions"
        ])
        XCTAssertTrue(CaptureStudioGuidePresentation.sections.allSatisfy { !$0.items.isEmpty })
        XCTAssertTrue(editorItems.contains { $0.contains("Quick Redact") })
        XCTAssertFalse(editorItems.contains { $0.localizedCaseInsensitiveContains("blur") })
    }

    func testGuideSectionsMentionPersonalWorkflowFeatures() {
        let allItems = CaptureStudioGuidePresentation.sections.flatMap(\.items).joined(separator: " ")

        XCTAssertTrue(allItems.contains("History"))
        XCTAssertTrue(allItems.contains("Pin"))
        XCTAssertTrue(allItems.contains("GIF"))
        XCTAssertTrue(allItems.contains("Presets"))
        XCTAssertTrue(allItems.contains("smart filenames"))
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
        let screenAllowed = AdvancedPermissionStatusPresentation.screenRecordingRow(isAuthorized: true)
        let screenBlocked = AdvancedPermissionStatusPresentation.screenRecordingRow(isAuthorized: false)
        let microphoneOff = AdvancedPermissionStatusPresentation.microphoneRow(
            includeMicrophone: false,
            authorization: .denied
        )
        let microphonePending = AdvancedPermissionStatusPresentation.microphoneRow(
            includeMicrophone: true,
            authorization: .notDetermined
        )
        let microphoneBlocked = AdvancedPermissionStatusPresentation.microphoneRow(
            includeMicrophone: true,
            authorization: .denied
        )

        XCTAssertEqual(
            screenAllowed,
            AdvancedPermissionStatusPresentation.Row(
                title: "Screen Recording",
                status: "Allowed",
                detail: "CaptureStudio can capture screenshots and screen recordings.",
                actionTitle: nil,
                tone: .positive
            )
        )
        XCTAssertEqual(
            screenBlocked.actionTitle,
            "Open Privacy Settings"
        )
        XCTAssertEqual(
            microphoneOff.status,
            "Off"
        )
        XCTAssertEqual(
            microphonePending.status,
            "Needs approval"
        )
        XCTAssertEqual(
            microphoneBlocked.actionTitle,
            "Open Privacy Settings"
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
