import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct MetricListView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            processList
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

    private var processList: some View {
        let groups = viewModel.displayedProcessGroups
        let selectedGroupID = viewModel.selectedProcessGroup?.id
        return VStack(spacing: 0) {
            if viewModel.showsProcessControls {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search apps, processes, PID, path", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button { viewModel.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .help("Clear search")
                    }
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
                Text("App / Process")
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

            HStack {
                Text("\(groups.count) \(groups.count == 1 ? "group" : "groups") · \(groups.reduce(0) { $0 + $1.processes.count }) processes")
                Spacer()
                Image(systemName: "info.circle")
                    .help("Total CPU uses all cores as 100%. Each process uses one core as 100%, so process CPU can exceed 100%.")
                    .accessibilityLabel("Process CPU uses one core as 100 percent")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if groups.isEmpty {
                ContentUnavailableView {
                    Label(viewModel.searchText.isEmpty ? "No Processes Available" : "No Search Results", systemImage: "magnifyingglass")
                } description: {
                    Text(viewModel.searchText.isEmpty ? "Waiting for a process sample." : "Try an app name, process name, or PID.")
                } actions: {
                    if !viewModel.searchText.isEmpty {
                        Button("Clear Search") { viewModel.searchText = "" }
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(groups) { group in
                        ProcessAppGroupRow(
                            group: group,
                            isSelected: selectedGroupID == group.id
                        ) {
                            viewModel.selectProcessGroup(group)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
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
