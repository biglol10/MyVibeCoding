import XCTest

final class CalendarTypographySourceTests: XCTestCase {
    func testMonthGridDateTypographyUsesCompactApprovedSizes() throws {
        let source = try String(contentsOfFile: monthGridSourcePath(), encoding: .utf8)

        XCTAssertTrue(source.contains("weekdayFontSize: CGFloat = 14"))
        XCTAssertTrue(source.contains("dateFontSize: CGFloat = 15"))
        XCTAssertTrue(source.contains("todayFontSize: CGFloat = 15"))
        XCTAssertTrue(source.contains("todayBadgeSize: CGFloat = 24"))
        XCTAssertTrue(source.contains("entryFontSize: CGFloat = 11"))
        XCTAssertTrue(source.contains("overflowFontSize: CGFloat = 10"))
    }

    func testMainWindowTypographyUsesCompactApprovedSizes() throws {
        let source = try String(contentsOfFile: mainWindowSourcePath(), encoding: .utf8)

        XCTAssertTrue(source.contains("monthTitleFontSize: CGFloat = 38"))
        XCTAssertTrue(source.contains("toolbarIconSize: CGFloat = 15"))
        XCTAssertTrue(source.contains("toolbarTextFontSize: CGFloat = 14"))
    }

    private func monthGridSourcePath() -> String {
        sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift")
    }

    private func mainWindowSourcePath() -> String {
        sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift")
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
