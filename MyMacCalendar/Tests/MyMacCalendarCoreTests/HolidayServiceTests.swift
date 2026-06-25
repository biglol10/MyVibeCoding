import XCTest
@testable import MyMacCalendarCore

final class HolidayServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testHiddenApiHolidayStaysHiddenAfterRefetch() throws {
        let newYear = HolidayImport(date: try date(2026, 1, 1), title: "New Year's Day", providerKey: "2026-01-01-New Year's Day")
        let hidden = HolidayRecord(date: try date(2026, 1, 1), title: "New Year's Day", source: .api, providerKey: "2026-01-01-New Year's Day", isHidden: true, year: 2026)

        let visible = HolidayMerger().merge(imports: [newYear], existing: [hidden], year: 2026)

        XCTAssertTrue(visible.isEmpty)
    }

    func testManualHolidayOverridesApiOnSameDate() throws {
        let api = HolidayImport(date: try date(2026, 5, 5), title: "Children's Day", providerKey: "2026-05-05-Children's Day")
        let manual = HolidayRecord(date: try date(2026, 5, 5), title: "어린이날 직접수정", source: .manual, year: 2026)

        let visible = HolidayMerger().merge(imports: [api], existing: [manual], year: 2026)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].title, "어린이날 직접수정")
        XCTAssertEqual(visible[0].source, .manual)
    }

    func testNagerDecodeMapsLocalNameAndProviderKey() throws {
        let data = """
        [{"date":"2026-01-01","localName":"새해","name":"New Year's Day","countryCode":"KR","fixed":false,"global":true,"counties":null,"launchYear":null,"types":["Public"]}]
        """.data(using: .utf8)!

        let imports = try NagerHolidayDecoder().decode(data: data, calendar: calendar)

        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports[0].title, "새해")
        XCTAssertEqual(imports[0].providerKey, "2026-01-01-새해")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
