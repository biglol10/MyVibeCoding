import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileGridView: View {
    @EnvironmentObject private var store: ExplorerStore
    let paneID: PaneID
    let thumbnails: Bool
    @State private var anchor: URL?
    @FocusState private var hasFocus: Bool

    private var pane: PaneState? { store.pane(withID: paneID) }
    private var entries: [FileEntry] { store.visibleEntries(forPaneID: paneID) }
    var body: some View {
        if let pane {
            grid(for: pane)
        }
    }

    private func grid(for pane: PaneState) -> some View {
        let entries = entries
        return GeometryReader { geometry in
            let columns = max(1, Int(geometry.size.width / 142))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 10) {
                        ForEach(entries) { entry in
                            FileGridTile(entry: entry, paneID: pane.id, thumbnails: thumbnails,
                                         selected: pane.selectedURLs.contains(entry.url))
                                .id(entry.url)
                                .overlay {
                                    FileGridDragSource(enabled: store.inlineRenameRequest?.url != entry.url,
                                        paneID: pane.id,
                                        onClick: { flags, count in
                                            if count == 2 {
                                                Task {
                                                    guard activate() else { return }
                                                    await store.open(entry.url)
                                                }
                                            }
                                            else { select(entry.url, flags: flags) }
                                        },
                                        dragURLs: {
                                            guard activate(), let currentPane = self.pane,
                                                  !currentPane.location.isArchive else { return [] }
                                            if !currentPane.selectedURLs.contains(entry.url) { store.updateSelection([entry.url]) }
                                            guard let selected = self.pane?.selectedURLs else { return [] }
                                            return self.entries.filter { selected.contains($0.url) }.map(\.url)
                                        })
                                }
                                .contextMenu {
                                    ForEach([ExplorerCommand.open, .quickLook, .rename, .batchRename, .share, .duplicate, .copy, .cut,
                                             .paste, .compressToZip, .extractZip, .copyPath, .revealInFinder, .moveToTrash]) { command in
                                        Button(command.title) {
                                            Task {
                                                guard activate(), let currentPane = self.pane else { return }
                                                if !currentPane.selectedURLs.contains(entry.url) { store.updateSelection([entry.url]) }
                                                await store.perform(command)
                                            }
                                        }
                                        .disabled((command.mutatesFileSystem && store.isFileMutationInProgress) ||
                                            !command.isEnabled(selectionCount: pane.selectedURLs.contains(entry.url) ? pane.selectedURLs.count : 1,
                                            canPaste: store.canPaste, canUndo: store.canUndo,
                                            selectedEntries: pane.selectedURLs.contains(entry.url) ? store.activeSelectedEntries : [entry],
                                            isArchiveLocation: pane.location.isArchive))
                                    }
                                }
                                .onDrop(of: [UTType.fileURL], delegate: FileGridDropDelegate(
                                    store: store, paneID: paneID,
                                    destination: entry.isDirectoryLike ? entry.url : pane.currentURL,
                                    disabled: pane.location.isArchive))
                        }
                    }
                    .padding(10)
                }
                .onDrop(of: [UTType.fileURL], delegate: FileGridDropDelegate(
                    store: store, paneID: paneID, destination: pane.currentURL, disabled: pane.location.isArchive))
                .focusable().focused($hasFocus)
                .onKeyPress(.leftArrow) { moveSelection(-1, proxy: proxy); return .handled }
                .onKeyPress(.rightArrow) { moveSelection(1, proxy: proxy); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-columns, proxy: proxy); return .handled }
                .onKeyPress(.downArrow) { moveSelection(columns, proxy: proxy); return .handled }
                .onChange(of: store.inlineRenameRequest?.id) { _, _ in
                    if let request = store.inlineRenameRequest, request.paneID == pane.id {
                        proxy.scrollTo(request.url, anchor: .center)
                    }
                }
                .onChange(of: pane.selectedURLs) { _, selectedURLs in
                    // A rename or external-open request can select an item far from
                    // the current scroll position. Keep that single item visible.
                    if selectedURLs.count == 1, let url = selectedURLs.first,
                       entries.contains(where: { $0.url == url }) {
                        proxy.scrollTo(url)
                    }
                }
                .onChange(of: pane.location) { _, _ in anchor = nil; if let first = entries.first { proxy.scrollTo(first.url, anchor: .top) } }
                .contextMenu {
                    ForEach([ExplorerCommand.newFolder, .newFile, .paste, .refresh]) { command in
                        Button(command.title) {
                            Task {
                                guard activate() else { return }
                                await store.perform(command)
                            }
                        }
                            .disabled(!store.isCommandEnabled(command, forPaneID: paneID))
                    }
                }
            }
        }
    }
    @discardableResult
    private func activate() -> Bool {
        guard store.activatePane(withID: paneID) else { return false }
        store.requestToolbarFocusClear()
        NSApp.keyWindow?.makeFirstResponder(nil)
        hasFocus = true
        return true
    }
    private func select(_ url: URL, flags: NSEvent.ModifierFlags) {
        guard activate(), let pane else { return }
        if flags.contains(.shift), let anchor,
           let first = entries.firstIndex(where: { $0.url == anchor }),
           let last = entries.firstIndex(where: { $0.url == url }) {
            store.updateSelection(Set(entries[min(first,last)...max(first,last)].map(\.url)))
        } else if flags.contains(.command) || flags.contains(.control) {
            var urls = pane.selectedURLs
            if urls.contains(url) { urls.remove(url) } else { urls.insert(url) }
            store.updateSelection(urls); anchor = url
        } else { store.updateSelection([url]); anchor = url }
    }
    private func moveSelection(_ offset: Int, proxy: ScrollViewProxy) {
        guard !entries.isEmpty, activate(), let pane else { return }
        let current = entries.firstIndex(where: { $0.url == anchor }) ?? entries.firstIndex(where: { pane.selectedURLs.contains($0.url) })
        let next = min(entries.count - 1, max(0, (current ?? (offset > 0 ? -offset : entries.count)) + offset))
        anchor = entries[next].url
        store.updateSelection([entries[next].url]); proxy.scrollTo(entries[next].url)
    }
}

