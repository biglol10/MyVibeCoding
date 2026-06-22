import SwiftUI
import MyMacStatsCore

extension HealthState {
    var statusColor: Color {
        switch self {
        case .normal: .primary
        case .warning: .yellow
        case .critical: .red
        case .unavailable: .secondary
        }
    }

    var dotColor: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        case .unavailable: .gray
        }
    }
}

struct PanelHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ProcessMetricRow: View {
    let process: ProcessMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(process.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .gridCellColumns(2)

                    Text(MetricFormatters.percent(process.cpuPercent, fractionDigits: process.cpuPercent < 10 ? 1 : 0))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text(MetricFormatters.bytes(process.memoryBytes))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
