import XCTest
import MyMacStatsCore
@testable import MyMacStatsAppSupport

@MainActor
final class SystemMetricsServiceTests: XCTestCase {
    func testRefreshBuildsSummariesFromSamplerValues() async {
        let now = Date(timeIntervalSince1970: 100)
        let service = SystemMetricsService(
            sampler: MockSystemSampler(
                cpu: CPUSnapshot(totalUsagePercent: 75, userPercent: 50, systemPercent: 25, idlePercent: 25, sampledAt: now),
                memory: MemorySnapshot(totalBytes: gib(16), usedBytes: gib(13), freeBytes: gib(3), compressedBytes: gib(1), cachedBytes: gib(2), swapUsedBytes: gib(1), pressure: .warning, sampledAt: now),
                disk: DiskSnapshot(volumeName: "Macintosh HD", mountPoint: "/", totalBytes: gib(100), freeBytes: gib(25), readBytesPerSecond: nil, writeBytesPerSecond: nil, sampledAt: now),
                network: NetworkSnapshot(interfaceName: "en0", downloadBytesPerSecond: 1_048_576, uploadBytesPerSecond: 524_288, receivedBytes: 10, sentBytes: 5, isConnected: true, sampledAt: now),
                battery: BatterySnapshot(isPresent: true, percentage: 78, isCharging: true, powerSource: "AC Power", timeRemainingMinutes: nil, cycleCount: 42, serviceRecommended: false, sampledAt: now),
                diskSpaceCandidates: [
                    DiskSpaceCandidate(title: "Downloads", path: "/Users/me/Downloads", sizeBytes: gib(3))
                ],
                processes: [
                    ProcessMetric(pid: 1, name: "launchd", cpuPercent: 1, memoryBytes: 100, path: "/sbin/launchd", bundleIdentifier: nil),
                    ProcessMetric(pid: 2, name: "Xcode", cpuPercent: 80, memoryBytes: gib(2), path: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode")
                ]
            ),
            evaluator: HealthEvaluator(cpuSustainedSeconds: 0, debounceSamples: 1)
        )

        let snapshot = await service.refresh(now: now)

        XCTAssertEqual(snapshot.summary(for: .cpu)?.valueText, "75%")
        XCTAssertEqual(snapshot.summary(for: .cpu)?.health, .warning)
        XCTAssertEqual(snapshot.summary(for: .memory)?.valueText, "13G / 16G")
        XCTAssertEqual(snapshot.summary(for: .memory)?.health, .warning)
        XCTAssertEqual(snapshot.summary(for: .disk)?.valueText, "75%")
        XCTAssertEqual(snapshot.summary(for: .network)?.valueText, "↓ 1M/s")
        XCTAssertEqual(snapshot.summary(for: .network)?.detailText, "en0  ↑ 512K/s")
        XCTAssertEqual(snapshot.summary(for: .battery)?.valueText, "78%")
        XCTAssertEqual(snapshot.summary(for: .processes)?.valueText, "2")
        XCTAssertEqual(snapshot.diskSpaceCandidates, [])
        XCTAssertEqual(snapshot.processes.first?.name, "Xcode")
        XCTAssertEqual(snapshot.cpuHistory, [75])

        try? await Task.sleep(nanoseconds: 50_000_000)
        let cachedSnapshot = await service.refresh(now: now.addingTimeInterval(1))

        XCTAssertEqual(cachedSnapshot.diskSpaceCandidates.map(\.title), ["Downloads"])
    }

    func testRefreshDoesNotWaitForSlowDiskCandidateScan() async {
        let service = SystemMetricsService(
            sampler: SlowDiskCandidateSampler(),
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        let start = Date()
        let snapshot = await service.refresh(now: Date(timeIntervalSince1970: 300))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertEqual(snapshot.diskSpaceCandidates, [])
    }

    func testUnavailableSummariesAreShownWhenSamplersReturnNil() async {
        let now = Date(timeIntervalSince1970: 200)
        let service = SystemMetricsService(
            sampler: MockSystemSampler(),
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        let snapshot = await service.refresh(now: now)

        XCTAssertEqual(snapshot.summary(for: .cpu)?.health, .unavailable)
        XCTAssertEqual(snapshot.summary(for: .memory)?.valueText, "Unavailable")
        XCTAssertEqual(snapshot.summary(for: .network)?.health, .unavailable)
        XCTAssertEqual(snapshot.summary(for: .battery)?.valueText, "Unavailable")
    }

    func testCPUHistoryRetainsFiveMinutesOfTimestampedSamples() async {
        let sampler = SequenceSystemSampler(cpuUsages: [10, 20, 30, 40])
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        _ = await service.refresh(now: Date(timeIntervalSince1970: 0))
        _ = await service.refresh(now: Date(timeIntervalSince1970: 100))
        _ = await service.refresh(now: Date(timeIntervalSince1970: 240))
        let snapshot = await service.refresh(now: Date(timeIntervalSince1970: 301))

        XCTAssertEqual(snapshot.cpuHistorySamples.map(\.value), [20, 30, 40])
        XCTAssertEqual(snapshot.cpuHistory, [20, 30, 40])
    }

    private func gib(_ value: UInt64) -> UInt64 {
        value * 1_024 * 1_024 * 1_024
    }
}

private struct MockSystemSampler: SystemSampler {
    var cpu: CPUSnapshot?
    var memory: MemorySnapshot?
    var disk: DiskSnapshot?
    var network: NetworkSnapshot?
    var battery: BatterySnapshot?
    var diskSpaceCandidates: [DiskSpaceCandidate]
    var processes: [ProcessMetric]

    init(
        cpu: CPUSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        disk: DiskSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        battery: BatterySnapshot? = nil,
        diskSpaceCandidates: [DiskSpaceCandidate] = [],
        processes: [ProcessMetric] = []
    ) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.diskSpaceCandidates = diskSpaceCandidates
        self.processes = processes
    }

    func sampleCPU() async -> CPUSnapshot? { cpu }
    func sampleMemory() async -> MemorySnapshot? { memory }
    func sampleDisk() async -> DiskSnapshot? { disk }
    func sampleNetwork() async -> NetworkSnapshot? { network }
    func sampleBattery() async -> BatterySnapshot? { battery }
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { diskSpaceCandidates }
    func sampleProcesses() async -> [ProcessMetric] { processes }
}

private struct SlowDiskCandidateSampler: SystemSampler {
    func sampleCPU() async -> CPUSnapshot? { nil }
    func sampleMemory() async -> MemorySnapshot? { nil }
    func sampleDisk() async -> DiskSnapshot? { nil }
    func sampleNetwork() async -> NetworkSnapshot? { nil }
    func sampleBattery() async -> BatterySnapshot? { nil }

    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return [
            DiskSpaceCandidate(title: "Downloads", path: "/Users/me/Downloads", sizeBytes: 1)
        ]
    }

    func sampleProcesses() async -> [ProcessMetric] { [] }
}

@MainActor
private final class SequenceSystemSampler: SystemSampler {
    private var cpuUsages: [Double]

    init(cpuUsages: [Double]) {
        self.cpuUsages = cpuUsages
    }

    func sampleCPU() async -> CPUSnapshot? {
        guard !cpuUsages.isEmpty else { return nil }
        return CPUSnapshot(totalUsagePercent: cpuUsages.removeFirst(), userPercent: 0, systemPercent: 0, idlePercent: 0)
    }

    func sampleMemory() async -> MemorySnapshot? { nil }
    func sampleDisk() async -> DiskSnapshot? { nil }
    func sampleNetwork() async -> NetworkSnapshot? { nil }
    func sampleBattery() async -> BatterySnapshot? { nil }
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }
    func sampleProcesses() async -> [ProcessMetric] { [] }
}
