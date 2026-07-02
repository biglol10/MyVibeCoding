import SwiftData
import XCTest
@testable import MyMacCalendarCore

final class SettingsStoreTests: XCTestCase {
    func testPersistentStoreURLCanBeOverriddenForIsolatedE2ETests() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MyMacCalendarStoreOverride-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("E2E.store")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        setenv("MYMACCALENDAR_STORE_URL", storeURL.path, 1)
        defer {
            unsetenv("MYMACCALENDAR_STORE_URL")
            try? fileManager.removeItem(at: directory)
        }

        let container = try CalendarStore.makeContainer()
        let context = ModelContext(container)
        let event = CalendarEvent(title: "isolated e2e", startDate: Date(), endDate: Date())
        context.insert(event)
        try context.save()

        XCTAssertTrue(fileManager.fileExists(atPath: storeURL.path), "Expected persistent store at explicit e2e override path")
    }

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
