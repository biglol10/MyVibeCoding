import MyMacSearchAppSupport
import MyMacSearchCore
import SwiftUI

struct IndexCenterView: View {
    @Bindable var model: AppModel
    @State private var issueScopeFilter = ""
    @State private var issueCategoryFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Index Center")
                    .font(.title2)
                Spacer()
                if model.coordinator?.scopeStates.values.contains(where: { $0.state == .permissionNeeded }) == true {
                    Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                }
                Button("Refresh") { model.refreshIndexHealth() }
                Button("Verify Index") { model.verifyIndex() }
                    .disabled(model.indexHealthViewModel?.isVerifying == true)
                Button("Rescan All") { model.rescanAllScopes() }
            }
            .padding()

            Divider()

            if let health = model.indexHealthViewModel,
               let snapshot = health.snapshot {
                VStack(spacing: 0) {
                    Table(snapshot.scopes) {
                        TableColumn("Location") { scope in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: scope.rootPath).lastPathComponent)
                                Text(scope.rootPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .width(min: 220, ideal: 300)

                        TableColumn("Status") { scope in
                            Text(scope.state.rawValue)
                        }
                        .width(100)

                        TableColumn("Indexed Entries") { scope in
                            Text(scope.entryCount.formatted())
                                .monospacedDigit()
                        }
                        .width(105)

                        TableColumn("Last Completed Scan") { scope in
                            if let date = scope.lastCompletedScanAt {
                                Text(date, format: .dateTime.year().month().day().hour().minute())
                            } else {
                                Text("—")
                            }
                        }
                        .width(150)

                        TableColumn("Issues") { scope in
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(scope.unresolvedIssueCount.formatted())
                                if scope.lastSkippedCount > 0 || scope.lastPermissionDeniedCount > 0 {
                                    Text("\(scope.lastSkippedCount) skipped · \(scope.lastPermissionDeniedCount) denied")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(min: 90, ideal: 135)

                        TableColumn("") { scope in
                            Button("Rescan") { model.rescan(scopeID: scope.scopeID) }
                                .disabled(scope.state == .offline || scope.state == .scanning)
                        }
                        .width(70)
                    }

                    Divider()

                    HStack {
                        Text("\(snapshot.totalEntryCount.formatted()) indexed")
                        Text(ByteCountFormatter.string(fromByteCount: snapshot.databaseBytes + snapshot.auxiliaryBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let verification = health.verification {
                            Label(
                                verification.isHealthy ? "Index verified" : "Verification found problems",
                                systemImage: verification.isHealthy ? "checkmark.circle" : "exclamationmark.triangle"
                            )
                            .foregroundStyle(verification.isHealthy ? Color.secondary : Color.orange)
                        }
                    }
                    .font(.caption)
                    .padding(10)

                    if !health.issues.isEmpty {
                        Divider()
                        HStack {
                            Picker("Location", selection: $issueScopeFilter) {
                                Text("All Locations").tag("")
                                ForEach(snapshot.scopes) { scope in
                                    Text(URL(fileURLWithPath: scope.rootPath).lastPathComponent)
                                        .tag(scope.scopeID)
                                }
                            }
                            Picker("Category", selection: $issueCategoryFilter) {
                                Text("All Categories").tag("")
                                ForEach(IndexIssueCategory.allCases, id: \.rawValue) { category in
                                    Text(category.rawValue).tag(category.rawValue)
                                }
                            }
                            Spacer()
                        }
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                        List(filteredIssues(health.issues).prefix(100)) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.message)
                                Text(issue.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .contextMenu {
                                Button("Copy Path") { model.copyIndexIssuePath(issue.path) }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 190)
                    }
                }
            } else if let error = model.indexHealthViewModel?.errorMessage {
                ContentUnavailableView("Index Health Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Reading index health…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { model.refreshIndexHealth(force: false) }
        .onChange(of: model.coordinator?.scopeStates ?? [:]) { _, _ in
            model.refreshIndexHealth(force: false)
        }
    }

    private func filteredIssues(_ issues: [IndexIssueRecord]) -> [IndexIssueRecord] {
        issues.filter { issue in
            (issueScopeFilter.isEmpty || issue.scopeID == issueScopeFilter)
                && (issueCategoryFilter.isEmpty || issue.category.rawValue == issueCategoryFilter)
        }
    }
}
