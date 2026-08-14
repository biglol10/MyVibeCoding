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

    func testParsesSupportedSizeFilters() throws {
        let cases: [(String, ByteSizeRange)] = [
            ("size:>100MB", .greaterThan(104_857_600)),
            ("size:>=1GB", .atLeast(1_073_741_824)),
            ("size:<500KB", .lessThan(512_000)),
            ("size:<=2MB", .atMost(2_097_152)),
            ("size:10MB..1GB", .closed(10_485_760, 1_073_741_824))
        ]

        for (input, expected) in cases {
            XCTAssertEqual(try SearchQueryParser.parse(input).sizeRange, expected, input)
        }
    }

    func testRejectsAmbiguousOrInvalidSizeFilters() {
        for input in ["size:100", "size:1PB", "size:-1MB", "size:1.5MB", "size:..1GB", "size:2GB..1GB"] {
            XCTAssertThrowsError(try SearchQueryParser.parse(input), input) { error in
                guard case SearchQueryParseError.invalidSize = error else {
                    return XCTFail("Expected invalidSize for \(input), got \(error)")
                }
            }
        }
    }

    func testDetailedTokensPreserveOriginalCharacterRangesIncludingQuotes() throws {
        let input = #"report kind:pdf path:"Project Files""#

        let parsed = try SearchQueryParser.parseDetailed(input)

        XCTAssertEqual(parsed.tokens.map(\.rawText), ["kind:pdf", #"path:"Project Files""#])
        let pathToken = parsed.tokens[1]
        let characters = Array(input)
        XCTAssertEqual(String(characters[pathToken.characterRange]), #"path:"Project Files""#)
    }
}
