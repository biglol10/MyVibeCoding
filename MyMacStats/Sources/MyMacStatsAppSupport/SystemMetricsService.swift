import Foundation
import MyMacStatsCore

@MainActor
public protocol SystemSampler {
    func sampleCPU() async -> CPUSnapshot?
    func sampleMemory() async -> MemorySnapshot?
    func sampleDisk() async -> DiskSnapshot?
    func sampleNetwork() async -> NetworkSnapshot?
    func sampleBattery() async -> BatterySnapshot?
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate]
    func sampleProcesses() async -> [ProcessMetric]
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public let summaries: [MetricSummary]
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let disk: DiskSnapshot?
    public let network: NetworkSnapshot?
    public let battery: BatterySnapshot?
    public let diskSpaceCandidates: [DiskSpaceCandidate]
    public let processes: [ProcessMetric]
    public let cpuHistory: [Double]
    public let cpuHistorySamples: [MetricHistorySample]
    public let updatedAt: Date

    public init(
        summaries: [MetricSummary],
        cpu: CPUSnapshot?,
        memory: MemorySnapshot?,
        disk: DiskSnapshot?,
        network: NetworkSnapshot?,
        battery: BatterySnapshot?,
        diskSpaceCandidates: [DiskSpaceCandidate] = [],
        processes: [ProcessMetric],
        cpuHistory: [Double],
        cpuHistorySamples: [MetricHistorySample] = [],
        updatedAt: Date
    ) {
        self.summaries = summaries
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.diskSpaceCandidates = diskSpaceCandidates
        self.processes = processes
        self.cpuHistory = cpuHistory
        self.cpuHistorySamples = cpuHistorySamples
        self.updatedAt = updatedAt
    }

    public func summary(for kind: MetricKind) -> MetricSummary? {
        summaries.first { $0.kind == kind }
    }

    public static func empty(updatedAt: Date = Date()) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            summaries: [],
            cpu: nil,
            memory: nil,
            disk: nil,
            network: nil,
            battery: nil,
            diskSpaceCandidates: [],
            processes: [],
            cpuHistory: [],
            updatedAt: updatedAt
        )
    }
}

@MainActor
public final class SystemMetricsService {
    private let sampler: SystemSampler
    private var evaluator: HealthEvaluator
    private var cpuHistorySamples: [MetricHistorySample] = []
    private var consecutiveNetworkFailures = 0
    private var diskSpaceCandidates: [DiskSpaceCandidate] = []
    private var diskSpaceCandidateRefreshTask: Task<Void, Never>?
    private var lastDiskSpaceCandidateRefreshStartedAt: Date?
    private let diskSpaceCandidateRefreshInterval: TimeInterval

    deinit {
        diskSpaceCandidateRefreshTask?.cancel()
    }

    public init(
        sampler: SystemSampler = DefaultSystemSampler(),
        evaluator: HealthEvaluator = HealthEvaluator(),
        diskSpaceCandidateRefreshInterval: TimeInterval = 60
    ) {
        self.sampler = sampler
        self.evaluator = evaluator
        self.diskSpaceCandidateRefreshInterval = diskSpaceCandidateRefreshInterval
    }

    public convenience init(sampler: SystemSampler, evaluator: HealthEvaluator) {
        self.init(
            sampler: sampler,
            evaluator: evaluator,
            diskSpaceCandidateRefreshInterval: 60
        )
    }

    public func refresh(now: Date = Date()) async -> SystemMetricsSnapshot {
        refreshDiskSpaceCandidatesIfNeeded(now: now)

        let cpu = await sampler.sampleCPU()
        let memory = await sampler.sampleMemory()
        let disk = await sampler.sampleDisk()
        let network = await sampler.sampleNetwork()
        let battery = await sampler.sampleBattery()
        let processes = ProcessSorting.filtered(await sampler.sampleProcesses(), searchText: "", sortKey: .cpu)

        if let cpu {
            cpuHistorySamples.append(MetricHistorySample(date: now, value: cpu.totalUsagePercent))
            cpuHistorySamples.removeAll { now.timeIntervalSince($0.date) > 300 }
        }

        if network == nil {
            consecutiveNetworkFailures += 1
        } else {
            consecutiveNetworkFailures = 0
        }

        let summaries = buildSummaries(
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            processes: processes,
            now: now
        )

        return SystemMetricsSnapshot(
            summaries: summaries,
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            diskSpaceCandidates: diskSpaceCandidates,
            processes: processes,
            cpuHistory: cpuHistorySamples.map(\.value),
            cpuHistorySamples: cpuHistorySamples,
            updatedAt: now
        )
    }

    private func refreshDiskSpaceCandidatesIfNeeded(now: Date) {
        guard diskSpaceCandidateRefreshTask == nil else { return }
        if let lastDiskSpaceCandidateRefreshStartedAt,
           now.timeIntervalSince(lastDiskSpaceCandidateRefreshStartedAt) < diskSpaceCandidateRefreshInterval {
            return
        }

        lastDiskSpaceCandidateRefreshStartedAt = now
        diskSpaceCandidateRefreshTask = Task { [weak self] in
            guard let self else { return }
            let candidates = await self.sampler.sampleDiskSpaceCandidates()
            guard !Task.isCancelled else { return }
            self.diskSpaceCandidates = candidates
            self.diskSpaceCandidateRefreshTask = nil
        }
    }

