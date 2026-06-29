import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore
    @State private var draggingFavoriteID: SidebarFavorite.ID?

    var body: some View {
        GeometryReader { geometry in
            let rowWidth = max(1, geometry.size.width - 20)

            sidebarContent(rowWidth: rowWidth)
        }
        .task {
            await explorerStore.refreshMountedVolumes()
        }
    }

    private func sidebarContent(rowWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("Favorites") {
                        Button {
                            explorerStore.addPrimaryFolderToFavorites()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(!explorerStore.canAddPrimaryFolderToFavorites)
                        .help("Add Selected Folder or Current Folder to Favorites")
                    }

                    ForEach(explorerStore.favoriteSidebarItems) { item in
                        favoriteButton(item, rowWidth: rowWidth)
                            .onDrag {
                                draggingFavoriteID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarFavoriteDropDelegate(
                                    targetID: item.id,
                                    draggingFavoriteID: $draggingFavoriteID,
                                    explorerStore: explorerStore
                                )
                            )
                            .frame(width: rowWidth, alignment: .leading)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                guard !item.isMissing else {
                                    return
                                }
                                Task { await explorerStore.navigateFromSidebar(to: item.favorite.url) }
                            })
                            .contextMenu {
                                Button("Move Up") {
                                    explorerStore.moveFavoriteUp(id: item.id)
                                }
                                Button("Move Down") {
                                    explorerStore.moveFavoriteDown(id: item.id)
                                }
                                Divider()
                                Button("Remove from Favorites") {
                                    explorerStore.removeFavorite(id: item.id)
                                }
                            }
                    }

                    favoriteEndDropTarget(rowWidth: rowWidth)
                    addCurrentFolderButton(rowWidth: rowWidth)
                }

                if !explorerStore.recentFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader("Recent Folders")
                        ForEach(explorerStore.recentFolders) { folder in
                            sidebarButton(folder.title, systemImage: "clock", rowWidth: rowWidth) {
                                Task { await explorerStore.navigateToRecentFolder(folder) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("Locations") {
                        Button {
                            Task { await explorerStore.refreshMountedVolumes() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Locations")
                    }

                    ForEach(explorerStore.mountedVolumes) { volume in
                        sidebarButton(volume.displayName, systemImage: volume.systemImageName, rowWidth: rowWidth) {
                            Task { await explorerStore.navigateToMountedVolume(volume) }
                        }
                    }

                    if let volumeError = explorerStore.volumeError {
                        Text(volumeError.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    private func favoriteButton(_ item: SidebarFavoriteItem, rowWidth: CGFloat) -> some View {
        sidebarButton(item.favorite.title, systemImage: item.favorite.systemImageName, rowWidth: rowWidth) {
            guard !item.isMissing else {
                return
            }
            Task { await explorerStore.navigateFromSidebar(to: item.favorite.url) }
        }
        .foregroundStyle(item.isMissing ? .secondary : .primary)
        .opacity(item.isMissing ? 0.55 : 1)
        .help(item.isMissing ? "Missing path: \(item.favorite.url.path)" : item.favorite.url.path)
    }

    private func addCurrentFolderButton(rowWidth: CGFloat) -> some View {
        sidebarButton("Add Current Folder", systemImage: "plus.circle", rowWidth: rowWidth) {
            explorerStore.addActiveFolderToFavorites()
        }
        .foregroundStyle(explorerStore.canAddActiveFolderToFavorites ? .secondary : .tertiary)
        .disabled(!explorerStore.canAddActiveFolderToFavorites)
        .help("Add Current Folder to Favorites")
    }

    private func favoriteEndDropTarget(rowWidth: CGFloat) -> some View {
        Color.clear
            .frame(height: 8)
            .frame(width: rowWidth)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: SidebarFavoriteEndDropDelegate(
                    draggingFavoriteID: $draggingFavoriteID,
                    explorerStore: explorerStore
                )
            )
    }

    private func sidebarButton(
        _ title: String,
        systemImage: String,
        rowWidth: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        SidebarButtonRow(
            title: title,
            systemImage: systemImage,
            rowWidth: rowWidth,
            action: action
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) {
            EmptyView()
        }
    }

    private func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarButtonRow: View {
    @Environment(\.isEnabled) private var isEnabled

    var title: String
    var systemImage: String
    var rowWidth: CGFloat
    var action: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.001))

            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(width: rowWidth, height: 26, alignment: .leading)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded {
            guard isEnabled else {
                return
            }
            action()
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else {
                return
            }
            action()
        }
    }
}

private struct SidebarFavoriteDropDelegate: DropDelegate {
    let targetID: SidebarFavorite.ID
    @Binding var draggingFavoriteID: SidebarFavorite.ID?
    let explorerStore: ExplorerStore

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingFavoriteID, sourceID != targetID else {
            return
        }

        explorerStore.moveFavorite(id: sourceID, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingFavoriteID = nil
        return true
    }
}

private struct SidebarFavoriteEndDropDelegate: DropDelegate {
    @Binding var draggingFavoriteID: SidebarFavorite.ID?
    let explorerStore: ExplorerStore

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingFavoriteID else {
            return
        }

        explorerStore.moveFavorite(id: sourceID, toOffset: explorerStore.favoriteSidebarItems.count)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingFavoriteID = nil
        return true
    }
}
