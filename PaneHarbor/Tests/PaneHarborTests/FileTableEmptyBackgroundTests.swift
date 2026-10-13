import AppKit
import SwiftUI
import XCTest
@testable import PaneHarbor

@MainActor
final class FileTableEmptyBackgroundTests: XCTestCase {
    func testEmptyFolderBackgroundHasNoStripesAndStillOffersFolderCommands() throws {
        let folder = URL(fileURLWithPath: "/tmp/PaneHarbor-empty-view-fixture", isDirectory: true)
        var commands: [ExplorerCommand] = []
        var focusCount = 0
        let view = FileTableView(
            entries: [], selectedURLs: [], canPaste: true, canUndo: false, canCloseTab: false,
            currentURL: folder, currentLocation: .fileSystem(folder),
            currentSort: EntrySortDescriptor(), showsPathColumn: false,
            onFocus: { focusCount += 1 }, onSelectionChange: { _ in }, onOpen: { _ in },
            onCommand: { commands.append($0) }, onDropItems: { _, _, _ in }, onSortChange: { _ in }
        )
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let scroll = try XCTUnwrap(descendant(NSScrollView.self, in: host))
        let table = try XCTUnwrap(scroll.documentView as? FileTableView.ContextMenuTableView)
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertFalse(table.usesAlternatingRowBackgroundColors, "An empty folder must not draw placeholder row bands")

        // Background events can target the clip view rather than the table document.
        let point = NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.maxY - 15)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: scroll.contentView.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        let hit = try XCTUnwrap(scroll.contentView.hitTest(scroll.contentView.convert(point, to: scroll.contentView.superview)))
        let menu = try XCTUnwrap(hit.menu(for: event), "The actual empty-background hit must offer a folder menu")
        let newFolder = try XCTUnwrap(menu.items.first { $0.representedObject as? String == ExplorerCommand.newFolder.rawValue })
        XCTAssertTrue(newFolder.isEnabled)
        XCTAssertTrue(menu.items.contains { $0.representedObject as? String == ExplorerCommand.paste.rawValue && $0.isEnabled })
        XCTAssertTrue(menu.items.contains { $0.representedObject as? String == ExplorerCommand.refresh.rawValue && $0.isEnabled })
        if let target = newFolder.target as? NSObject, let action = newFolder.action {
            target.perform(action, with: newFolder)
        }
        XCTAssertEqual(commands, [.newFolder])
        // The normal table hit receives focus in rightMouseDown; explicitly
        // check the clip fallback's own focus path without opening a menu.
        XCTAssertNotNil(scroll.contentView.menu(for: event))
        XCTAssertGreaterThan(focusCount, 0)
    }

    func testShortListBlankClipBackgroundKeepsSelectionAndOffersFolderMenu() throws {
        let folder = URL(fileURLWithPath: "/tmp/PaneHarbor-empty-view-fixture", isDirectory: true)
        let entry = FileEntry(url: folder.appendingPathComponent("report.txt"), name: "report.txt",
                              kind: .file, typeDescription: "Text", fileExtension: "txt", size: 1,
                              dateModified: nil, dateCreated: nil, dateAccessed: nil,
                              isHidden: false, isDirectoryLike: false, isReadable: true)
        let view = FileTableView(
            entries: [entry], selectedURLs: [entry.url], canPaste: true, canUndo: false, canCloseTab: false,
            currentURL: folder, currentLocation: .fileSystem(folder),
            currentSort: EntrySortDescriptor(), showsPathColumn: false,
            onSelectionChange: { _ in }, onOpen: { _ in }, onCommand: { _ in },
            onDropItems: { _, _, _ in }, onSortChange: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let table = FileTableView.ContextMenuTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 25))
        table.menuProvider = coordinator
        table.dataSource = coordinator
        table.delegate = coordinator
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        coordinator.tableView = table
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        let clip = FileTableView.ContextMenuClipView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        clip.documentView = table
        let point = NSPoint(x: 100, y: 300)
        let hit = try XCTUnwrap(clip.hitTest(point))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(hit.menu(for: event))
        XCTAssertTrue(menu.items.contains { $0.representedObject as? String == ExplorerCommand.newFolder.rawValue })
        XCTAssertFalse(menu.items.contains { $0.representedObject as? String == ExplorerCommand.rename.rawValue })
        XCTAssertEqual(table.selectedRowIndexes, [0])
        let fallback = try XCTUnwrap(clip.menu(for: event))
        XCTAssertFalse(fallback.items.contains { $0.representedObject as? String == ExplorerCommand.rename.rawValue })
    }

    func testRowBackgroundsFollowTransitionsIntoAndOutOfEmptyFolder() {
        let folder = URL(fileURLWithPath: "/tmp/PaneHarbor-empty-view-fixture", isDirectory: true)
        let entry = FileEntry(url: folder.appendingPathComponent("folder", isDirectory: true), name: "folder",
                              kind: .folder, typeDescription: "Folder", fileExtension: "", size: nil,
                              dateModified: nil, dateCreated: nil, dateAccessed: nil,
                              isHidden: false, isDirectoryLike: true, isReadable: true)
        let view = FileTableView(
            entries: [entry], selectedURLs: [], canPaste: false, canUndo: false, canCloseTab: false,
            currentURL: folder, currentLocation: .fileSystem(folder),
            currentSort: EntrySortDescriptor(), showsPathColumn: false,
            onSelectionChange: { _ in }, onOpen: { _ in }, onCommand: { _ in },
            onDropItems: { _, _, _ in }, onSortChange: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let table = FileTableView.ContextMenuTableView()
        coordinator.tableView = table
        table.dataSource = coordinator
        coordinator.reloadDataIfNeeded()
        XCTAssertTrue(table.usesAlternatingRowBackgroundColors)
        coordinator.parent.entries = []
        coordinator.reloadDataIfNeeded()
        XCTAssertFalse(table.usesAlternatingRowBackgroundColors)
        coordinator.parent.entries = [entry]
        coordinator.reloadDataIfNeeded()
        XCTAssertTrue(table.usesAlternatingRowBackgroundColors)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }
}