    private func buildSummaries(
        cpu: CPUSnapshot?,
        memory: MemorySnapshot?,
        disk: DiskSnapshot?,
        network: NetworkSnapshot?,
        battery: BatterySnapshot?,
        processes: [ProcessMetric],
        now: Date
    ) -> [MetricSummary] {
        MetricKind.allCases.map { kind in
            switch kind {
            case .cpu:
                guard let cpu else {
                    return unavailableSummary(kind: .cpu, now: now)
                }
                let threshold = cpu.totalUsagePercent >= evaluator.cpuCriticalThreshold
                    ? evaluator.cpuCriticalThreshold
                    : evaluator.cpuWarningThreshold
                let sustainedSeconds = sustainedCPUSeconds(above: threshold, now: now)
                let health = evaluator.cpuHealth(
                    usagePercent: cpu.totalUsagePercent,
                    sustainedSecondsAboveThreshold: sustainedSeconds
                )
                return MetricSummary(
                    kind: .cpu,
                    title: MetricKind.cpu.title,
                    valueText: MetricFormatters.percent(cpu.totalUsagePercent),
                    detailText: "User \(MetricFormatters.percent(cpu.userPercent)) / System \(MetricFormatters.percent(cpu.systemPercent))",
                    health: health,
                    updatedAt: now
                )

            case .memory:
                guard let memory else {
                    return unavailableSummary(kind: .memory, now: now)
                }
                return MetricSummary(
                    kind: .memory,
                    title: MetricKind.memory.title,
                    valueText: "\(MetricFormatters.compactBytes(memory.usedBytes)) / \(MetricFormatters.compactBytes(memory.totalBytes))",
                    detailText: "Free \(MetricFormatters.bytes(memory.freeBytes))",
                    health: evaluator.memoryHealth(snapshot: memory),
                    updatedAt: now
                )

            case .disk:
                guard let disk else {
                    return unavailableSummary(kind: .disk, now: now)
                }
                let usedRatio = 1 - disk.freeRatio
                return MetricSummary(
                    kind: .disk,
                    title: MetricKind.disk.title,
                    valueText: MetricFormatters.percent(usedRatio * 100),
                    detailText: "Free \(MetricFormatters.bytes(disk.freeBytes))",
                    health: evaluator.diskHealth(snapshot: disk),
                    updatedAt: now
                )

            case .network:
                guard let network else {
                    return MetricSummary(
                        kind: .network,
                        title: MetricKind.network.title,
                        valueText: "Unavailable",
                        detailText: "No active interface",
                        health: evaluator.networkHealth(snapshot: nil, consecutiveFailures: consecutiveNetworkFailures),
                        updatedAt: now
                    )
                }
                return MetricSummary(
                    kind: .network,
                    title: MetricKind.network.title,
                    valueText: "↓ \(MetricFormatters.compactSpeed(network.downloadBytesPerSecond))",
                    detailText: "\(network.interfaceName ?? "No interface")  ↑ \(MetricFormatters.compactSpeed(network.uploadBytesPerSecond))",
                    health: evaluator.networkHealth(snapshot: network, consecutiveFailures: consecutiveNetworkFailures),
                    updatedAt: now
                )

            case .battery:
                guard let battery else {
                    return unavailableSummary(kind: .battery, now: now)
                }
                return MetricSummary(
                    kind: .battery,
                    title: MetricKind.battery.title,
                    valueText: battery.percentage.map { MetricFormatters.percent($0) } ?? "Unavailable",
                    detailText: battery.powerSource,
                    health: evaluator.batteryHealth(snapshot: battery),
                    updatedAt: now
                )

            case .processes:
                return MetricSummary(
                    kind: .processes,
                    title: MetricKind.processes.title,
                    valueText: "\(processes.count)",
                    detailText: "Running processes",
                    health: .normal,
                    updatedAt: now
                )
            }
        }
    }

    private func unavailableSummary(kind: MetricKind, now: Date) -> MetricSummary {
        MetricSummary(
            kind: kind,
            title: kind.title,
            valueText: "Unavailable",
            detailText: "Sampler unavailable",
            health: .unavailable,
            updatedAt: now
        )
    }

    private func sustainedCPUSeconds(above threshold: Double, now: Date) -> TimeInterval {
        guard let latest = cpuHistorySamples.last, latest.value >= threshold else { return 0 }
        let sustainedSamples = cpuHistorySamples.reversed().prefix { $0.value >= threshold }
        guard let earliest = sustainedSamples.last else { return 0 }
        return now.timeIntervalSince(earliest.date)
    }
}

public final class DefaultSystemSampler: SystemSampler {
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()
    private var networkSampler = NetworkSampler()
    private let batterySampler = BatterySampler()

    public init() {}

    public func sampleCPU() async -> CPUSnapshot? {
        await Task.detached(priority: .utility) {
            var sampler = CPUSampler()
            return try? sampler.sample()
        }.value
    }

    public func sampleMemory() async -> MemorySnapshot? {
        try? memorySampler.sample()
    }

    public func sampleDisk() async -> DiskSnapshot? {
        try? diskSampler.sample()
    }

    public func sampleNetwork() async -> NetworkSnapshot? {
        try? networkSampler.sample()
    }

    public func sampleBattery() async -> BatterySnapshot? {
        try? batterySampler.sample()
    }

    public func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] {
        await Task.detached(priority: .utility) {
            DiskSpaceCandidateScanner().scan()
        }.value
    }

    public func sampleProcesses() async -> [ProcessMetric] {
        await Task.detached(priority: .utility) {
            (try? ProcessSampler().sample()) ?? []
        }.value
    }
}
