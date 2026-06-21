import SwiftUI
import MyMacCleanCore
import MyMacCleanAppSupport

struct ContentView: View {
    @State private var viewModel = ApplicationListViewModel()
    @State private var historyViewModel = DeleteHistoryViewModel()
    @State private var orphanFilesViewModel = OrphanFilesViewModel(installedApps: [])
    @State private var navigationState = SidebarNavigationState()
    @State private var confirmationText = ""
    @State private var showsConfirmation = false
    @State private var confirmationMode: DeletionConfirmationMode = .application

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .task {
            await viewModel.loadApps()
            orphanFilesViewModel.updateInstalledApps(viewModel.apps)
        }
        .alert("MyMacClean", isPresented: Binding(
            get: {
                viewModel.errorMessage != nil
                    || historyViewModel.errorMessage != nil
                    || orphanFilesViewModel.errorMessage != nil
            },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    historyViewModel.errorMessage = nil
                    orphanFilesViewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
                historyViewModel.errorMessage = nil
                orphanFilesViewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? historyViewModel.errorMessage ?? orphanFilesViewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showsConfirmation) {
            confirmationSheet
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("Current Release", destinations: SidebarDestination.currentRelease)
                sidebarSection("Roadmap", destinations: SidebarDestination.roadmap)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
        }
        .background(Color.primary.opacity(0.025))
        .navigationTitle("MyMacClean")
    }

