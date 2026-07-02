import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileTableColumnDefinition {
    let key: String
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
}

struct FileTableIconResolver {
    typealias ResolveIcon = @MainActor (FileEntry) -> NSImage

    private let resolveIcon: ResolveIcon

    init(_ resolveIcon: @escaping ResolveIcon) {
        self.resolveIcon = resolveIcon
    }

    @MainActor
    func icon(for entry: FileEntry) -> NSImage {
        Self.sizedIcon(resolveIcon(entry))
    }

    static let live = FileTableIconResolver { entry in
        defaultIcon(for: entry)
    }

    @MainActor
    private static func defaultIcon(for entry: FileEntry) -> NSImage {
        switch entry.kind {
        case .folder, .volume, .zipVirtualFolder:
            return NSImage(named: NSImage.folderName)
                ?? NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
                ?? typeIcon(for: nil)
        case .package:
            return NSImage(named: NSImage.applicationIconName)
                ?? NSImage(systemSymbolName: "app", accessibilityDescription: "Package")
                ?? NSWorkspace.shared.icon(for: .applicationBundle)
        case .symlink:
            return NSImage(systemSymbolName: "arrowshape.turn.up.right", accessibilityDescription: "Alias")
                ?? typeIcon(for: entry.fileExtension)
        case .file, .zipVirtualFile, .other:
            if !entry.fileExtension.isEmpty {
                return typeIcon(for: entry.fileExtension)
            }
            return NSImage(named: NSImage.multipleDocumentsName)
                ?? NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
                ?? typeIcon(for: nil)
        }
    }

    @MainActor
    private static func typeIcon(for fileExtension: String?) -> NSImage {
        let contentType = fileExtension
            .flatMap { UTType(filenameExtension: $0) }
            ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }

