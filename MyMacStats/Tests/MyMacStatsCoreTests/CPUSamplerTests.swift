import XCTest
@testable import MyMacStatsCore

final class CPUSamplerTests: XCTestCase {
    func testSampleReadsKernelProcessorInfo() throws {
        var sampler = CPUSampler()

        let snapshot = try sampler.sample()

        XCTAssertGreaterThanOrEqual(snapshot.totalUsagePercent, 0)
        XCTAssertLessThanOrEqual(snapshot.totalUsagePercent, 100)
        XCTAssertGreaterThanOrEqual(snapshot.userPercent, 0)
        XCTAssertGreaterThanOrEqual(snapshot.systemPercent, 0)
        XCTAssertGreaterThanOrEqual(snapshot.idlePercent, 0)
    }

    func testPercentagesUseProcessorTickDeltas() {
        let previous = CPUTicks(user: 100, system: 100, idle: 800)
        let current = CPUTicks(user: 180, system: 120, idle: 900)

        let snapshot = CPUSampler.snapshot(previous: previous, current: current, sampledAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot.totalUsagePercent, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.userPercent, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.systemPercent, 10, accuracy: 0.001)
        XCTAssertEqual(snapshot.idlePercent, 50, accuracy: 0.001)
        XCTAssertNotEqual(snapshot.systemPercent, snapshot.totalUsagePercent * 0.35, accuracy: 0.001)
    }

    func testSnapshotFallsBackToCurrentTicksWhenNoPreviousSampleExists() {
        let current = CPUTicks(user: 30, system: 20, idle: 50)

        let snapshot = CPUSampler.snapshot(previous: nil, current: current, sampledAt: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(snapshot.totalUsagePercent, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.userPercent, 30, accuracy: 0.001)
        XCTAssertEqual(snapshot.systemPercent, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot.idlePercent, 50, accuracy: 0.001)
    }
}
