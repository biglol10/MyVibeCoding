import XCTest

final class EventEditorSourceTests: XCTestCase {
    func testEventEditorUsesCustomMonthCalendarInsteadOfSystemDatePicker() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/EventEditorView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("DatePicker("))
        XCTAssertTrue(source.contains("EventDateGridView"))
        XCTAssertTrue(source.contains("DateSelectionRole"))
        XCTAssertTrue(source.contains("selectDate(_ date: Date)"))
        XCTAssertTrue(source.contains("formattedDate("))
    }

    func testEventEditorConnectsSavedAndDeletedEventsToMacNotifications() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/EventEditorView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@Query private var settingsRows: [AppSettings]"))
        XCTAssertTrue(source.contains("EventService().deletePlan(for:"))
        XCTAssertTrue(source.contains("NotificationService().cancel(identifiers:"))
        XCTAssertTrue(source.contains("NotificationService().requestAuthorization()"))
        XCTAssertTrue(source.contains("NotificationService().schedule("))
        XCTAssertTrue(source.contains("event: event"))
        XCTAssertTrue(source.contains("settings.defaultReminderHour"))
        XCTAssertTrue(source.contains("settings.defaultReminderMinute"))
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
