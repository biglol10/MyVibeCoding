import XCTest
@testable import MyMacSearchCore

final class SearchQueryParserTests: XCTestCase {
    func testParsesCombinedQuotedAndStructuredFilters() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_723_593_600)

        let query = try SearchQueryParser.parse(
            #"name:"annual report" ext:PDF path:Downloads kind:pdf modified:7d free"#,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(query.nameTerms, ["annual report"])
        XCTAssertEqual(query.extensions, ["pdf"])
        XCTAssertEqual(query.pathTerms, ["downloads"])
        XCTAssertEqual(query.kinds, [.pdf])
        XCTAssertEqual(query.freeTerms, ["free"])
        XCTAssertEqual(query.modifiedRange?.upperBound, now)
        XCTAssertEqual(query.modifiedRange?.lowerBound, now.addingTimeInterval(-7 * 86_400))
    }

    func testTodayUsesLocalCalendarDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let now = Date(timeIntervalSince1970: 1_723_593_600)

        let query = try SearchQueryParser.parse("modified:today", now: now, calendar: calendar)

        XCTAssertEqual(query.modifiedRange?.lowerBound, calendar.startOfDay(for: now))
        XCTAssertEqual(
            query.modifiedRange?.upperBound,
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        )
    }

    func testRejectsUnknownFilter() {
        XCTAssertThrowsError(try SearchQueryParser.parse("owner:me")) { error in
            XCTAssertEqual(error as? SearchQueryParseError, .unknownFilter("owner"))
        }
    }

    func testRejectsUnterminatedQuote() {
        XCTAssertThrowsError(try SearchQueryParser.parse(#"name:"annual report"#)) { error in
            XCTAssertEqual(error as? SearchQueryParseError, .unterminatedQuote)
        }
    }

    func testNormalizesCanonicalUnicodeAndCase() throws {
        let query = try SearchQueryParser.parse("name:CAFÉ")
        XCTAssertEqual(query.nameTerms, ["cafe"])
    }
}
