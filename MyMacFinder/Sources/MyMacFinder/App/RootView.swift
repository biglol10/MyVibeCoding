import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore
    @FocusState private var focusedToolbarField: ToolbarField?
    @State private var toolbarFocusClearSequence = 0

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                ToolbarPathView(
                    focusedField: $focusedToolbarField,
                    focusClearSequence: toolbarFocusClearSequence
                )
                TabBarView()
                if let progress = explorerStore.activeOperationProgress {
                    OperationProgressBanner(
                        snapshot: progress,
                        onCancel: {
                            explorerStore.cancelActiveOperation()
                        },
                        onDismiss: {
                            explorerStore.clearCompletedOperationProgress()
                        }
                    )
                }
                Divider()
                HSplitView {
                    filePane(at: 0)

                    if explorerStore.paneMode == .dual {
                        filePane(at: 1)
                    }

                    if explorerStore.isInspectorVisible {
                        InspectorView(
                            selection: explorerStore.activeSelectedEntries,
                            calculatedFolderSizes: explorerStore.calculatedFolderSizes,
                            onCommand: { command in
                                Task { await explorerStore.perform(command) }
                            }
                        )
                            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    }
                }
            }
        }
        .alert("MyMacFinder", isPresented: explorerStore.hasVisibleError) {
            if let guidance = explorerStore.visibleErrorGuidance,
               let actionTitle = guidance.primaryActionTitle {
                Button(actionTitle) {
                    performRecoveryAction(guidance)
                }
            }
            Button("OK", role: .cancel) {
                explorerStore.clearError()
            }
        } message: {
            Text(explorerStore.visibleErrorMessage)
        }
        .onChange(of: explorerStore.requestedFocus) { _, target in
            guard let target else {
                return
            }
            switch target {
            case .path:
                focusedToolbarField = .path
            case .search:
                focusedToolbarField = .search
            case .clear:
                focusedToolbarField = nil
                toolbarFocusClearSequence += 1
            }
            explorerStore.clearFocusRequest()
        }
        .onChange(of: focusedToolbarField) { _, field in
            explorerStore.setToolbarTextInputFocused(field != nil)
        }
        .background(
            ExplorerShortcutMonitor(
                isToolbarTextInputFocused: explorerStore.isToolbarTextInputFocused,
                isCommandEnabled: { explorerStore.isCommandEnabled($0) },
                onCommand: { command in
                    Task { await explorerStore.perform(command) }
                }
            )
            .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private func filePane(at index: Int) -> some View {
        if explorerStore.panes.indices.contains(index) {
            let pane = explorerStore.panes[index]
            FileTableView(
                entries: explorerStore.visibleEntries(forPaneAt: index),
                selectedURLs: pane.selectedURLs,
                canPaste: explorerStore.canPaste,
                canUndo: explorerStore.canUndo,
                canCloseTab: explorerStore.canCloseTab,
                canGoBack: !pane.backStack.isEmpty,
                canGoForward: !pane.forwardStack.isEmpty,
                canGoUp: explorerStore.canGoUp(forPaneAt: index),
                currentURL: pane.currentURL,
                currentLocation: pane.location,
                currentSort: pane.sort,
                showsPathColumn: explorerStore.isShowingRecursiveSearchResults,
                requestsInitialFocus: index == explorerStore.activePaneIndex,
                onFocus: {
                    focusedToolbarField = nil
                    explorerStore.activatePane(at: index)
                    explorerStore.setToolbarTextInputFocused(false)
                },
                onSelectionChange: { urls in
                    explorerStore.activatePane(at: index)
                    explorerStore.updateSelection(urls)
                },
                onOpen: { url in
                    explorerStore.activatePane(at: index)
                    Task { await explorerStore.open(url) }
                },
                onCommand: { command in
                    explorerStore.activatePane(at: index)
                    Task { await explorerStore.perform(command) }
                },
                openWithApplications: explorerStore.openWithApplications(forPaneAt: index),
                onOpenWithApplication: { application in
                    explorerStore.activatePane(at: index)
                    Task { await explorerStore.openSelected(with: application) }
                },
                onDropItems: { urls, destinationFolder, operation in
                    explorerStore.activatePane(at: index)
                    Task {
                        await explorerStore.performDrop(
                            urls: urls,
                            destinationFolder: destinationFolder,
                            operation: operation
                        )
                    }
                },
                onSortChange: { sortKey in
                    explorerStore.activatePane(at: index)
                    explorerStore.sortActivePane(by: sortKey)
                }
            )
            .frame(minWidth: explorerStore.paneMode == .dual ? 420 : 520)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: explorerStore.activePaneIndex == index ? 2 : 0)
            }
        }
    }

    private func performRecoveryAction(_ guidance: PermissionGuidance) {
        switch guidance.recoveryAction {
        case .chooseFolder:
            let retryingPath = explorerStore.pendingPermissionRecoveryPath
            let startingURL = retryingPath.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            Task {
                await explorerStore.chooseFolderForAccess(
                    startingAt: startingURL,
                    retryingPermissionPath: retryingPath
                )
            }
        case .openPrivacySettings:
            NSWorkspace.shared.open(PermissionGuidance.privacySettingsURL)
            explorerStore.clearError()
        case .none:
            explorerStore.clearError()
        }
    }
}

