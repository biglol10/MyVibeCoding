import XCTest

final class MonthGridInteractionSourceTests: XCTestCase {
    func testSelectedDateHasClearVisualTreatment() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("selectedCellBorder"))
        XCTAssertTrue(source.contains("selectedCellBackground"))
        XCTAssertTrue(source.contains("strokeBorder(isSelected ? AppTheme.selectedCellBorder : AppTheme.gridLine"))
        XCTAssertTrue(source.contains("lineWidth: isSelected ? 1.8 : 0.8"))
    }

    func testCellContentIsClippedInsideItsCalendarCell() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains(".clipShape(Rectangle())"))
        XCTAssertTrue(source.contains(".padding(.horizontal, 10)"))
        XCTAssertTrue(source.contains("minHeight: CalendarGridLayout.entryHeight(for: density)"))
        XCTAssertTrue(source.contains("static func entryHeight(for density: CalendarDensityMode) -> CGFloat"))
    }

    func testMonthGridShowsTwoEntriesBeforeOverflowSummary() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("density == .compact ? 3 : 2"))
        XCTAssertTrue(source.contains("let visibleEntries = Array(dayEntries.prefix(CalendarGridLayout.visibleEntryLimit(for: density)))"))
        XCTAssertTrue(source.contains("let overflowCount = max(0, dayEntries.count - visibleEntries.count)"))
        XCTAssertTrue(source.contains("Text(\"+\\(overflowCount)개\")"))
    }

    func testDatesSitCloseToTopGridLine() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("static let dateTopPadding: CGFloat = 2"))
        XCTAssertTrue(source.contains("static func entryTopPadding(for density: CalendarDensityMode) -> CGFloat"))
        XCTAssertTrue(source.contains("density == .compact ? 2 : 4"))
        XCTAssertTrue(source.contains("static let bottomPadding: CGFloat = 4"))
    }

    func testMonthGridsDoNotFallBackToHardCodedYear() throws {
        let monthGridSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MonthGridView.swift"), encoding: .utf8)
        let eventEditorSource = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/EventEditorView.swift"), encoding: .utf8)

        XCTAssertFalse(monthGridSource.contains("?? 2026"))
        XCTAssertFalse(eventEditorSource.contains("?? 2026"))
        XCTAssertTrue(monthGridSource.contains("guard let year = components.year"))
        XCTAssertTrue(eventEditorSource.contains("guard let year = components.year"))
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
