import XCTest

final class SettingsBehaviorSourceTests: XCTestCase {
    func testSettingsControlsAreConnectedToAppBehavior() throws {
        let settingsSource = try source("Sources/MyMacCalendar/Views/SettingsView.swift")
        let notificationsSource = try source("Sources/MyMacCalendar/App/AppCommandNotifications.swift")
        let menuBarSource = try source("Sources/MyMacCalendar/Controllers/MenuBarController.swift")
        let appDelegateSource = try source("Sources/MyMacCalendar/App/AppDelegate.swift")
        let mainWindowSource = try source("Sources/MyMacCalendar/Views/MainWindowView.swift")
        let monthGridSource = try source("Sources/MyMacCalendar/Views/MonthGridView.swift")

        XCTAssertTrue(settingsSource.contains("launchAtLoginBinding"))
        XCTAssertTrue(settingsSource.contains("LoginItemController.setEnabled"))
        XCTAssertTrue(settingsSource.contains("notifyAppSettingsChanged()"))
        XCTAssertFalse(settingsSource.contains("SettingsRow(\"테마\")"))

        XCTAssertTrue(notificationsSource.contains("appSettingsDidChange"))
        XCTAssertTrue(menuBarSource.contains("func setVisible(_ visible: Bool)"))
        XCTAssertTrue(menuBarSource.contains("removeStatusItem"))
        XCTAssertTrue(appDelegateSource.contains(".appSettingsDidChange"))
        XCTAssertTrue(appDelegateSource.contains("menuBarController.setVisible"))
        XCTAssertTrue(mainWindowSource.contains("density: calendarDensity"))
        XCTAssertTrue(monthGridSource.contains("enum CalendarDensityMode"))
    }

    func testHolidayTabConnectsCoreHolidayFetchToUserAction() throws {
        let settingsSource = try source("Sources/MyMacCalendar/Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("isFetchingHolidays"))
        XCTAssertTrue(settingsSource.contains("fetchOnlineHolidays()"))
        XCTAssertTrue(settingsSource.contains("HolidayService().fetchKoreanHolidays"))
        XCTAssertTrue(settingsSource.contains("HolidayImportPlanner().newRecords"))
        XCTAssertTrue(settingsSource.contains("applyHolidayImports"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOfFile: sourcePath(relativePath), encoding: .utf8)
    }

    private func sourcePath(_ relativePath: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
