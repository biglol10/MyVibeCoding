import AppKit
import SwiftUI

@main
struct MyMacFinderApp: App {
    @StateObject private var explorerStore: ExplorerStore

    init() {
        _explorerStore = StateObject(
            wrappedValue: ExplorerStore(
                fileOperationService: FileOperationService(conflictResolver: AppKitFileConflictResolver()),
                zipExtractor: ZipExtractionService(conflictResolver: AppKitFileConflictResolver()),
                zipCompressor: ZipCompressionService(conflictResolver: AppKitFileConflictResolver())
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(explorerStore)
                .task {
                    await explorerStore.loadInitialDirectory()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    perform(.newTab)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("New Folder") {
                    perform(.newFolder)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") {
                    perform(.closeTab)
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Explorer") {
                Button("Close Tab") {
                    perform(.closeTab)
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!isEnabled(.closeTab))

                Button("Next Tab") {
                    perform(.nextTab)
                }
                .keyboardShortcut(.tab, modifiers: [.control])

                Button("Previous Tab") {
                    perform(.previousTab)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button("Undo") {
                    perform(.undo)
                }
                .disabled(!isEnabled(.undo))

                Divider()

                Button("Focus Search") {
                    perform(.focusSearch)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Focus Path") {
                    perform(.focusPath)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Clear Search") {
                    perform(.clearSearch)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Divider()

                Button("Select All") {
                    perform(.selectAll)
                }
                .disabled(!isEnabled(.selectAll))

                Divider()

                Button("Open") {
                    perform(.open)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!isEnabled(.open))

                Button("Quick Look") {
                    perform(.quickLook)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!isEnabled(.quickLook))

                Button("Add to Favorites") {
                    perform(.addToFavorites)
                }
                .disabled(!isEnabled(.addToFavorites))

                Button("Edit Tags") {
                    perform(.editTags)
                }
                .disabled(!isEnabled(.editTags))

                Divider()

                Button("Rename") {
                    perform(.rename)
                }
                .disabled(!isEnabled(.rename))

                Button("Duplicate") {
                    perform(.duplicate)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!isEnabled(.duplicate))

                Button("Extract ZIP") {
                    perform(.extractZip)
                }
                .disabled(!isEnabled(.extractZip))

                Button("Compress to ZIP") {
                    perform(.compressToZip)
                }
                .disabled(!isEnabled(.compressToZip))

                Divider()

                Button("Copy") {
                    perform(.copy)
                }
                .disabled(!isEnabled(.copy))

                Button("Cut") {
                    perform(.cut)
                }
                .disabled(!isEnabled(.cut))

                Button("Paste") {
                    perform(.paste)
                }
                .disabled(!isEnabled(.paste))

                Button("Copy Path") {
                    perform(.copyPath)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!isEnabled(.copyPath))

                Divider()

                Button("Move to Trash") {
                    perform(.moveToTrash)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!isEnabled(.moveToTrash))

                Button("Reveal in Finder") {
                    perform(.revealInFinder)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!isEnabled(.revealInFinder))

                Divider()

                Button("Back") {
                    perform(.goBack)
                }
                .disabled(!isEnabled(.goBack))

                Button("Forward") {
                    perform(.goForward)
                }
                .disabled(!isEnabled(.goForward))

                Button("Go Up") {
                    perform(.goUp)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!isEnabled(.goUp))

                Button("Refresh") {
                    perform(.refresh)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Toggle Hidden Files") {
                    perform(.toggleHiddenFiles)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    perform(.toggleInspector)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }

        Settings {
            TabView {
                Form {
                    Section("Layout") {
                        Picker("Pane Mode", selection: paneModeBinding) {
                            ForEach(ExplorerPaneMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Show Inspector", isOn: $explorerStore.isInspectorVisible)
                    }

                    Section("Files") {
                        Toggle("Show Hidden Files", isOn: showHiddenFilesBinding)
                        Picker("Default Sort", selection: defaultSortKeyBinding) {
                            ForEach(SortKey.userSelectableCases, id: \.self) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        Picker("Sort Direction", selection: defaultSortDirectionBinding) {
                            ForEach(SortDirection.allCases, id: \.self) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }
                        Picker("Folder/File Order", selection: folderFileOrderingBinding) {
                            ForEach(FolderFileOrdering.allCases, id: \.self) { ordering in
                                Text(ordering.title).tag(ordering)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }

                Form {
                    Section("Privacy & Access") {
                        LabeledContent("Sandbox") {
                            Text(explorerStore.sandboxPolicy.statusTitle)
                        }
                        Text(explorerStore.sandboxPolicy.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                Task {
                                    await explorerStore.chooseFolderForAccess()
                                }
                            } label: {
                                Label("Choose Folder...", systemImage: "folder.badge.plus")
                            }

                            Button {
                                openPrivacySettings()
                            } label: {
                                Label("Privacy Settings", systemImage: "lock.shield")
                            }
                        }

                        if explorerStore.grantedFolderSummaries.isEmpty {
                            Text("No folders selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(explorerStore.grantedFolderSummaries) { grant in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(grant.displayPath)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task {
                                            await explorerStore.removeGrantedFolder(id: grant.id)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove")
                                }
                            }

                            Button("Reset Folder Access", role: .destructive) {
                                Task {
                                    await explorerStore.resetGrantedFolders()
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .tabItem {
                    Label("Privacy & Access", systemImage: "lock.shield")
                }
            }
            .padding(20)
            .frame(width: 560, height: 420)
        }
    }

    private var paneModeBinding: Binding<ExplorerPaneMode> {
        Binding(
            get: {
                explorerStore.paneMode
            },
            set: { mode in
                Task {
                    await explorerStore.setPaneMode(mode)
                }
            }
        )
    }

    private var defaultSortKeyBinding: Binding<SortKey> {
        Binding(
            get: {
                explorerStore.defaultSort.key
            },
            set: { key in
                var descriptor = explorerStore.defaultSort
                descriptor.key = key
                explorerStore.setDefaultSort(descriptor)
            }
        )
    }

    private var defaultSortDirectionBinding: Binding<SortDirection> {
        Binding(
            get: {
                explorerStore.defaultSort.direction
            },
            set: { direction in
                var descriptor = explorerStore.defaultSort
                descriptor.direction = direction
                explorerStore.setDefaultSort(descriptor)
            }
        )
    }

    private var folderFileOrderingBinding: Binding<FolderFileOrdering> {
        Binding(
            get: {
                explorerStore.defaultSort.folderFileOrdering
            },
            set: { ordering in
                var descriptor = explorerStore.defaultSort
                descriptor.folderFileOrdering = ordering
                explorerStore.setDefaultSort(descriptor)
            }
        )
    }

    private var showHiddenFilesBinding: Binding<Bool> {
        Binding(
            get: {
                explorerStore.showHiddenFiles
            },
            set: { showHiddenFiles in
                Task {
                    await explorerStore.setShowHiddenFiles(showHiddenFiles)
                }
            }
        )
    }

    private func perform(_ command: ExplorerCommand) {
        Task {
            await explorerStore.perform(command)
        }
    }

    private func isEnabled(_ command: ExplorerCommand) -> Bool {
        explorerStore.isCommandEnabled(command)
    }

    private func openPrivacySettings() {
        NSWorkspace.shared.open(PermissionGuidance.privacySettingsURL)
    }
}
