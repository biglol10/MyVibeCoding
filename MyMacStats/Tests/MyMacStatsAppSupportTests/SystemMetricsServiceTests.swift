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
        XCTAssertEqual(snapshot.summary(for: .memory)?.valueText, "13 GB / 16 GB")
        XCTAssertEqual(snapshot.summary(for: .memory)?.health, .warning)
        XCTAssertEqual(snapshot.summary(for: .disk)?.valueText, "75%")
        XCTAssertEqual(snapshot.summary(for: .network)?.valueText, "↓ 1 MB/s  ↑ 512 KB/s")
        XCTAssertEqual(snapshot.summary(for: .battery)?.valueText, "78%")
        XCTAssertEqual(snapshot.summary(for: .processes)?.valueText, "2")
        XCTAssertEqual(snapshot.processes.first?.name, "Xcode")
        XCTAssertEqual(snapshot.cpuHistory, [75])
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
    var processes: [ProcessMetric]

    init(
        cpu: CPUSnapshot? = nil,
        memory: MemorySnapshot? = nil,
        disk: DiskSnapshot? = nil,
        network: NetworkSnapshot? = nil,
        battery: BatterySnapshot? = nil,
        processes: [ProcessMetric] = []
    ) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.processes = processes
    }

    func sampleCPU() async -> CPUSnapshot? { cpu }
    func sampleMemory() async -> MemorySnapshot? { memory }
    func sampleDisk() async -> DiskSnapshot? { disk }
    func sampleNetwork() async -> NetworkSnapshot? { network }
    func sampleBattery() async -> BatterySnapshot? { battery }
    func sampleProcesses() async -> [ProcessMetric] { processes }
}
