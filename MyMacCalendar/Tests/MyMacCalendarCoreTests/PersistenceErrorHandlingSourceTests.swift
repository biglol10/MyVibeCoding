import XCTest

final class PersistenceErrorHandlingSourceTests: XCTestCase {
    func testUserSavePathsUseRollbackTransaction() throws {
        let quickAddSource = try source("Sources/MyMacCalendar/Views/QuickAddView.swift")
        let eventEditorSource = try source("Sources/MyMacCalendar/Views/EventEditorView.swift")
        let settingsSource = try source("Sources/MyMacCalendar/Views/SettingsView.swift")
        let settingsStoreSource = try source("Sources/MyMacCalendarCore/Stores/SettingsStore.swift")

        XCTAssertFalse(quickAddSource.contains("try? modelContext.save()"))
        XCTAssertTrue(quickAddSource.contains("@State private var errorMessage"))
        XCTAssertTrue(quickAddSource.contains(".alert(\"저장할 수 없습니다\""))
        XCTAssertTrue(quickAddSource.contains("PersistenceTransaction.save(context: modelContext)"))

        XCTAssertFalse(settingsSource.contains("try? modelContext.save()"))
        XCTAssertTrue(settingsSource.contains("saveModelContext("))
        XCTAssertTrue(settingsSource.contains("PersistenceTransaction.save(context: modelContext)"))
        XCTAssertTrue(eventEditorSource.contains("PersistenceTransaction.save(context: modelContext)"))
        XCTAssertTrue(settingsStoreSource.contains("PersistenceTransaction.save(context: $0)"))
        XCTAssertFalse(eventEditorSource.contains("try modelContext.save()"))
        XCTAssertFalse(settingsSource.contains("try modelContext.save()"))
        XCTAssertFalse(settingsSource.contains("modelContext.insert(created)\n        return created"))
        XCTAssertTrue(settingsSource.contains("guard let settings = settingsRows.first else"))
    }

    func testLoginItemChangeUsesCompensationWhenPersistenceFails() throws {
        let settingsSource = try source("Sources/MyMacCalendar/Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("ExternalStateTransaction.apply("))
        XCTAssertTrue(settingsSource.contains("previous: LoginItemController.isEnabled"))
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
