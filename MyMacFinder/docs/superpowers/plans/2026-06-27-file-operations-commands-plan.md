# File Operations And Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Finder-baseline file operations, shared command routing, context menus, and keyboard/menu shortcuts on top of the existing MyMacFinder foundation.

**Architecture:** Introduce a focused `FileOperationService` for filesystem mutations and an `ExplorerCommand` layer so menu bar commands, context menus, shortcuts, toolbar actions, and the next drag/drop plan all call the same store methods. This pass uses real filesystem operations against temporary folders in tests, keeps deletion safe by moving items to Trash, and refreshes the active pane after mutations.

**Tech Stack:** Swift 6.1.2, macOS 15 SDK, SwiftUI, AppKit, XCTest, `FileManager`, `NSWorkspace`, `NSPasteboard`, `NSTableView` context menus.

---

## Scope

This plan implements:

- New Folder
- Rename
- Duplicate
- Copy
- Cut
- Paste
- Move to Trash
- Copy Path
- Reveal in Finder
- Refresh
- Context menu for selected file/folder rows
- Context menu for empty table space
- Menu bar and shortcut routing for the same commands
- Manual QA pass with the real app open

This plan creates the operation backbone required for drag-and-drop. Drag-and-drop is a separate required plan after this one because it needs additional `NSTableView` pasteboard validation and visual drop feedback, but it must reuse `FileOperationService` and `ExplorerCommand`.

## File Structure

- Create: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Create: `Sources/MyMacFinder/Services/FileOperationService.swift`
- Create: `Sources/MyMacFinder/Services/FileClipboard.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`
- Test: `Tests/MyMacFinderTests/FileOperationServiceTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`
- Test: `Tests/MyMacFinderTests/FileClipboardTests.swift`

## Task 1: Command Model

**Files:**
- Create: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Test: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`

- [ ] **Step 1: Write failing command capability tests**

Create `Tests/MyMacFinderTests/ExplorerCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerCommandTests: XCTestCase {
    func testSelectionCommandsRequireSelection() {
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.rename.isEnabled(selectionCount: 1, canPaste: false))
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 2, canPaste: false))

        XCTAssertFalse(ExplorerCommand.moveToTrash.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.moveToTrash.isEnabled(selectionCount: 2, canPaste: false))
    }

    func testPasteDependsOnClipboardState() {
        XCTAssertFalse(ExplorerCommand.paste.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.paste.isEnabled(selectionCount: 0, canPaste: true))
    }

    func testEmptyAreaCommandsAreAlwaysAvailable() {
        XCTAssertTrue(ExplorerCommand.newFolder.isEnabled(selectionCount: 0, canPaste: false))
        XCTAssertTrue(ExplorerCommand.refresh.isEnabled(selectionCount: 0, canPaste: false))
    }
}
```

- [ ] **Step 2: Run command tests and verify RED**

Run:

```bash
swift test --filter ExplorerCommandTests
```

Expected: FAIL with `cannot find 'ExplorerCommand' in scope`.

- [ ] **Step 3: Implement command model**

Create `Sources/MyMacFinder/Domain/ExplorerCommand.swift`:

```swift
import Foundation

public enum ExplorerCommand: String, CaseIterable, Identifiable {
    case open
    case revealInFinder
    case copyPath
    case newFolder
    case rename
    case duplicate
    case copy
    case cut
    case paste
    case moveToTrash
    case refresh

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .open: return "Open"
        case .revealInFinder: return "Reveal in Finder"
        case .copyPath: return "Copy Path"
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .moveToTrash: return "Move to Trash"
        case .refresh: return "Refresh"
        }
    }

    public func isEnabled(selectionCount: Int, canPaste: Bool) -> Bool {
        switch self {
        case .newFolder, .refresh:
            return true
        case .paste:
            return canPaste
        case .rename:
            return selectionCount == 1
        case .open, .revealInFinder, .copyPath, .duplicate, .copy, .cut, .moveToTrash:
            return selectionCount > 0
        }
    }
}
```

- [ ] **Step 4: Run command tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerCommandTests
```

Expected: PASS.

- [ ] **Step 5: Commit command model**

