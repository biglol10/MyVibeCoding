import XCTest

final class PersistenceErrorHandlingSourceTests: XCTestCase {
    func testQuickAddAndSettingsDoNotSilentlyIgnoreModelContextSaveFailures() throws {
        let quickAddSource = try source("Sources/MyMacCalendar/Views/QuickAddView.swift")
        let settingsSource = try source("Sources/MyMacCalendar/Views/SettingsView.swift")

        XCTAssertFalse(quickAddSource.contains("try? modelContext.save()"))
        XCTAssertTrue(quickAddSource.contains("@State private var errorMessage"))
        XCTAssertTrue(quickAddSource.contains(".alert(\"저장할 수 없습니다\""))

        XCTAssertFalse(settingsSource.contains("try? modelContext.save()"))
        XCTAssertTrue(settingsSource.contains("saveModelContext("))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOfFile: sourcePath(relativePath), encoding: .utf8)
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
