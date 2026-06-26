import XCTest

final class SettingsLayoutSourceTests: XCTestCase {
    func testSettingsViewUsesCustomCompactLayoutInsteadOfLooseForms() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/SettingsView.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("Stepper(\"시:"))
        XCTAssertFalse(source.contains("Stepper(\"분:"))
        XCTAssertFalse(source.contains("Stepper(\"표시할 일정 수:"))
        XCTAssertTrue(source.contains("SettingsPage"))
        XCTAssertTrue(source.contains("SettingsSection"))
        XCTAssertTrue(source.contains("SettingsRow"))
        XCTAssertTrue(source.contains("static let contentWidth: CGFloat = 620"))
        XCTAssertTrue(source.contains("static let compactSliderWidth: CGFloat = 240"))
    }

    func testNotificationTimeCanBeSelectedWithoutIncrementSteppers() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/SettingsView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("ReminderTimePresetButton"))
        XCTAssertTrue(source.contains("DatePicker(\"\", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)"))
        XCTAssertTrue(source.contains("setReminderTime(hour: preset.hour, minute: preset.minute)"))
        XCTAssertTrue(source.contains("reminderTimeBinding"))
    }

    func testWidgetControlsUseShortSliderAndMenuPickers() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/Views/SettingsView.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains(".frame(width: SettingsLayout.compactSliderWidth)"))
        XCTAssertTrue(source.contains("Text(opacityPercentText)"))
        XCTAssertTrue(source.contains("Picker(\"\", selection: binding(\\.floatingWidgetVisibleCount))"))
        XCTAssertTrue(source.contains("Text(\"3개\").tag(3)"))
        XCTAssertTrue(source.contains("Text(\"12개\").tag(12)"))
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
