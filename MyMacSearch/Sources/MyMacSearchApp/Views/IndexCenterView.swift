import MyMacSearchAppSupport
import MyMacSearchCore
import SwiftUI

struct IndexCenterView: View {
    @Bindable var model: AppModel

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
                            Text(scope.unresolvedIssueCount.formatted())
                        }
                        .width(55)

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
                        List(health.issues.prefix(100)) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.message)
                                Text(issue.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
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
    }
}
