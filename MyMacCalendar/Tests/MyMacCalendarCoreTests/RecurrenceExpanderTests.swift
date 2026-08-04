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

    func testMonthlyExpansionClampsWithoutPermanentEndOfMonthDrift() throws {
        let start = try date(2026, 1, 31)
        let event = CalendarEvent(title: "Monthly Bill", startDate: start, endDate: start, recurrence: .monthly)
        let range = DateInterval(start: try date(2026, 1, 1), end: try date(2026, 5, 1))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.month, from: $0.startDate) }, [1, 2, 3, 4])
        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [31, 28, 31, 30])
    }

    func testYearlyLeapDayClampsToFebruaryEndWithoutDrift() throws {
        let start = try date(2024, 2, 29)
        let event = CalendarEvent(title: "Leap", startDate: start, endDate: start, recurrence: .yearly)
        let range = DateInterval(start: try date(2024, 1, 1), end: try date(2029, 1, 1))

        let occurrences = RecurrenceExpander(calendar: calendar).occurrences(for: event, in: range)

        XCTAssertEqual(occurrences.map { calendar.component(.year, from: $0.startDate) }, [2024, 2025, 2026, 2027, 2028])
        XCTAssertEqual(occurrences.map { calendar.component(.day, from: $0.startDate) }, [29, 28, 28, 28, 29])
    }

    func testOldWeeklyAnchorFastForwardsNearRequestedInterval() throws {
        let anchor = try date(1900, 1, 1)
        let intervalStart = try date(2026, 7, 1)
        let snapshot = CalendarEventSnapshot(
            id: UUID(),
            title: "Old weekly",
            startDate: anchor,
            endDate: anchor,
            colorHex: "#000000",
            recurrence: .weekly,
            notificationOffsetsDays: []
        )
        let calculator = EventRecurrenceCalculator(calendar: calendar)

        let index = calculator.firstOccurrenceIndex(for: snapshot, near: intervalStart)
        let occurrences = calculator.occurrences(
            for: snapshot,
            in: DateInterval(start: intervalStart, end: try date(2026, 8, 1))
        )

        XCTAssertGreaterThan(index, 6_000)
        XCTAssertFalse(occurrences.isEmpty)
        XCTAssertTrue(occurrences.allSatisfy { $0.startDate >= intervalStart })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
