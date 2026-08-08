import XCTest
@testable import MyMacCalendarCore

final class EventOccurrenceDetailTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testDetailUsesSelectedRecurringOccurrenceDatesAndEventMetadata() throws {
        let event = CalendarEvent(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
            title: "Weekly trip",
            startDate: try date(2026, 7, 1),
            endDate: try date(2026, 7, 2),
            colorHex: "#34C759",
            notes: "Bring documents",
            recurrence: .weekly,
            notificationOffsetsDays: [7, 1]
        )
        let interval = DateInterval(start: try date(2026, 7, 8), end: try date(2026, 7, 10))
        let occurrence = try XCTUnwrap(RecurrenceExpander(calendar: calendar).occurrences(for: event, in: interval).first)

        let detail = EventOccurrenceDetail(event: event, occurrence: occurrence)

        XCTAssertEqual(detail.eventID, event.id)
        XCTAssertEqual(detail.title, "Weekly trip")
        XCTAssertEqual(detail.startDate, try date(2026, 7, 8))
        XCTAssertEqual(detail.endDate, try date(2026, 7, 9))
        XCTAssertEqual(detail.colorHex, "#34C759")
        XCTAssertEqual(detail.notes, "Bring documents")
        XCTAssertEqual(detail.recurrence, .weekly)
        XCTAssertEqual(detail.notificationOffsetsDays, [7, 1])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
