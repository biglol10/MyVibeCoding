import XCTest
@testable import MyMacCalendarCore

final class EventServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testUpcomingSortsByDateThenTitle() throws {
        let events = [
            CalendarEvent(title: "B", startDate: try date(2026, 6, 27), endDate: try date(2026, 6, 27)),
            CalendarEvent(title: "A", startDate: try date(2026, 6, 27), endDate: try date(2026, 6, 27)),
            CalendarEvent(title: "Earlier", startDate: try date(2026, 6, 26), endDate: try date(2026, 6, 26))
        ]

        let upcoming = EventService(calendar: calendar).upcomingEvents(from: try date(2026, 6, 25), events: events, limit: 3)

        XCTAssertEqual(upcoming.map(\.title), ["Earlier", "A", "B"])
    }

    func testUpcomingOccurrencesIncludeWeeklyRepeats() throws {
        let weekly = CalendarEvent(title: "Weekly", startDate: try date(2026, 6, 1), endDate: try date(2026, 6, 1), recurrence: .weekly)

        let occurrences = EventService(calendar: calendar).upcomingOccurrences(from: try date(2026, 6, 25), events: [weekly], limit: 2, horizonDays: 21)

        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [29, 6])
    }

    func testSearchMatchesTitleAndNotes() throws {
        let events = [
            CalendarEvent(title: "Doctor", startDate: try date(2026, 6, 26), endDate: try date(2026, 6, 26), notes: "Gangnam"),
            CalendarEvent(title: "Codex Renewal", startDate: try date(2026, 6, 30), endDate: try date(2026, 6, 30))
        ]

        let service = EventService(calendar: calendar)

        XCTAssertEqual(service.search("codex", in: events).map(\.title), ["Codex Renewal"])
        XCTAssertEqual(service.search("gangnam", in: events).map(\.title), ["Doctor"])
    }

    func testDeletePlanContainsEventAndNotificationIdentifiers() throws {
        let event = CalendarEvent(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Delete Me",
            startDate: try date(2026, 6, 30),
            endDate: try date(2026, 6, 30),
            notificationOffsetsDays: [7, 1, 0]
        )

        let plan = EventService(calendar: calendar).deletePlan(for: event)

        XCTAssertEqual(plan.eventID, event.id)
        XCTAssertEqual(plan.notificationIdentifiers.sorted(), [
            "event-11111111-1111-1111-1111-111111111111-offset-0",
            "event-11111111-1111-1111-1111-111111111111-offset-1",
            "event-11111111-1111-1111-1111-111111111111-offset-7"
        ])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
