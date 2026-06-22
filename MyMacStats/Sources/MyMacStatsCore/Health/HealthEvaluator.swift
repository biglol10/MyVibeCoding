import Foundation

public struct HealthEvaluator: Sendable {
    public var cpuWarningThreshold: Double
    public var cpuCriticalThreshold: Double
    public var cpuSustainedSeconds: TimeInterval
    public var memoryWarningRatio: Double
    public var memoryCriticalRatio: Double
    public var diskWarningFreeRatio: Double
    public var diskCriticalFreeRatio: Double
    public var debounceSamples: Int

    private var appliedStates: [MetricKind: HealthState]
    private var pendingStates: [MetricKind: PendingState]

    public init(
        cpuWarningThreshold: Double = 70,
        cpuCriticalThreshold: Double = 90,
        cpuSustainedSeconds: TimeInterval = 10,
        memoryWarningRatio: Double = 0.8,
        memoryCriticalRatio: Double = 0.9,
        diskWarningFreeRatio: Double = 0.2,
        diskCriticalFreeRatio: Double = 0.1,
        debounceSamples: Int = 2
    ) {
        self.cpuWarningThreshold = cpuWarningThreshold
        self.cpuCriticalThreshold = cpuCriticalThreshold
        self.cpuSustainedSeconds = cpuSustainedSeconds
        self.memoryWarningRatio = memoryWarningRatio
        self.memoryCriticalRatio = memoryCriticalRatio
        self.diskWarningFreeRatio = diskWarningFreeRatio
        self.diskCriticalFreeRatio = diskCriticalFreeRatio
        self.debounceSamples = debounceSamples
        self.appliedStates = [:]
        self.pendingStates = [:]
    }

    public func cpuHealth(usagePercent: Double, sustainedSecondsAboveThreshold: TimeInterval) -> HealthState {
        guard sustainedSecondsAboveThreshold >= cpuSustainedSeconds else { return .normal }
        if usagePercent >= cpuCriticalThreshold {
            return .critical
        }
        if usagePercent >= cpuWarningThreshold {
            return .warning
        }
        return .normal
    }

    public func memoryHealth(snapshot: MemorySnapshot, isSwapIncreasing: Bool = false) -> HealthState {
        guard snapshot.totalBytes > 0 else { return .unavailable }

        if snapshot.pressure == .critical || snapshot.usageRatio >= memoryCriticalRatio || isSwapIncreasing {
            return .critical
        }
        if snapshot.pressure == .warning || snapshot.usageRatio >= memoryWarningRatio {
            return .warning
        }
        if snapshot.pressure == .unavailable {
            return .unavailable
        }
        return .normal
    }

    public func diskHealth(snapshot: DiskSnapshot) -> HealthState {
        guard snapshot.totalBytes > 0 else { return .unavailable }
        if snapshot.freeRatio < diskCriticalFreeRatio {
            return .critical
        }
        if snapshot.freeRatio < diskWarningFreeRatio {
            return .warning
        }
        return .normal
    }

    public func batteryHealth(snapshot: BatterySnapshot) -> HealthState {
        guard snapshot.isPresent, let percentage = snapshot.percentage else {
            return .unavailable
        }
        if snapshot.serviceRecommended || percentage <= 10 {
            return .critical
        }
        if percentage <= 20 {
            return .warning
        }
        return .normal
    }

    public func networkHealth(snapshot: NetworkSnapshot?, consecutiveFailures: Int) -> HealthState {
        guard consecutiveFailures < 2, let snapshot else {
            return .unavailable
        }
        if snapshot.interfaceName == nil || !snapshot.isConnected || consecutiveFailures == 1 {
            return .warning
        }
        return .normal
    }

    public mutating func debouncedHealth(for kind: MetricKind, candidate: HealthState) -> HealthState {
        let current = appliedStates[kind] ?? .normal
        guard candidate != current else {
            pendingStates[kind] = nil
            appliedStates[kind] = current
            return current
        }

        guard debounceSamples > 1 else {
            appliedStates[kind] = candidate
            pendingStates[kind] = nil
            return candidate
        }

        var pending = pendingStates[kind] ?? PendingState(state: candidate, count: 0)
        if pending.state == candidate {
            pending.count += 1
        } else {
            pending = PendingState(state: candidate, count: 1)
        }

        if pending.count >= debounceSamples {
            appliedStates[kind] = candidate
            pendingStates[kind] = nil
            return candidate
        }

        pendingStates[kind] = pending
        return current
    }
}

private struct PendingState: Sendable {
    var state: HealthState
    var count: Int
}
