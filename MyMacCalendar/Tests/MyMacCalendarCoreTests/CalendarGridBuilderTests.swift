import XCTest
@testable import MyMacCalendarCore

final class CalendarGridBuilderTests: XCTestCase {
    func testJune2026StartsOnMondayAndHasThirtyDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let builder = CalendarGridBuilder(calendar: calendar)
        let cells = try builder.makeMonthGrid(year: 2026, month: 6)

        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells[0].day, 31)
        XCTAssertFalse(cells[0].isInDisplayedMonth)
        XCTAssertEqual(cells[1].day, 1)
        XCTAssertTrue(cells[1].isInDisplayedMonth)
        XCTAssertEqual(cells[30].day, 30)
        XCTAssertTrue(cells[30].isInDisplayedMonth)
        XCTAssertEqual(cells[31].day, 1)
        XCTAssertFalse(cells[31].isInDisplayedMonth)
    }

    func testWeekendFlags() throws {
        let builder = CalendarGridBuilder(calendar: Calendar(identifier: .gregorian))
        let cells = try builder.makeMonthGrid(year: 2026, month: 6)

        let sunday = try XCTUnwrap(cells.first { $0.day == 7 && $0.isInDisplayedMonth })
        let saturday = try XCTUnwrap(cells.first { $0.day == 6 && $0.isInDisplayedMonth })

        XCTAssertTrue(sunday.isSunday)
        XCTAssertFalse(sunday.isSaturday)
        XCTAssertTrue(saturday.isSaturday)
        XCTAssertFalse(saturday.isSunday)
    }
}
