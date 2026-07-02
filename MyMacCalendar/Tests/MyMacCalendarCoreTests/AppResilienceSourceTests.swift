import XCTest

final class AppResilienceSourceTests: XCTestCase {
    func testAppFallsBackToInMemoryStoreWhenPersistentContainerCreationFails() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/App/MyMacCalendarApp.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("fatalError(\"Failed to create SwiftData container"))
        XCTAssertTrue(source.contains("CalendarStore.makeInMemoryContainer()"))
        XCTAssertTrue(source.contains("NSLog(\"Failed to create SwiftData container"))
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
