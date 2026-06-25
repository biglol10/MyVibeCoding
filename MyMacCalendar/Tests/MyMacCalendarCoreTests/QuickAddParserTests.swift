import XCTest
@testable import MyMacCalendarCore

final class QuickAddParserTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNumericSlashDate() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("6/30 codex 만료", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "codex 만료")
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 6)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 30)
        XCTAssertFalse(result.needsConfirmation)
    }

    func testIsoDate() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("2026-12-25 여행", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "여행")
        XCTAssertEqual(calendar.component(.year, from: result.startDate), 2026)
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 12)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 25)
    }

    func testNextMondayKoreanPhrase() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("다음주 월요일 병원", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "병원")
        XCTAssertEqual(calendar.component(.month, from: result.startDate), 6)
        XCTAssertEqual(calendar.component(.day, from: result.startDate), 29)
    }

    func testAmbiguousInputNeedsConfirmation() throws {
        let parser = QuickAddParser(calendar: calendar)
        let result = parser.parse("회의", now: try date(2026, 6, 25))

        XCTAssertEqual(result.title, "회의")
        XCTAssertTrue(result.needsConfirmation)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
