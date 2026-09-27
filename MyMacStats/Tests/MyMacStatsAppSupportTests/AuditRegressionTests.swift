import XCTest
import MyMacStatsCore
@testable import MyMacStatsAppSupport

@MainActor
final class AuditRegressionTests: XCTestCase {
    func testExactPIDSearchSelectsMatchingChildEvenOutsideFirstSix() {
        let processes = (1...80).map { process(Int32(20_000 + $0), cpu: Double(100 - $0)) }
        let model = DashboardViewModel(snapshot: snapshot(processes))
        model.selectProcess(pid: 20_001)
        model.searchText = "20080"
        XCTAssertEqual(model.selectedProcess?.pid, 20_080)
        model.selectProcessGroup(model.displayedProcessGroups[0])
        XCTAssertEqual(model.selectedProcess?.pid, 20_080)
        XCTAssertEqual(model.selectedProcessGroup?.processes.count, 80)
    }

    func testAllGroupsRemainAvailableAndMenuRankingIgnoresSearchAndSort() {
        let processes = (1...80).map { process(Int32(20_000 + $0), cpu: Double($0), path: "/opt/bin/worker") }
        let model = DashboardViewModel(snapshot: snapshot(processes))
        XCTAssertEqual(model.displayedProcessGroups.count, 80)
        model.sortAscending = true
        model.searchText = "no-match"
        XCTAssertTrue(model.displayedProcessGroups.isEmpty)
        XCTAssertEqual(model.topCPUProcessGroups.map(\.cpuPercent), [80, 79, 78])
        model.select(.memory)
        XCTAssertEqual(model.topCPUProcessGroups.map(\.cpuPercent), [80, 79, 78])
    }

    func testStandaloneTerminationDoesNotSignalSameNamedSibling() async {
        let processes = [process(20_001, path: "/opt/bin/node"), process(20_002, path: "/opt/bin/node")]
        let sampler = AuditSampler(processes: processes)
        var signals: [Int32] = []
        let model = DashboardViewModel(snapshot: snapshot(processes), service: SystemMetricsService(sampler: sampler),
            terminator: ProcessTerminator(currentProcessID: 99, signalSender: { pid, _ in signals.append(pid); return 0 }),
            applicationTerminator: AuditApplicationTerminator())
        model.requestTermination(for: processes[1])
        await model.confirmPendingTermination()
        XCTAssertEqual(signals, [20_002])
    }