    @MainActor
    private static func sizedIcon(_ image: NSImage) -> NSImage {
        let icon = image.copy() as? NSImage ?? image
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

struct FileTableView: NSViewRepresentable {
    private static let sortableColumnKeys: Set<String> = [
        "name",
        "size",
        "modified",
        "kind",
        "path"
    ]

    var entries: [FileEntry]
    var selectedURLs: Set<URL>
    var canPaste: Bool
    var canUndo: Bool
    var canCloseTab: Bool
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var canGoUp: Bool = true
    var currentURL: URL
    var currentLocation: PaneLocation
    var currentSort: EntrySortDescriptor
    var showsPathColumn: Bool
    var inlineRenameRequest: InlineRenameRequest?
    var requestsInitialFocus: Bool = false
    var onFocus: () -> Void = {}
    var onSelectionChange: (Set<URL>) -> Void
    var onOpen: (URL) -> Void
    var onRename: (String) -> Void = { _ in }
    var onCommand: (ExplorerCommand) -> Void
    var isCommandEnabled: (ExplorerCommand) -> Bool = { _ in true }
    var openWithApplications: [OpenWithApplication] = []
    var onOpenWithApplication: (OpenWithApplication) -> Void = { _ in }
    var iconResolver: FileTableIconResolver = .live
    var onDropItems: ([URL], URL, DropOperation) -> Void
    var onSortChange: (SortKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ContextMenuTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.target = context.coordinator
        tableView.menuProvider = context.coordinator
        tableView.registerForDraggedTypes(FileDropPasteboardReader.acceptedTypes)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.columnAutoresizingStyle = columnAutoresizingStyle
        let coordinator = context.coordinator
        tableView.didMoveToWindowHandler = { [weak coordinator] in
            coordinator?.requestInitialFocusIfNeeded()
        }

        for column in columnDefinitions {
            tableView.addTableColumn(makeTableColumn(column))
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.requestInitialFocusIfNeeded()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncColumns()
        context.coordinator.resetScrollIfLocationChanged(in: nsView)
        context.coordinator.reloadDataIfNeeded()
        context.coordinator.applySelection(selectedURLs)
        context.coordinator.syncSortDescriptor()
        context.coordinator.syncInlineRenameRequest()
        context.coordinator.requestInitialFocusIfNeeded()
    }

    var columnDefinitions: [FileTableColumnDefinition] {
        var columns = [
            FileTableColumnDefinition(key: "name", title: "Name", width: 300, minWidth: 220),
            FileTableColumnDefinition(key: "size", title: "Size", width: 60, minWidth: 50),
            FileTableColumnDefinition(key: "modified", title: "Date Modified", width: 150, minWidth: 140),
            FileTableColumnDefinition(key: "kind", title: "Kind", width: 170, minWidth: 150),
            FileTableColumnDefinition(key: "tags", title: "Tags", width: 60, minWidth: 50)
        ]
        if showsPathColumn {
            columns.append(FileTableColumnDefinition(key: "path", title: "Path", width: 280, minWidth: 220))
        }
        return columns
    }

    var columnAutoresizingStyle: NSTableView.ColumnAutoresizingStyle {
        .firstColumnOnlyAutoresizingStyle
    }

    func makeTableColumn(_ column: FileTableColumnDefinition) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
        tableColumn.title = column.title
        tableColumn.width = column.width
        tableColumn.minWidth = column.minWidth
        tableColumn.resizingMask = [.userResizingMask, .autoresizingMask]
        if Self.sortableColumnKeys.contains(column.key) {
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.key, ascending: true)
        }
        return tableColumn
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?
        private var renderedEntries: [FileEntry] = []
        private var renderedLocation: PaneLocation?
        private var isSyncingSortDescriptor = false
        private var didRequestInitialFocus = false
        private var iconCache: [IconCacheKey: NSImage] = [:]
        private var handledInlineRenameRequestID: UUID?
        private weak var activeInlineRenameField: InlineRenameTextField?
        private weak var activeInlineRenameSourceTextField: NSTextField?
        private var activeInlineRenameOriginalName: String?
        private var isPreparingInlineRenameEditor = false
        private static let inlineRenameFieldAccessibilityIdentifier = "FileTableInlineRenameField"

        private struct IconCacheKey: Hashable {
            var kind: FileEntryKind
            var fileExtension: String
            var isArchiveBacked: Bool

            init(entry: FileEntry) {
                self.kind = entry.kind
                self.fileExtension = entry.fileExtension
                self.isArchiveBacked = entry.isArchiveBacked
            }
        }

        init(parent: FileTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.entries.count else {
                return nil
            }

            let entry = parent.entries[row]
            let identifier = tableColumn?.identifier.rawValue ?? "name"
            let cellIdentifier = NSUserInterfaceItemIdentifier("FileTableCell.\(identifier)")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
                ?? makeReusableCell(identifier: cellIdentifier, column: identifier)
            cell.textField?.stringValue = value(for: entry, column: identifier)
            if identifier == "name" {
                cell.imageView?.image = icon(for: entry)
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            handleTableFocus()
            publishSelection()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isSyncingSortDescriptor else {
                return
            }
            guard
                let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key,
                let sortKey = sortKey(for: key)
            else {
                return
            }
            parent.onSortChange(sortKey)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0, row < parent.entries.count else {
                return nil
            }
            let entry = parent.entries[row]
            guard !entry.isArchiveBacked else {
                return nil
            }
            return entry.url as NSURL
        }

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
            let urls = rowIndexes.compactMap { index -> NSURL? in
                guard index >= 0, index < parent.entries.count else {
                    return nil
                }
                let entry = parent.entries[index]
                guard !entry.isArchiveBacked else {
                    return nil
                }
                return entry.url as NSURL
            }
            guard !urls.isEmpty else {
                return false
            }

            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
            return true
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let normalizedDropOperation = normalizedDropOperation(
                row: row,
                dropOperation: dropOperation,
                tableView: tableView
            )
            return validateDrop(info, row: row, dropOperation: normalizedDropOperation)
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            acceptDrop(info, row: row, dropOperation: dropOperation)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? InlineRenameTextField,
                  field === activeInlineRenameField,
                  let originalName = activeInlineRenameOriginalName else {
                return
            }

            let fieldEditor = notification.userInfo?["NSFieldEditor"] as? NSText
            syncInlineRenameText(field, name: originalName, fieldEditor: fieldEditor)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? InlineRenameTextField,
                  field === activeInlineRenameField else {
                return
            }
            guard !isPreparingInlineRenameEditor else {
                return
            }

            let didCancel = field.didCancelRename
            let originalName = activeInlineRenameOriginalName
            let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            removeInlineRenameEditor()

            guard !didCancel,
                  !newName.isEmpty,
                  newName != originalName else {
                return
            }
            parent.onRename(newName)
        }

        func publishSelection() {
            guard let tableView else {
                return
            }
            let urls = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < parent.entries.count else { return nil }
                return parent.entries[index].url
            }
            let newSelection = Set(urls)
            guard newSelection != parent.selectedURLs else {
                return
            }
            parent.onSelectionChange(newSelection)
        }

        func handleTableFocus() {
            parent.onFocus()
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.entries.count else {
                return
            }
            if !sender.selectedRowIndexes.contains(row) {
                sender.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            publishSelection()
            parent.onOpen(parent.entries[row].url)
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard
                let shortcut = shortcut(from: event),
                let command = ExplorerKeyboardShortcut.command(for: shortcut)
            else {
                return false
            }

            return performCommand(command)
        }

        func canPerformCommand(_ command: ExplorerCommand) -> Bool {
            guard parent.isCommandEnabled(command) else {
                return false
            }
            return command.isEnabled(
                selectionCount: currentSelectionCount,
                canPaste: parent.canPaste,
                canUndo: parent.canUndo,
                canCloseTab: parent.canCloseTab,
                canGoBack: parent.canGoBack,
                canGoForward: parent.canGoForward,
                canGoUp: parent.canGoUp,
                selectedEntries: currentSelectedEntries,
                isArchiveLocation: parent.currentLocation.isArchive
            )
        }

        func performCommand(_ command: ExplorerCommand) -> Bool {
            guard canPerformCommand(command) else {
                return false
            }
            if command == .rename {
                return beginInlineRenameForCurrentSelection()
            }
            parent.onCommand(command)
            return true
        }

        func itemMenu() -> NSMenu {
            let menu = NSMenu()
            addMenuItem(to: menu, command: .undo)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .open)
            addOpenWithMenu(to: menu)
            if canPerformCommand(.openInTerminal) || canPerformCommand(.openInVSCode) {
                addMenuItem(to: menu, command: .openInTerminal)
                addMenuItem(to: menu, command: .openInVSCode)
            }
            addMenuItem(to: menu, command: .addToFavorites)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .rename)
            addMenuItem(to: menu, command: .editTags)
            addMenuItem(to: menu, command: .duplicate)
            addMenuItem(to: menu, command: .extractZip)
            addMenuItem(to: menu, command: .compressToZip)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .copy)
            addMenuItem(to: menu, command: .cut)
            addMenuItem(to: menu, command: .paste)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .copyPath)
            addMenuItem(to: menu, command: .moveToTrash)
            addMenuItem(to: menu, command: .revealInFinder)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .refresh)
            return menu
        }

        func emptyMenu() -> NSMenu {
            let menu = NSMenu()
            addMenuItem(to: menu, command: .undo, selectionCount: 0)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .newFolder)
            addMenuItem(to: menu, command: .paste, selectionCount: 0)
            menu.addItem(.separator())
            addMenuItem(to: menu, command: .refresh)
            return menu
        }

        func applySelection(_ urls: Set<URL>) {
            guard let tableView else {
                return
            }

            let indexes = IndexSet(parent.entries.enumerated().compactMap { index, entry in
                urls.contains(entry.url) ? index : nil
            })

            if tableView.selectedRowIndexes != indexes {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        func reloadDataIfNeeded() {
            guard renderedEntries != parent.entries else {
                return
            }

            let previousEntries = renderedEntries
            renderedEntries = parent.entries
            iconCache.removeAll()
            if reloadChangedRowsIfPossible(previousEntries: previousEntries, updatedEntries: parent.entries) {
                return
            }
            tableView?.reloadData()
        }

        private func reloadChangedRowsIfPossible(previousEntries: [FileEntry], updatedEntries: [FileEntry]) -> Bool {
            guard let tableView, !previousEntries.isEmpty, previousEntries.count == updatedEntries.count else {
                return false
            }

            let previousURLs = previousEntries.map(\.url)
            let updatedURLs = updatedEntries.map(\.url)
            guard previousURLs == updatedURLs else {
                return false
            }

            let changedRows = IndexSet(updatedEntries.indices.filter { previousEntries[$0] != updatedEntries[$0] })
            guard !changedRows.isEmpty else {
                return true
            }

            let columns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: changedRows, columnIndexes: columns)
            return true
        }

        func resetScrollIfLocationChanged(in scrollView: NSScrollView) {
            guard renderedLocation != parent.currentLocation else {
                return
            }

            renderedLocation = parent.currentLocation
            iconCache.removeAll()
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func syncColumns() {
            guard let tableView else {
                return
            }

            let desiredKeys = parent.columnDefinitions.map(\.key)
            let currentKeys = tableView.tableColumns.map(\.identifier.rawValue)
            guard desiredKeys != currentKeys else {
                return
            }

            tableView.tableColumns.forEach(tableView.removeTableColumn)
            parent.columnDefinitions
                .map(parent.makeTableColumn)
                .forEach(tableView.addTableColumn)
        }

        func syncSortDescriptor() {
            guard let tableView else {
                return
            }
            guard let columnKey = columnKey(for: parent.currentSort.key) else {
                isSyncingSortDescriptor = true
                tableView.sortDescriptors = []
                isSyncingSortDescriptor = false
                return
            }

            let descriptor = NSSortDescriptor(
                key: columnKey,
                ascending: parent.currentSort.direction == .ascending
            )

            guard tableView.sortDescriptors != [descriptor] else {
                return
            }

            isSyncingSortDescriptor = true
            tableView.sortDescriptors = [descriptor]
            isSyncingSortDescriptor = false
        }

        func requestInitialFocusIfNeeded() {
            guard parent.requestsInitialFocus, !didRequestInitialFocus, let tableView, let window = tableView.window else {
                return
            }

            window.makeFirstResponder(tableView)
            didRequestInitialFocus = true
        }

        func syncInlineRenameRequest() {
            guard let request = parent.inlineRenameRequest else {
                return
            }
            guard handledInlineRenameRequestID != request.id else {
                return
            }
            handledInlineRenameRequestID = request.id
            beginInlineRename(for: request.url)
        }

        @discardableResult
        private func beginInlineRenameForCurrentSelection() -> Bool {
            guard let entry = currentSelectedEntries.first else {
                return false
            }
            return beginInlineRename(for: entry.url)
        }

        @discardableResult
        private func beginInlineRename(for url: URL) -> Bool {
            guard let tableView else {
                return false
            }
            guard let row = parent.entries.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
                return false
            }
            let nameColumn = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
            guard nameColumn >= 0 else {
                return false
            }

            let entryName = parent.entries[row].name
            tableView.window?.makeFirstResponder(tableView)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            publishSelection()

            tableView.scrollRowToVisible(row)
            tableView.scrollColumnToVisible(nameColumn)
            tableView.layoutSubtreeIfNeeded()

            guard let cell = tableView.view(atColumn: nameColumn, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let sourceTextField = cell.textField else {
                return false
            }
            sourceTextField.stringValue = entryName
            sourceTextField.objectValue = entryName
            cell.objectValue = entryName
            showInlineRenameEditor(
                name: entryName,
                cell: cell,
                sourceTextField: sourceTextField,
                tableView: tableView
            )
            return true
        }

        private func showInlineRenameEditor(
            name: String,
            cell: NSTableCellView,
            sourceTextField: NSTextField,
            tableView: NSTableView
        ) {
            removeInlineRenameEditor()

            let field = InlineRenameTextField(string: name)
            field.setAccessibilityIdentifier(Self.inlineRenameFieldAccessibilityIdentifier)
            field.delegate = self
            field.font = sourceTextField.font
            field.textColor = sourceTextField.textColor
            field.lineBreakMode = .byClipping
            field.maximumNumberOfLines = 1
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = true
            field.isBezeled = true
            field.drawsBackground = true
            field.backgroundColor = .textBackgroundColor
            field.focusRingType = .default
            field.translatesAutoresizingMaskIntoConstraints = false

            sourceTextField.isHidden = true
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: sourceTextField.leadingAnchor, constant: -3),
                field.trailingAnchor.constraint(equalTo: sourceTextField.trailingAnchor, constant: 3),
                field.centerYAnchor.constraint(equalTo: sourceTextField.centerYAnchor),
                field.heightAnchor.constraint(greaterThanOrEqualTo: sourceTextField.heightAnchor, constant: 6)
            ])

            activeInlineRenameField = field
            activeInlineRenameSourceTextField = sourceTextField
            activeInlineRenameOriginalName = name

            isPreparingInlineRenameEditor = true
            focusInlineRenameField(field, in: tableView, name: name)
            scheduleInlineRenameSettledSync(field, in: tableView, name: name)
        }

        private func removeInlineRenameEditor() {
            activeInlineRenameSourceTextField?.isHidden = false
            activeInlineRenameField?.removeFromSuperview()
            activeInlineRenameField = nil
            activeInlineRenameSourceTextField = nil
            activeInlineRenameOriginalName = nil
            isPreparingInlineRenameEditor = false
        }

        private func focusInlineRenameField(_ field: InlineRenameTextField, in tableView: NSTableView, name: String) {
            guard let window = tableView.window else {
                syncInlineRenameText(field, name: name)
                return
            }
            window.makeFirstResponder(field)
            syncInlineRenameText(field, name: name)
        }

        private func scheduleInlineRenameSettledSync(
            _ field: InlineRenameTextField,
            in tableView: NSTableView,
            name: String
        ) {
            let delays: [TimeInterval] = [0, 0.05, 0.15]
            for (index, delay) in delays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak field, weak tableView] in
                    guard let self,
                          let field,
                          let tableView,
                          field === self.activeInlineRenameField else {
                        return
                    }

                    let currentText = field.currentEditor()?.string ?? field.stringValue
                    if currentText == name
                        || currentText == self.parent.currentURL.path
                        || currentText == self.parent.currentLocation.displayPath {
                        self.focusInlineRenameField(field, in: tableView, name: name)
                    }

                    if index == 0 {
                        self.isPreparingInlineRenameEditor = false
                    }
                }
            }
        }

        private func syncInlineRenameText(
            _ field: InlineRenameTextField,
            name: String,
            fieldEditor: NSText? = nil
        ) {
            field.stringValue = name
            let editor = fieldEditor ?? field.currentEditor()
            editor?.string = name
            editor?.selectedRange = NSRange(location: 0, length: (name as NSString).length)
        }

        private func addMenuItem(
            to menu: NSMenu,
            command: ExplorerCommand,
            selectionCount: Int? = nil,
            title: String? = nil
        ) {
            let item = NSMenuItem(
                title: title ?? command.title,
                action: #selector(runMenuCommand(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = command.rawValue
            item.isEnabled = command.isEnabled(
                selectionCount: selectionCount ?? currentSelectionCount,
                canPaste: parent.canPaste,
                canUndo: parent.canUndo,
                canCloseTab: parent.canCloseTab,
                canGoBack: parent.canGoBack,
                canGoForward: parent.canGoForward,
                selectedEntries: currentSelectedEntries,
                isArchiveLocation: parent.currentLocation.isArchive
            )
            menu.addItem(item)
        }

        private func addOpenWithMenu(to menu: NSMenu) {
            let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Open With")

            addMenuItem(to: submenu, command: .open, title: "Default App")

            let applications = parent.openWithApplications.prefix(8)
            if !applications.isEmpty {
                submenu.addItem(.separator())
                for application in applications {
                    addOpenWithApplicationItem(to: submenu, application: application)
                }
            }

            submenu.addItem(.separator())
            addMenuItem(to: submenu, command: .chooseOpenWithApplication)

            item.submenu = submenu
            item.isEnabled = currentSelectionCount > 0 && !parent.currentLocation.isArchive
            menu.addItem(item)
        }

        private func addOpenWithApplicationItem(to menu: NSMenu, application: OpenWithApplication) {
            let item = NSMenuItem(
                title: application.title,
                action: #selector(runOpenWithApplicationMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = application
            item.isEnabled = currentSelectionCount > 0 && !parent.currentLocation.isArchive
            menu.addItem(item)
        }

        @objc private func runOpenWithApplicationMenuItem(_ sender: NSMenuItem) {
            guard let application = sender.representedObject as? OpenWithApplication else {
                return
            }
            parent.onOpenWithApplication(application)
        }

        private func makeReusableCell(
            identifier: NSUserInterfaceItemIdentifier,
            column: String
        ) -> NSTableCellView {
            if column == "name" {
                return makeReusableNameCell(identifier: identifier)
            }
            return makeReusableTextCell(identifier: identifier)
        }

        private func makeReusableNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = baseCell(identifier: identifier)

            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = imageView
            cell.addSubview(imageView)

            let textField = makeTextField(isEditable: false)
            textField.delegate = self
            cell.textField = textField
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func makeReusableTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = baseCell(identifier: identifier)
            let textField = makeTextField(isEditable: false)
            cell.textField = textField
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func baseCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            cell.wantsLayer = true
            cell.layer?.masksToBounds = true
            return cell
        }

        private func makeTextField(isEditable: Bool) -> NSTextField {
            let textField = NSTextField(string: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.maximumNumberOfLines = 1
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = isEditable
            textField.isSelectable = isEditable
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.translatesAutoresizingMaskIntoConstraints = false
            return textField
        }

        private func icon(for entry: FileEntry) -> NSImage {
            let cacheKey = IconCacheKey(entry: entry)
            if let cached = iconCache[cacheKey] {
                return cached
            }

            let icon = parent.iconResolver.icon(for: entry)
            iconCache[cacheKey] = icon
            return icon
        }

        @objc private func runMenuCommand(_ sender: NSMenuItem) {
            guard
                let rawValue = sender.representedObject as? String,
                let command = ExplorerCommand(rawValue: rawValue)
            else {
                return
            }
            parent.onCommand(command)
        }

        private func shortcut(from event: NSEvent) -> ExplorerShortcut? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let unsupportedFlags = flags.subtracting([.command, .control, .option, .shift, .capsLock, .numericPad, .function])
            guard unsupportedFlags.isEmpty else {
                return nil
            }

            var modifiers = Set<ExplorerShortcutModifier>()
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }

            let key = ExplorerKeyCodeMapper.key(
                for: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            )

            guard !key.isEmpty else {
                return nil
            }
            return ExplorerShortcut(key: key, modifiers: modifiers)
        }

        private var currentSelectionCount: Int {
            tableView?.selectedRowIndexes.count ?? parent.selectedURLs.count
        }

        private var currentSelectedEntries: [FileEntry] {
            guard let tableView else {
                return parent.entries.filter { parent.selectedURLs.contains($0.url) }
            }
            return tableView.selectedRowIndexes.compactMap { index in
                guard index >= 0, index < parent.entries.count else {
                    return nil
                }
                return parent.entries[index]
            }
        }

        private func columnKey(for sortKey: SortKey) -> String? {
            switch sortKey {
            case .name:
                return "name"
            case .size:
                return "size"
            case .dateModified:
                return "modified"
            case .kind:
                return "kind"
            case .path:
                return "path"
            case .fileExtension, .dateCreated, .dateAccessed, .permissions, .owner, .hidden, .folderFileType:
                return nil
            }
        }

        private func sortKey(for columnKey: String) -> SortKey? {
            switch columnKey {
            case "name":
                return .name
            case "size":
                return .size
            case "modified":
                return .dateModified
            case "kind":
                return .kind
            case "path":
                return .path
            default:
                return nil
            }
        }

        private struct PendingDrop {
            var urls: [URL]
            var destinationFolder: URL
            var operation: DropOperation
        }

        private func validateDrop(
            _ info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard !parent.currentLocation.isArchive else {
                return []
            }
            guard
                let drop = makeDrop(info: info, row: row, dropOperation: dropOperation),
                canDrop(drop)
            else {
                return []
            }

            return drop.operation == .copy ? .copy : .move
        }

        private func acceptDrop(
            _ info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard
                let drop = makeDrop(info: info, row: row, dropOperation: dropOperation),
                canDrop(drop)
            else {
                return false
            }

            parent.onDropItems(drop.urls, drop.destinationFolder, drop.operation)
            return true
        }

        private func makeDrop(
            info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> PendingDrop? {
            let urls = FileDropPasteboardReader.fileURLs(from: info.draggingPasteboard)
            guard !urls.isEmpty else {
                return nil
            }

            guard let destination = destinationFolder(row: row, dropOperation: dropOperation) else {
                return nil
            }

            let source: DropSource = (info.draggingSource as? NSTableView) === tableView ? .local : .external
            let optionKeyPressed = NSApp.currentEvent?.modifierFlags.contains(.option) == true
            let proposedOperation: DropOperation?
            if info.draggingSourceOperationMask.contains(.move) && !info.draggingSourceOperationMask.contains(.copy) {
                proposedOperation = .move
            } else {
                proposedOperation = nil
            }

            let operation = FileDropOperationResolver.operation(
                source: source,
                optionKeyPressed: optionKeyPressed,
                proposedOperation: proposedOperation
            )

            return PendingDrop(urls: urls, destinationFolder: destination, operation: operation)
        }

        private func canDrop(_ drop: PendingDrop) -> Bool {
            do {
                try FileDropValidator.validate(
                    urls: drop.urls,
                    destinationFolder: drop.destinationFolder,
                    operation: drop.operation
                )
                return true
            } catch {
                return false
            }
        }

        private func normalizedDropOperation(
            row: Int,
            dropOperation: NSTableView.DropOperation,
            tableView: NSTableView
        ) -> NSTableView.DropOperation {
            guard row >= 0, row < parent.entries.count, parent.entries[row].isDirectoryLike else {
                return dropOperation
            }

            tableView.setDropRow(row, dropOperation: .on)
            return .on
        }

        private func destinationFolder(row: Int, dropOperation: NSTableView.DropOperation) -> URL? {
            guard row >= 0, row < parent.entries.count, dropOperation == .on else {
                return parent.currentURL
            }

            let entry = parent.entries[row]
            guard entry.isDirectoryLike else {
                return nil
            }
            return entry.url
        }

        private func value(for entry: FileEntry, column: String) -> String {
            switch column {
            case "name":
                return entry.name
            case "size":
                guard let size = entry.size else { return "--" }
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            case "modified":
                guard let date = entry.dateModified else { return "--" }
                return Self.compactDateFormatter.string(from: date)
            case "kind":
                return entry.typeDescription
            case "tags":
                return entry.finderTags.map(\.name).joined(separator: ", ")
            case "path":
                return entry.url.deletingLastPathComponent().path
            default:
                return ""
            }
        }

        private static let compactDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter
        }()
    }

    @MainActor
    final class ContextMenuTableView: NSTableView {
        weak var menuProvider: Coordinator?
        var didMoveToWindowHandler: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            didMoveToWindowHandler?()
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            menuProvider?.handleTableFocus()
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            menuProvider?.handleTableFocus()
            super.rightMouseDown(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let didBecomeFirstResponder = super.becomeFirstResponder()
            if didBecomeFirstResponder {
                menuProvider?.handleTableFocus()
            }
            return didBecomeFirstResponder
        }

        override func keyDown(with event: NSEvent) {
            if menuProvider?.handleKeyDown(event) == true {
                return
            }
            super.keyDown(with: event)
        }

        @objc override func insertNewline(_ sender: Any?) {
            if menuProvider?.performCommand(.open) == true {
                return
            }
        }

        @objc(copy:)
        func copyAction(_ sender: Any?) {
            _ = menuProvider?.performCommand(.copy)
        }

        @objc(cut:)
        func cutAction(_ sender: Any?) {
            _ = menuProvider?.performCommand(.cut)
        }

        @objc(paste:)
        func pasteAction(_ sender: Any?) {
            _ = menuProvider?.performCommand(.paste)
        }

        @objc override func selectAll(_ sender: Any?) {
            if menuProvider?.performCommand(.selectAll) != true {
                super.selectAll(sender)
            }
        }

        @objc(undo:)
        func undoAction(_ sender: Any?) {
            _ = menuProvider?.performCommand(.undo)
        }

        override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if let command = Self.command(for: item.action) {
                return menuProvider?.canPerformCommand(command) == true
            }
            return super.validateUserInterfaceItem(item)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let menuProvider else {
                return super.menu(for: event)
            }

            let point = convert(event.locationInWindow, from: nil)
            let row = row(at: point)
            guard row >= 0 else {
                return menuProvider.emptyMenu()
            }

            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                menuProvider.publishSelection()
            }

            return menuProvider.itemMenu()
        }

        private static func command(for action: Selector?) -> ExplorerCommand? {
            switch action {
            case #selector(copyAction(_:)):
                return .copy
            case #selector(cutAction(_:)):
                return .cut
            case #selector(pasteAction(_:)):
                return .paste
            case #selector(selectAll(_:)):
                return .selectAll
            case #selector(undoAction(_:)):
                return .undo
            default:
                return nil
            }
        }
    }

    @MainActor
    final class InlineRenameTextField: NSTextField {
        private(set) var didCancelRename = false

        override var acceptsFirstResponder: Bool {
            true
        }

        override func becomeFirstResponder() -> Bool {
            let didBecomeFirstResponder = super.becomeFirstResponder()
            if didBecomeFirstResponder {
                selectText(nil)
            }
            return didBecomeFirstResponder
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76:
                window?.makeFirstResponder(superview)
            case 53:
                didCancelRename = true
                window?.makeFirstResponder(superview)
            default:
                super.keyDown(with: event)
            }
        }
    }
}
