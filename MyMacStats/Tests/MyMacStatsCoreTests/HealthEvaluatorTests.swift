import XCTest
@testable import MyMacStatsCore

final class HealthEvaluatorTests: XCTestCase {
    func testCPUWarningAndCriticalRequireSustainedTenSeconds() {
        let evaluator = HealthEvaluator()

        XCTAssertEqual(evaluator.cpuHealth(usagePercent: 75, sustainedSecondsAboveThreshold: 9), .normal)
        XCTAssertEqual(evaluator.cpuHealth(usagePercent: 75, sustainedSecondsAboveThreshold: 10), .warning)
        XCTAssertEqual(evaluator.cpuHealth(usagePercent: 95, sustainedSecondsAboveThreshold: 10), .critical)
    }

    func testMemoryHealthUsesUsagePressureAndSwapIncrease() {
        let warningSnapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 80,
            freeBytes: 20,
            compressedBytes: nil,
            cachedBytes: nil,
            swapUsedBytes: nil,
            pressure: .normal
        )
        let criticalSnapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 91,
            freeBytes: 9,
            compressedBytes: nil,
            cachedBytes: nil,
            swapUsedBytes: nil,
            pressure: .normal
        )
        let pressureSnapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 40,
            freeBytes: 60,
            compressedBytes: nil,
            cachedBytes: nil,
            swapUsedBytes: nil,
            pressure: .critical
        )
        let evaluator = HealthEvaluator()

        XCTAssertEqual(evaluator.memoryHealth(snapshot: warningSnapshot), .warning)
        XCTAssertEqual(evaluator.memoryHealth(snapshot: criticalSnapshot), .critical)
        XCTAssertEqual(evaluator.memoryHealth(snapshot: pressureSnapshot), .critical)
        XCTAssertEqual(evaluator.memoryHealth(snapshot: warningSnapshot, isSwapIncreasing: true), .critical)
    }

    func testDiskHealthUsesFreeSpaceThresholds() {
        let evaluator = HealthEvaluator()

        XCTAssertEqual(evaluator.diskHealth(snapshot: disk(free: 25)), .normal)
        XCTAssertEqual(evaluator.diskHealth(snapshot: disk(free: 19)), .warning)
        XCTAssertEqual(evaluator.diskHealth(snapshot: disk(free: 9)), .critical)
    }

    func testBatteryHealthUsesChargeAndServiceState() {
        let evaluator = HealthEvaluator()

        XCTAssertEqual(evaluator.batteryHealth(snapshot: battery(percentage: 50)), .normal)
        XCTAssertEqual(evaluator.batteryHealth(snapshot: battery(percentage: 20)), .warning)
        XCTAssertEqual(evaluator.batteryHealth(snapshot: battery(percentage: 10)), .critical)
        XCTAssertEqual(evaluator.batteryHealth(snapshot: battery(percentage: 80, service: true)), .critical)
        XCTAssertEqual(evaluator.batteryHealth(snapshot: BatterySnapshot(isPresent: false, percentage: nil, isCharging: nil, powerSource: "AC Power", timeRemainingMinutes: nil, cycleCount: nil, serviceRecommended: false)), .unavailable)
    }

    func testNetworkHealthTreatsMissingOrDisconnectedInterfaceAsUnavailableOrWarning() {
        let evaluator = HealthEvaluator()

        XCTAssertEqual(evaluator.networkHealth(snapshot: nil, consecutiveFailures: 2), .unavailable)
        XCTAssertEqual(evaluator.networkHealth(snapshot: NetworkSnapshot(interfaceName: "en0", downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, receivedBytes: 0, sentBytes: 0, isConnected: false), consecutiveFailures: 0), .warning)
        XCTAssertEqual(evaluator.networkHealth(snapshot: NetworkSnapshot(interfaceName: "en0", downloadBytesPerSecond: 10, uploadBytesPerSecond: 5, receivedBytes: 10, sentBytes: 5, isConnected: true), consecutiveFailures: 0), .normal)
    }

    func testDebounceRequiresTwoConsecutiveSamplesBeforeChangingState() {
        var evaluator = HealthEvaluator(debounceSamples: 2)

        XCTAssertEqual(evaluator.debouncedHealth(for: .memory, candidate: .normal), .normal)
        XCTAssertEqual(evaluator.debouncedHealth(for: .memory, candidate: .critical), .normal)
        XCTAssertEqual(evaluator.debouncedHealth(for: .memory, candidate: .critical), .critical)
        XCTAssertEqual(evaluator.debouncedHealth(for: .memory, candidate: .warning), .critical)
        XCTAssertEqual(evaluator.debouncedHealth(for: .memory, candidate: .warning), .warning)
    }

    private func disk(free: UInt64) -> DiskSnapshot {
        DiskSnapshot(volumeName: "Macintosh HD", mountPoint: "/", totalBytes: 100, freeBytes: free, readBytesPerSecond: nil, writeBytesPerSecond: nil)
    }

    private func battery(percentage: Double, service: Bool = false) -> BatterySnapshot {
        BatterySnapshot(isPresent: true, percentage: percentage, isCharging: false, powerSource: "Battery Power", timeRemainingMinutes: nil, cycleCount: nil, serviceRecommended: service)
    }
}
