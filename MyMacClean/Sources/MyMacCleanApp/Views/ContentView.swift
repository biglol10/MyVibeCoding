import AppKit
import SwiftUI
import MyMacCleanCore
import MyMacCleanAppSupport

struct ContentView: View {
    @State private var viewModel = ApplicationListViewModel(
        executor: DeletionExecutor(protectionPolicy: ContentView.deletionProtectionPolicy)
    )
    @State private var historyViewModel = DeleteHistoryViewModel()
    @State private var orphanFilesViewModel = OrphanFilesViewModel(
        installedApps: [],
        executor: DeletionExecutor(protectionPolicy: ContentView.deletionProtectionPolicy)
    )
    @State private var largeFilesViewModel = LargeFilesViewModel(
        scanRoots: LargeFilesViewModel.defaultScanRoots()
    )
    @State private var developerCacheViewModel = DeveloperCacheViewModel()
    @State private var startupItemsViewModel = StartupItemsViewModel()
    @State private var navigationState = SidebarNavigationState()
    @State private var confirmationText = ""
    @State private var confirmationMode: DeletionConfirmationMode?
    @State private var pendingStartupAction: StartupItemAction?
    @State private var forceDelete = false
    @State private var permanentDelete = false

    private static var deletionProtectionPolicy: ProtectionPolicy {
        ProtectionPolicy(additionalProtectedRoots: currentApplicationProtectedRoots)
    }

