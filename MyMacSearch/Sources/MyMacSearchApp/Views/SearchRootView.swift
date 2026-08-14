import MyMacSearchAppSupport
import MyMacSearchCore
import SwiftUI

struct SearchRootView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var showingSaveSearch = false

    var body: some View {
        Group {
            if let startupError = model.startupError {
                ContentUnavailableView(
                    "MyMacSearch Could Not Start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(startupError)
                )
            } else if model.needsOnboarding {
                OnboardingView(model: model)
            } else if let searchViewModel = model.searchViewModel,
                      let coordinator = model.coordinator {
                searchTool(search: searchViewModel, coordinator: coordinator)
            } else {
                ProgressView("Opening search index…")
            }
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.dismissActionError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissActionError() }
        } message: {
            Text(model.actionError ?? "The action could not be completed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .myMacSearchFocusSearch)) { _ in
            searchFieldFocused = true
        }
    }

    @ViewBuilder
    private func searchTool(
        search: SearchViewModel,
        coordinator: IndexCoordinator
    ) -> some View {
        @Bindable var search = search
        NavigationSplitView {
            SearchSidebar(model: model, search: search)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Search files and folders", text: $search.query)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .font(.system(size: 20, weight: .regular))
                            .focused($searchFieldFocused)
                            .accessibilityIdentifier("mainSearchField")

                        Menu {
                            ForEach(SearchSort.allCases, id: \.self) { sort in
                                Button {
                                    search.chooseSort(sort)
                                } label: {
                                    if search.sort == sort {
                                        Label(sort.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(sort.displayName)
                                    }
                                }
                            }
                        } label: {
                            Label(search.sort.displayName, systemImage: "arrow.up.arrow.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button("Save Search") { showingSaveSearch = true }
                            .keyboardShortcut("s", modifiers: [.command])
                            .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.parserError != nil)
                    }

                    if !search.tokens.isEmpty {
                        SearchFilterTokensView(tokens: search.tokens, onRemove: search.removeToken)
                    }

                    if let parserError = search.parserError {
                        Text(parserError.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let searchError = search.searchError {
                        Text(searchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)

                Divider()

                SearchResultsTable(model: model, search: search)

                Divider()

                IndexStatusBar(
                    coordinator: coordinator,
                    resultCount: search.rows.count,
                    onResume: model.resumeIndexing,
                    onOpenPermissions: model.openFullDiskAccessSettings,
                    onOpenIndexCenter: { openWindow(id: "index-center") }
                )
            }
        }
        .onChange(of: coordinator.status) { oldStatus, newStatus in
            if oldStatus != .watching, newStatus == .watching {
                search.refresh()
            }
        }
        .task {
            searchFieldFocused = true
        }
        .sheet(isPresented: $showingSaveSearch) {
            SaveSearchSheet(query: search.query, sort: search.sort) { name in
                search.saveCurrentSearch(name: name)
            }
        }
    }
}

private struct SearchSidebar: View {
    let model: AppModel
    let search: SearchViewModel
    @State private var renameTarget: SavedSearch?
    @State private var renameText = ""

    var body: some View {
        List {
            if !search.savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(search.savedSearches) { saved in
                        Button(saved.name) { search.activateSavedSearch(saved.id) }
                            .buttonStyle(.plain)
                            .help(saved.query)
                            .contextMenu {
                                Button("Rename…") {
                                    renameTarget = saved
                                    renameText = saved.name
                                }
                                Button("Update with Current Search") {
                                    search.replaceSavedSearch(id: saved.id)
                                }
                                Button("Remove", role: .destructive) {
                                    search.removeSavedSearch(id: saved.id)
                                }
                            }
                    }
                    .onMove(perform: search.moveSavedSearch)
                }
            }

            if !search.recentSearches.isEmpty {
                Section("Recent") {
                    ForEach(search.recentSearches) { recent in
                        Button(recent.query) { search.activateRecentSearch(recent) }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                            .help(recent.query)
                    }
                    Button("Clear Recent Searches") { search.clearRecentSearches() }
                        .font(.caption)
                        .buttonStyle(.plain)
                }
            }

            Section("Locations") {
                ForEach(model.settings.scopes.filter(\.isEnabled)) { scope in
                    Button {
                        appendFilter("path:\"\(URL(fileURLWithPath: scope.rootPath).lastPathComponent)\"")
                    } label: {
                        HStack {
                            Label(
                                URL(fileURLWithPath: scope.rootPath).lastPathComponent,
                                systemImage: "folder"
                            )
                            Spacer()
                            if let state = model.coordinator?.scopeStates[scope.id]?.state {
                                Image(systemName: scopeStateSymbol(state))
                                    .foregroundStyle(state == .permissionNeeded ? Color.orange : Color.secondary)
                                    .help(state.rawValue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(scope.rootPath)
                }
            }

            Section("Kind") {
                ForEach(IndexedFileKind.allCases, id: \.self) { kind in
                    Button {
                        appendFilter("kind:\(kind.rawValue)")
                    } label: {
                        Text(kind.rawValue.capitalized)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Modified") {
                Button("Today") { appendFilter("modified:today") }
                    .buttonStyle(.plain)
                Button("Last 7 Days") { appendFilter("modified:7d") }
                    .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .sheet(item: $renameTarget) { saved in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Saved Search").font(.headline)
                TextField("Name", text: $renameText)
                HStack {
                    Spacer()
                    Button("Cancel") { renameTarget = nil }
                    Button("Rename") {
                        search.renameSavedSearch(id: saved.id, name: renameText)
                        renameTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private func appendFilter(_ filter: String) {
        search.query = search.query.isEmpty ? filter : "\(search.query) \(filter)"
    }

    private func scopeStateSymbol(_ state: ScopeIndexState) -> String {
        switch state {
        case .scanning: "arrow.triangle.2.circlepath"
        case .watching: "eye"
        case .paused: "pause.circle"
        case .offline: "externaldrive.badge.xmark"
        case .permissionNeeded: "lock.trianglebadge.exclamationmark"
        case .error: "exclamationmark.triangle"
        case .disabled: "minus.circle"
        }
    }
}
