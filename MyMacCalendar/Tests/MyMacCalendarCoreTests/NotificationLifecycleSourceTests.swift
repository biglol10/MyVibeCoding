import XCTest

final class NotificationLifecycleSourceTests: XCTestCase {
    func testMainWindowRefreshesFromValueSnapshotsAndIncludesAllNotificationInputs() throws {
        let source = try String(
            contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("events.map(CalendarEventSnapshot.init(event:))"))
        XCTAssertTrue(source.contains("AppNotificationCoordinator.shared.refresh("))
        XCTAssertTrue(source.contains("settings.defaultReminderHour"))
        XCTAssertTrue(source.contains("settings.defaultReminderMinute"))
        XCTAssertTrue(source.contains("event.notificationOffsetsRaw"))
        XCTAssertTrue(source.contains("event.recurrenceRaw"))
        XCTAssertTrue(source.contains("12 * 60 * 60"))
    }

    func testSystemCoordinatorIsSharedAcrossWindowAndEditor() throws {
        let source = try String(
            contentsOfFile: sourcePath("Sources/MyMacCalendar/Controllers/AppNotificationCoordinator.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("static let shared"))
        XCTAssertTrue(source.contains("NotificationUpdateCoordinator"))
        XCTAssertTrue(source.contains("SystemNotificationClient"))
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
