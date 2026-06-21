import XCTest
@testable import CaptureStudio

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testStoreLoadsDefaultsWhenEmpty() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.empty")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.empty")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .defaults)
    }

    @MainActor
    func testStorePersistsUpdatedSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.persist")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.persist")

        let store = SettingsStore(defaults: defaults)
        store.update { settings in
            settings.automaticallySaveScreenshots = false
            settings.screenshotFolderPath = "/tmp/captures"
        }

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertFalse(reloaded.settings.automaticallySaveScreenshots)
        XCTAssertEqual(reloaded.settings.screenshotFolderPath, "/tmp/captures")
    }

    @MainActor
    func testResetRestoresDefaults() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.reset")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.reset")

        let store = SettingsStore(defaults: defaults)
        store.update { settings in
            settings.automaticallySaveRecordings = false
        }

        store.reset()

        XCTAssertEqual(store.settings, .defaults)
    }
}
