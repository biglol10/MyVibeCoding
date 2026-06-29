import AppKit
import XCTest
@testable import MyMacFinder

@MainActor
final class FileTableViewReuseTests: XCTestCase {
    func testStandardResponderActionsRouteClipboardCommandsThroughTable() {
        let entry = makeTableEntry(name: "report.txt")
        var commands: [ExplorerCommand] = []
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: true,
            canUndo: true,
            onCommand: { commands.append($0) }
        )

        let actions: [(Selector, ExplorerCommand)] = [
            (#selector(FileTableView.ContextMenuTableView.copyAction(_:)), .copy),
            (#selector(FileTableView.ContextMenuTableView.cutAction(_:)), .cut),
            (#selector(FileTableView.ContextMenuTableView.pasteAction(_:)), .paste),
            (#selector(FileTableView.ContextMenuTableView.selectAll(_:)), .selectAll),
            (#selector(FileTableView.ContextMenuTableView.undoAction(_:)), .undo)
        ]

        for (selector, command) in actions {
            let menuItem = NSMenuItem(title: command.title, action: selector, keyEquivalent: "")
            XCTAssertTrue(harness.tableView.responds(to: selector), "\(command) should be handled by the file table")
            XCTAssertTrue(harness.tableView.validateUserInterfaceItem(menuItem), "\(command) should be enabled")
            if harness.tableView.responds(to: selector) {
                harness.tableView.perform(selector, with: nil)
            }
        }

        XCTAssertEqual(commands, [.copy, .cut, .paste, .selectAll, .undo])
    }

    func testStandardResponderActionsRespectCommandAvailability() {
        let entry = makeTableEntry(name: "report.txt")
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            onCommand: { _ in }
        )

        XCTAssertFalse(
            harness.tableView.validateUserInterfaceItem(
                NSMenuItem(title: "Copy", action: #selector(FileTableView.ContextMenuTableView.copyAction(_:)), keyEquivalent: "")
            )
        )
        XCTAssertFalse(
            harness.tableView.validateUserInterfaceItem(
                NSMenuItem(title: "Cut", action: #selector(FileTableView.ContextMenuTableView.cutAction(_:)), keyEquivalent: "")
            )
        )
        XCTAssertFalse(
            harness.tableView.validateUserInterfaceItem(
                NSMenuItem(title: "Paste", action: #selector(FileTableView.ContextMenuTableView.pasteAction(_:)), keyEquivalent: "")
            )
        )
        XCTAssertFalse(
            harness.tableView.validateUserInterfaceItem(
                NSMenuItem(title: "Undo", action: #selector(FileTableView.ContextMenuTableView.undoAction(_:)), keyEquivalent: "")
            )
        )
        XCTAssertTrue(
            harness.tableView.validateUserInterfaceItem(
                NSMenuItem(title: "Select All", action: #selector(FileTableView.ContextMenuTableView.selectAll(_:)), keyEquivalent: "")
            )
        )
    }

    func testItemContextMenuIncludesOpenWithSubmenuAndRoutesApplicationChoice() throws {
        let entry = makeTableEntry(name: "report.txt")
        let preview = OpenWithApplication(
            url: URL(fileURLWithPath: "/Applications/Preview.app", isDirectory: true),
            title: "Preview",
            bundleIdentifier: "com.apple.Preview"
        )
        var openedApplication: OpenWithApplication?
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: false,
            canUndo: false,
            openWithApplications: [preview],
            onOpenWithApplication: { openedApplication = $0 },
            onCommand: { _ in }
        )

        let menu = harness.coordinator.itemMenu()
        let openWithItem = try XCTUnwrap(menu.item(withTitle: "Open With"))
        let submenu = try XCTUnwrap(openWithItem.submenu)
        let previewItem = try XCTUnwrap(submenu.item(withTitle: "Preview"))

        _ = (previewItem.target as AnyObject).perform(previewItem.action, with: previewItem)

        XCTAssertEqual(openedApplication, preview)
    }

    func testTableFocusCallbackPublishesEvenWhenSelectionDoesNotChange() {
        let entry = makeTableEntry(name: "report.txt")
        var focusCount = 0
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: false,
            canUndo: false,
            onFocus: { focusCount += 1 },
            onCommand: { _ in }
        )

        harness.coordinator.handleTableFocus()

        XCTAssertEqual(focusCount, 1)
    }

    func testCellsHaveStableReuseIdentifiersPerColumn() {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            name: "report.txt",
            kind: .file,
            typeDescription: "Text document",
            fileExtension: "txt",
            size: 12,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableView.addTableColumn(column)

        let cell = coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView

        XCTAssertEqual(cell?.identifier?.rawValue, "FileTableCell.name")
        XCTAssertEqual(cell?.textField?.stringValue, "report.txt")
    }

    func testNameColumnDisplaysAnIconBeforeText() throws {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/Projects", isDirectory: true),
            name: "Projects",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)

        XCTAssertEqual(cell.textField?.stringValue, "Projects")
        XCTAssertNotNil(cell.imageView)
        XCTAssertNotNil(cell.imageView?.image)
    }

    func testTextColumnsDoNotDisplayIcons() throws {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            name: "report.txt",
            kind: .file,
            typeDescription: "Text document",
            fileExtension: "txt",
            size: 12,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)

        XCTAssertEqual(cell.textField?.stringValue, "Text document")
        XCTAssertNil(cell.imageView)
    }

    func testArchiveBackedNameColumnDisplaysFallbackIcon() throws {
        let archiveLocation = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/archive.zip"),
            internalPath: "Nested/readme.txt"
        )
        let entry = FileEntry(
            url: archiveLocation.virtualURL,
            name: "readme.txt",
            kind: .zipVirtualFile,
            typeDescription: "ZIP Item",
            fileExtension: "txt",
            size: 12,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true,
            source: .archive(archiveLocation)
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .archive(ArchiveLocation(archiveURL: URL(fileURLWithPath: "/tmp/archive.zip"), internalPath: "")),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)

        XCTAssertEqual(cell.textField?.stringValue, "readme.txt")
        XCTAssertNotNil(cell.imageView)
        XCTAssertNotNil(cell.imageView?.image)
    }

    func testCellsClipLongColumnTextToBounds() throws {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            name: "report.txt",
            kind: .file,
            typeDescription: "Text document",
            fileExtension: "txt",
            size: 12,
            dateModified: Date(timeIntervalSince1970: 1_787_000_000),
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)
        let textField = try XCTUnwrap(cell.textField)

        XCTAssertTrue(cell.wantsLayer)
        XCTAssertEqual(cell.layer?.masksToBounds, true)
        XCTAssertEqual(textField.lineBreakMode, .byTruncatingMiddle)
        XCTAssertLessThanOrEqual(
            textField.contentCompressionResistancePriority(for: .horizontal).rawValue,
            NSLayoutConstraint.Priority.defaultLow.rawValue
        )
    }

    func testModifiedColumnUsesCompactTimestamp() throws {
        let modifiedAt = Date(timeIntervalSince1970: 1_787_000_000)
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            name: "report.txt",
            kind: .file,
            typeDescription: "Text document",
            fileExtension: "txt",
            size: 12,
            dateModified: modifiedAt,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        XCTAssertEqual(cell.textField?.stringValue, formatter.string(from: modifiedAt))
    }

    func testTagsColumnDisplaysFinderTags() throws {
        let entry = FileEntry(
            url: URL(fileURLWithPath: "/tmp/report.txt"),
            name: "report.txt",
            kind: .file,
            typeDescription: "Text document",
            fileExtension: "txt",
            size: 12,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true,
            finderTags: [FinderTag("Work"), FinderTag("Red")]
        )
        let fileTable = FileTableView(
            entries: [entry],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let coordinator = fileTable.makeCoordinator()
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tags"))
        tableView.addTableColumn(column)

        let cell = try XCTUnwrap(coordinator.tableView(tableView, viewFor: column, row: 0) as? NSTableCellView)

        XCTAssertTrue(fileTable.columnDefinitions.contains { $0.key == "tags" })
        XCTAssertEqual(cell.textField?.stringValue, "Red, Work")
    }

    func testRegularColumnsFitDualPaneMinimumWidthWhileKeepingDateReadable() throws {
        let fileTable = FileTableView(
            entries: [],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )

        let regularColumns = fileTable.columnDefinitions
        let dateColumn = try XCTUnwrap(regularColumns.first { $0.key == "modified" })
        let kindColumn = try XCTUnwrap(regularColumns.first { $0.key == "kind" })

        XCTAssertGreaterThanOrEqual(dateColumn.minWidth, 132)
        XCTAssertGreaterThanOrEqual(kindColumn.minWidth, 90)
        XCTAssertLessThanOrEqual(regularColumns.reduce(0) { $0 + $1.minWidth }, 480)
        XCTAssertLessThanOrEqual(regularColumns.reduce(0) { $0 + $1.width }, 480)
    }

    func testTableColumnsApplyReadableMinimumWidths() throws {
        let fileTable = FileTableView(
            entries: [],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )
        let dateDefinition = try XCTUnwrap(fileTable.columnDefinitions.first { $0.key == "modified" })

        let tableColumn = fileTable.makeTableColumn(dateDefinition)

        XCTAssertEqual(tableColumn.minWidth, dateDefinition.minWidth)
        XCTAssertTrue(tableColumn.resizingMask.contains(.autoresizingMask))
    }

    func testLastColumnReceivesRemainingWidthInNarrowDualPaneLayouts() {
        let fileTable = FileTableView(
            entries: [],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: false,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )

        XCTAssertEqual(fileTable.columnAutoresizingStyle, .lastColumnOnlyAutoresizingStyle)
    }
}

private func makeTableEntry(name: String) -> FileEntry {
    FileEntry(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        kind: .file,
        typeDescription: "Text document",
        fileExtension: URL(fileURLWithPath: name).pathExtension,
        size: 12,
        dateModified: nil,
        dateCreated: nil,
        dateAccessed: nil,
        isHidden: false,
        isDirectoryLike: false,
        isReadable: true
    )
}

@MainActor
private func makeTableHarness(
    entries: [FileEntry],
    selectedRowIndexes: IndexSet,
    canPaste: Bool,
    canUndo: Bool,
    openWithApplications: [OpenWithApplication] = [],
    onFocus: @escaping () -> Void = {},
    onOpenWithApplication: @escaping (OpenWithApplication) -> Void = { _ in },
    onCommand: @escaping (ExplorerCommand) -> Void
) -> (fileTable: FileTableView, coordinator: FileTableView.Coordinator, tableView: FileTableView.ContextMenuTableView) {
    let selectedURLs = Set(selectedRowIndexes.compactMap { index in
        index < entries.count ? entries[index].url : nil
    })
    let fileTable = FileTableView(
        entries: entries,
        selectedURLs: selectedURLs,
        canPaste: canPaste,
        canUndo: canUndo,
        canCloseTab: false,
        currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
        currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
        currentSort: EntrySortDescriptor(),
        showsPathColumn: false,
        onFocus: onFocus,
        onSelectionChange: { _ in },
        onOpen: { _ in },
        onCommand: onCommand,
        openWithApplications: openWithApplications,
        onOpenWithApplication: onOpenWithApplication,
        onDropItems: { _, _, _ in },
        onSortChange: { _ in }
    )
    let coordinator = fileTable.makeCoordinator()
    let tableView = FileTableView.ContextMenuTableView()
    tableView.menuProvider = coordinator
    tableView.dataSource = coordinator
    tableView.delegate = coordinator
    tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
    coordinator.tableView = tableView
    tableView.reloadData()
    tableView.selectRowIndexes(selectedRowIndexes, byExtendingSelection: false)
    return (fileTable, coordinator, tableView)
}
