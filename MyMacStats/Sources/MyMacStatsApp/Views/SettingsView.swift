import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Settings", subtitle: "Monitoring preferences")
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Refresh Interval")
                    .font(.callout.weight(.semibold))
                Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(16)

            Divider()

            InfoRow(title: "Menu Bar Display", value: "CPU + RAM")
            InfoRow(title: "Dock Icon", value: "Visible")
            InfoRow(title: "Appearance", value: "Follows macOS")
            Divider()
            InfoRow(title: "CPU, RAM, Network", value: viewModel.refreshInterval.title)
            InfoRow(title: "Processes", value: "\(max(2, viewModel.refreshInterval.rawValue))s")
            InfoRow(title: "Disk, Battery", value: "\(max(10, viewModel.refreshInterval.rawValue))s")
            InfoRow(title: "Disk Space Candidates", value: "60s or Scan Again")
            Spacer(minLength: 0)
        }
    }
}
