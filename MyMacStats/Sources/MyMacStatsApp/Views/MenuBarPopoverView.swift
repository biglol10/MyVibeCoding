import SwiftUI
import AppKit
import MyMacStatsAppSupport
import MyMacStatsCore

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MyMacStats")
                .font(.headline.weight(.semibold))

            VStack(spacing: 6) {
                summaryRow(.cpu)
                summaryRow(.memory)
                summaryRow(.disk)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Top Culprits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(viewModel.displayedProcessGroups.prefix(3)) { group in
                    HStack(spacing: 8) {
                        Text(group.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(MetricFormatters.percent(group.cpuPercent, fractionDigits: group.cpuPercent < 10 ? 1 : 0))
                            .monospacedDigit()
                        Text(MetricFormatters.bytes(group.memoryBytes))
                            .monospacedDigit()
                            .frame(width: 82, alignment: .trailing)
                    }
                    .font(.caption.weight(.medium))
                }
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            } label: {
                Label("Open Dashboard", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(width: 320)
        .preferredColorScheme(.dark)
        .task {
            viewModel.start()
        }
    }

    private func summaryRow(_ kind: MetricKind) -> some View {
        let summary = viewModel.snapshot.summary(for: kind)
        return HStack(spacing: 8) {
            Circle()
                .fill((summary?.health ?? .unavailable).dotColor)
                .frame(width: 7, height: 7)
            Text(kind.title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(summary?.valueText ?? "Unavailable")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle((summary?.health ?? .unavailable).statusColor)
        }
    }
}
