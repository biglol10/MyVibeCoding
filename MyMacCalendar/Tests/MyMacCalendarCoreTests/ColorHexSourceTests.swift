import XCTest

final class ColorHexSourceTests: XCTestCase {
    func testColorHexInitializerIsDefinedOnceForCalendarViews() throws {
        let files = [
            "Sources/MyMacCalendar/Views/Color+Hex.swift",
            "Sources/MyMacCalendar/Views/MonthGridView.swift",
            "Sources/MyMacCalendar/Views/DayAgendaPanelView.swift",
            "Sources/MyMacCalendar/Views/FloatingWidgetView.swift"
        ]

        let initializerCount = try files
            .map { try String(contentsOfFile: sourcePath($0), encoding: .utf8) }
            .reduce(0) { count, source in
                count + source.components(separatedBy: "init(hex:").count - 1
            }

        XCTAssertEqual(initializerCount, 1)
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
