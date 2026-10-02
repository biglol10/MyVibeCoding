import AppKit
import SwiftUI

@main
struct PaneHarborApp: App {
    @NSApplicationDelegateAdaptor(ExternalOpenAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var explorerStore: ExplorerStore
    @AppStorage("PaneHarbor.language") private var language = "system"
    @AppStorage("PaneHarbor.keyboardProfile") private var keyboardProfile = "windows"

    init() {
        _explorerStore = StateObject(
            wrappedValue: ExplorerStore(
                fileOperationService: FileOperationService(conflictResolver: AppKitFileConflictResolver()),
                sessionStore: UserDefaultsExplorerSessionStore(),
                zipExtractor: ZipExtractionService(conflictResolver: AppKitFileConflictResolver()),
                zipCompressor: ZipCompressionService(conflictResolver: AppKitFileConflictResolver())
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: "explorer") {
            RootView()
                // L10n resolves strings eagerly. Recreate child views when the
                // language changes while preserving the shared explorer state.
                .id(language)
                .environmentObject(explorerStore)
                .onOpenURL { url in
                    appDelegate.receiver.enqueue([url])
                }
                .task {
                    appDelegate.receiver.showWindow = {
                        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                            window.makeKeyAndOrderFront(nil)
                        } else {
                            openWindow(id: "explorer")
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    await appDelegate.receiver.start(store: explorerStore)
                }
        }
        .commands {
            CommandMenu(L10n.text("Go")) {
                Button(L10n.text("Connect to Server…")) {
                    explorerStore.isServerConnectionPresented = true
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button(L10n.text("Choose Folder…")) {
                    Task { await explorerStore.chooseWorkingFolder() }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("New Tab")) {
                    perform(.newTab)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(L10n.text("New Folder")) {
                    perform(.newFolder)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!isEnabled(.newFolder))

                Button(L10n.text("New File")) { perform(.newFile) }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!isEnabled(.newFile))
            }

            CommandGroup(replacing: .saveItem) {
                Button(L10n.text("Close Tab")) {
                    perform(.closeTab)
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Explorer") {
                Button(L10n.text("Close Tab")) {
                    perform(.closeTab)
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!isEnabled(.closeTab))

                Button(L10n.text("Next Tab")) {
                    perform(.nextTab)
                }
                .keyboardShortcut(.tab, modifiers: [.control])

                Button(L10n.text("Previous Tab")) {
                    perform(.previousTab)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button(L10n.text("Undo")) {
                    perform(.undo)
                }
                .disabled(!isEnabled(.undo))

                Divider()

                Button(L10n.text("Focus Search")) {
                    perform(.focusSearch)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(L10n.text("Focus Path")) {
                    perform(.focusPath)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button(L10n.text("Clear Search")) {
                    perform(.clearSearch)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Divider()

                Button(L10n.text("Select All")) {
                    perform(.selectAll)
                }
                .disabled(!isEnabled(.selectAll))

                Divider()

                Button(L10n.text("Open")) {
                    perform(.open)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!isEnabled(.open))

                Button(L10n.text("Quick Look")) {
                    perform(.quickLook)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!isEnabled(.quickLook))

                Button(L10n.text("Add to Favorites")) {
                    perform(.addToFavorites)
                }
                .disabled(!isEnabled(.addToFavorites))

                Button(L10n.text("Edit Tags")) {
                    perform(.editTags)
                }
                .disabled(!isEnabled(.editTags))

                Divider()

                Button(L10n.text("Rename")) {
                    perform(.rename)
                }
                .disabled(!isEnabled(.rename))

                Button(L10n.text("Batch Rename…")) { perform(.batchRename) }.disabled(!isEnabled(.batchRename))
                Button(L10n.text("Share…")) { perform(.share) }.disabled(!isEnabled(.share))

                Button(L10n.text("Duplicate")) {
                    perform(.duplicate)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!isEnabled(.duplicate))

                Button(L10n.text("Extract ZIP")) {
                    perform(.extractZip)
                }
                .disabled(!isEnabled(.extractZip))

                Button(L10n.text("Compress to ZIP")) {
                    perform(.compressToZip)
                }
                .disabled(!isEnabled(.compressToZip))

                Divider()

                Button(L10n.text("Copy")) {
                    perform(.copy)
                }
                .disabled(!isEnabled(.copy))

                Button(L10n.text("Cut")) {
                    perform(.cut)
                }
                .disabled(!isEnabled(.cut))

                Button(L10n.text("Paste")) {
                    perform(.paste)
                }
                .disabled(!isEnabled(.paste))

                Button(L10n.text("Copy Path")) {
                    perform(.copyPath)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!isEnabled(.copyPath))

                Divider()

                Button(L10n.text("Move to Trash")) {
                    perform(.moveToTrash)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!isEnabled(.moveToTrash))

                Button(L10n.text("Reveal in Finder")) {
                    perform(.revealInFinder)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!isEnabled(.revealInFinder))

                Divider()

                Button(L10n.text("Back")) {
                    perform(.goBack)
                }
                .disabled(!isEnabled(.goBack))

                Button(L10n.text("Forward")) {
                    perform(.goForward)
                }
                .disabled(!isEnabled(.goForward))

                Button(L10n.text("Go Up")) {
                    perform(.goUp)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!isEnabled(.goUp))

                Button(L10n.text("Refresh")) {
                    perform(.refresh)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(L10n.text("Toggle Hidden Files")) {
                    perform(.toggleHiddenFiles)
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Button(L10n.text("Toggle Inspector")) {
                    perform(.toggleInspector)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }

        Settings {
            TabView {
                ScrollView {
                    Form {
                        Section(L10n.text("Language & Keyboard")) {
                            Picker(L10n.text("Language"), selection: $language) {
                                Text(L10n.text("System")).tag("system")
                                Text("한국어").tag("ko")
                                Text("English").tag("en")
                            }
                            Picker(L10n.text("Keys"), selection: $keyboardProfile) {
                                Text(L10n.text("Windows keys")).tag("windows")
                                Text(L10n.text("Mac keys")).tag("mac")
                            }
                        }
                        Section(L10n.text("Layout")) {
                            Picker(L10n.text("Pane Mode"), selection: paneModeBinding) {
                                ForEach(ExplorerPaneMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Toggle(L10n.text("Show Inspector"), isOn: $explorerStore.isInspectorVisible)
                        }

                        Section(L10n.text("Files")) {
                            Toggle(L10n.text("Show Hidden Files"), isOn: showHiddenFilesBinding)
                            Picker(L10n.text("Default Sort"), selection: defaultSortKeyBinding) {
                                ForEach(SortKey.userSelectableCases, id: \.self) { key in
                                    Text(key.title).tag(key)
                                }
                            }
                            Picker(L10n.text("Sort Direction"), selection: defaultSortDirectionBinding) {
                                ForEach(SortDirection.allCases, id: \.self) { direction in
                                    Text(direction.title).tag(direction)
                                }
                            }
                            Picker(L10n.text("Folder/File Order"), selection: folderFileOrderingBinding) {
                                ForEach(FolderFileOrdering.allCases, id: \.self) { ordering in
                                    Text(ordering.title).tag(ordering)
                                }
                            }
                            Picker(L10n.text("Preview"), selection: previewModeBinding) {
                                ForEach(FilePreviewMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            Picker(L10n.text("Text Preview Limit"), selection: previewByteLimitBinding) {
                                ForEach(FilePreviewByteLimit.allCases) { limit in
                                    Text(limit.title).tag(limit)
                                }
                            }
                        }

                        SavedDataRecoveryView(
                            restorePreviousSession: restorePreviousSessionBinding,
                            settingsErrorMessage: explorerStore.settingsPersistenceErrorMessage,
                            sidebarErrorMessage: explorerStore.sidebarPersistenceErrorMessage,
                            sessionErrorMessage: explorerStore.sessionPersistenceErrorMessage,
                            onResetSettings: explorerStore.resetSavedSettings,
                            onResetSidebar: explorerStore.resetSavedSidebar,
                            onResetSession: explorerStore.resetSavedSession
                        )
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .tabItem {
                    Label(L10n.text("General"), systemImage: "slider.horizontal.3")
                }

                PrivacyAccessSettingsView(
                    sandboxPolicy: explorerStore.sandboxPolicy,
                    grantedFolderSummaries: explorerStore.grantedFolderSummaries,
                    persistenceErrorMessage: explorerStore.folderAccessPersistenceErrorMessage,
                    onChooseFolder: {
                        Task {
                            await explorerStore.chooseFolderForAccess()
                        }
                    },
                    onOpenPrivacySettings: openPrivacySettings,
                    onRemoveGrant: { id in
                        Task {
                            await explorerStore.removeGrantedFolder(id: id)
                        }
                    },
                    onResetGrants: {
                        Task {
                            await explorerStore.resetGrantedFolders()
                        }
                    }
                )
                .tabItem {
                    Label(L10n.text("Privacy & Access"), systemImage: "lock.shield")
                }
            }
            .id(language)
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

    private var previewByteLimitBinding: Binding<FilePreviewByteLimit> {
        Binding(
            get: {
                explorerStore.previewByteLimit
            },
            set: { limit in
                explorerStore.setPreviewByteLimit(limit)
            }
        )
    }

    private var previewModeBinding: Binding<FilePreviewMode> {
        Binding(
            get: {
                explorerStore.previewMode
            },
            set: { mode in
                explorerStore.setPreviewMode(mode)
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

    private var restorePreviousSessionBinding: Binding<Bool> {
        Binding(
            get: {
                explorerStore.restorePreviousSession
            },
            set: { restorePreviousSession in
                explorerStore.setRestorePreviousSession(restorePreviousSession)
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