Run:

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift
git commit -m "feat: add explorer command model"
```

Expected: commit succeeds.

## Task 2: File Operation Service

**Files:**
- Create: `Sources/MyMacFinder/Services/FileOperationService.swift`
- Test: `Tests/MyMacFinderTests/FileOperationServiceTests.swift`

- [ ] **Step 1: Write failing file operation tests**

Create `Tests/MyMacFinderTests/FileOperationServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FileOperationServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderOps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCreatesUniquelyNamedFolder() throws {
        let service = FileOperationService()
        let first = try service.createFolder(in: tempDirectory)
        let second = try service.createFolder(in: tempDirectory)

        XCTAssertEqual(first.lastPathComponent, "Untitled Folder")
        XCTAssertEqual(second.lastPathComponent, "Untitled Folder 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testRenamesItem() throws {
        let file = tempDirectory.appendingPathComponent("old.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        let renamed = try service.rename(file, to: "new.txt")

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testDuplicateKeepsBothNames() throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let service = FileOperationService()

        let duplicate = try service.duplicate(file)

        XCTAssertEqual(duplicate.lastPathComponent, "note copy.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicate.path))
    }

    func testCopyItemsUsesKeepBothCollisionName() throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        let existingDest = destFolder.appendingPathComponent("note.txt")
        try "one".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "two".write(to: existingDest, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let copied = try service.copyItems([sourceFile], to: destFolder)

        XCTAssertEqual(copied.map(\.lastPathComponent), ["note copy.txt"])
        XCTAssertEqual(try String(contentsOf: existingDest), "two")
        XCTAssertEqual(try String(contentsOf: copied[0]), "one")
    }

    func testMoveItemsRemovesOriginal() throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: sourceFile, atomically: true, encoding: .utf8)

        let service = FileOperationService()
        let moved = try service.moveItems([sourceFile], to: destFolder)

        XCTAssertEqual(moved.map(\.lastPathComponent), ["move.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved[0].path))
    }
}
```

- [ ] **Step 2: Run file operation tests and verify RED**

Run:

```bash
swift test --filter FileOperationServiceTests
```

Expected: FAIL with `cannot find 'FileOperationService' in scope`.

- [ ] **Step 3: Implement file operation service**

Create `Sources/MyMacFinder/Services/FileOperationService.swift`:

```swift
import Foundation

public struct FileOperationService: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func createFolder(in parent: URL) throws -> URL {
        let folderURL = uniqueURL(in: parent, baseName: "Untitled Folder", extension: nil)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    @discardableResult
    public func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExplorerError.invalidPath(newName)
        }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard destination != url else {
            return url
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ExplorerError.readFailed("An item named \(trimmed) already exists.")
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    @discardableResult
    public func duplicate(_ url: URL) throws -> URL {
        let destination = copyName(for: url)
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    @discardableResult
    public func copyItems(_ urls: [URL], to destinationFolder: URL) throws -> [URL] {
        try urls.map { source in
            let destination = uniqueCopyDestination(for: source, in: destinationFolder)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
    }

    @discardableResult
    public func moveItems(_ urls: [URL], to destinationFolder: URL) throws -> [URL] {
        try urls.map { source in
            let destination = uniqueMoveDestination(for: source, in: destinationFolder)
            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    public func moveToTrash(_ urls: [URL]) throws {
        for url in urls {
            var result: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &result)
        }
    }

    private func uniqueCopyDestination(for source: URL, in folder: URL) -> URL {
        let proposed = folder.appendingPathComponent(source.lastPathComponent)
        if !fileManager.fileExists(atPath: proposed.path) {
            return proposed
        }
        return copyName(for: proposed)
    }

    private func uniqueMoveDestination(for source: URL, in folder: URL) -> URL {
        let proposed = folder.appendingPathComponent(source.lastPathComponent)
        if !fileManager.fileExists(atPath: proposed.path) {
            return proposed
        }
        return copyName(for: proposed)
    }

    private func copyName(for url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let stem = ext == nil ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        return uniqueURL(in: parent, baseName: "\(stem) copy", extension: ext)
    }

    private func uniqueURL(in parent: URL, baseName: String, extension ext: String?) -> URL {
        func candidate(_ suffix: Int?) -> URL {
            let name = suffix.map { "\(baseName) \($0)" } ?? baseName
            if let ext {
                return parent.appendingPathComponent(name).appendingPathExtension(ext)
            }
            return parent.appendingPathComponent(name)
        }

        var current = candidate(nil)
        var index = 2
        while fileManager.fileExists(atPath: current.path) {
            current = candidate(index)
            index += 1
        }
        return current
    }
}
```

- [ ] **Step 4: Run file operation tests and verify GREEN**

Run:

```bash
swift test --filter FileOperationServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit file operation service**

Run:

```bash
git add Sources/MyMacFinder/Services/FileOperationService.swift Tests/MyMacFinderTests/FileOperationServiceTests.swift
git commit -m "feat: add file operation service"
```

Expected: commit succeeds.

## Task 3: Clipboard Model

**Files:**
- Create: `Sources/MyMacFinder/Services/FileClipboard.swift`
- Test: `Tests/MyMacFinderTests/FileClipboardTests.swift`

- [ ] **Step 1: Write failing clipboard tests**

Create `Tests/MyMacFinderTests/FileClipboardTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FileClipboardTests: XCTestCase {
    func testClipboardReportsEmptyWhenNoURLs() {
        let clipboard = FileClipboard(urls: [], mode: .copy)

        XCTAssertTrue(clipboard.isEmpty)
    }

    func testClipboardStoresURLsAndMode() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let clipboard = FileClipboard(urls: [url], mode: .move)

        XCTAssertFalse(clipboard.isEmpty)
        XCTAssertEqual(clipboard.urls, [url])
        XCTAssertEqual(clipboard.mode, .move)
    }
}
```

- [ ] **Step 2: Run clipboard tests and verify RED**

Run:

```bash
swift test --filter FileClipboardTests
```

Expected: FAIL with `cannot find 'FileClipboard' in scope`.

- [ ] **Step 3: Implement file clipboard value type**

Create `Sources/MyMacFinder/Services/FileClipboard.swift`:

```swift
import Foundation

public enum FileClipboardMode: String, Codable, Sendable {
    case copy
    case move
}

public struct FileClipboard: Equatable, Sendable {
    public var urls: [URL]
    public var mode: FileClipboardMode

    public init(urls: [URL], mode: FileClipboardMode) {
        self.urls = urls
        self.mode = mode
    }

    public var isEmpty: Bool {
        urls.isEmpty
    }
}
```

- [ ] **Step 4: Run clipboard tests and verify GREEN**

Run:

```bash
swift test --filter FileClipboardTests
```

Expected: PASS.

- [ ] **Step 5: Run existing tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit clipboard model**

Run:

```bash
git add Sources/MyMacFinder/Services/FileClipboard.swift Tests/MyMacFinderTests/FileClipboardTests.swift
git commit -m "feat: add file clipboard model"
```

Expected: commit succeeds.

## Task 4: ExplorerStore Command Execution

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerStoreTests.swift`

- [ ] **Step 1: Add failing store tests for file commands**

Append these tests to `Tests/MyMacFinderTests/ExplorerStoreTests.swift`:

```swift
    @MainActor
    func testCreateFolderCommandCreatesFolderAndRefreshesEntries() async {
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.perform(.newFolder)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "Untitled Folder" })
    }

    @MainActor
    func testDuplicateCommandDuplicatesSelectedFile() async throws {
        let file = tempDirectory.appendingPathComponent("note.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.duplicate)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "note copy.txt" })
    }

    @MainActor
    func testCopyAndPasteCommandsCopySelectedFileIntoCurrentFolder() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("copy.txt")
        try "copy".write(to: sourceFile, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()
        store.updateSelection([sourceFile.standardizedFileURL])

        await store.perform(.copy)
        await store.navigate(to: destFolder)
        await store.perform(.paste)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "copy.txt" })
    }
```

- [ ] **Step 2: Run store tests and verify RED**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: FAIL because `ExplorerStore` has no `perform(_:)` method.

- [ ] **Step 3: Add operation service and command execution to store**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

```swift
// Add property near existing services:
private let fileOperationService: FileOperationService
private var fileClipboard: FileClipboard?

// Update init parameters:
fileOperationService: FileOperationService = FileOperationService(),

// Assign in init:
self.fileOperationService = fileOperationService
self.fileClipboard = nil

// Add computed property:
public var canPaste: Bool {
    fileClipboard?.isEmpty == false
}

// Add selected URLs helper:
private var selectedURLs: [URL] {
    activePane.selectedURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}

// Add command performer:
public func perform(_ command: ExplorerCommand) async {
    do {
        switch command {
        case .open:
            if let first = selectedURLs.first { await open(first) }
        case .revealInFinder:
            revealSelectedInFinder()
        case .copyPath:
            copySelectedPaths()
        case .newFolder:
            _ = try fileOperationService.createFolder(in: activePane.currentURL)
            await refresh()
        case .rename:
            break
        case .duplicate:
            for url in selectedURLs { _ = try fileOperationService.duplicate(url) }
            await refresh()
        case .copy:
            fileClipboard = FileClipboard(urls: selectedURLs, mode: .copy)
        case .cut:
            fileClipboard = FileClipboard(urls: selectedURLs, mode: .move)
        case .paste:
            try pasteClipboard()
            await refresh()
        case .moveToTrash:
            try fileOperationService.moveToTrash(selectedURLs)
            await refresh()
        case .refresh:
            await refresh()
        }
    } catch let error as ExplorerError {
        visibleError = error
    } catch {
        visibleError = .readFailed(error.localizedDescription)
    }
}

private func pasteClipboard() throws {
    guard let fileClipboard, !fileClipboard.isEmpty else { return }
    switch fileClipboard.mode {
    case .copy:
        _ = try fileOperationService.copyItems(fileClipboard.urls, to: activePane.currentURL)
    case .move:
        _ = try fileOperationService.moveItems(fileClipboard.urls, to: activePane.currentURL)
        self.fileClipboard = nil
    }
}

private func copySelectedPaths() {
    let paths = selectedURLs.map(\.path).joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(paths, forType: .string)
}

private func revealSelectedInFinder() {
    guard let first = selectedURLs.first else { return }
    NSWorkspace.shared.activateFileViewerSelecting([first])
}
```

Also update the initializer to accept and store `fileOperationService`. Keep the existing `fileSystemService` and `pathResolver` parameters unchanged.

- [ ] **Step 4: Run store tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit store command execution**

Run:

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerStoreTests.swift
git commit -m "feat: route file commands through explorer store"
```

Expected: commit succeeds.

## Task 5: Context Menus

**Files:**
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`

- [ ] **Step 1: Replace file table with context-menu capable table**

Replace `Sources/MyMacFinder/UI/FileTableView.swift`:

```swift
import AppKit
import SwiftUI

struct FileTableView: NSViewRepresentable {
    var entries: [FileEntry]
    var selectedURLs: Set<URL>
    var onSelectionChange: (Set<URL>) -> Void
    var onOpen: (URL) -> Void
    var onCommand: (ExplorerCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ContextMenuTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.menuProvider = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.target = context.coordinator

        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 260),
            ("size", "Size", 90),
            ("modified", "Date Modified", 170),
            ("kind", "Kind", 120)
        ]

        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.tableView?.reloadData()
        context.coordinator.applySelection(selectedURLs)
    }

    @MainActor
    final class ContextMenuTableView: NSTableView {
        weak var menuProvider: Coordinator?

        override func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            let clicked = row(at: point)
            if clicked >= 0 {
                if !selectedRowIndexes.contains(clicked) {
                    selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
                    menuProvider?.publishSelectionFromTable()
                }
                return menuProvider?.itemMenu()
            }
            return menuProvider?.emptyMenu()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?

        init(parent: FileTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.entries.count else { return nil }
            let entry = parent.entries[row]
            let identifier = tableColumn?.identifier.rawValue ?? "name"
            let cell = NSTableCellView()
            let textField = NSTextField(labelWithString: value(for: entry, column: identifier))
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            publishSelectionFromTable()
        }

        func publishSelectionFromTable() {
            guard let tableView else { return }
            let urls = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < parent.entries.count else { return nil }
                return parent.entries[index].url
            }
            parent.onSelectionChange(Set(urls))
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.entries.count else { return }
            parent.onOpen(parent.entries[row].url)
        }

        func applySelection(_ urls: Set<URL>) {
            guard let tableView else { return }
            let indexes = IndexSet(parent.entries.enumerated().compactMap { index, entry in
                urls.contains(entry.url) ? index : nil
            })
            if tableView.selectedRowIndexes != indexes {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        func emptyMenu() -> NSMenu {
            let menu = NSMenu()
            add(menu, .newFolder)
            add(menu, .paste)
            menu.addItem(.separator())
            add(menu, .refresh)
            return menu
        }

        func itemMenu() -> NSMenu {
            let menu = NSMenu()
            add(menu, .open)
            add(menu, .revealInFinder)
            add(menu, .copyPath)
            menu.addItem(.separator())
            add(menu, .copy)
            add(menu, .cut)
            add(menu, .paste)
            add(menu, .duplicate)
            add(menu, .moveToTrash)
            return menu
        }

        private func add(_ menu: NSMenu, _ command: ExplorerCommand) {
            let item = NSMenuItem(title: command.title, action: #selector(runMenuCommand(_:)), keyEquivalent: "")
            item.representedObject = command.rawValue
            item.target = self
            menu.addItem(item)
        }

        @objc private func runMenuCommand(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let command = ExplorerCommand(rawValue: rawValue) else {
                return
            }
            parent.onCommand(command)
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
                return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            case "kind":
                return entry.typeDescription
            default:
                return ""
            }
        }
    }
}
```

- [ ] **Step 2: Wire context menu command callback in root view**

Modify `RootView` where `FileTableView` is created:

```swift
onCommand: { command in
    Task { await explorerStore.perform(command) }
}
```

- [ ] **Step 3: Run tests and build**

Run:

```bash
swift test
swift build
```

Expected: both PASS.

- [ ] **Step 4: Commit context menus**

Run:

```bash
git add Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/RootView.swift
git commit -m "feat: add file table context menus"
```

Expected: commit succeeds.

## Task 6: Menu Bar Commands And Shortcuts

**Files:**
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`

- [ ] **Step 1: Add menu command routing**

Modify `MyMacFinderApp.swift` `.commands` block:

```swift
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New Folder") {
            Task { await explorerStore.perform(.newFolder) }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    CommandGroup(after: .pasteboard) {
        Button("Duplicate") {
            Task { await explorerStore.perform(.duplicate) }
        }
        .keyboardShortcut("d", modifiers: [.command])

        Button("Move to Trash") {
            Task { await explorerStore.perform(.moveToTrash) }
        }
        .keyboardShortcut(.delete, modifiers: [.command])

        Button("Copy Path") {
            Task { await explorerStore.perform(.copyPath) }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    CommandMenu("Explorer") {
        Button("Refresh") {
            Task { await explorerStore.perform(.refresh) }
        }
        .keyboardShortcut("r", modifiers: [.command])

        Button("Reveal in Finder") {
            Task { await explorerStore.perform(.revealInFinder) }
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}
```

This pass adds explicit Explorer menu commands and keyboard shortcuts. Responder-chain replacement of the default Edit menu pasteboard items is a separate shortcuts refinement plan so text editing in the path field remains native.

- [ ] **Step 2: Run tests and build**

Run:

```bash
swift test
swift build
```

Expected: both PASS.

- [ ] **Step 3: Commit menu bar commands**

Run:

```bash
git add Sources/MyMacFinder/App/MyMacFinderApp.swift
git commit -m "feat: add explorer menu commands"
```

Expected: commit succeeds.

## Task 7: Manual QA

**Files:**
- Modify: none

- [ ] **Step 1: Prepare manual QA folder**

Run:

```bash
rm -rf /tmp/MyMacFinderManualQA
mkdir -p /tmp/MyMacFinderManualQA/source /tmp/MyMacFinderManualQA/dest
printf 'alpha' > /tmp/MyMacFinderManualQA/source/alpha.txt
printf 'beta' > /tmp/MyMacFinderManualQA/source/beta.txt
```

Expected: command exits with status `0`.

- [ ] **Step 2: Launch the app**

Run:

```bash
swift run MyMacFinder
```

Expected: app launches and remains running.

- [ ] **Step 3: Manual UI checks**

In the visible app:

- Enter `/tmp/MyMacFinderManualQA/source` in the path field and press Return.
- Confirm `alpha.txt` and `beta.txt` appear.
- Right-click empty table space and choose `New Folder`; confirm `Untitled Folder` appears.
- Select `alpha.txt`, right-click it, choose `Duplicate`; confirm `alpha copy.txt` appears.
- Select `beta.txt`, use `Copy Path`; paste into a text field and confirm the path is copied.
- Select `alpha copy.txt`, use `Move to Trash`; confirm it disappears.
- Use menu command `Explorer > Refresh`; confirm the list remains correct.

- [ ] **Step 4: Stop the app**

Stop the `swift run MyMacFinder` process with `Ctrl+C` in the terminal.

- [ ] **Step 5: Final verification**

Run:

```bash
swift test
swift build -c release
git status --short
```

Expected: tests pass, release build succeeds, and Git status is clean.
