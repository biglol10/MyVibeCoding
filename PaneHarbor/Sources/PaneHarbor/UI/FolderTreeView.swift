import SwiftUI

struct FolderTreeView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore
    @StateObject private var tree = FolderTreeStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Button {
                    if let url = explorerStore.activePane.location.fileSystemURL {
                        Task { await tree.setRoot(url, showHidden: explorerStore.showHiddenFiles) }
                    }
                } label: { Image(systemName: "scope") }
                .buttonStyle(.plain)
                .help(L10n.text("Use Current Folder as Tree Root"))
                .accessibilityLabel("Use Current Folder as Tree Root")
                .disabled(explorerStore.activePane.location.fileSystemURL == nil)
            }
            .padding(.horizontal, 8)
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(tree.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 3) {
                            Button { Task { await tree.toggle(row.node) } } label: {
                                Image(systemName: tree.expanded.contains(row.node.url) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10)).frame(width: 16, height: 24)
                            }
                            .buttonStyle(.plain)
                            .disabled(row.node.isCycle || row.depth >= 64)
                            .accessibilityLabel("\(tree.expanded.contains(row.node.url) ? "Collapse" : "Expand") \(row.node.title)")
                            Button {
                                Task { await explorerStore.navigateFromSidebar(to: row.node.url) }
                            } label: {
                                Label(row.node.title, systemImage: row.node.isCycle ? "arrow.trianglehead.2.clockwise.rotate.90" : "folder")
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(row.node.isCycle ? "Link returns to an ancestor; expansion is stopped." : row.node.url.path)
                            if tree.loading.contains(row.node.url) { ProgressView().controlSize(.mini) }
                        }
                        .padding(.leading, CGFloat(min(row.depth, 12)) * 12)
                        .background(isCurrent(row.node.url) ? Color.accentColor.opacity(0.12) : Color.clear)
                        if let error = tree.errors[row.node.url] {
                            Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
        .task(id: explorerStore.activePane.location) { await followNavigation() }
        .task(id: explorerStore.showHiddenFiles) { await followNavigation() }
        .task(id: explorerStore.directoryListingRevision) {
            if let url = explorerStore.activePane.location.fileSystemURL {
                await tree.refreshExpandedDirectory(url)
            }
        }
    }

    private func isCurrent(_ url: URL) -> Bool {
        explorerStore.activePane.location.fileSystemURL?.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func followNavigation() async {
        if let url = explorerStore.activePane.location.fileSystemURL {
            let components = url.standardizedFileURL.pathComponents
            let grantedRoot = explorerStore.grantedFolderSummaries
                .filter { grant in
                    let root = grant.url.standardizedFileURL.pathComponents
                    return grant.availability == .available && components.count >= root.count
                        && Array(components.prefix(root.count)) == root
                }
                .max { $0.url.pathComponents.count < $1.url.pathComponents.count }?.url
            if tree.rootURL == nil, let grantedRoot {
                await tree.setRoot(grantedRoot, showHidden: explorerStore.showHiddenFiles)
            }
            await tree.followNavigation(to: url, showHidden: explorerStore.showHiddenFiles)
        }
    }
}
