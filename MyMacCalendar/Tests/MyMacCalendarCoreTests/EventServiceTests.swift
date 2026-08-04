import XCTest
@testable import MyMacCalendarCore

final class EventServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNonPositiveLimitsReturnEmptyResults() throws {
        let date = try date(2026, 6, 25)
        let event = CalendarEvent(title: "Unsafe limit", startDate: date, endDate: date)
        let service = EventService(calendar: calendar)

        XCTAssertTrue(service.upcomingEvents(from: date, events: [event], limit: 0).isEmpty)
        XCTAssertTrue(service.upcomingEvents(from: date, events: [event], limit: -1).isEmpty)
        XCTAssertTrue(service.upcomingOccurrences(from: date, events: [event], limit: 0).isEmpty)
        XCTAssertTrue(service.upcomingOccurrences(from: date, events: [event], limit: -1).isEmpty)
    }

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

    func testSearchTrimsQueryAndSortsByDateThenTitle() throws {
        let events = [
            CalendarEvent(title: "Later", startDate: try date(2026, 7, 2), endDate: try date(2026, 7, 2), notes: "Roadmap"),
            CalendarEvent(title: "Zulu", startDate: try date(2026, 6, 30), endDate: try date(2026, 6, 30), notes: "Roadmap"),
            CalendarEvent(title: "Earlier", startDate: try date(2026, 6, 25), endDate: try date(2026, 6, 25), notes: "Roadmap"),
            CalendarEvent(title: "Alpha", startDate: try date(2026, 6, 30), endDate: try date(2026, 6, 30), notes: "Roadmap"),
            CalendarEvent(title: "Unrelated", startDate: try date(2026, 6, 20), endDate: try date(2026, 6, 20))
        ]

        let results = EventService(calendar: calendar).search("  roadmap  ", in: events)

        XCTAssertEqual(results.map(\.title), ["Earlier", "Alpha", "Zulu", "Later"])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