private struct TabBarView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(explorerStore.tabs.enumerated()), id: \.element.id) { index, tab in
                        ExplorerTabButton(
                            title: tab.title,
                            isActive: index == explorerStore.activeTabIndex,
                            canClose: explorerStore.tabs.count > 1,
                            onSelect: {
                                Task { await explorerStore.selectTab(at: index) }
                            },
                            onClose: {
                                Task { await explorerStore.closeTab(at: index) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                Task { await explorerStore.newTab() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ExplorerTabButton: View {
    var title: String
    var isActive: Bool
    var canClose: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 8)
        .frame(width: 170, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isActive ? Color.accentColor.opacity(0.38) : Color.clear, lineWidth: 1)
        )
    }
}

private struct ExplorerShortcutMonitor: NSViewRepresentable {
    var isToolbarTextInputFocused: Bool
    var isCommandEnabled: (ExplorerCommand) -> Bool
    var onCommand: (ExplorerCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isToolbarTextInputFocused: isToolbarTextInputFocused,
            isCommandEnabled: isCommandEnabled,
            onCommand: onCommand
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.isToolbarTextInputFocused = isToolbarTextInputFocused
        context.coordinator.isCommandEnabled = isCommandEnabled
        context.coordinator.onCommand = onCommand
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isToolbarTextInputFocused = isToolbarTextInputFocused
        context.coordinator.isCommandEnabled = isCommandEnabled
        context.coordinator.onCommand = onCommand
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var isToolbarTextInputFocused: Bool
        var isCommandEnabled: (ExplorerCommand) -> Bool
        var onCommand: (ExplorerCommand) -> Void
        private var monitor: Any?

        init(
            isToolbarTextInputFocused: Bool,
            isCommandEnabled: @escaping (ExplorerCommand) -> Bool,
            onCommand: @escaping (ExplorerCommand) -> Void
        ) {
            self.isToolbarTextInputFocused = isToolbarTextInputFocused
            self.isCommandEnabled = isCommandEnabled
            self.onCommand = onCommand
        }

        func install() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                guard
                    let shortcut = Self.shortcut(from: event),
                    let command = ExplorerShortcutRouting.command(
                        for: shortcut,
                        isToolbarTextInputFocused: isToolbarTextInputFocused,
                        isCommandEnabled: isCommandEnabled
                    )
                else {
                    return event
                }

                onCommand(command)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private static func shortcut(from event: NSEvent) -> ExplorerShortcut? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let unsupportedFlags = flags.subtracting([.command, .control, .shift, .capsLock, .numericPad, .function])
            guard unsupportedFlags.isEmpty else {
                return nil
            }

            var modifiers = Set<ExplorerShortcutModifier>()
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }

            let key: String
            switch event.keyCode {
            case 48:
                key = "tab"
            default:
                key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            }

            guard !key.isEmpty else {
                return nil
            }
            return ExplorerShortcut(key: key, modifiers: modifiers)
        }
    }
}
