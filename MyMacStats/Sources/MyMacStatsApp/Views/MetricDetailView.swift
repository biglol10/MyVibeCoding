import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct MetricDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isSettingsSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSettingsSelected {
                PanelHeader(title: "Settings", subtitle: "Refresh and display preferences")
                Divider()
                InfoRow(title: "Refresh Interval", value: viewModel.refreshInterval.title)
                InfoRow(title: "Menu Bar Metric", value: viewModel.selectedKind.title)
                Spacer(minLength: 0)
            } else {
                PanelHeader(title: detailTitle, subtitle: viewModel.selectedSummary?.detailText)
                Divider()
                detailContent
            }
        }
        .navigationSplitViewColumnWidth(min: 360, ideal: 430, max: 520)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedKind {
        case .cpu:
            cpuDetail
        case .memory:
            memoryDetail
        case .disk:
            diskDetail
        case .network:
            networkDetail
        case .battery:
            batteryDetail
        case .processes:
            processDetail
        }
    }

    private var cpuDetail: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let cpu = viewModel.snapshot.cpu {
                    InfoRow(title: "Total", value: MetricFormatters.percent(cpu.totalUsagePercent), valueColor: viewModel.selectedSummary?.health.statusColor ?? .primary)
                    InfoRow(title: "User", value: MetricFormatters.percent(cpu.userPercent))
                    InfoRow(title: "System", value: MetricFormatters.percent(cpu.systemPercent))
                    InfoRow(title: "Idle", value: MetricFormatters.percent(cpu.idlePercent))
                    Picker("History", selection: $viewModel.historyRange) {
                        ForEach(HistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    SparklineView(values: viewModel.displayedCPUHistory)
                        .frame(height: 76)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ContentUnavailableView("CPU Unavailable", systemImage: "cpu")
                }
                processDetail
            }
        }
    }

    private var memoryDetail: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let memory = viewModel.snapshot.memory {
                    if let causeSummary = viewModel.selectedCauseSummary {
                        InfoRow(title: "Likely Cause", value: causeSummary.message, valueColor: viewModel.selectedSummary?.health.statusColor ?? .primary)
                    }
                    InfoRow(title: "Used", value: MetricFormatters.bytes(memory.usedBytes))
                    InfoRow(title: "Free", value: MetricFormatters.bytes(memory.freeBytes))
                    InfoRow(title: "Compressed", value: memory.compressedBytes.map(MetricFormatters.bytes) ?? "Unavailable")
                    InfoRow(title: "Cached", value: memory.cachedBytes.map(MetricFormatters.bytes) ?? "Unavailable")
                    InfoRow(title: "Swap", value: memory.swapUsedBytes.map(MetricFormatters.bytes) ?? "Unavailable")
                    InfoRow(title: "Pressure", value: String(describing: memory.pressure).capitalized)
                } else {
                    ContentUnavailableView("RAM Unavailable", systemImage: "memorychip")
                }
                processDetail
            }
        }
    }

    private var diskDetail: some View {
        VStack(spacing: 0) {
            if let disk = viewModel.snapshot.disk {
                InfoRow(title: "Volume", value: disk.volumeName)
                InfoRow(title: "Used", value: MetricFormatters.bytes(disk.totalBytes - disk.freeBytes))
                InfoRow(title: "Free", value: MetricFormatters.bytes(disk.freeBytes), valueColor: viewModel.selectedSummary?.health.statusColor ?? .primary)
                InfoRow(title: "Read", value: disk.readBytesPerSecond.map(MetricFormatters.speed) ?? "Unavailable")
                InfoRow(title: "Write", value: disk.writeBytesPerSecond.map(MetricFormatters.speed) ?? "Unavailable")
                if !viewModel.snapshot.diskSpaceCandidates.isEmpty {
                    Divider()
                        .padding(.vertical, 6)
                    InfoRow(title: "Space Candidates", value: "\(viewModel.snapshot.diskSpaceCandidates.count)")
                    ForEach(viewModel.snapshot.diskSpaceCandidates.prefix(6)) { candidate in
                        DiskCandidateRow(candidate: candidate)
                    }
                }
            } else {
                ContentUnavailableView("Disk Unavailable", systemImage: "internaldrive")
            }
            Spacer(minLength: 0)
        }
    }

    private var networkDetail: some View {
        VStack(spacing: 0) {
            if let network = viewModel.snapshot.network {
                InfoRow(title: "Interface", value: network.interfaceName ?? "Unavailable")
                InfoRow(title: "Status", value: network.isConnected ? "Connected" : "Disconnected", valueColor: viewModel.selectedSummary?.health.statusColor ?? .primary)
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

    private var batteryDetail: some View {
        VStack(spacing: 0) {
            if let battery = viewModel.snapshot.battery, battery.isPresent {
                InfoRow(title: "Charge", value: battery.percentage.map { MetricFormatters.percent($0) } ?? "Unavailable", valueColor: viewModel.selectedSummary?.health.statusColor ?? .primary)
                InfoRow(title: "Power Source", value: battery.powerSource)
                InfoRow(title: "Charging", value: battery.isCharging == true ? "Yes" : "No")
                InfoRow(title: "Time Remaining", value: battery.timeRemainingMinutes.map { "\($0)m" } ?? "Unavailable")
                InfoRow(title: "Cycle Count", value: battery.cycleCount.map(String.init) ?? "Unavailable")
                InfoRow(title: "Service", value: battery.serviceRecommended ? "Recommended" : "OK")
            } else {
                ContentUnavailableView("Battery Unavailable", systemImage: "battery.0")
            }
            Spacer(minLength: 0)
        }
    }

    private var processDetail: some View {
        VStack(spacing: 0) {
            if let group = viewModel.selectedProcessGroup, let process = viewModel.selectedProcess {
                let terminationTarget = group.id.hasPrefix("app:") || group.processes.count > 1 ? "App" : "Process"
                InfoRow(title: "App", value: group.name)
                InfoRow(title: "Processes", value: "\(group.processes.count)")
                InfoRow(title: "Total CPU", value: MetricFormatters.percent(group.cpuPercent, fractionDigits: group.cpuPercent < 10 ? 1 : 0))
                InfoRow(title: "Total Memory", value: MetricFormatters.bytes(group.memoryBytes))
                Divider()
                    .padding(.vertical, 6)
                if let terminationMessage = viewModel.selectedProcessTerminationMessage {
                    InfoRow(title: "Status", value: terminationMessage, valueColor: .secondary)
                }
                InfoRow(title: "Process", value: process.name)
                InfoRow(title: "PID", value: "\(process.pid)")
                InfoRow(title: "CPU", value: MetricFormatters.percent(process.cpuPercent, fractionDigits: process.cpuPercent < 10 ? 1 : 0))
                InfoRow(title: "Memory", value: MetricFormatters.bytes(process.memoryBytes))
                InfoRow(title: "Path", value: process.path ?? "Unavailable")
                InfoRow(title: "Bundle ID", value: process.bundleIdentifier ?? "Unavailable")
                Button(role: .destructive) {
                    viewModel.requestTermination(for: process)
                } label: {
                    Label("Quit \(terminationTarget)", systemImage: "xmark.octagon")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.selectedProcessTerminationAvailability.isAllowed)
                .help(viewModel.selectedProcessTerminationAvailability.reason ?? "Quit selected \(terminationTarget.lowercased())")
                .padding(.horizontal, 16)
                .padding(.top, 10)
                if viewModel.selectedProcessCanForceQuit {
                    Button(role: .destructive) {
                        viewModel.requestForceTermination(for: process)
                    } label: {
                        Label("Force Quit \(terminationTarget)", systemImage: "exclamationmark.octagon")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                if group.processes.count > 1 {
                    Divider()
                        .padding(.vertical, 8)
                    ForEach(group.processes.prefix(6)) { child in
                        Button {
                            viewModel.selectProcess(pid: child.pid)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text("PID \(child.pid)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MetricFormatters.percent(child.cpuPercent, fractionDigits: child.cpuPercent < 10 ? 1 : 0))
                                    .monospacedDigit()
                                Text(MetricFormatters.bytes(child.memoryBytes))
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ContentUnavailableView("No Process Selected", systemImage: "list.bullet.rectangle")
            }
            Spacer(minLength: 0)
        }
    }

    private var detailTitle: String {
        switch viewModel.selectedKind {
        case .cpu: "CPU Details"
        case .memory: "RAM Details"
        case .disk: "Disk Details"
        case .network: "Network Details"
        case .battery: "Battery Details"
        case .processes: "Process Details"
        }
    }
}
