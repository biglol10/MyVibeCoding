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
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            onFocus: { focusCount += 1 },
            onCommand: { _ in }
        )

        harness.coordinator.handleTableFocus()

        XCTAssertEqual(focusCount, 1)
    }

    func testSelectionChangeClearsToolbarFocusThroughTableFocusCallback() {
        let entry = makeTableEntry(name: "report.txt")
        var focusCount = 0
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            onFocus: { focusCount += 1 },
            onCommand: { _ in }
        )
        harness.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        XCTAssertEqual(focusCount, 1)
    }

    func testRangeSelectionChangePublishesEverySelectedRow() {
        let entries = (0..<5).map { makeTableEntry(name: "file-\($0).txt") }
        var selections: [Set<URL>] = []
        let harness = makeTableHarness(
            entries: entries,
            selectedRowIndexes: IndexSet(integer: 1),
            canPaste: false,
            canUndo: false,
            onSelectionChange: { selections.append($0) },
            onCommand: { _ in }
        )

        harness.tableView.selectRowIndexes(IndexSet(integersIn: 1..<4), byExtendingSelection: false)

        XCTAssertEqual(selections.last, Set(entries[1...3].map(\.url)))
    }

    func testDoubleClickPublishesClickedSelectionBeforeOpening() {
        let entries = [
            makeTableEntry(name: "Alpha"),
            makeTableEntry(name: "Beta")
        ]
        var selections: [Set<URL>] = []
        var openedURLs: [URL] = []
        let harness = makeTableHarness(
            entries: entries,
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: false,
            canUndo: false,
            onSelectionChange: { selections.append($0) },
            onOpen: { openedURLs.append($0) },
            onCommand: { _ in }
        )
        let clickedTableView = ClickedRowTableView(clickedRow: 1)
        clickedTableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        clickedTableView.dataSource = harness.coordinator
        clickedTableView.delegate = harness.coordinator
        harness.coordinator.tableView = clickedTableView
        clickedTableView.reloadData()
        clickedTableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        selections.removeAll()

        harness.coordinator.doubleClicked(clickedTableView)

        XCTAssertEqual(selections, [Set([entries[1].url])])
        XCTAssertEqual(openedURLs, [entries[1].url])
    }

    func testInsertNewlineRoutesOpenCommandForSelectedRow() {
        let entry = makeTableEntry(name: "Projects")
        var commands: [ExplorerCommand] = []
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: false,
            canUndo: false,
            onCommand: { commands.append($0) }
        )

        harness.tableView.insertNewline(nil as Any?)

        XCTAssertEqual(commands, [.open])
        XCTAssertEqual(harness.tableView.selectedRowIndexes, IndexSet(integer: 0))
    }

    func testInsertNewlineDoesNotRouteOpenWithoutSelection() {
        let entry = makeTableEntry(name: "Projects")
        var commands: [ExplorerCommand] = []
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            onCommand: { commands.append($0) }
        )

        harness.tableView.insertNewline(nil as Any?)

        XCTAssertTrue(commands.isEmpty)
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

    func testArchiveBackedRowsAreNotWrittenToDragPasteboard() {
        let entry = makeArchiveBackedTableEntry(name: "readme.txt")
        let harness = makeTableHarness(
            entries: [entry],
            selectedRowIndexes: IndexSet(integer: 0),
            canPaste: false,
            canUndo: false,
            onCommand: { _ in }
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyMacFinderArchiveDrag-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("keep", forType: .string)

        let didWrite = harness.coordinator.tableView(
            harness.tableView,
            writeRowsWith: IndexSet(integer: 0),
            to: pasteboard
        )

        XCTAssertFalse(didWrite)
        XCTAssertEqual(FileDropPasteboardReader.fileURLs(from: pasteboard), [])
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
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
        let nameColumn = try XCTUnwrap(regularColumns.first { $0.key == "name" })
        let sizeColumn = try XCTUnwrap(regularColumns.first { $0.key == "size" })
        let dateColumn = try XCTUnwrap(regularColumns.first { $0.key == "modified" })
        let kindColumn = try XCTUnwrap(regularColumns.first { $0.key == "kind" })

        XCTAssertGreaterThanOrEqual(nameColumn.width, 300)
        XCTAssertGreaterThanOrEqual(nameColumn.minWidth, 220)
        XCTAssertGreaterThanOrEqual(sizeColumn.minWidth, 50)
        XCTAssertGreaterThanOrEqual(dateColumn.minWidth, 140)
        XCTAssertGreaterThanOrEqual(kindColumn.width, 170)
        XCTAssertGreaterThanOrEqual(kindColumn.minWidth, 150)
        XCTAssertLessThanOrEqual(regularColumns.reduce(0) { $0 + $1.minWidth }, 620)
        XCTAssertLessThanOrEqual(regularColumns.reduce(0) { $0 + $1.width }, 740)
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

    func testOnlySupportedColumnsExposeSortDescriptors() throws {
        let fileTable = FileTableView(
            entries: [],
            selectedURLs: [],
            canPaste: false,
            canUndo: false,
            canCloseTab: false,
            currentURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            currentLocation: .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
            currentSort: EntrySortDescriptor(),
            showsPathColumn: true,
            onSelectionChange: { _ in },
            onOpen: { _ in },
            onCommand: { _ in },
            onDropItems: { _, _, _ in },
            onSortChange: { _ in }
        )

        let columnsByKey = Dictionary(
            uniqueKeysWithValues: fileTable.columnDefinitions.map { definition in
                (definition.key, fileTable.makeTableColumn(definition))
            }
        )

        XCTAssertEqual(columnsByKey["name"]?.sortDescriptorPrototype?.key, "name")
        XCTAssertEqual(columnsByKey["size"]?.sortDescriptorPrototype?.key, "size")
        XCTAssertEqual(columnsByKey["modified"]?.sortDescriptorPrototype?.key, "modified")
        XCTAssertEqual(columnsByKey["kind"]?.sortDescriptorPrototype?.key, "kind")
        XCTAssertEqual(columnsByKey["path"]?.sortDescriptorPrototype?.key, "path")
        XCTAssertNil(columnsByKey["tags"]?.sortDescriptorPrototype)
    }

    func testNameColumnReceivesRemainingWidthInWideLayouts() {
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

        XCTAssertEqual(fileTable.columnAutoresizingStyle, .firstColumnOnlyAutoresizingStyle)
    }

    func testLocationChangeResetsScrollPositionButSameLocationKeepsIt() {
        let entries = (0..<50).map { makeTableEntry(name: "file-\($0).txt") }
        let oldLocation = PaneLocation.fileSystem(URL(fileURLWithPath: "/tmp/old", isDirectory: true))
        let newLocation = PaneLocation.fileSystem(URL(fileURLWithPath: "/tmp/new", isDirectory: true))
        let harness = makeTableHarness(
            entries: entries,
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            currentLocation: oldLocation,
            onCommand: { _ in }
        )
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        harness.tableView.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        scrollView.documentView = harness.tableView

        scrollView.contentView.scroll(to: NSPoint(x: 120, y: 80))
        harness.coordinator.resetScrollIfLocationChanged(in: scrollView)
        XCTAssertEqual(scrollView.contentView.bounds.origin, .zero)

        scrollView.contentView.scroll(to: NSPoint(x: 120, y: 80))
        harness.coordinator.resetScrollIfLocationChanged(in: scrollView)
        XCTAssertEqual(scrollView.contentView.bounds.origin, NSPoint(x: 120, y: 80))

        let updatedHarness = makeTableHarness(
            entries: entries,
            selectedRowIndexes: [],
            canPaste: false,
            canUndo: false,
            currentLocation: newLocation,
            onCommand: { _ in }
        )
        harness.coordinator.parent = updatedHarness.fileTable
        harness.coordinator.resetScrollIfLocationChanged(in: scrollView)
        XCTAssertEqual(scrollView.contentView.bounds.origin, .zero)
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

private func makeArchiveBackedTableEntry(name: String) -> FileEntry {
    let archiveLocation = ArchiveLocation(
        archiveURL: URL(fileURLWithPath: "/tmp/archive.zip"),
        internalPath: name
    )
    return FileEntry(
        url: archiveLocation.virtualURL,
        name: name,
        kind: .zipVirtualFile,
        typeDescription: "ZIP Item",
        fileExtension: URL(fileURLWithPath: name).pathExtension,
        size: 12,
        dateModified: nil,
        dateCreated: nil,
        dateAccessed: nil,
        isHidden: false,
        isDirectoryLike: false,
        isReadable: true,
        source: .archive(archiveLocation)
    )
}

@MainActor
private func makeTableHarness(
    entries: [FileEntry],
    selectedRowIndexes: IndexSet,
    canPaste: Bool,
    canUndo: Bool,
    currentLocation: PaneLocation = .fileSystem(URL(fileURLWithPath: "/tmp", isDirectory: true)),
    openWithApplications: [OpenWithApplication] = [],
    onFocus: @escaping () -> Void = {},
    onSelectionChange: @escaping (Set<URL>) -> Void = { _ in },
    onOpen: @escaping (URL) -> Void = { _ in },
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
        currentURL: currentLocation.fileSystemURL ?? URL(fileURLWithPath: "/tmp", isDirectory: true),
        currentLocation: currentLocation,
        currentSort: EntrySortDescriptor(),
        showsPathColumn: false,
        onFocus: onFocus,
        onSelectionChange: onSelectionChange,
        onOpen: onOpen,
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

@MainActor
private final class ClickedRowTableView: NSTableView {
    var clickedRowOverride: Int

    init(clickedRow: Int) {
        self.clickedRowOverride = clickedRow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var clickedRow: Int {
        clickedRowOverride
    }
}