    private static var currentApplicationProtectedRoots: [URL] {
        Bundle.main.bundleURL.pathExtension == "app" ? [Bundle.main.bundleURL] : []
    }

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
        .alert("MyMacClean", isPresented: errorAlertBinding) {
            Button("OK") {
                clearErrorMessages()
            }
        } message: {
            Text(currentErrorMessage ?? "")
        }
        .sheet(item: $confirmationMode) { mode in
            confirmationSheet(for: mode)
        }
        .alert("Startup Item Change", isPresented: startupActionAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingStartupAction = nil
            }
            if let pendingStartupAction {
                Button(pendingStartupAction == .disable ? "Disable Startup Item" : "Enable Startup Item", role: pendingStartupAction == .disable ? .destructive : nil) {
                    performStartupAction(pendingStartupAction)
                }
            }
        } message: {
            if let item = startupItemsViewModel.selectedItem {
                Text(StartupItemActionPresentation(item: item).confirmationMessage)
            }
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

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { currentErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    clearErrorMessages()
                }
            }
        )
    }

    private var startupActionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingStartupAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingStartupAction = nil
                }
            }
        )
    }

    private var currentErrorMessage: String? {
        viewModel.errorMessage
            ?? historyViewModel.errorMessage
            ?? orphanFilesViewModel.errorMessage
            ?? largeFilesViewModel.errorMessage
            ?? developerCacheViewModel.errorMessage
            ?? startupItemsViewModel.errorMessage
    }

    private func clearErrorMessages() {
        viewModel.errorMessage = nil
        historyViewModel.errorMessage = nil
        orphanFilesViewModel.errorMessage = nil
        largeFilesViewModel.errorMessage = nil
        developerCacheViewModel.errorMessage = nil
        startupItemsViewModel.errorMessage = nil
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
        case .startupItems:
            startupItemsContent
        case .largeFiles:
            largeFilesContent
        case .maintenance:
            developerCacheContent
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
        case .startupItems:
            startupItemsDetail
        case .largeFiles:
            largeFilesDetail
        case .maintenance:
            developerCacheDetail
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
                    Text("Review installed apps and related files before removing them.")
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

    private var startupItemsContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Startup Items")
                        .font(.title2.weight(.semibold))
                    Text("Audit login helpers, LaunchAgents, and LaunchDaemons before changing startup behavior.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(startupItemsViewModel.isScanning ? "Scanning..." : SidebarDestination.startupItems.primaryActionTitle) {
                    Task { await startupItemsViewModel.scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(startupItemsViewModel.isScanning || startupItemsViewModel.isApplyingChange)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search startup items by label, owner, scope, or path", text: $startupItemsViewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if startupItemsViewModel.isScanning {
                ProgressView("Scanning Startup Items")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !startupItemsViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Startup Items",
                    systemImage: SidebarDestination.startupItems.systemImage,
                    description: Text("User LaunchAgents can be disabled safely. System-wide items are shown as read-only.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if startupItemsViewModel.visibleItems.isEmpty {
                ContentUnavailableView("No Matching Startup Items", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { startupItemsViewModel.selectedItemID },
                    set: { startupItemsViewModel.selectItem(id: $0) }
                )) {
                    ForEach(startupItemsViewModel.visibleItems) { item in
                        StartupItemListRow(
                            item: item,
                            stateColor: startupStateColor(item.state),
                            scopeColor: startupScopeColor(item.scope)
                        )
                        .tag(item.id)
                    }
                }
            }
        }
    }

    private var largeFilesContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Large Files")
                        .font(.title2.weight(.semibold))
                    Text("Find oversized files for manual review before moving anything to Trash.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(largeFilesViewModel.isScanning ? "Scanning..." : SidebarDestination.largeFiles.primaryActionTitle) {
                    Task { await largeFilesViewModel.scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(largeFilesViewModel.isScanning || largeFilesViewModel.isDeleting)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search large files by name, kind, or path", text: $largeFilesViewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if largeFilesViewModel.isScanning {
                ProgressView("Scanning Large Files")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !largeFilesViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Large Files",
                    systemImage: "internaldrive",
                    description: Text("Large files are never selected automatically. Review results before moving anything to Trash.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if largeFilesViewModel.visibleCandidates.isEmpty {
                ContentUnavailableView("No Large Files", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(largeFilesViewModel.visibleCandidates) { candidate in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { largeFilesViewModel.selectedCandidateIDs.contains(candidate.id) },
                            set: { isSelected in
                                if isSelected {
                                    largeFilesViewModel.selectedCandidateIDs.insert(candidate.id)
                                } else {
                                    largeFilesViewModel.selectedCandidateIDs.remove(candidate.id)
                                }
                            }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.url.lastPathComponent)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Text(candidate.url.deletingLastPathComponent().path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(candidate.kind.rawValue)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        SizeText(bytes: candidate.size)
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var developerCacheContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer Cache")
                        .font(.title2.weight(.semibold))
                    Text("Review build caches that can be regenerated.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(developerCacheViewModel.isScanning ? "Scanning..." : SidebarDestination.maintenance.primaryActionTitle) {
                    Task { await developerCacheViewModel.scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(developerCacheViewModel.isScanning || developerCacheViewModel.isDeleting)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search developer caches by tool, safety, or path", text: $developerCacheViewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                Picker("Sort", selection: $developerCacheViewModel.sort) {
                    ForEach(DeveloperCacheSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .frame(width: 160)

                Spacer()

                Text("Safe items are selected automatically.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if developerCacheViewModel.isScanning {
                ProgressView("Scanning Developer Caches")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !developerCacheViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Developer Caches",
                    systemImage: SidebarDestination.maintenance.systemImage,
                    description: Text("Safe cache groups are selected by default. Review and read-only groups require manual attention.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if developerCacheViewModel.visibleCandidates.isEmpty {
                ContentUnavailableView("No Developer Caches", systemImage: SidebarDestination.maintenance.systemImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedDeveloperCacheVisibleCandidates, id: \.groupTitle) { group in
                        Section(group.groupTitle) {
                            ForEach(group.candidates) { candidate in
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { developerCacheViewModel.selectedCandidateIDs.contains(candidate.id) },
                                        set: { isSelected in
                                            developerCacheViewModel.setCandidateSelection(candidate.id, isSelected: isSelected)
                                        }
                                    ))
                                    .labelsHidden()
                                    .disabled(!candidate.isDeletable)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.tool.title)
                                            .font(.headline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(candidate.url.path)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(candidate.safety.title)
                                        .font(.callout.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(developerCacheSafetyColor(candidate.safety).opacity(0.16))
                                        .foregroundStyle(developerCacheSafetyColor(candidate.safety))
                                        .clipShape(Capsule())

                                    SizeText(bytes: candidate.size)
                                        .font(.callout.weight(.semibold))
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
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
                HistoryMetric(title: summary.primaryCountTitle, value: "\(summary.primaryCount)")
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

    private var startupItemsDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup Item Details")
                    .font(.title2.weight(.semibold))
                Text("\(startupItemsViewModel.items.count) items found")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let item = startupItemsViewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.scope == .globalLaunchDaemon ? "gearshape.2.fill" : "bolt.fill")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(startupScopeColor(item.scope))
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.label)
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(2)
                                    Text(item.ownerName)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StartupItemBadge(title: item.state.title, color: startupStateColor(item.state))
                            }

                            HStack(spacing: 8) {
                                StartupItemBadge(title: item.scope.title, color: startupScopeColor(item.scope))
                                if item.isReadOnly {
                                    StartupItemBadge(title: "Read-only", color: .secondary)
                                }
                                if item.hasMissingTarget {
                                    StartupItemBadge(title: "Missing Target", color: .orange)
                                }
                                if item.disabledByRename {
                                    StartupItemBadge(title: "Disabled by MyMacClean", color: .blue)
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

                        startupDetailRow(title: "Plist", value: item.plistURL.path, copyValue: item.plistURL.path, revealURL: item.plistURL)
                        startupDetailRow(title: "Program", value: item.program ?? "Not declared", copyValue: item.program)
                        startupDetailRow(title: "Arguments", value: item.programArguments.isEmpty ? "None" : item.programArguments.joined(separator: " "), copyValue: item.programArguments.isEmpty ? nil : item.programArguments.joined(separator: " "))
                        startupDetailRow(title: "Target", value: startupTargetSummary(for: item), copyValue: item.targetURL?.path, revealURL: item.targetURL)
                        startupDetailRow(title: "Owner Evidence", value: item.ownerEvidence)
                        startupDetailRow(title: "Run At Load", value: item.runAtLoad ? "true" : "false")
                        startupDetailRow(title: "Keep Alive", value: item.keepAliveSummary ?? "Not configured")
                        startupDetailRow(title: "Start Interval", value: item.startInterval.map(String.init) ?? "Not configured")
                        startupDetailRow(title: "Calendar", value: item.startCalendarSummary ?? "Not configured")
                    }
                    .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    startupActionButton(for: item)
                    if let statusMessage = startupItemsViewModel.statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(startupActionHelp(for: item))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    startupItemsViewModel.hasScanned ? "No Startup Item Selected" : "No Scan Yet",
                    systemImage: SidebarDestination.startupItems.systemImage,
                    description: Text("Run a scan, then select an item to inspect its startup plist.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(22)
    }

    private var largeFilesDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Large Files")
                    .font(.title2.weight(.semibold))
                Text("\(largeFilesViewModel.candidates.count) files, \(largeFilesViewModel.selectedCandidates.count) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let report = largeFilesViewModel.deletionReport {
                DeletionReportPanel(report: report)
            }

            if largeFilesViewModel.candidates.isEmpty {
                ContentUnavailableView(
                    largeFilesViewModel.hasScanned ? "No Large Files" : "No Scan Yet",
                    systemImage: "internaldrive",
                    description: Text("Run a scan and select files manually before cleanup.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HistoryMetric(title: "Found", value: "\(largeFilesViewModel.candidates.count)")
                    HistoryMetric(
                        title: "Total Size",
                        value: ByteCountFormatter.string(fromByteCount: largeFilesViewModel.totalBytes, countStyle: .file)
                    )
                    HistoryMetric(
                        title: "Selected",
                        value: ByteCountFormatter.string(fromByteCount: largeFilesViewModel.selectedBytes, countStyle: .file)
                    )
                }

                Spacer()

                DeleteActionButton(
                    selectedCount: largeFilesViewModel.selectedCandidates.count,
                    selectedBytes: largeFilesViewModel.selectedBytes,
                    disabledSummary: "Select large files first"
                ) {
                    presentConfirmation(.largeFiles)
                }
            }
        }
        .padding(22)
    }

    private var developerCacheDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Developer Cache")
                    .font(.title2.weight(.semibold))
                Text("\(developerCacheViewModel.candidates.count) groups, \(developerCacheViewModel.selectedCandidates.count) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let report = developerCacheViewModel.deletionReport {
                DeletionReportPanel(report: report)
            }

            if developerCacheViewModel.candidates.isEmpty {
                ContentUnavailableView(
                    developerCacheViewModel.hasScanned ? "No Developer Caches" : "No Scan Yet",
                    systemImage: SidebarDestination.maintenance.systemImage,
                    description: Text("Run a scan to review safe, review, and read-only developer cache groups.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HistoryMetric(title: "Found", value: "\(developerCacheViewModel.candidates.count)")
                    HistoryMetric(
                        title: "Total Size",
                        value: ByteCountFormatter.string(fromByteCount: developerCacheViewModel.totalBytes, countStyle: .file)
                    )
                    HistoryMetric(
                        title: "Selected",
                        value: ByteCountFormatter.string(fromByteCount: developerCacheViewModel.selectedBytes, countStyle: .file)
                    )
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(developerCacheViewModel.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(candidate.tool.title)
                                        .font(.headline.weight(.semibold))
                                    Spacer()
                                    Text(candidate.safety.title)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(developerCacheSafetyColor(candidate.safety))
                                }
                                Text(candidate.explanation)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(candidate.url.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                DeleteActionButton(
                    selectedCount: developerCacheViewModel.selectedCandidates.count,
                    selectedBytes: developerCacheViewModel.selectedBytes,
                    disabledSummary: "Select developer caches first"
                ) {
                    presentConfirmation(.developerCache)
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
            let allowsAdvancedDeleteOptions = mode != .largeFiles && mode != .developerCache
            let effectivePermanentDelete = allowsAdvancedDeleteOptions && permanentDelete
            Text(effectivePermanentDelete ? "Permanent Deletion" : "Move to Trash")
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
            Text(effectivePermanentDelete ? "Type DELETE to permanently remove selected items. This cannot be undone from Trash." : "Type DELETE to move selected items to Trash.")
                .foregroundStyle(.secondary)
            TextField(requiredConfirmation, text: $confirmationText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDeleting)
            if allowsAdvancedDeleteOptions {
                Toggle("Permanently delete instead", isOn: $permanentDelete)
                    .toggleStyle(.checkbox)
                    .disabled(isDeleting)
                Toggle("Force unlock locked items", isOn: $forceDelete)
                    .toggleStyle(.checkbox)
                    .help("Clears file locks and restores write permission before retrying. This cannot bypass Full Disk Access or administrator-only paths.")
                    .disabled(isDeleting)
                if forceDelete {
                    Text("Force unlock retries locked files, but Full Disk Access and administrator-only paths can still block deletion.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel") { confirmationMode = nil }
                    .disabled(isDeleting)
                Spacer()
                Button(isDeleting ? "Deleting..." : (effectivePermanentDelete ? "Permanently Delete" : "Move to Trash"), role: .destructive) {
                    Task {
                        let deletionMode: DeletionMode = effectivePermanentDelete ? .permanent : .moveToTrash
                        switch mode {
                        case .application:
                            await viewModel.deleteConfirmedItems(confirmation: confirmationText, force: forceDelete, mode: deletionMode)
                        case .orphanFiles:
                            await orphanFilesViewModel.deleteSelectedLeftovers(confirmation: confirmationText, force: forceDelete, mode: deletionMode)
                        case .largeFiles:
                            await largeFilesViewModel.moveSelectedToTrash(confirmation: confirmationText)
                        case .developerCache:
                            await developerCacheViewModel.moveSelectedToTrash(confirmation: confirmationText)
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
        permanentDelete = false
        confirmationMode = mode
    }

    private func confirmationSelectedCandidates(for mode: DeletionConfirmationMode) -> [RelatedFileCandidate] {
        switch mode {
        case .application:
            selectedCandidates
        case .orphanFiles:
            orphanFilesViewModel.selectedCandidates
        case .largeFiles:
            largeFilesViewModel.selectedCandidates.map { candidate in
                RelatedFileCandidate(
                    id: candidate.id,
                    url: candidate.url,
                    kind: .unknown,
                    size: candidate.size,
                    matchReason: "large file selected by user",
                    confidence: .high,
                    safety: .review,
                    defaultSelected: false,
                    requiresManualReview: true,
                    isProtected: false
                )
            }
        case .developerCache:
            developerCacheViewModel.selectedRelatedCandidates
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
        case .largeFiles:
            "Large Files"
        case .developerCache:
            "Developer Cache"
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
        case .largeFiles:
            largeFilesViewModel.isDeleting
        case .developerCache:
            developerCacheViewModel.isDeleting
        }
    }

    private var groupedDeveloperCacheVisibleCandidates: [(groupTitle: String, candidates: [DeveloperCacheCandidate])] {
        let groups = Dictionary(grouping: developerCacheViewModel.visibleCandidates) { $0.tool.groupTitle }
        let order = ["Xcode", "Swift", "Node", "CocoaPods", "Gradle", "Docker"]
        return groups.keys.sorted {
            let lhsIndex = order.firstIndex(of: $0) ?? .max
            let rhsIndex = order.firstIndex(of: $1) ?? .max
            if lhsIndex == rhsIndex {
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
            return lhsIndex < rhsIndex
        }.map { groupTitle in
            (groupTitle: groupTitle, candidates: groups[groupTitle] ?? [])
        }
    }

    private func developerCacheSafetyColor(_ safety: DeveloperCacheSafety) -> Color {
        switch safety {
        case .safe: Color.green
        case .review: Color.orange
        case .readOnly: Color.secondary
        }
    }

    private func startupStateColor(_ state: StartupItemState) -> Color {
        switch state {
        case .enabled: Color.green
        case .disabled: Color.secondary
        }
    }

    private func startupScopeColor(_ scope: StartupItemScope) -> Color {
        switch scope {
        case .userLaunchAgent: Color.blue
        case .globalLaunchAgent: Color.purple
        case .globalLaunchDaemon: Color.indigo
        }
    }

    private func startupTargetSummary(for item: StartupItem) -> String {
        guard let targetURL = item.targetURL else {
            return "No executable target declared"
        }
        return item.targetExists ? targetURL.path : "\(targetURL.path) (missing)"
    }

    private func startupActionHelp(for item: StartupItem) -> String {
        StartupItemActionPresentation(item: item).helpText
    }

    private func startupDetailRow(
        title: String,
        value: String,
        copyValue: String? = nil,
        revealURL: URL? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            if let copyValue {
                Button {
                    copyToPasteboard(copyValue)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }

            if let revealURL {
                Button {
                    revealInFinder(revealURL)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func startupActionButton(for item: StartupItem) -> some View {
        let presentation = StartupItemActionPresentation(item: item)
        if presentation.action == nil {
            Button {
            } label: {
                Label(presentation.buttonTitle, systemImage: presentation.systemImage)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        } else if presentation.action == .disable {
            Button {
                pendingStartupAction = .disable
            } label: {
                Label(startupItemsViewModel.isApplyingChange ? presentation.applyingTitle : presentation.buttonTitle, systemImage: presentation.systemImage)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(startupItemsViewModel.isApplyingChange)
        } else if presentation.action == .enable {
            Button {
                pendingStartupAction = .enable
            } label: {
                Label(startupItemsViewModel.isApplyingChange ? presentation.applyingTitle : presentation.buttonTitle, systemImage: presentation.systemImage)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(startupItemsViewModel.isApplyingChange)
        }
    }

    private func performStartupAction(_ action: StartupItemAction) {
        pendingStartupAction = nil
        Task {
            switch action {
            case .disable:
                await startupItemsViewModel.disableSelectedItem()
            case .enable:
                await startupItemsViewModel.enableSelectedItem()
            }
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
    case largeFiles
    case developerCache

    var id: String {
        switch self {
        case .application: "application"
        case .orphanFiles: "orphanFiles"
        case .largeFiles: "largeFiles"
        case .developerCache: "developerCache"
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
            Text(report.summaryLine)
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

private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

private struct StartupItemListRow: View {
    let item: StartupItem
    let stateColor: Color
    let scopeColor: Color

    private var presentation: StartupItemListPresentation {
        StartupItemListPresentation(item: item)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.scope == .globalLaunchDaemon ? "gearshape.2" : "bolt")
                .font(.title3.weight(.semibold))
                .foregroundStyle(scopeColor)
                .frame(width: 26, height: 32, alignment: .top)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.label)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    StartupItemBadge(title: presentation.stateBadgeTitle, color: stateColor, compact: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.ownerName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(item.plistURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 6) {
                    StartupItemBadge(title: presentation.scopeBadgeTitle, color: scopeColor, compact: true)

                    if let attentionBadgeTitle = presentation.attentionBadgeTitle {
                        StartupItemBadge(
                            title: attentionBadgeTitle,
                            color: item.hasMissingTarget ? .orange : .secondary,
                            compact: true
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 86)
        .contentShape(Rectangle())
    }
}

private struct StartupItemBadge: View {
    let title: String
    let color: Color
    var compact = false

    var body: some View {
        Text(title)
            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
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
