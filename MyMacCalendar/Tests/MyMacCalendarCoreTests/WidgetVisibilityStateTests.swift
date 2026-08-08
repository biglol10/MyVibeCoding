import XCTest
@testable import MyMacCalendarCore

final class WidgetVisibilityStateTests: XCTestCase {
    func testUnchangedSettingsKeepManualVisibilityOverride() {
        var state = WidgetVisibilityState(configuredEnabled: true)

        state.toggleManually()
        state.updateConfiguredEnabled(true)

        XCTAssertFalse(state.isVisible)
    }

    func testPersistedSettingChangeClearsStaleManualOverride() {
        var state = WidgetVisibilityState(configuredEnabled: true)
        state.toggleManually()
        XCTAssertFalse(state.isVisible)

        state.updateConfiguredEnabled(false)
        state.updateConfiguredEnabled(true)

        XCTAssertTrue(state.isVisible)
    }

    func testManualShowDoesNotOverrideLaterDisabledSetting() {
        var state = WidgetVisibilityState(configuredEnabled: false)
        state.toggleManually()
        XCTAssertTrue(state.isVisible)

        state.updateConfiguredEnabled(true)
        state.updateConfiguredEnabled(false)

        XCTAssertFalse(state.isVisible)
    }
}
