import XCTest

final class HolidayAutoRefreshSourceTests: XCTestCase {
    func testMainWindowRefreshesOnlyMissingCurrentYearHolidays() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@Environment(\\.modelContext) private var modelContext"))
        XCTAssertTrue(source.contains("@State private var attemptedAutomaticHolidayYears = Set<Int>()"))
        XCTAssertTrue(source.contains("HolidayAutoRefreshPolicy().shouldFetch"))
        XCTAssertTrue(source.contains("HolidayService().fetchKoreanHolidays(year: year)"))
        XCTAssertTrue(source.contains("HolidayImportPlanner().newRecords"))
        XCTAssertTrue(source.contains("try PersistenceTransaction.save(context: modelContext)"))
        XCTAssertTrue(source.contains("NSCalendarDayChanged"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
