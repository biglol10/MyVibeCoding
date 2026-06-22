import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct SidebarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isSettingsSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MyMacStats")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(MetricKind.allCases) { kind in
                        sidebarButton(for: kind)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    Button {
                        isSettingsSelected = true
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "gearshape")
                                .frame(width: 20)
                            Text("Settings")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                        .background(isSettingsSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background(Color.primary.opacity(0.025))
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }

    private func sidebarButton(for kind: MetricKind) -> some View {
        let summary = viewModel.snapshot.summary(for: kind)
        let isSelected = viewModel.selectedKind == kind && !isSettingsSelected
        let health = summary?.health ?? .unavailable

        return Button {
            isSettingsSelected = false
            viewModel.select(kind)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(health.dotColor)
                    .frame(width: 7, height: 7)

                Image(systemName: kind.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(health.statusColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(kind.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        Text(summary?.valueText ?? "Unavailable")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(health.statusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }

                    if let detail = summary?.detailText {
                        Text(detail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
