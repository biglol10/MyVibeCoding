import XCTest
@testable import MyMacStatsCore

final class MetricFormattersTests: XCTestCase {
    func testBytesUseBinaryUnitsWithOneDecimalWhenNeeded() {
        XCTAssertEqual(MetricFormatters.bytes(512), "512 B")
        XCTAssertEqual(MetricFormatters.bytes(1_536), "1.5 KB")
        XCTAssertEqual(MetricFormatters.bytes(1_073_741_824), "1 GB")
    }

    func testCompactBytesUseSingleLetterUnits() {
        XCTAssertEqual(MetricFormatters.compactBytes(1_073_741_824), "1G")
        XCTAssertEqual(MetricFormatters.compactBytes(1_610_612_736), "1.5G")
    }

    func testPercentFormattingRoundsWithRequestedFractionDigits() {
        XCTAssertEqual(MetricFormatters.percent(34.44), "34%")
        XCTAssertEqual(MetricFormatters.percent(34.45, fractionDigits: 1), "34.5%")
    }

    func testSpeedAddsPerSecondSuffix() {
        XCTAssertEqual(MetricFormatters.speed(1_048_576), "1 MB/s")
    }
}
