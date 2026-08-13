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
    func sampleProcesses() async -> [ProcessMetric]?
}

public enum SystemMetricsRefreshReason: Equatable, Sendable {
    case scheduled(baseInterval: TimeInterval)
    case terminationValidation(baseInterval: TimeInterval)

    var baseInterval: TimeInterval {
        switch self {
        case .scheduled(let interval), .terminationValidation(let interval): interval
        }
    }

    var forcesProcessSampling: Bool {
        if case .terminationValidation = self { return true }
        return false
    }
}

@MainActor
private final class RefreshSerializationGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var isHeld = false
    private var waiters: [Waiter] = []

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }

        if !isHeld {
            isHeld = true
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if !isHeld {
                    isHeld = true
                    continuation.resume(returning: true)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: id)
            }
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }

        waiters.removeFirst().continuation.resume(returning: true)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}

private struct MetricSampleCache<Value> {
    var value: Value?
    var lastSuccessAt: Date?
    var lastAttemptAt: Date?
    var consecutiveFailures = 0

    func isDue(at now: Date, cadence: TimeInterval, forced: Bool = false) -> Bool {
        guard !forced, let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= cadence
    }

    mutating func record(_ result: Value?, at now: Date) {
        lastAttemptAt = now
        if let result {
            value = result
            lastSuccessAt = now
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }
    }
}

private enum SamplePresentationState: Equatable {
    case fresh
    case stale
    case unavailable
}

private extension MetricSampleCache {
    var presentationState: SamplePresentationState {
        guard value != nil else { return .unavailable }
        if consecutiveFailures == 0 { return .fresh }
        if consecutiveFailures == 1 { return .stale }
        return .unavailable
    }

    var presentedValue: Value? {
        presentationState == .unavailable ? nil : value
    }
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
    public let processesAreFresh: Bool
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
        processesAreFresh: Bool = true,
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
        self.processesAreFresh = processesAreFresh
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
            processesAreFresh: false,
            cpuHistory: [],
            updatedAt: updatedAt
        )
    }
}

@MainActor
public final class SystemMetricsService {
    private let sampler: SystemSampler
    private var evaluator: HealthEvaluator
    private let refreshGate = RefreshSerializationGate()
    private var cpuCache = MetricSampleCache<CPUSnapshot>()
    private var memoryCache = MetricSampleCache<MemorySnapshot>()
    private var diskCache = MetricSampleCache<DiskSnapshot>()
    private var networkCache = MetricSampleCache<NetworkSnapshot>()
    private var batteryCache = MetricSampleCache<BatterySnapshot>()
    private var processCache = MetricSampleCache<[ProcessMetric]>()
    private var summaryCache: [MetricKind: MetricSummary] = [:]
    private var cpuHistorySamples: [MetricHistorySample] = []
    private var diskSpaceCandidates: [DiskSpaceCandidate] = []
    private var diskSpaceCandidateRefreshTask: Task<Void, Never>?
    private var lastDiskSpaceCandidateRefreshStartedAt: Date?
    private let diskSpaceCandidateRefreshInterval: TimeInterval
    private var previousMemorySwapUsedBytes: UInt64?

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

