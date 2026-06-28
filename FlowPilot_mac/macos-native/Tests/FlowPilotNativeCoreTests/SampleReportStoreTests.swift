import XCTest
@testable import FlowPilotNativeCore

final class SampleReportStoreTests: XCTestCase {
    func testSummaryMatchesUsageItems() {
        let store = SampleReportStore()

        XCTAssertEqual(store.summary.totalSeconds, store.usageItems.map(\.durationSeconds).reduce(0, +))
        XCTAssertEqual(store.summary.sessionCount, store.timelineSessions.count)
        XCTAssertGreaterThan(store.summary.productiveSeconds, 0)
    }

    func testTopUsageIsSortedByDurationDescending() {
        let store = SampleReportStore()
        let durations = store.usageItems.map(\.durationSeconds)

        XCTAssertEqual(durations, durations.sorted(by: >))
    }
}
