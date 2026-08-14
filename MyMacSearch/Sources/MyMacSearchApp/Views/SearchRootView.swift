import MyMacSearchAppSupport
import MyMacSearchCore
import SwiftUI

struct SearchRootView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFieldFocused: Bool

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
                    TextField("Search files and folders", text: $search.query)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .font(.system(size: 20, weight: .regular))
                        .focused($searchFieldFocused)
                        .accessibilityIdentifier("mainSearchField")

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
                    onOpenPermissions: model.openFullDiskAccessSettings
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
    }
}

private struct SearchSidebar: View {
    let model: AppModel
    let search: SearchViewModel

    var body: some View {
        List {
            Section("Locations") {
                ForEach(model.settings.scopes.filter(\.isEnabled)) { scope in
                    Button {
                        appendFilter("path:\"\(URL(fileURLWithPath: scope.rootPath).lastPathComponent)\"")
                    } label: {
                        Label(
                            URL(fileURLWithPath: scope.rootPath).lastPathComponent,
                            systemImage: "folder"
                        )
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
    }

    private func appendFilter(_ filter: String) {
        search.query = search.query.isEmpty ? filter : "\(search.query) \(filter)"
    }
}
