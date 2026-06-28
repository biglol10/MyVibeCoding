import XCTest
@testable import FlowPilotNativeCore

final class DurationFormattingTests: XCTestCase {
    func testFormatsZeroSecondsAsZeroMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 0), "0m")
    }

    func testFormatsSubMinuteAsLessThanOneMinute() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 25), "<1m")
    }

    func testFormatsMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 17 * 60), "17m")
    }

    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 3 * 3_600 + 15 * 60), "3h 15m")
    }
}
