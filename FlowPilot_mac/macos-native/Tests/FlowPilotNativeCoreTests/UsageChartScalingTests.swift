import XCTest
@testable import FlowPilotNativeCore

final class UsageChartScalingTests: XCTestCase {
    func testComputesRelativeBarWidthsFromLargestDuration() {
        let rows = UsageChartScaling.rows(
            items: [
                usageItem(name: "A", seconds: 120),
                usageItem(name: "B", seconds: 60),
                usageItem(name: "C", seconds: 0)
            ],
            limit: 3
        )

        XCTAssertEqual(rows.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(rows.map(\.relativeWidth), [1.0, 0.5, 0.0])
    }

    func testLimitsRows() {
        let rows = UsageChartScaling.rows(
            items: [
                usageItem(name: "A", seconds: 120),
                usageItem(name: "B", seconds: 60),
                usageItem(name: "C", seconds: 30)
            ],
            limit: 2
        )

        XCTAssertEqual(rows.map(\.name), ["A", "B"])
    }

    private func usageItem(name: String, seconds: Int) -> UsageItem {
        UsageItem(
            id: UUID(),
            name: name,
            kind: "앱",
            category: .productive,
            durationSeconds: seconds,
            share: 0,
            ruleSource: "사용자 규칙"
        )
    }
}
