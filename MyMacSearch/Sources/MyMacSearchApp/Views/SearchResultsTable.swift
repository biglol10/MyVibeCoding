import MyMacSearchAppSupport
import MyMacSearchCore
import SwiftUI

struct SearchResultsTable: View {
    let model: AppModel
    @Bindable var search: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            Table(search.rows, selection: $search.selectedEntryID) {
                TableColumn("Name") { entry in
                    HStack(spacing: 6) {
                        Image(systemName: symbol(for: entry))
                            .foregroundStyle(.secondary)
                        Text(entry.name)
                            .lineLimit(1)
                        if searchScopeIsOffline(entry.scopeID) {
                            Text("Offline")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 160, ideal: 210, max: 250)

                TableColumn("Path") { entry in
                    Text(entry.parentPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 200, ideal: 300, max: 380)

                TableColumn("Kind") { entry in
                    Text(entry.kind.rawValue.capitalized)
                }
                .width(min: 70, ideal: 85, max: 100)

                TableColumn("Size") { entry in
                    Text(entry.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: entry.sizeBytes))
                        .monospacedDigit()
                }
                .width(min: 65, ideal: 75, max: 90)

                TableColumn("Modified") { entry in
                    Text(entry.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                        .monospacedDigit()
                }
                .width(min: 125, ideal: 140, max: 155)
            }
            .contextMenu {
                resultMenu
            }
            .onKeyPress(phases: .down) { keyPress in
                guard ResultKeyboardCommand.resolve(
                    characters: keyPress.characters,
                    hasModifiers: !keyPress.modifiers.isEmpty
                ) == .quickLook else {
                    return .ignored
                }
                model.toggleQuickLook()
                return .handled
            }

            if search.canLoadMore {
                Divider()
                Button(search.isLoadingMore ? "Loading…" : "Load More") {
                    search.loadMore()
                }
                .disabled(search.isLoadingMore)
                .buttonStyle(.plain)
                .padding(.vertical, 7)
            }
        }
    }

    @ViewBuilder
    private var resultMenu: some View {
        Button("Open") { model.perform(.open) }
        Button("Quick Look") { model.toggleQuickLook() }
        Divider()
        Button("Reveal in Finder") { model.perform(.revealInFinder) }
        Button("Copy Path") { model.perform(.copyPath) }
        Button("Open in Terminal") { model.perform(.openInTerminal) }
        Button("Open in MyMacFinder") { model.perform(.openInMyMacFinder) }
    }

    private func symbol(for entry: IndexedEntry) -> String {
        switch entry.kind {
        case .folder: "folder"
        case .application: "app"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .archive: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .document: "doc"
        case .other: "doc"
        }
    }

    private func searchScopeIsOffline(_ scopeID: String) -> Bool {
        model.coordinator?.scopeStates[scopeID]?.state == .offline
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()
}

struct IndexStatusBar: View {
    let coordinator: IndexCoordinator
    let resultCount: Int
    let onResume: () -> Void
    let onOpenPermissions: () -> Void
    let onOpenIndexCenter: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
            Button(action: onOpenIndexCenter) {
                Text(statusText)
            }
            .buttonStyle(.plain)
            .help("Open Index Center")

            if coordinator.status == .initialScan {
                ProgressView(value: coordinator.progress.estimatedFraction)
                    .frame(width: 110)
                Text("\(coordinator.progress.scannedCount.formatted()) indexed")
                if let path = coordinator.progress.currentPath {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            if coordinator.progress.skippedCount > 0 {
                Text("\(coordinator.progress.skippedCount.formatted()) skipped")
                    .foregroundStyle(.secondary)
            }
            Text("\(resultCount.formatted()) results")
                .foregroundStyle(.secondary)

            if coordinator.status == .paused {
                Button("Resume", action: onResume)
                    .buttonStyle(.borderless)
            } else if coordinator.status == .permissionNeeded {
                Button("Open Privacy Settings", action: onOpenPermissions)
                    .buttonStyle(.borderless)
            } else {
                Button("Pause") { coordinator.pause() }
                    .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private var statusText: String {
        switch coordinator.status {
        case .initialScan: "Initial scan"
        case .watching: "Watching"
        case .paused: "Paused"
        case .permissionNeeded: "Permission needed"
        case .error(let message): "Error: \(message)"
        }
    }

    private var statusSymbol: String {
        switch coordinator.status {
        case .initialScan: "arrow.triangle.2.circlepath"
        case .watching: "eye"
        case .paused: "pause.circle"
        case .permissionNeeded: "lock.trianglebadge.exclamationmark"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .watching: .green
        case .permissionNeeded, .error: .orange
        default: .secondary
        }
    }
}
