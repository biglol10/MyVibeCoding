import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct MetricListView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isSettingsSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSettingsSelected {
                SettingsView(viewModel: viewModel)
            } else {
                header
                Divider()
                content
            }
        }
        .navigationSplitViewColumnWidth(min: 360, ideal: 460, max: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PanelHeader(title: viewModel.selectedKind.title, subtitle: subtitle)

            if viewModel.showsProcessControls {
                Picker("Sort", selection: $viewModel.sortKey) {
                    ForEach(ProcessSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Toggle("Asc", isOn: $viewModel.sortAscending)
                    .toggleStyle(.checkbox)
                    .frame(width: 62)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedKind {
        case .cpu, .memory, .processes:
            processList
        case .disk:
            diskList
        case .network:
            networkList
        case .battery:
            batteryList
        }
    }

    private var processList: some View {
        VStack(spacing: 0) {
            if viewModel.showsProcessControls {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search apps, processes, PID, path", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }

            if let causeSummary = viewModel.selectedCauseSummary {
                CauseSummaryBanner(summary: causeSummary)
            }

            HStack {
                Text("App")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU")
                    .frame(width: 72, alignment: .trailing)
                Text("Memory")
                    .frame(width: 110, alignment: .trailing)
                Text("")
                    .frame(width: 40)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.vertical, 7)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(viewModel.displayedProcessGroups.prefix(60)) { group in
                        ProcessAppGroupRow(
                            group: group,
                            isSelected: viewModel.selectedProcessGroup?.id == group.id
                        ) {
                            if let process = group.processes.first {
                                viewModel.selectProcess(pid: process.pid)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }

    private var diskList: some View {
        VStack(spacing: 0) {
            if let disk = viewModel.snapshot.disk {
                InfoRow(title: disk.volumeName, value: "\(MetricFormatters.bytes(disk.freeBytes)) free")
                InfoRow(title: "Mount Point", value: disk.mountPoint)
                InfoRow(title: "Total", value: MetricFormatters.bytes(disk.totalBytes))
                if !viewModel.snapshot.diskSpaceCandidates.isEmpty {
                    Divider()
                        .padding(.vertical, 6)
                    InfoRow(title: "Space Candidates", value: "\(viewModel.snapshot.diskSpaceCandidates.count)")
                    ForEach(viewModel.snapshot.diskSpaceCandidates.prefix(4)) { candidate in
                        DiskCandidateRow(candidate: candidate)
                    }
                }
            } else {
                ContentUnavailableView("Disk Unavailable", systemImage: "internaldrive")
            }
            Spacer(minLength: 0)
        }
    }

    private var networkList: some View {
        VStack(spacing: 0) {
            if let network = viewModel.snapshot.network {
                InfoRow(title: "Interface", value: network.interfaceName ?? "Unavailable")
                InfoRow(title: "Download", value: MetricFormatters.speed(network.downloadBytesPerSecond))
                InfoRow(title: "Upload", value: MetricFormatters.speed(network.uploadBytesPerSecond))
                InfoRow(title: "Received", value: MetricFormatters.bytes(network.receivedBytes))
                InfoRow(title: "Sent", value: MetricFormatters.bytes(network.sentBytes))
            } else {
                ContentUnavailableView("Network Unavailable", systemImage: "network")
            }
            Spacer(minLength: 0)
        }
    }

    private var batteryList: some View {
        VStack(spacing: 0) {
            if let battery = viewModel.snapshot.battery, battery.isPresent {
                InfoRow(title: "Charge", value: battery.percentage.map { MetricFormatters.percent($0) } ?? "Unavailable")
                InfoRow(title: "Power Source", value: battery.powerSource)
                InfoRow(title: "Charging", value: battery.isCharging == true ? "Yes" : "No")
                InfoRow(title: "Cycle Count", value: battery.cycleCount.map(String.init) ?? "Unavailable")
            } else {
                ContentUnavailableView("Battery Unavailable", systemImage: "battery.0")
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String? {
        switch viewModel.selectedKind {
        case .cpu: "Top CPU-consuming processes"
        case .memory: "Top memory-consuming processes"
        case .disk: "Main system volume"
        case .network: "Active interface throughput"
        case .battery: "Power and charging status"
        case .processes: "Search and sort all sampled processes"
        }
    }
}
