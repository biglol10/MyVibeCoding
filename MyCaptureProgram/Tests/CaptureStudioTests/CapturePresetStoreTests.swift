import XCTest
@testable import CaptureStudio

final class CapturePresetStoreTests: XCTestCase {
    @MainActor
    func testDefaultPresetsIncludePersonalCaptureWorkflows() {
        let names = CapturePreset.defaultPresets.map(\.name)

        XCTAssertTrue(names.contains("Quick Clipboard"))
        XCTAssertTrue(names.contains("Bug Recording"))
        XCTAssertTrue(names.contains("Document Save"))
        XCTAssertTrue(names.contains("Share Safe"))
    }

    @MainActor
    func testSavingPresetPersistsAndReloads() {
        let defaults = isolatedDefaults("persist")
        let preset = CapturePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Personal Debug",
            captureMode: .record,
            areaType: .window,
            settings: {
                var settings = AppSettings.defaults
                settings.recordingDurationSeconds = 12
                settings.countdownSeconds = 0
                return settings
            }()
        )
        let store = CapturePresetStore(defaults: defaults)

        store.save(preset)

        XCTAssertEqual(CapturePresetStore(defaults: defaults).userPresets, [preset])
    }

    @MainActor
    func testApplyingPresetUpdatesWorkflowSettingsWithoutResettingDurableUserPreferences() {
        let settingsStore = SettingsStore(defaults: isolatedDefaults("applySettings"))
        let appState = AppState(captureMode: .screenshot, areaType: .rectangle)
        settingsStore.update { settings in
            settings.screenshotFolderPath = "/Users/me/Screenshots"
            settings.recordingFolderPath = "/Users/me/Recordings"
            settings.recordingQuality = .high
        }
        var settings = AppSettings.defaults
        settings.automaticallySaveScreenshots = false
        settings.copyCapturedImageToClipboard = false
        settings.defaultDelaySeconds = 5
        settings.screenshotFolderPath = "/tmp/preset-screenshots"
        settings.recordingFolderPath = "/tmp/preset-recordings"
        settings.recordingQuality = .standard
        let preset = CapturePreset(
            name: "Manual Clipboard Off",
            captureMode: .screenshot,
            areaType: .fullScreen,
            settings: settings
        )

        CapturePresetStore(defaults: isolatedDefaults("applyPreset")).apply(
            preset,
            to: appState,
            settingsStore: settingsStore
        )

        XCTAssertEqual(appState.captureMode, .screenshot)
        XCTAssertEqual(appState.areaType, .fullScreen)
        XCTAssertEqual(settingsStore.settings.automaticallySaveScreenshots, false)
        XCTAssertEqual(settingsStore.settings.copyCapturedImageToClipboard, false)
        XCTAssertEqual(settingsStore.settings.defaultDelaySeconds, 5)
        XCTAssertEqual(settingsStore.settings.screenshotFolderPath, "/Users/me/Screenshots")
        XCTAssertEqual(settingsStore.settings.recordingFolderPath, "/Users/me/Recordings")
        XCTAssertEqual(settingsStore.settings.recordingQuality, .high)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CapturePresetStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