    public func refresh(
        now: Date = Date(),
        reason: SystemMetricsRefreshReason = .scheduled(baseInterval: 1)
    ) async -> SystemMetricsSnapshot {
        let acquiredRefreshGate = await refreshGate.acquire()
        guard acquiredRefreshGate else {
            return .empty(updatedAt: now)
        }
        guard !Task.isCancelled else {
            refreshGate.release()
            return .empty(updatedAt: now)
        }
        defer { refreshGate.release() }

        refreshDiskSpaceCandidatesIfNeeded(now: now)

        let base = max(reason.baseInterval, 1)
        let processCadence = max(base, 2)
        let slowCadence = max(base, 10)

        var freshKinds = Set<MetricKind>()

        if cpuCache.isDue(at: now, cadence: base) {
            let result = await sampler.sampleCPU()
            cpuCache.record(result, at: now)
            if let result {
                freshKinds.insert(.cpu)
                cpuHistorySamples.append(MetricHistorySample(date: now, value: result.totalUsagePercent))
                cpuHistorySamples.removeAll { now.timeIntervalSince($0.date) > 300 }
            }
        }

        if memoryCache.isDue(at: now, cadence: base) {
            let result = await sampler.sampleMemory()
            memoryCache.record(result, at: now)
            if result != nil { freshKinds.insert(.memory) }
        }

        if diskCache.isDue(at: now, cadence: slowCadence) {
            let result = await sampler.sampleDisk()
            diskCache.record(result, at: now)
            if result != nil { freshKinds.insert(.disk) }
        }

        if networkCache.isDue(at: now, cadence: base) {
            let result = await sampler.sampleNetwork()
            networkCache.record(result, at: now)
            if result != nil { freshKinds.insert(.network) }
        }

        if batteryCache.isDue(at: now, cadence: slowCadence) {
            let result = await sampler.sampleBattery()
            batteryCache.record(result, at: now)
            if result != nil { freshKinds.insert(.battery) }
        }

        if processCache.isDue(at: now, cadence: processCadence, forced: reason.forcesProcessSampling) {
            let result = await sampler.sampleProcesses()
            processCache.record(result, at: now)
            if result != nil { freshKinds.insert(.processes) }
        }

        let cpu = cpuCache.presentedValue
        let memory = memoryCache.presentedValue
        let disk = diskCache.presentedValue
        let network = networkCache.presentedValue
        let battery = batteryCache.presentedValue
        let processes = ProcessSorting.filtered(processCache.presentedValue ?? [], searchText: "", sortKey: .cpu)
        let summaries = buildSummaries(
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            processes: processes,
            now: now,
            presentationStates: [
                .cpu: cpuCache.presentationState,
                .memory: memoryCache.presentationState,
                .disk: diskCache.presentationState,
                .network: networkCache.presentationState,
                .battery: batteryCache.presentationState,
                .processes: processCache.presentationState
            ],
            freshKinds: freshKinds
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
            processesAreFresh: freshKinds.contains(.processes),
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
        now: Date,
        presentationStates: [MetricKind: SamplePresentationState],
        freshKinds: Set<MetricKind>
    ) -> [MetricSummary] {
        MetricKind.allCases.map { kind in
            guard freshKinds.contains(kind) else {
                switch presentationStates[kind] ?? .unavailable {
                case .fresh:
                    return summaryCache[kind] ?? unavailableSummary(kind: kind, now: now)
                case .stale:
                    return staleSummary(kind: kind, now: now)
                case .unavailable:
                    return unavailableSummary(kind: kind, now: now)
                }
            }

            let summary: MetricSummary
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
                summary = MetricSummary(
                    kind: .cpu,
                    title: MetricKind.cpu.title,
                    valueText: MetricFormatters.percent(cpu.totalUsagePercent),
                    detailText: "User \(MetricFormatters.percent(cpu.userPercent)) / System \(MetricFormatters.percent(cpu.systemPercent))",
                    health: evaluator.debouncedHealth(for: .cpu, candidate: health),
                    updatedAt: now
                )

            case .memory:
                guard let memory else {
                    return unavailableSummary(kind: .memory, now: now)
                }
                summary = MetricSummary(
                    kind: .memory,
                    title: MetricKind.memory.title,
                    valueText: "\(MetricFormatters.compactBytes(memory.usedBytes)) / \(MetricFormatters.compactBytes(memory.totalBytes))",
                    detailText: "Free \(MetricFormatters.bytes(memory.freeBytes))",
                    health: evaluator.debouncedHealth(
                        for: .memory,
                        candidate: evaluator.memoryHealth(
                            snapshot: memory,
                            isSwapIncreasing: isMemorySwapIncreasing(memory)
                        )
                    ),
                    updatedAt: now
                )

            case .disk:
                guard let disk else {
                    return unavailableSummary(kind: .disk, now: now)
                }
                let usedRatio = 1 - disk.freeRatio
                summary = MetricSummary(
                    kind: .disk,
                    title: MetricKind.disk.title,
                    valueText: MetricFormatters.percent(usedRatio * 100),
                    detailText: "Free \(MetricFormatters.bytes(disk.freeBytes))",
                    health: evaluator.debouncedHealth(for: .disk, candidate: evaluator.diskHealth(snapshot: disk)),
                    updatedAt: now
                )

            case .network:
                guard let network else {
                    return unavailableSummary(kind: .network, now: now)
                }
                summary = MetricSummary(
                    kind: .network,
                    title: MetricKind.network.title,
                    valueText: "↓ \(MetricFormatters.compactSpeed(network.downloadBytesPerSecond))",
                    detailText: "\(network.interfaceName ?? "No interface")  ↑ \(MetricFormatters.compactSpeed(network.uploadBytesPerSecond))",
                    health: evaluator.debouncedHealth(
                        for: .network,
                        candidate: evaluator.networkHealth(snapshot: network, consecutiveFailures: 0)
                    ),
                    updatedAt: now
                )

            case .battery:
                guard let battery else {
                    return unavailableSummary(kind: .battery, now: now)
                }
                summary = MetricSummary(
                    kind: .battery,
                    title: MetricKind.battery.title,
                    valueText: battery.percentage.map { MetricFormatters.percent($0) } ?? "Unavailable",
                    detailText: battery.powerSource,
                    health: evaluator.debouncedHealth(for: .battery, candidate: evaluator.batteryHealth(snapshot: battery)),
                    updatedAt: now
                )

            case .processes:
                summary = MetricSummary(
                    kind: .processes,
                    title: MetricKind.processes.title,
                    valueText: "\(processes.count)",
                    detailText: "Running processes",
                    health: .normal,
                    updatedAt: now
                )
            }

            summaryCache[kind] = summary
            return summary
        }
    }

    private func staleSummary(kind: MetricKind, now: Date) -> MetricSummary {
        guard let summary = summaryCache[kind] else {
            return unavailableSummary(kind: kind, now: now)
        }

        let detailText = [summary.detailText, "Using last sample"].compactMap { $0 }.joined(separator: " ")
        return MetricSummary(
            kind: summary.kind,
            title: summary.title,
            valueText: summary.valueText,
            detailText: detailText,
            health: summary.health == .critical ? .critical : .warning,
            updatedAt: summary.updatedAt
        )
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

    private func isMemorySwapIncreasing(_ memory: MemorySnapshot) -> Bool {
        guard let current = memory.swapUsedBytes else {
            previousMemorySwapUsedBytes = nil
            return false
        }
        defer { previousMemorySwapUsedBytes = current }
        guard let previous = previousMemorySwapUsedBytes else { return false }
        return current > previous
    }
}

public final class DefaultSystemSampler: SystemSampler {
    private var cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let diskSampler = DiskSampler()
    private var networkSampler = NetworkSampler()
    private let batterySampler = BatterySampler()
    private let processSampler = ProcessSampler()

    public init() {}

    public func sampleCPU() async -> CPUSnapshot? {
        try? cpuSampler.sample()
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

    public func sampleProcesses() async -> [ProcessMetric]? {
        let processSampler = processSampler
        return await Task.detached(priority: .utility) {
            try? processSampler.sample()
        }.value
    }
}
