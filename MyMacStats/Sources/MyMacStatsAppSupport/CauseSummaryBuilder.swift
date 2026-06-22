import Foundation
import MyMacStatsCore

public struct CauseSummary: Equatable, Sendable {
    public let title: String
    public let message: String
    public let health: HealthState

    public init(title: String, message: String, health: HealthState) {
        self.title = title
        self.message = message
        self.health = health
    }
}

public enum CauseSummaryBuilder {
    public static func summary(for kind: MetricKind, snapshot: SystemMetricsSnapshot) -> CauseSummary? {
        guard let metricSummary = snapshot.summary(for: kind),
              metricSummary.health == .warning || metricSummary.health == .critical
        else {
            return nil
        }

        switch kind {
        case .cpu:
            guard let topGroup = ProcessGrouping.groups(snapshot.processes, searchText: "", sortKey: .cpu).first else {
                return nil
            }
            return CauseSummary(
                title: "CPU \(metricSummary.health.label)",
                message: "\(topGroup.name) is using \(MetricFormatters.percent(topGroup.cpuPercent, fractionDigits: topGroup.cpuPercent < 10 ? 1 : 0)) CPU.",
                health: metricSummary.health
            )

        case .memory:
            guard let topGroup = ProcessGrouping.groups(snapshot.processes, searchText: "", sortKey: .memory).first else {
                return nil
            }
            var message = "\(topGroup.name) is using \(MetricFormatters.bytes(topGroup.memoryBytes))."
            if let swapUsedBytes = snapshot.memory?.swapUsedBytes, swapUsedBytes > 0 {
                message += " Swap is \(MetricFormatters.bytes(swapUsedBytes))."
            }
            return CauseSummary(
                title: "RAM \(metricSummary.health.label)",
                message: message,
                health: metricSummary.health
            )

        case .disk:
            guard let disk = snapshot.disk else { return nil }
            return CauseSummary(
                title: "Disk \(metricSummary.health.label)",
                message: "\(MetricFormatters.bytes(disk.freeBytes)) free on \(disk.volumeName).",
                health: metricSummary.health
            )

        case .network, .battery, .processes:
            return nil
        }
    }
}

private extension HealthState {
    var label: String {
        switch self {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        case .unavailable: "unavailable"
        }
    }
}