    func testIndividualAppChildQuitAndForceQuitStayScopedToOnePID() async {
        let processes = [process(20_001), process(20_002)]
        let applicationTerminator = AuditApplicationTerminator()
        var signals: [(Int32, Int32)] = []
        let model = DashboardViewModel(snapshot: snapshot(processes), service: SystemMetricsService(sampler: AuditSampler(processes: processes)),
            terminator: ProcessTerminator(currentProcessID: 99, signalSender: { pid, signal in signals.append((pid, signal)); return 0 }),
            applicationTerminator: applicationTerminator)
        model.selectProcess(pid: 20_002)
        model.requestTermination(for: processes[1], scope: .process)
        XCTAssertFalse(model.pendingTerminationTargetsApp)
        XCTAssertNil(model.pendingTerminationGroup)
        await model.confirmPendingTermination()
        XCTAssertTrue(model.selectedIndividualProcessCanForceQuit)
        XCTAssertFalse(model.selectedProcessCanForceQuit)
        model.requestForceTermination(for: processes[1], scope: .process)
        await model.confirmPendingTermination()
        XCTAssertEqual(signals.map(\.0), [20_002, 20_002])
        XCTAssertEqual(signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertEqual(applicationTerminator.callCount, 0)
    }

    func testRisingCPUDoesNotClearAnExistingWarning() async {
        let sampler = AuditSampler(processes: [])
        sampler.cpuUsage = 80
        let service = SystemMetricsService(sampler: sampler)
        var latest = SystemMetricsSnapshot.empty()
        for second in 0...12 {
            latest = await service.refresh(now: Date(timeIntervalSince1970: Double(second)))
        }
        XCTAssertEqual(latest.summary(for: .cpu)?.health, .warning)
        sampler.cpuUsage = 95
        for second in 13...14 {
            latest = await service.refresh(now: Date(timeIntervalSince1970: Double(second)))
        }
        XCTAssertEqual(latest.summary(for: .cpu)?.health, .warning)
        for second in 15...24 {
            latest = await service.refresh(now: Date(timeIntervalSince1970: Double(second)))
        }
        XCTAssertEqual(latest.summary(for: .cpu)?.health, .critical)
        sampler.cpuUsage = 20
        for second in 25...26 {
            latest = await service.refresh(now: Date(timeIntervalSince1970: Double(second)))
        }
        XCTAssertEqual(latest.summary(for: .cpu)?.health, .normal)
    }

    func testPendingNotificationPermissionDoesNotBlockRefreshOrTermination() async {
        let target = process(20_001, path: "/opt/bin/worker")
        let sampler = AuditSampler(processes: [target])
        sampler.memoryCritical = true
        let notifier = SuspendedAuditNotifier()
        let controller = HealthAlertController(notifier: notifier, sustainedCriticalSeconds: 0)
        var signals: [Int32] = []
        let model = DashboardViewModel(service: SystemMetricsService(sampler: sampler, evaluator: HealthEvaluator(debounceSamples: 1)),
            healthAlertController: controller,
            terminator: ProcessTerminator(currentProcessID: 99, signalSender: { pid, _ in signals.append(pid); return 0 }))
        let finished = expectation(description: "Refresh and termination finish while authorization is pending")
        let task = Task {
            await model.refreshNow()
            model.requestTermination(for: target, scope: .process)
            await model.confirmPendingTermination()
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(signals, [20_001])
        XCTAssertEqual(sampler.processCallCount, 2)
        XCTAssertEqual(notifier.deliveredCount, 0)
        notifier.release()
        await task.value
    }

    func testRecoveryWhilePermissionPendingSuppressesOutdatedAlert() async {
        let notifier = SuspendedAuditNotifier()
        let controller = HealthAlertController(notifier: notifier, sustainedCriticalSeconds: 0)
        let critical = SystemMetricsSnapshot(summaries: [.init(kind: .memory, title: "RAM", valueText: "95%", detailText: nil, health: .critical, updatedAt: Date())], cpu: nil, memory: nil, disk: nil, network: nil, battery: nil, processes: [], cpuHistory: [], updatedAt: Date())
        let task = controller.submit(snapshot: critical)
        controller.submit(snapshot: .empty())
        notifier.release()
        await task?.value
        XCTAssertEqual(notifier.deliveredCount, 0)
    }

    private func process(_ pid: Int32, cpu: Double = 1, path: String = "/Applications/Fixture.app/Contents/MacOS/worker") -> ProcessMetric {
        ProcessMetric(pid: pid, name: "worker", cpuPercent: cpu, memoryBytes: 100, path: path, bundleIdentifier: nil)
    }

    private func snapshot(_ processes: [ProcessMetric]) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(summaries: [], cpu: nil, memory: nil, disk: nil, network: nil, battery: nil, processes: processes, cpuHistory: [], updatedAt: Date())
    }
}

@MainActor
private final class AuditSampler: SystemSampler {
    let processes: [ProcessMetric]
    var cpuUsage = 10.0
    var memoryCritical = false
    var processCallCount = 0
    init(processes: [ProcessMetric]) { self.processes = processes }
    func sampleCPU() async -> CPUSnapshot? { .init(totalUsagePercent: cpuUsage, userPercent: cpuUsage, systemPercent: 0, idlePercent: 100 - cpuUsage) }
    func sampleMemory() async -> MemorySnapshot? {
        memoryCritical ? .init(totalBytes: 100, usedBytes: 95, freeBytes: 5, compressedBytes: nil, cachedBytes: nil, swapUsedBytes: nil, pressure: .critical) : nil
    }
    func sampleDisk() async -> DiskSnapshot? { nil }
    func sampleNetwork() async -> NetworkSnapshot? { nil }
    func sampleBattery() async -> BatterySnapshot? { nil }
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }
    func sampleProcesses() async -> [ProcessMetric]? { processCallCount += 1; return processes }
}

private final class AuditApplicationTerminator: ApplicationTerminating {
    var callCount = 0
    func terminateApplicationProcesses(_ processes: [ProcessMetric], mode: ProcessTerminationMode) -> Bool { callCount += 1; return false }
}

@MainActor
private final class SuspendedAuditNotifier: HealthAlertNotifying {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var deliveredCount = 0
    func requestAuthorization() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func deliver(_ alert: HealthAlert) async { deliveredCount += 1 }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
