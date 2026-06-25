import XCTest
@testable import MyMacCalendarCore

final class VersionTests: XCTestCase {
    func testVersionName() {
        XCTAssertEqual(AppVersion.name, "MyMacCalendar")
    }
}
