import AppKit
import SwiftUI

enum ToolbarField: Hashable {
    case path
    case search
}

struct ToolbarPathView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore
    @FocusState.Binding var focusedField: ToolbarField?
    var focusClearSequence: Int = 0
    @State private var isSearchOptionsPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await explorerStore.goBack() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(explorerStore.activePane.backStack.isEmpty)

            Button {
                Task { await explorerStore.goForward() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(explorerStore.activePane.forwardStack.isEmpty)

            Button {
                Task { await explorerStore.goUp() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!explorerStore.canGoUp)

            PathInputField(
                text: $explorerStore.pathInput,
                isFocused: focusedField == .path,
                focusClearSequence: focusClearSequence,
                onFocusChange: { isFocused in
                    focusedField = isFocused ? .path : nil
                },
                onSubmit: { path in
                    Task { await explorerStore.resolveAndNavigate(path) }
                }
            )

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Search",
                    text: Binding(
                        get: { explorerStore.searchQuery },
                        set: { explorerStore.setSearchQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
                .onExitCommand {
                    explorerStore.clearSearch()
                }

                if explorerStore.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                if !explorerStore.searchQuery.isEmpty {
                    Button {
                        explorerStore.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button {
                    isSearchOptionsPresented.toggle()
                } label: {
                    Image(systemName: explorerStore.searchOptions == ExplorerSearchOptions()
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Search Options")
                .popover(isPresented: $isSearchOptionsPresented, arrowEdge: .bottom) {
                    SearchOptionsPopover(
                        scope: searchScopeBinding,
                        kind: searchKindBinding,
                        fileExtension: searchFileExtensionBinding,
                        finderTagQuery: searchFinderTagQueryBinding
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 300)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button {
                Task { await explorerStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var searchScopeBinding: Binding<SearchScope> {
        Binding(
            get: { explorerStore.searchOptions.scope },
            set: { explorerStore.setSearchScope($0) }
        )
    }

    private var searchKindBinding: Binding<SearchKindFilter> {
        Binding(
            get: { explorerStore.searchOptions.kind },
            set: { explorerStore.setSearchKindFilter($0) }
        )
    }

    private var searchFileExtensionBinding: Binding<String> {
        Binding(
            get: { explorerStore.searchOptions.fileExtension },
            set: { explorerStore.setSearchFileExtension($0) }
        )
    }

    private var searchFinderTagQueryBinding: Binding<String> {
        Binding(
            get: { explorerStore.searchOptions.finderTagQuery },
            set: { explorerStore.setSearchFinderTagQuery($0) }
        )
    }
}

struct PathInputField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var focusClearSequence: Int = 0
    var onFocusChange: (Bool) -> Void
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Path"
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submitFromTextField(_:))
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.attach(textField)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyTextIfNeeded(text, to: nsView)
        context.coordinator.applyFocusClearIfNeeded(focusClearSequence, to: nsView)
        context.coordinator.syncFocus(for: nsView, shouldFocus: isFocused)
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathInputField
        private var isApplyingFocus = false
        private weak var monitoredTextField: NSTextField?
        private var returnKeyMonitor: Any?
        private var appliedFocusClearSequence: Int

        init(parent: PathInputField) {
            self.parent = parent
            self.appliedFocusClearSequence = parent.focusClearSequence
        }

        func attach(_ textField: NSTextField) {
            monitoredTextField = textField
            installReturnKeyMonitor(for: textField)
        }

        func detach() {
            removeReturnKeyMonitor()
            monitoredTextField = nil
        }

        func syncFocus(for textField: NSTextField, shouldFocus: Bool) {
            guard let window = textField.window else {
                return
            }
            if shouldFocus, window.firstResponder !== textField.currentEditor() {
                isApplyingFocus = true
                window.makeFirstResponder(textField)
                textField.currentEditor()?.selectAll(nil)
                isApplyingFocus = false
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard !isApplyingFocus else {
                return
            }
            if let textField = notification.object as? NSTextField {
                installReturnKeyMonitor(for: textField)
            }
            parent.onFocusChange(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent.text = visibleText(for: textField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func applyTextIfNeeded(_ text: String, to textField: NSTextField) {
            guard visibleText(for: textField) != text else {
                return
            }

            let editor = activeEditor(for: textField)
            textField.stringValue = text
            editor?.string = text
        }

        func applyFocusClearIfNeeded(_ sequence: Int, to textField: NSTextField) {
            guard sequence != appliedFocusClearSequence else {
                return
            }

            appliedFocusClearSequence = sequence
            resignFocus(for: textField)
        }

        @objc func submitFromTextField(_ sender: NSTextField) {
            submit(activeEditor(for: sender)?.string ?? sender.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let newlineCommands = [
                #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            ]
            guard newlineCommands.contains(commandSelector) else {
                return false
            }

            submit(textView.string)
            return true
        }

        private func submit(_ submittedText: String) {
            parent.text = submittedText
            parent.onSubmit(submittedText)
        }

        private func visibleText(for textField: NSTextField) -> String {
            activeEditor(for: textField)?.string ?? textField.stringValue
        }

        private func resignFocus(for textField: NSTextField) {
            guard let window = textField.window,
                  let editor = activeEditor(for: textField),
                  window.firstResponder === editor else {
                return
            }
            window.makeFirstResponder(nil)
        }

        private func installReturnKeyMonitor(for textField: NSTextField) {
            removeReturnKeyMonitor()
            returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak textField] event in
                guard let self,
                      let textField,
                      let editor = self.activeEditor(for: textField),
                      Self.isPlainReturnKey(event) else {
                    return event
                }
                self.submit(editor.string)
                return nil
            }
        }

        private func removeReturnKeyMonitor() {
            if let returnKeyMonitor {
                NSEvent.removeMonitor(returnKeyMonitor)
                self.returnKeyMonitor = nil
            }
        }

        static func isPlainReturnKey(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.numericPad)
            guard modifiers.isEmpty else {
                return false
            }

            return event.keyCode == 36
                || event.keyCode == 76
                || event.charactersIgnoringModifiers == "\r"
                || event.charactersIgnoringModifiers == "\n"
        }

        private func activeEditor(for textField: NSTextField) -> NSText? {
            if let currentEditor = textField.currentEditor() {
                return currentEditor
            }

            guard let window = textField.window,
                  let fieldEditor = window.fieldEditor(false, for: textField),
                  window.firstResponder === fieldEditor else {
                return nil
            }
            return fieldEditor
        }
    }
}

private struct SearchOptionsPopover: View {
    @Binding var scope: SearchScope
    @Binding var kind: SearchKindFilter
    @Binding var fileExtension: String
    @Binding var finderTagQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Scope", selection: $scope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Picker("Kind", selection: $kind) {
                ForEach(SearchKindFilter.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField("Extension", text: $fileExtension)
                .textFieldStyle(.roundedBorder)

            TextField("Tag", text: $finderTagQuery)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .frame(width: 280)
    }
}
