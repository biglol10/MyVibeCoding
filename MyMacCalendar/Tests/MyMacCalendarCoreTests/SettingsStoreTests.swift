import SwiftData
import XCTest
@testable import MyMacCalendarCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettings() throws {
        let settings = AppSettings()

        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.showMenuBar)
        XCTAssertTrue(settings.floatingWidgetEnabled)
        XCTAssertTrue(settings.floatingWidgetAlwaysOnTop)
        XCTAssertEqual(settings.defaultReminderHour, 9)
        XCTAssertEqual(settings.defaultReminderMinute, 0)
    }

    func testStoreCreatesSettingsWhenMissing() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let store = SettingsStore(context: context)

        let settings = try store.load()

        XCTAssertEqual(settings.defaultReminderHour, 9)
        XCTAssertTrue(settings.showMenuBar)
    }
}
