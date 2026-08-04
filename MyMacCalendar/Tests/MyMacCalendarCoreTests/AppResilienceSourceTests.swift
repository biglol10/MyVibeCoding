import XCTest

final class AppResilienceSourceTests: XCTestCase {
    func testAppBlocksEditingWhenPersistentContainerCreationFails() throws {
        let source = try String(contentsOfFile: sourcePath("Sources/MyMacCalendar/App/MyMacCalendarApp.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("CalendarStore.makeInMemoryContainer()"))
        XCTAssertFalse(source.contains("Falling back to in-memory store"))
        XCTAssertTrue(source.contains("CalendarApplicationState"))
        XCTAssertTrue(source.contains("case .failed"))
        XCTAssertTrue(source.contains("StorageFailureView"))
        XCTAssertFalse(source.contains("error.localizedDescription"))
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
