import AppKit
import SwiftUI
import MyMacCleanCore
import MyMacCleanAppSupport

struct ContentView: View {
    @State private var viewModel = ApplicationListViewModel()
    @State private var historyViewModel = DeleteHistoryViewModel()
    @State private var orphanFilesViewModel = OrphanFilesViewModel(installedApps: [])
    @State private var navigationState = SidebarNavigationState()
    @State private var confirmationText = ""
    @State private var confirmationMode: DeletionConfirmationMode?
    @State private var forceDelete = false

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
        .sheet(item: $confirmationMode) { mode in
            confirmationSheet(for: mode)
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
                Button {
                    Task { await refreshApplications() }
                } label: {
                    Label("Refresh Applications", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .help("Refresh Applications")
                .disabled(viewModel.isLoadingApps || viewModel.isScanning || viewModel.isDeleting)

                Button(viewModel.isScanning ? "Scanning..." : SidebarDestination.applications.primaryActionTitle) {
                    Task { await viewModel.scanSelectedApp() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedApp == nil || viewModel.isScanning || viewModel.isLoadingApps || viewModel.isDeleting)
            }
            .padding()

            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search applications, bundle IDs, or paths", text: $viewModel.appSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Picker("Filter", selection: $viewModel.appFilter) {
                        ForEach(ApplicationListFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()

                    Picker("Sort", selection: $viewModel.appSort) {
                        ForEach(ApplicationListSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if viewModel.isLoadingApps && viewModel.apps.isEmpty {
                ProgressView("Loading Applications")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.hasLoadedApps && viewModel.apps.isEmpty {
                ContentUnavailableView("No Applications Found", systemImage: "app.dashed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visibleApps.isEmpty {
                ContentUnavailableView("No Matching Applications", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.visibleApps, selection: Binding(
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
                List(historyViewModel.filteredReceipts, selection: Binding(
                    get: { historyViewModel.selectedReceiptID },
                    set: { historyViewModel.selectReceipt(id: $0) }
                )) { receipt in
                    let summary = DeletionHistoryReceiptSummary(receipt: receipt)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(receipt.appName)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(summary.statusTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(deletionStatusColor(for: summary.status))
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
                Button(orphanFilesViewModel.isScanning ? "Scanning..." : SidebarDestination.orphanFiles.primaryActionTitle) {
                    orphanFilesViewModel.updateInstalledApps(viewModel.apps)
                    Task { await orphanFilesViewModel.loadGroups() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(orphanFilesViewModel.isScanning || orphanFilesViewModel.isDeleting)
            }
            .padding()

            Divider()

            if orphanFilesViewModel.isScanning {
                ProgressView("Scanning Leftovers")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !orphanFilesViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Leftovers",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Run a scan to find leftovers from apps that are no longer installed.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if orphanFilesViewModel.groups.isEmpty {
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
                Text(historyViewModel.selectedReceipt.map { $0.completedAt.formatted(date: .abbreviated, time: .standard) } ?? "\(historyViewModel.filteredReceipts.count) receipts shown")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let receipt = historyViewModel.selectedReceipt {
                        historyReceiptDetailCard(receipt)
                    } else {
                        ContentUnavailableView("No Receipt Selected", systemImage: "clock")
                            .frame(maxWidth: .infinity, minHeight: 280)
                    }
                }
                .padding(.vertical, 2)
            }

            Button(role: .destructive) {
                historyViewModel.requestClearHistory()
            } label: {
                Label("Clear Delete History", systemImage: "trash")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(historyViewModel.receipts.isEmpty)
        }
        .padding(22)
        .confirmationDialog(
            "Clear Delete History?",
            isPresented: Binding(
                get: { historyViewModel.isClearHistoryConfirmationPresented },
                set: { isPresented in
                    if !isPresented {
                        historyViewModel.cancelClearHistory()
                    }
                }
            )
        ) {
            Button("Clear Delete History", role: .destructive) {
                historyViewModel.confirmClearHistory()
            }
            Button("Cancel", role: .cancel) {
                historyViewModel.cancelClearHistory()
            }
        } message: {
            Text("This removes local deletion receipts. It does not restore deleted files.")
        }
    }

    private func historyReceiptDetailCard(_ receipt: DeletionReceipt) -> some View {
        let summary = DeletionHistoryReceiptSummary(receipt: receipt)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.appName)
                        .font(.headline.weight(.semibold))
                    Text(receipt.completedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyToPasteboard(DeletionReportViewModel(receipt: receipt).copyableReportText)
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy Report")
                Text(summary.statusTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(deletionStatusColor(for: summary.status))
            }

            Text(receipt.bundlePath)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 18) {
                HistoryMetric(title: "Selected", value: "\(receipt.selectedCandidates.count)")
                HistoryMetric(title: "Deleted", value: "\(summary.deletedCount)")
                HistoryMetric(title: "Remaining", value: "\(summary.remainingCount)")
            }

            if summary.remainingCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remaining Paths")
                        .font(.callout.weight(.semibold))
                    ForEach(summary.remainingPaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Text(path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                copyToPasteboard(path)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Path")
                        }
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

            if orphanFilesViewModel.isScanning {
                ProgressView("Scanning Leftovers")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !orphanFilesViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Leftovers",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Use the scan button to review leftover files before deleting anything.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if orphanFilesViewModel.groups.isEmpty {
                ContentUnavailableView("No Orphan Files", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                    selectedBytes: orphanFilesViewModel.selectedBytes,
                    disabledSummary: "Select leftover files first"
                ) {
                    presentConfirmation(.orphanFiles)
                }
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
                    selectedBytes: selectedCandidateBytes,
                    disabledSummary: viewModel.candidates.isEmpty ? "Scan selected app first" : "Select related files first"
                ) {
                    presentConfirmation(.application)
                }
            } else if let report = viewModel.deletionReport {
                ContentUnavailableView(
                    "Application Removed",
                    systemImage: "checkmark.circle",
                    description: Text("Review remaining items from the last deletion.")
                )
                DeletionReportPanel(report: report)
                Spacer()
            } else {
                ContentUnavailableView("No App Selected", systemImage: "app.dashed")
            }
        }
        .padding(22)
    }

    private func confirmationSheet(for mode: DeletionConfirmationMode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let requiredConfirmation = "DELETE"
            let isDeleting = confirmationIsDeleting(for: mode)
            Text("Permanent Deletion")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(confirmationTargetTitle(for: mode))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 14) {
                    Label("\(confirmationSelectedCount(for: mode)) items", systemImage: "checkmark.square")
                    Label(ByteCountFormatter.string(fromByteCount: confirmationSelectedBytes(for: mode), countStyle: .file), systemImage: "internaldrive")
                    if confirmationIncludesAppBundle(for: mode) {
                        Label("Includes app bundle", systemImage: "app.dashed")
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Type DELETE to permanently remove selected items. This does not move files to Trash.")
                .foregroundStyle(.secondary)
            TextField(requiredConfirmation, text: $confirmationText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDeleting)
            Toggle("Force delete locked items", isOn: $forceDelete)
                .toggleStyle(.checkbox)
                .help("Clears file locks and restores write permission before retrying. This cannot bypass Full Disk Access or administrator-only paths.")
                .disabled(isDeleting)
            if forceDelete {
                Text("Force delete retries locked files, but Full Disk Access and administrator-only paths can still block deletion.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { confirmationMode = nil }
                    .disabled(isDeleting)
                Spacer()
                Button(isDeleting ? "Deleting..." : "Delete", role: .destructive) {
                    Task {
                        switch mode {
                        case .application:
                            await viewModel.deleteConfirmedItems(confirmation: confirmationText, force: forceDelete)
                        case .orphanFiles:
                            await orphanFilesViewModel.deleteSelectedLeftovers(confirmation: confirmationText, force: forceDelete)
                        }
                        confirmationMode = nil
                    }
                }
                .disabled(confirmationText != requiredConfirmation || isDeleting)
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

    private func presentConfirmation(_ mode: DeletionConfirmationMode) {
        confirmationText = ""
        forceDelete = false
        confirmationMode = mode
    }

    private func confirmationSelectedCandidates(for mode: DeletionConfirmationMode) -> [RelatedFileCandidate] {
        switch mode {
        case .application:
            selectedCandidates
        case .orphanFiles:
            orphanFilesViewModel.selectedCandidates
        }
    }

    private func confirmationSelectedCount(for mode: DeletionConfirmationMode) -> Int {
        confirmationSelectedCandidates(for: mode).count
    }

    private func confirmationSelectedBytes(for mode: DeletionConfirmationMode) -> Int64 {
        confirmationSelectedCandidates(for: mode).reduce(Int64(0)) { $0 + $1.size }
    }

    private func confirmationTargetTitle(for mode: DeletionConfirmationMode) -> String {
        switch mode {
        case .application:
            viewModel.selectedApp?.displayName ?? "Selected Application"
        case .orphanFiles:
            "Orphan Files"
        }
    }

    private func confirmationIncludesAppBundle(for mode: DeletionConfirmationMode) -> Bool {
        confirmationSelectedCandidates(for: mode).contains { $0.kind == .appBundle }
    }

    private func confirmationIsDeleting(for mode: DeletionConfirmationMode) -> Bool {
        switch mode {
        case .application:
            viewModel.isDeleting
        case .orphanFiles:
            orphanFilesViewModel.isDeleting
        }
    }

    private var activeSection: SidebarDestination {
        navigationState.selectedDestination
    }

    private func refreshApplications() async {
        await viewModel.refreshApps()
        orphanFilesViewModel.updateInstalledApps(viewModel.apps)
    }

    private func deletionStatusColor(for status: DeletionHistoryStatus) -> Color {
        switch status {
        case .verified: Color.green
        case .failed: Color.red
        case .needsReview: Color.orange
        }
    }

    private func toggleOrphanCandidate(_ id: RelatedFileCandidate.ID) {
        if orphanFilesViewModel.selectedCandidateIDs.contains(id) {
            orphanFilesViewModel.selectedCandidateIDs.remove(id)
        } else {
            orphanFilesViewModel.selectedCandidateIDs.insert(id)
        }
    }
}

private enum DeletionConfirmationMode: Identifiable {
    case application
    case orphanFiles

    var id: String {
        switch self {
        case .application: "application"
        case .orphanFiles: "orphanFiles"
        }
    }
}

private struct DeletionReportPanel: View {
    let report: DeletionReportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.statusTitle)
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    copyToPasteboard(report.copyableReportText)
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy Report")
            }
            Text("\(report.deletedCount) deleted, \(report.remainingCount) remaining")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(report.remainingPaths, id: \.self) { path in
                HStack(spacing: 8) {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        copyToPasteboard(path)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Path")
                }
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

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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
