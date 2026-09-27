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
    func testApplyingPresetRestoresCaptureOptionsAndPreservesOutputFolders() {
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
        settings.hideAppDuringCapture = false
        settings.smartFilenamesEnabled = false
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
        XCTAssertEqual(settingsStore.settings.recordingQuality, .standard)
        XCTAssertFalse(settingsStore.settings.hideAppDuringCapture)
        XCTAssertFalse(settingsStore.settings.smartFilenamesEnabled)
    }

    @MainActor
    func testNewPresetAfterDeletionKeepsRemainingPreset() {
        let store = CapturePresetStore(defaults: isolatedDefaults("names"))
        let one = CapturePreset(name: "Personal 1", captureMode: .screenshot, areaType: .rectangle, settings: .defaults)
        let two = CapturePreset(name: "Personal 2", captureMode: .record, areaType: .window, settings: .defaults)
        store.save(one); store.save(two); store.remove(id: one.id)
        store.save(CapturePreset(name: store.nextPersonalPresetName, captureMode: .screenshot, areaType: .rectangle, settings: .defaults))
        XCTAssertEqual(store.userPresets.count, 2)
        XCTAssertTrue(store.userPresets.contains(two))
        store.save(CapturePreset(name: "Personal 2", captureMode: .screenshot, areaType: .rectangle, settings: .defaults))
        XCTAssertEqual(store.userPresets.count, 3)
        XCTAssertTrue(store.userPresets.contains(two))
    }

    @MainActor
    func testPresetCheckmarksRequireAllCaptureOptionsToMatch() {
        let store = CapturePresetStore(defaults: isolatedDefaults("match"))
        let settings = SettingsStore(defaults: isolatedDefaults("matchSettings"))
        let state = AppState()
        let quick = CapturePreset.defaultPresets.first { $0.name == "Quick Clipboard" }!
        let safe = CapturePreset.defaultPresets.first { $0.name == "Share Safe" }!
        store.apply(quick, to: state, settingsStore: settings)
        XCTAssertTrue(store.matches(quick, appState: state, settings: settings.settings))
        XCTAssertFalse(store.matches(safe, appState: state, settings: settings.settings))
        settings.update { $0.recordingQuality = .high }
        XCTAssertFalse(store.matches(quick, appState: state, settings: settings.settings))
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CapturePresetStoreTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