    private func sidebarSection(_ title: String, destinations: [SidebarDestination]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            ForEach(destinations) { destination in
                SidebarDestinationRow(
                    destination: destination,
                    isSelected: activeSection == destination
                ) {
                    navigationState.select(destination)
                }
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch activeSection {
        case .applications:
            appList
        case .orphanFiles:
            orphanFilesContent
        case .deleteHistory:
            deleteHistoryContent
        default:
            featureContent(for: activeSection)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch activeSection {
        case .applications:
            inspector
        case .orphanFiles:
            orphanFilesDetail
        case .deleteHistory:
            deleteHistoryDetail
        default:
            featureDetail(for: activeSection)
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Applications")
                        .font(.title2.weight(.semibold))
                    Text("Review installed apps and related files before permanent deletion.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(SidebarDestination.applications.primaryActionTitle) {
                    Task { await viewModel.scanSelectedApp() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedApp == nil || viewModel.isScanning)
            }
            .padding()

            Table(viewModel.apps, selection: Binding(
                get: { viewModel.selectedApp?.id },
                set: { newID in viewModel.selectApp(id: newID) }
            )) {
                TableColumn("Name") { app in
                    Text(app.displayName)
                }
                TableColumn("Bundle ID") { app in
                    Text(app.bundleIdentifier ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Size") { app in
                    SizeText(bytes: app.bundleSize)
                }
            }
        }
    }

    private func featureContent(for destination: SidebarDestination) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(destination.title)
                        .font(.title2.weight(.semibold))
                    Text(destination.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(destination.primaryActionTitle) {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
            .padding()

            Divider()

            ContentUnavailableView(destination.title, systemImage: destination.systemImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var deleteHistoryContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete History")
                        .font(.title2.weight(.semibold))
                    Text("Verified deletion receipts, remaining files, and failed cleanup attempts.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(SidebarDestination.deleteHistory.primaryActionTitle) {
                    Task { await historyViewModel.load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by app, bundle ID, or path", text: $historyViewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if historyViewModel.filteredReceipts.isEmpty {
                ContentUnavailableView("No Delete History", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyViewModel.filteredReceipts) { receipt in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(receipt.appName)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(deletionStatusTitle(for: receipt))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(deletionStatusColor(for: receipt))
                        }

                        Text(receipt.bundleIdentifier ?? receipt.bundlePath)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 12) {
                            Text(receipt.completedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("\(receipt.selectedCandidates.count) items")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .task {
            await historyViewModel.load()
        }
    }

    private var orphanFilesContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Orphan Files")
                        .font(.title2.weight(.semibold))
                    Text("Find leftovers from apps that are no longer installed.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(SidebarDestination.orphanFiles.primaryActionTitle) {
                    orphanFilesViewModel.updateInstalledApps(viewModel.apps)
                    Task { await orphanFilesViewModel.loadGroups() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(orphanFilesViewModel.isScanning)
            }
            .padding()

            Divider()

            if orphanFilesViewModel.groups.isEmpty {
                ContentUnavailableView("No Orphan Files", systemImage: "folder.badge.questionmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(orphanFilesViewModel.groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.inferredIdentifier)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            SizeText(bytes: group.totalSize)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(group.candidates.count) related leftovers")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func featureDetail(for destination: SidebarDestination) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(destination.title)
                    .font(.title2.weight(.semibold))
                Text(destination.subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ContentUnavailableView("Not Available", systemImage: destination.systemImage)

            Spacer()

            Button {} label: {
                HStack(spacing: 14) {
                    Image(systemName: destination.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(destination.primaryActionTitle)
                            .font(.headline.weight(.semibold))
                        Text("Available in a later build")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Color.primary.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(22)
    }

    private var deleteHistoryDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("History Details")
                    .font(.title2.weight(.semibold))
                Text("\(historyViewModel.filteredReceipts.count) receipts shown")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(historyViewModel.filteredReceipts) { receipt in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(receipt.appName)
                                        .font(.headline.weight(.semibold))
                                    Text(receipt.completedAt.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(deletionStatusTitle(for: receipt))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(deletionStatusColor(for: receipt))
                            }

                            Text(receipt.bundlePath)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)

                            HStack(spacing: 18) {
                                HistoryMetric(title: "Selected", value: "\(receipt.selectedCandidates.count)")
                                HistoryMetric(title: "Deleted", value: "\(deletedCount(for: receipt))")
                                HistoryMetric(title: "Remaining", value: "\(remainingCount(for: receipt))")
                            }

                            if remainingCount(for: receipt) > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remaining Paths")
                                        .font(.callout.weight(.semibold))
                                    ForEach(remainingPaths(for: receipt), id: \.self) { path in
                                        Text(path)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }

            Button(role: .destructive) {
                historyViewModel.clearHistory()
            } label: {
                Label("Clear Delete History", systemImage: "trash")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(historyViewModel.receipts.isEmpty)
        }
        .padding(22)
    }

    private var orphanFilesDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Orphan Files")
                    .font(.title2.weight(.semibold))
                Text("\(orphanFilesViewModel.groups.count) groups, \(orphanFilesViewModel.selectedCandidates.count) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let report = orphanFilesViewModel.deletionReport {
                DeletionReportPanel(report: report)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(orphanFilesViewModel.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(group.inferredIdentifier)
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                SizeText(bytes: group.totalSize)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(group.candidates) { candidate in
                                RelatedFileRow(
                                    candidate: candidate,
                                    isSelected: orphanFilesViewModel.selectedCandidateIDs.contains(candidate.id),
                                    toggle: {
                                        toggleOrphanCandidate(candidate.id)
                                    }
                                )
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }

            DeleteActionButton(
                selectedCount: orphanFilesViewModel.selectedCandidates.count,
                selectedBytes: orphanFilesViewModel.selectedBytes
            ) {
                confirmationMode = .orphanFiles
                confirmationText = ""
                showsConfirmation = true
            }
        }
        .padding(22)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let app = viewModel.selectedApp {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.displayName)
                        .font(.title2.weight(.semibold))
                    Text(app.bundleIdentifier ?? app.bundleURL.path)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("App Bundle")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        SizeText(bytes: app.bundleSize)
                            .font(.title3.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Related Items")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.candidates.count)")
                            .font(.title3.weight(.bold))
                    }
                }
                Divider()
                if let report = viewModel.deletionReport {
                    DeletionReportPanel(report: report)
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.candidates) { candidate in
                            RelatedFileRow(
                                candidate: candidate,
                                isSelected: viewModel.selectedCandidateIDs.contains(candidate.id),
                                toggle: {
                                    if viewModel.selectedCandidateIDs.contains(candidate.id) {
                                        viewModel.selectedCandidateIDs.remove(candidate.id)
                                    } else {
                                        viewModel.selectedCandidateIDs.insert(candidate.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                DeleteActionButton(
                    selectedCount: selectedCandidates.count,
                    selectedBytes: selectedCandidateBytes
                ) {
                    confirmationMode = .application
                    confirmationText = ""
                    showsConfirmation = true
                }
            } else {
                ContentUnavailableView("No App Selected", systemImage: "app.dashed")
            }
        }
        .padding(22)
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            let requiredConfirmation = "DELETE"
            Text("Permanent Deletion")
                .font(.title2.weight(.semibold))
            Text("Type DELETE to permanently remove selected items. This does not move files to Trash.")
                .foregroundStyle(.secondary)
            TextField(requiredConfirmation, text: $confirmationText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showsConfirmation = false }
                Spacer()
                Button("Delete", role: .destructive) {
                    Task {
                        switch confirmationMode {
                        case .application:
                            await viewModel.deleteConfirmedItems(confirmation: confirmationText)
                        case .orphanFiles:
                            await orphanFilesViewModel.deleteSelectedLeftovers(confirmation: confirmationText)
                        }
                        showsConfirmation = false
                    }
                }
                .disabled(confirmationText != requiredConfirmation)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private var selectedCandidates: [RelatedFileCandidate] {
        viewModel.candidates.filter { viewModel.selectedCandidateIDs.contains($0.id) }
    }

    private var selectedCandidateBytes: Int64 {
        selectedCandidates.reduce(Int64(0)) { $0 + $1.size }
    }

    private var activeSection: SidebarDestination {
        navigationState.selectedDestination
    }

    private func deletionStatusTitle(for receipt: DeletionReceipt) -> String {
        if receipt.verificationResults.contains(where: { $0.status == .stillExists || $0.status == .permissionDenied }) {
            return "Needs Review"
        }
        if receipt.executionResults.contains(where: { !$0.success }) {
            return "Failed"
        }
        return "Verified"
    }

    private func deletionStatusColor(for receipt: DeletionReceipt) -> Color {
        switch deletionStatusTitle(for: receipt) {
        case "Verified": Color.green
        case "Failed": Color.red
        default: Color.orange
        }
    }

    private func deletedCount(for receipt: DeletionReceipt) -> Int {
        receipt.verificationResults.filter { $0.status == .deleted }.count
    }

    private func remainingCount(for receipt: DeletionReceipt) -> Int {
        receipt.verificationResults.filter { $0.status == .stillExists || $0.status == .permissionDenied }.count
    }

    private func remainingPaths(for receipt: DeletionReceipt) -> [String] {
        receipt.verificationResults
            .filter { $0.status == .stillExists || $0.status == .permissionDenied }
            .map(\.path)
    }

    private func toggleOrphanCandidate(_ id: RelatedFileCandidate.ID) {
        if orphanFilesViewModel.selectedCandidateIDs.contains(id) {
            orphanFilesViewModel.selectedCandidateIDs.remove(id)
        } else {
            orphanFilesViewModel.selectedCandidateIDs.insert(id)
        }
    }
}

private enum DeletionConfirmationMode {
    case application
    case orphanFiles
}

private struct DeletionReportPanel: View {
    let report: DeletionReportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.statusTitle)
                .font(.headline.weight(.semibold))
            Text("\(report.deletedCount) deleted, \(report.remainingCount) remaining")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(report.remainingPaths, id: \.self) { path in
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
