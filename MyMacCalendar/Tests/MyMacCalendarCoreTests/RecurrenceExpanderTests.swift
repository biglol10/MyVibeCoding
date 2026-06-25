import XCTest
@testable import MyMacCalendarCore

final class RecurrenceExpanderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testWeeklyExpansionWithinRange() throws {
        let start = try date(2026, 6, 1)
        let event = CalendarEvent(title: "Weekly Sync", startDate: start, endDate: start, recurrence: .weekly)
        let range = DateInterval(start: try date(2026, 6, 1), end: try date(2026, 6, 30))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [1, 8, 15, 22, 29])
    }

    func testMonthlyExpansionKeepsDayOfMonth() throws {
        let start = try date(2026, 1, 25)
        let event = CalendarEvent(title: "Monthly Bill", startDate: start, endDate: start, recurrence: .monthly)
        let range = DateInterval(start: try date(2026, 1, 1), end: try date(2026, 4, 1))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.month, from: $0.startDate) }, [1, 2, 3])
        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [25, 25, 25])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
