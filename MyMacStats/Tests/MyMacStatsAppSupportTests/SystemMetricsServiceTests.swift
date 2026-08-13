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

    func testInitialNetworkSamplingFailureIsUnavailableWithoutLastKnownGoodValue() async {
        let service = SystemMetricsService(
            sampler: MockSystemSampler(),
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        let snapshot = await service.refresh(now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.summary(for: .network)?.health, .unavailable)
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

    func testSummariesUseDebouncedHealthStates() async {
        let sampler = SequenceMemorySampler(usages: [40, 95, 95])
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 2)
        )

        let first = await service.refresh(now: Date(timeIntervalSince1970: 0))
        let second = await service.refresh(now: Date(timeIntervalSince1970: 1))
        let third = await service.refresh(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(first.summary(for: .memory)?.health, .normal)
        XCTAssertEqual(second.summary(for: .memory)?.health, .normal)
        XCTAssertEqual(third.summary(for: .memory)?.health, .critical)
    }

    func testScheduledRefreshUsesMetricSpecificCadence() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let process = ProcessMetric(
            pid: 1,
            name: "launchd",
            cpuPercent: 1,
            memoryBytes: 100,
            path: "/sbin/launchd",
            bundleIdentifier: nil
        )
        let sampler = RecordingSystemSampler(
            cpu: CPUSnapshot(totalUsagePercent: 10, userPercent: 5, systemPercent: 5, idlePercent: 90, sampledAt: now),
            memory: MemorySnapshot(totalBytes: 100, usedBytes: 50, freeBytes: 50, compressedBytes: nil, cachedBytes: nil, swapUsedBytes: nil, pressure: .normal, sampledAt: now),
            disk: DiskSnapshot(volumeName: "Macintosh HD", mountPoint: "/", totalBytes: 100, freeBytes: 50, readBytesPerSecond: nil, writeBytesPerSecond: nil, sampledAt: now),
            network: NetworkSnapshot(interfaceName: "en0", downloadBytesPerSecond: 1, uploadBytesPerSecond: 1, receivedBytes: 1, sentBytes: 1, isConnected: true, sampledAt: now),
            battery: BatterySnapshot(isPresent: true, percentage: 50, isCharging: false, powerSource: "Battery Power", timeRemainingMinutes: nil, cycleCount: nil, serviceRecommended: false, sampledAt: now),
            processes: [process]
        )
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        _ = await service.refresh(now: now, reason: .scheduled(baseInterval: 1))
        _ = await service.refresh(now: now.addingTimeInterval(1), reason: .scheduled(baseInterval: 1))

        XCTAssertEqual(sampler.cpuCallCount, 2)
        XCTAssertEqual(sampler.memoryCallCount, 2)
        XCTAssertEqual(sampler.networkCallCount, 2)
        XCTAssertEqual(sampler.processCallCount, 1)
        XCTAssertEqual(sampler.diskCallCount, 1)
        XCTAssertEqual(sampler.batteryCallCount, 1)

        _ = await service.refresh(now: now.addingTimeInterval(2), reason: .scheduled(baseInterval: 1))
        XCTAssertEqual(sampler.processCallCount, 2)

        _ = await service.refresh(now: now.addingTimeInterval(10), reason: .scheduled(baseInterval: 1))
        XCTAssertEqual(sampler.diskCallCount, 2)
        XCTAssertEqual(sampler.batteryCallCount, 2)
    }

    func testCadenceSkipReusesSuccessfulUnavailableBatterySummary() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let sampler = RecordingSystemSampler(
            cpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: BatterySnapshot(
                isPresent: false,
                percentage: nil,
                isCharging: nil,
                powerSource: "Battery Power",
                timeRemainingMinutes: nil,
                cycleCount: nil,
                serviceRecommended: false,
                sampledAt: now
            ),
            processes: nil
        )
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        let first = await service.refresh(now: now, reason: .scheduled(baseInterval: 1))
        let second = await service.refresh(now: now.addingTimeInterval(1), reason: .scheduled(baseInterval: 1))

        XCTAssertEqual(sampler.batteryCallCount, 1)
        XCTAssertEqual(second.summary(for: .battery), first.summary(for: .battery))
    }

    func testFirstCPUFailureRetainsLastValueThenSecondFailureBecomesUnavailable() async {
        let start = Date(timeIntervalSince1970: 2_000)
        let sampler = recordingSampler(at: start)
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(cpuSustainedSeconds: 0, debounceSamples: 1)
        )

        _ = await service.refresh(now: start, reason: .scheduled(baseInterval: 1))
        sampler.cpuResult = nil

        let stale = await service.refresh(
            now: start.addingTimeInterval(1),
            reason: .scheduled(baseInterval: 1)
        )

        XCTAssertEqual(stale.cpu?.totalUsagePercent, 40)
        XCTAssertEqual(stale.summary(for: .cpu)?.health, .warning)
        XCTAssertTrue(stale.summary(for: .cpu)?.detailText?.contains("Using last sample") == true)
        XCTAssertEqual(stale.summary(for: .cpu)?.updatedAt, start)
        XCTAssertEqual(stale.cpuHistory, [40])

        let unavailable = await service.refresh(
            now: start.addingTimeInterval(2),
            reason: .scheduled(baseInterval: 1)
        )

        XCTAssertNil(unavailable.cpu)
        XCTAssertEqual(unavailable.summary(for: .cpu)?.health, .unavailable)
        XCTAssertEqual(unavailable.cpuHistory, [40])

        sampler.cpuResult = cpuSnapshot(usage: 25, at: start.addingTimeInterval(3))
        let recovered = await service.refresh(
            now: start.addingTimeInterval(3),
            reason: .scheduled(baseInterval: 1)
        )

        XCTAssertEqual(recovered.cpu?.totalUsagePercent, 25)
        XCTAssertEqual(recovered.summary(for: .cpu)?.health, .normal)
        XCTAssertEqual(recovered.cpuHistory, [40, 25])
    }

    func testProcessFailuresRetainOnceThenBecomeUnavailableAndEmptySuccessRecovers() async {
        let start = Date(timeIntervalSince1970: 3_000)
        let sampler = recordingSampler(at: start)
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 1)
        )

        _ = await service.refresh(now: start, reason: .scheduled(baseInterval: 1))
        sampler.processResult = nil

        let stale = await service.refresh(
            now: start.addingTimeInterval(2),
            reason: .scheduled(baseInterval: 1)
        )
        XCTAssertEqual(stale.processes.map(\.name), ["Safari"])
        XCTAssertEqual(stale.summary(for: .processes)?.health, .warning)
        XCTAssertFalse(stale.processesAreFresh)

        let unavailable = await service.refresh(
            now: start.addingTimeInterval(4),
            reason: .scheduled(baseInterval: 1)
        )
        XCTAssertEqual(unavailable.processes, [])
        XCTAssertEqual(unavailable.summary(for: .processes)?.health, .unavailable)

        sampler.processResult = []
        let recovered = await service.refresh(
            now: start.addingTimeInterval(6),
            reason: .scheduled(baseInterval: 1)
        )
        XCTAssertEqual(recovered.processes, [])
        XCTAssertEqual(recovered.summary(for: .processes)?.health, .normal)
        XCTAssertTrue(recovered.processesAreFresh)
    }

    func testSkippedDiskSampleDoesNotAdvanceHealthDebounce() async {
        let start = Date(timeIntervalSince1970: 4_000)
        let sampler = recordingSampler(at: start)
        let service = SystemMetricsService(
            sampler: sampler,
            evaluator: HealthEvaluator(debounceSamples: 2)
        )

        let first = await service.refresh(now: start, reason: .scheduled(baseInterval: 1))
        let skipped = await service.refresh(
            now: start.addingTimeInterval(1),
            reason: .scheduled(baseInterval: 1)
        )
        sampler.diskResult = diskSnapshot(freeBytes: 5, at: start.addingTimeInterval(10))
        let second = await service.refresh(
            now: start.addingTimeInterval(10),
            reason: .scheduled(baseInterval: 1)
        )
        let third = await service.refresh(
            now: start.addingTimeInterval(20),
            reason: .scheduled(baseInterval: 1)
        )

        XCTAssertEqual(first.summary(for: .disk)?.health, .normal)
        XCTAssertEqual(skipped.summary(for: .disk)?.health, .normal)
        XCTAssertEqual(second.summary(for: .disk)?.health, .normal)
        XCTAssertEqual(third.summary(for: .disk)?.health, .critical)
        XCTAssertEqual(sampler.diskCallCount, 3)
    }

    private func recordingSampler(at now: Date) -> RecordingSystemSampler {
        RecordingSystemSampler(
            cpu: cpuSnapshot(usage: 40, at: now),
            memory: MemorySnapshot(totalBytes: 100, usedBytes: 50, freeBytes: 50, compressedBytes: nil, cachedBytes: nil, swapUsedBytes: nil, pressure: .normal, sampledAt: now),
            disk: diskSnapshot(freeBytes: 50, at: now),
            network: NetworkSnapshot(interfaceName: "en0", downloadBytesPerSecond: 1, uploadBytesPerSecond: 1, receivedBytes: 1, sentBytes: 1, isConnected: true, sampledAt: now),
            battery: BatterySnapshot(isPresent: true, percentage: 50, isCharging: false, powerSource: "Battery Power", timeRemainingMinutes: nil, cycleCount: nil, serviceRecommended: false, sampledAt: now),
            processes: [ProcessMetric(pid: 1, name: "Safari", cpuPercent: 1, memoryBytes: 100, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")]
        )
    }

    private func cpuSnapshot(usage: Double, at now: Date) -> CPUSnapshot {
        CPUSnapshot(totalUsagePercent: usage, userPercent: usage / 2, systemPercent: usage / 2, idlePercent: 100 - usage, sampledAt: now)
    }

    private func diskSnapshot(freeBytes: UInt64, at now: Date) -> DiskSnapshot {
        DiskSnapshot(volumeName: "Macintosh HD", mountPoint: "/", totalBytes: 100, freeBytes: freeBytes, readBytesPerSecond: nil, writeBytesPerSecond: nil, sampledAt: now)
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
    func sampleProcesses() async -> [ProcessMetric]? { processes }
}

@MainActor
private final class RecordingSystemSampler: SystemSampler {
    var cpuResult: CPUSnapshot?
    var memoryResult: MemorySnapshot?
    var diskResult: DiskSnapshot?
    var networkResult: NetworkSnapshot?
    var batteryResult: BatterySnapshot?
    var processResult: [ProcessMetric]?

    private(set) var cpuCallCount = 0
    private(set) var memoryCallCount = 0
    private(set) var diskCallCount = 0
    private(set) var networkCallCount = 0
    private(set) var batteryCallCount = 0
    private(set) var processCallCount = 0

    init(
        cpu: CPUSnapshot?,
        memory: MemorySnapshot?,
        disk: DiskSnapshot?,
        network: NetworkSnapshot?,
        battery: BatterySnapshot?,
        processes: [ProcessMetric]?
    ) {
        cpuResult = cpu
        memoryResult = memory
        diskResult = disk
        networkResult = network
        batteryResult = battery
        processResult = processes
    }

    func sampleCPU() async -> CPUSnapshot? {
        cpuCallCount += 1
        return cpuResult
    }

    func sampleMemory() async -> MemorySnapshot? {
        memoryCallCount += 1
        return memoryResult
    }

    func sampleDisk() async -> DiskSnapshot? {
        diskCallCount += 1
        return diskResult
    }

    func sampleNetwork() async -> NetworkSnapshot? {
        networkCallCount += 1
        return networkResult
    }

    func sampleBattery() async -> BatterySnapshot? {
        batteryCallCount += 1
        return batteryResult
    }

    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }

    func sampleProcesses() async -> [ProcessMetric]? {
        processCallCount += 1
        return processResult
    }
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

    func sampleProcesses() async -> [ProcessMetric]? { [] }
}

@MainActor
private final class SequenceMemorySampler: SystemSampler {
    private var usages: [UInt64]

    init(usages: [UInt64]) {
        self.usages = usages
    }

    func sampleCPU() async -> CPUSnapshot? { nil }

    func sampleMemory() async -> MemorySnapshot? {
        guard !usages.isEmpty else { return nil }
        let used = usages.removeFirst()
        return MemorySnapshot(
            totalBytes: 100,
            usedBytes: used,
            freeBytes: 100 - used,
            compressedBytes: nil,
            cachedBytes: nil,
            swapUsedBytes: nil,
            pressure: .normal
        )
    }

    func sampleDisk() async -> DiskSnapshot? { nil }
    func sampleNetwork() async -> NetworkSnapshot? { nil }
    func sampleBattery() async -> BatterySnapshot? { nil }
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }
    func sampleProcesses() async -> [ProcessMetric]? { [] }
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
    func sampleProcesses() async -> [ProcessMetric]? { [] }
}