private struct FileGridTile: View {
    @EnvironmentObject private var store: ExplorerStore
    let entry: FileEntry
    let paneID: PaneID
    let thumbnails: Bool
    let selected: Bool
    @State private var image: NSImage?
    @State private var draft = ""
    @FocusState private var renaming: Bool
    private var request: InlineRenameRequest? {
        guard let value = store.inlineRenameRequest, value.paneID == paneID, value.url == entry.url else { return nil }
        return value
    }
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: image ?? FileEntryIconResolver.icon(for: entry, size: NSSize(width: 72, height: 72)))
                .resizable().scaledToFit().frame(width: 82, height: 74)
            if let request {
                TextField(L10n.text("Name"), text: $draft)
                    .textFieldStyle(.roundedBorder).focused($renaming)
                    .accessibilityIdentifier("FileGridInlineRenameField")
                    .onAppear { draft = entry.name; renaming = true }
                    .onSubmit {
                        renaming = false
                        store.clearInlineRenameRequest(matching: request.id)
                        store.requestToolbarFocusClear()
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        Task { await store.rename(entry.url, to: draft, inPane: paneID) }
                    }
                    .onExitCommand {
                        renaming = false
                        store.clearInlineRenameRequest(matching: request.id)
                        store.requestToolbarFocusClear()
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
            } else {
                Text(entry.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 34)
            }
        }
        .padding(8).frame(maxWidth: .infinity)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain).accessibilityLabel(entry.name)
        .task(id: "\(entry.url.absoluteString)|\(entry.dateModified?.timeIntervalSince1970 ?? 0)|\(thumbnails)") {
            image = nil
            guard thumbnails, !entry.isDirectoryLike, !entry.isArchiveBacked, entry.kind != .symlink else { return }
            let result = await FilePreviewThumbnailLoader.loadPreviewImage(for: entry.url, scale: 2, size: CGSize(width: 96, height: 96))
            if !Task.isCancelled { image = result.image }
        }
    }
}
