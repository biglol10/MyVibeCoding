import XCTest
@testable import MyMacCalendarCore

final class NotificationServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNotificationRequestsUseDefaultReminderTime() throws {
        let eventID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let event = CalendarEvent(
            id: eventID,
            title: "Codex 만료",
            startDate: try date(2026, 6, 30),
            endDate: try date(2026, 6, 30),
            notificationOffsetsDays: [7, 1, 0]
        )

        let planner = NotificationPlanner(calendar: calendar)
        let plans = planner.plans(for: event, defaultHour: 9, defaultMinute: 0, now: try date(2026, 6, 1, hour: 12))

        XCTAssertEqual(plans.map(\.identifier), [
            "event-22222222-2222-2222-2222-222222222222-offset-7",
            "event-22222222-2222-2222-2222-222222222222-offset-1",
            "event-22222222-2222-2222-2222-222222222222-offset-0"
        ])
        XCTAssertEqual(plans.map { calendar.component(.day, from: $0.fireDate) }, [23, 29, 30])
        XCTAssertTrue(plans.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 9 })
    }

    func testPastNotificationsAreSkipped() throws {
        let event = CalendarEvent(
            title: "Tomorrow",
            startDate: try date(2026, 6, 26),
            endDate: try date(2026, 6, 26),
            notificationOffsetsDays: [7, 1, 0]
        )

        let plans = NotificationPlanner(calendar: calendar).plans(for: event, defaultHour: 9, defaultMinute: 0, now: try date(2026, 6, 25, hour: 10))

        XCTAssertEqual(plans.map(\.offsetDays), [0])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
