import XCTest

final class SettingsEntrySourceTests: XCTestCase {
    func testMainWindowSettingsButtonOpensInAppSettingsSheet() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/MainWindowView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("activeSheet = .settings"))
        XCTAssertTrue(source.contains("case .settings:"))
        XCTAssertTrue(source.contains("SettingsView()"))
        XCTAssertTrue(source.contains("return \"settings\""))
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
