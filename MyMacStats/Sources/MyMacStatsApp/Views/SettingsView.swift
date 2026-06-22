import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Settings", subtitle: "MVP refresh controls")
            Divider()

            HStack {
                Text("Refresh Interval")
                    .font(.callout.weight(.semibold))
                Spacer()
                Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(16)

            Divider()

            InfoRow(title: "Menu Bar Metric", value: viewModel.selectedKind.title)
            InfoRow(title: "Dock Icon", value: "Always visible in MVP")
            Spacer(minLength: 0)
        }
    }
}
