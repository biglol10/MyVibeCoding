import SwiftUI
import MyMacStatsAppSupport
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
                .truncationMode(.middle)
                .lineLimit(2)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct CauseSummaryBanner: View {
    let summary: CauseSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(summary.health.dotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.callout.weight(.semibold))
                Text(summary.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(summary.health.statusColor.opacity(0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(summary.health.statusColor.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct ProcessAppGroupRow: View {
    let group: ProcessAppGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.processes.count) process\(group.processes.count == 1 ? "" : "es")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(MetricFormatters.percent(group.cpuPercent, fractionDigits: group.cpuPercent < 10 ? 1 : 0))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 72, alignment: .trailing)

                Text(MetricFormatters.bytes(group.memoryBytes))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 110, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.028))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.05), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DiskCandidateRow: View {
    let candidate: DiskSpaceCandidate

    var body: some View {
        InfoRow(title: candidate.title, value: MetricFormatters.bytes(candidate.sizeBytes))
            .help(candidate.path)
    }
}

struct ProcessMetricRow: View {
    let process: ProcessMetric
    let isSelected: Bool
    let terminationAvailability: ProcessTerminationAvailability
    let action: () -> Void
    let terminate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(process.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("PID \(process.pid)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(MetricFormatters.percent(process.cpuPercent, fractionDigits: process.cpuPercent < 10 ? 1 : 0))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 72, alignment: .trailing)

                    Text(MetricFormatters.bytes(process.memoryBytes))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: terminate) {
                Image(systemName: "xmark.octagon")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(terminationAvailability.isAllowed ? Color.red.opacity(0.9) : Color.secondary.opacity(0.55))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!terminationAvailability.isAllowed)
            .accessibilityLabel(terminationAvailability.isAllowed ? "Quit process" : "Process protected")
            .accessibilityHint(terminationAvailability.reason ?? "Requests confirmation before quitting this process")
            .help(terminationAvailability.isAllowed ? "Quit process" : (terminationAvailability.reason ?? "Cannot quit this process"))
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.028))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.05), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
