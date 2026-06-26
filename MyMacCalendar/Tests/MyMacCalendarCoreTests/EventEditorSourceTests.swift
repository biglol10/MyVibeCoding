import XCTest

final class EventEditorSourceTests: XCTestCase {
    func testEventEditorUsesCustomMonthCalendarInsteadOfSystemDatePicker() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/EventEditorView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("DatePicker("))
        XCTAssertTrue(source.contains("EventDateGridView"))
        XCTAssertTrue(source.contains("DateSelectionRole"))
        XCTAssertTrue(source.contains("selectDate(_ date: Date)"))
        XCTAssertTrue(source.contains("formattedDate("))
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
