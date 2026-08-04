import Foundation
import XCTest
@testable import MyMacCalendarCore

final class CalendarStoreFailureTests: XCTestCase {
    func testPersistentStoreParentFailureIsNotReplacedWithTemporaryStorage() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MyMacCalendar-FailClosed-\(UUID().uuidString)", isDirectory: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        let requestedStore = blockingFile.appendingPathComponent("Calendar.store")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: blockingFile)
        setenv("MYMACCALENDAR_STORE_URL", requestedStore.path, 1)
        defer {
            unsetenv("MYMACCALENDAR_STORE_URL")
            try? fileManager.removeItem(at: directory)
        }

        XCTAssertThrowsError(try CalendarStore.makeContainer())
        XCTAssertTrue(fileManager.fileExists(atPath: blockingFile.path))
        XCTAssertFalse(fileManager.fileExists(atPath: requestedStore.path))
    }
}
