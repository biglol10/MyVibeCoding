# File Operations Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conflict handling, undo, ZIP extraction, and a repeatable long manual QA process for write-heavy file operations.

**Architecture:** Keep write behavior centralized in `FileOperationService`, with UI decisions supplied through a `FileConflictResolving` protocol. `ExplorerStore` remains the command coordinator: it injects the resolver, records undo actions from operation results, refreshes panes, and exposes new commands. AppKit-specific dialogs live outside the service so tests can use deterministic resolvers.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, XCTest, ZIPFoundation, SwiftPM resources/build scripts.

---

## File Structure

Create:
- `Sources/MyMacFinder/Domain/FileConflictModels.swift`: collision operation, conflict payload, decision enum, resolver protocol, cancellation error.
- `Sources/MyMacFinder/Domain/FileOperationResult.swift`: result records for created, moved, renamed, trashed, skipped paths.
- `Sources/MyMacFinder/Domain/FileUndoAction.swift`: LIFO undo action model and user-visible title.
- `Sources/MyMacFinder/Services/DefaultFileConflictResolver.swift`: deterministic resolver used by tests and headless defaults.
- `Sources/MyMacFinder/Services/AppKitFileConflictResolver.swift`: modal conflict decision UI.
- `Sources/MyMacFinder/Services/ZipExtractionService.swift`: extracts selected ZIP files into destination folders through collision-aware file operations.
- `Tests/MyMacFinderTests/FileConflictModelTests.swift`: model behavior.
- `Tests/MyMacFinderTests/FileUndoActionTests.swift`: undo action titles and payloads.
- `Tests/MyMacFinderTests/ZipExtractionServiceTests.swift`: ZIP extraction behavior.
- `Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift`: store undo behavior.
- `Tests/MyMacFinderTests/ExplorerZipExtractionCommandTests.swift`: command availability and store extraction flow.
- `docs/qa/file-operations-stabilization-manual-qa.md`: long manual QA checklist.
- `scripts/create-file-operations-qa-fixture.sh`: repeatable QA fixture generator.

Modify:
- `Sources/MyMacFinder/Services/FileOperationService.swift`: apply conflict decisions and return `FileOperationResult`.
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`: inject resolver/extractor, record undo stack, run undo, run ZIP extraction.
- `Sources/MyMacFinder/Domain/ExplorerCommand.swift`: add `undo` and `extractZip`.
- `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`: map `Cmd+Z`.
- `Sources/MyMacFinder/App/MyMacFinderApp.swift`: add Undo and Extract ZIP menu items.
- `Sources/MyMacFinder/UI/FileTableView.swift`: add context menu entries and command enablement.
- Existing tests that construct `ExplorerCommand` expectations.

---

### Task 1: Conflict Models

**Files:**
- Create: `Sources/MyMacFinder/Domain/FileConflictModels.swift`
- Create: `Tests/MyMacFinderTests/FileConflictModelTests.swift`

- [ ] **Step 1: Write the failing model tests**

Create `Tests/MyMacFinderTests/FileConflictModelTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileConflictModelTests: XCTestCase {
    func testDefaultResolverReturnsConfiguredDecision() async throws {
        let source = URL(fileURLWithPath: "/tmp/source.txt")
        let destination = URL(fileURLWithPath: "/tmp/dest.txt")
        let conflict = FileConflict(
            operation: .copy,
            sourceURL: source,
            destinationURL: destination,
            itemIndex: 2,
            itemCount: 5
        )
        let resolver = DefaultFileConflictResolver(decision: .keepBoth)

        let decision = try await resolver.resolve(conflict)

        XCTAssertEqual(decision, .keepBoth)
        XCTAssertEqual(conflict.displayName, "source.txt")
        XCTAssertEqual(conflict.progressDescription, "3 of 5")
    }

    func testCancelDecisionThrowsCancellationError() async {
        let resolver = DefaultFileConflictResolver(decision: .cancel)
        let conflict = FileConflict(
            operation: .move,
            sourceURL: URL(fileURLWithPath: "/tmp/a.txt"),
            destinationURL: URL(fileURLWithPath: "/tmp/b.txt"),
            itemIndex: 0,
            itemCount: 1
        )

        do {
            _ = try await resolver.resolve(conflict)
            XCTFail("Expected cancellation")
        } catch let error as FileOperationCancellation {
            XCTAssertEqual(error.operation, .move)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter FileConflictModelTests
```

Expected: compile fails because `FileConflict`, `FileConflictOperation`, `FileConflictDecision`, `DefaultFileConflictResolver`, and `FileOperationCancellation` do not exist.

- [ ] **Step 3: Implement conflict model**

Create `Sources/MyMacFinder/Domain/FileConflictModels.swift`:

```swift
import Foundation

public enum FileConflictOperation: String, Equatable, Sendable {
    case copy
    case move
    case rename
    case duplicate
    case extract

    public var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .extract: return "Extract"
        }
    }
}

public enum FileConflictDecision: Equatable, Sendable {
    case replace
    case keepBoth
    case skip
    case cancel
}

public struct FileConflict: Equatable, Sendable {
    public var operation: FileConflictOperation
    public var sourceURL: URL
    public var destinationURL: URL
    public var itemIndex: Int
    public var itemCount: Int

    public init(
        operation: FileConflictOperation,
        sourceURL: URL,
        destinationURL: URL,
        itemIndex: Int,
        itemCount: Int
    ) {
        self.operation = operation
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.itemIndex = itemIndex
        self.itemCount = itemCount
    }

    public var displayName: String {
        sourceURL.lastPathComponent
    }

    public var progressDescription: String {
        "\(itemIndex + 1) of \(itemCount)"
    }
}

public struct FileOperationCancellation: LocalizedError, Equatable, Sendable {
    public var operation: FileConflictOperation

    public init(operation: FileConflictOperation) {
        self.operation = operation
    }

    public var errorDescription: String? {
        "\(operation.title) cancelled."
    }
}

public protocol FileConflictResolving: Sendable {
    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision
}
```

Create `Sources/MyMacFinder/Services/DefaultFileConflictResolver.swift`:

```swift
import Foundation

public struct DefaultFileConflictResolver: FileConflictResolving {
    private let decision: FileConflictDecision

    public init(decision: FileConflictDecision = .keepBoth) {
        self.decision = decision
    }

    public func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        if decision == .cancel {
            throw FileOperationCancellation(operation: conflict.operation)
        }
        return decision
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
swift test --filter FileConflictModelTests
```

Expected: `FileConflictModelTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Domain/FileConflictModels.swift Sources/MyMacFinder/Services/DefaultFileConflictResolver.swift Tests/MyMacFinderTests/FileConflictModelTests.swift
git commit -m "feat: add file conflict model"
```

---

### Task 2: Collision-Aware File Operation Results

**Files:**
- Create: `Sources/MyMacFinder/Domain/FileOperationResult.swift`
- Modify: `Sources/MyMacFinder/Services/FileOperationService.swift`
- Modify: `Tests/MyMacFinderTests/FileOperationServiceTests.swift`

- [ ] **Step 1: Add failing service tests**

Append these tests to `Tests/MyMacFinderTests/FileOperationServiceTests.swift`:

```swift
func testCopyItemsReplacesExistingFileWhenResolverChoosesReplace() async throws {
    let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
    let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
    let sourceFile = sourceFolder.appendingPathComponent("note.txt")
    let existingDest = destFolder.appendingPathComponent("note.txt")
    try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
    try "old".write(to: existingDest, atomically: true, encoding: .utf8)
    let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

    let result = try await service.copyItems([sourceFile], to: destFolder)

    XCTAssertEqual(result.createdURLs, [existingDest.standardizedFileURL])
    XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "new")
}

func testCopyItemsSkipsExistingFileWhenResolverChoosesSkip() async throws {
    let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
    let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
    let sourceFile = sourceFolder.appendingPathComponent("note.txt")
    let existingDest = destFolder.appendingPathComponent("note.txt")
    try "new".write(to: sourceFile, atomically: true, encoding: .utf8)
    try "old".write(to: existingDest, atomically: true, encoding: .utf8)
    let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .skip))

    let result = try await service.copyItems([sourceFile], to: destFolder)

    XCTAssertEqual(result.createdURLs, [])
    XCTAssertEqual(result.skippedURLs, [sourceFile.standardizedFileURL])
    XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "old")
}

func testMoveItemsCanKeepBothOnCollision() async throws {
    let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
    let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
    let sourceFile = sourceFolder.appendingPathComponent("note.txt")
    let existingDest = destFolder.appendingPathComponent("note.txt")
    try "moved".write(to: sourceFile, atomically: true, encoding: .utf8)
    try "existing".write(to: existingDest, atomically: true, encoding: .utf8)
    let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .keepBoth))

    let result = try await service.moveItems([sourceFile], to: destFolder)

    XCTAssertEqual(result.movedItems.first?.source, sourceFile.standardizedFileURL)
    XCTAssertEqual(result.movedItems.first?.destination.lastPathComponent, "note copy.txt")
    XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
    XCTAssertEqual(try String(contentsOf: existingDest, encoding: .utf8), "existing")
}

func testRenameCanReplaceExistingFile() async throws {
    let oldFile = tempDirectory.appendingPathComponent("old.txt")
    let existing = tempDirectory.appendingPathComponent("new.txt")
    try "old content".write(to: oldFile, atomically: true, encoding: .utf8)
    try "existing content".write(to: existing, atomically: true, encoding: .utf8)
    let service = FileOperationService(conflictResolver: DefaultFileConflictResolver(decision: .replace))

    let result = try await service.rename(oldFile, to: "new.txt")

    XCTAssertEqual(result.renamedItem?.source, oldFile.standardizedFileURL)
    XCTAssertEqual(result.renamedItem?.destination, existing.standardizedFileURL)
    XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old content")
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter FileOperationServiceTests
```

Expected: compile fails because `FileOperationService` does not accept `conflictResolver`, async operation signatures are not present, and `FileOperationResult` does not exist.

- [ ] **Step 3: Implement operation result types**

Create `Sources/MyMacFinder/Domain/FileOperationResult.swift`:

```swift
import Foundation

public struct FileMoveRecord: Equatable, Sendable {
    public var source: URL
    public var destination: URL

    public init(source: URL, destination: URL) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
    }
}

public struct FileTrashRecord: Equatable, Sendable {
    public var original: URL
    public var trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original.standardizedFileURL
        self.trashed = trashed.standardizedFileURL
    }
}

public struct FileOperationResult: Equatable, Sendable {
    public var createdURLs: [URL]
    public var movedItems: [FileMoveRecord]
    public var renamedItem: FileMoveRecord?
    public var trashedItems: [FileTrashRecord]
    public var skippedURLs: [URL]

    public init(
        createdURLs: [URL] = [],
        movedItems: [FileMoveRecord] = [],
        renamedItem: FileMoveRecord? = nil,
        trashedItems: [FileTrashRecord] = [],
        skippedURLs: [URL] = []
    ) {
        self.createdURLs = createdURLs.map(\.standardizedFileURL)
        self.movedItems = movedItems
        self.renamedItem = renamedItem
        self.trashedItems = trashedItems
        self.skippedURLs = skippedURLs.map(\.standardizedFileURL)
    }

    public var changedFileSystem: Bool {
        !createdURLs.isEmpty || !movedItems.isEmpty || renamedItem != nil || !trashedItems.isEmpty
    }
}
```

- [ ] **Step 4: Refactor `FileOperationService`**

Modify `Sources/MyMacFinder/Services/FileOperationService.swift`:

- Add `private let conflictResolver: any FileConflictResolving`.
- Change initializer to `public init(fileManager: FileManager = .default, conflictResolver: any FileConflictResolving = DefaultFileConflictResolver())`.
- Convert all write methods to `async throws` so conflict prompts can be awaited consistently.
- Return `FileOperationResult` from create, rename, duplicate, copy, move, and trash methods.
- Keep destination naming from the existing `copyName(for:)` and `uniqueURL(in:baseName:extension:)`.
- Add a private async helper:

```swift
private func resolvedDestination(
    operation: FileConflictOperation,
    source: URL,
    proposed: URL,
    itemIndex: Int,
    itemCount: Int
) async throws -> URL? {
    guard fileManager.fileExists(atPath: proposed.path) else {
        return proposed
    }

    let conflict = FileConflict(
        operation: operation,
        sourceURL: source,
        destinationURL: proposed,
        itemIndex: itemIndex,
        itemCount: itemCount
    )

    let decision = try await conflictResolver.resolve(conflict)
    switch decision {
    case .replace:
        try replaceExistingItem(at: proposed)
        return proposed
    case .keepBoth:
        return copyName(for: proposed)
    case .skip:
        return nil
    case .cancel:
        throw FileOperationCancellation(operation: operation)
    }
}
```

- Add conservative replacement:

```swift
private func replaceExistingItem(at url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    var trashedURL: NSURL?
    try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
}
```

- [ ] **Step 5: Update existing call sites and existing tests to await new signatures**

Update `ExplorerStore` temporarily with `try await` for:

- `createFolder`
- `rename`
- `duplicate`
- `copyItems`
- `moveItems`
- `moveToTrash`

This task does not record undo yet; it only preserves existing behavior with the new result-returning service.

Update existing `FileOperationServiceTests` methods from `throws` to `async throws` when they call `FileOperationService`, and add `try await` to service calls. For example:

```swift
func testRenamesItem() async throws {
    let file = tempDirectory.appendingPathComponent("old.txt")
    try "text".write(to: file, atomically: true, encoding: .utf8)
    let service = FileOperationService()

    let result = try await service.rename(file, to: "new.txt")

    XCTAssertEqual(result.renamedItem?.destination.lastPathComponent, "new.txt")
}
```

Add cancellation-specific handling in `ExplorerStore.perform(_:)`, `renameSelected(to:)`, and `performDrop(urls:destinationFolder:operation:)`:

```swift
} catch is FileOperationCancellation {
    return
}
```

Place that catch before the `ExplorerError` catch so user cancellation does not show an alert.

- [ ] **Step 6: Run service tests and existing store tests**

Run:

```bash
swift test --filter FileOperationServiceTests
swift test --filter ExplorerStoreTests
swift test --filter ExplorerStoreDropTests
```

Expected: all listed tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacFinder/Domain/FileOperationResult.swift Sources/MyMacFinder/Services/FileOperationService.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/FileOperationServiceTests.swift
git commit -m "feat: add collision-aware file operations"
```

---

### Task 3: Undo Model and Store Stack

**Files:**
- Create: `Sources/MyMacFinder/Domain/FileUndoAction.swift`
- Create: `Tests/MyMacFinderTests/FileUndoActionTests.swift`
- Create: `Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`

- [ ] **Step 1: Write failing undo model tests**

Create `Tests/MyMacFinderTests/FileUndoActionTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileUndoActionTests: XCTestCase {
    func testUndoActionTitlesDescribeUserOperation() {
        XCTAssertEqual(FileUndoAction.created([URL(fileURLWithPath: "/tmp/a")]).title, "Undo Create")
        XCTAssertEqual(FileUndoAction.copied([URL(fileURLWithPath: "/tmp/a")]).title, "Undo Copy")
        XCTAssertEqual(
            FileUndoAction.moved([FileMoveRecord(source: URL(fileURLWithPath: "/tmp/a"), destination: URL(fileURLWithPath: "/tmp/b"))]).title,
            "Undo Move"
        )
        XCTAssertEqual(
            FileUndoAction.renamed(FileMoveRecord(source: URL(fileURLWithPath: "/tmp/a"), destination: URL(fileURLWithPath: "/tmp/b"))).title,
            "Undo Rename"
        )
    }
}
```

- [ ] **Step 2: Write failing store undo tests**

Create `Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerUndoCommandTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderUndo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testUndoCreateFolderMovesCreatedFolderToTrash() async {
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        await store.perform(.newFolder)

        XCTAssertTrue(store.canUndo)
        await store.perform(.undo)

        XCTAssertFalse(store.activePane.entries.contains { $0.name == "Untitled Folder" })
    }

    func testUndoRenameRestoresOriginalName() async throws {
        let file = tempDirectory.appendingPathComponent("old.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.renameSelected(to: "new.txt")
        await store.perform(.undo)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "old.txt" })
        XCTAssertFalse(store.activePane.entries.contains { $0.name == "new.txt" })
    }

    func testUndoMoveRestoresMovedFile() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let file = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: file, atomically: true, encoding: .utf8)
        let store = ExplorerStore(initialURL: sourceFolder, directoryWatcher: nil)
        await store.refresh()
        store.updateSelection([file.standardizedFileURL])

        await store.perform(.cut)
        await store.navigate(to: destFolder)
        await store.perform(.paste)
        await store.perform(.undo)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("move.txt").path))
    }
}
```

- [ ] **Step 3: Run undo tests and verify RED**

Run:

```bash
swift test --filter FileUndoActionTests
swift test --filter ExplorerUndoCommandTests
```

Expected: compile fails because `FileUndoAction`, `ExplorerCommand.undo`, and `ExplorerStore.canUndo` do not exist.

- [ ] **Step 4: Implement undo action model**

Create `Sources/MyMacFinder/Domain/FileUndoAction.swift`:

```swift
import Foundation

public enum FileUndoAction: Equatable, Sendable {
    case created([URL])
    case copied([URL])
    case moved([FileMoveRecord])
    case renamed(FileMoveRecord)
    case trashed([FileTrashRecord])
    case extracted([URL])

    public var title: String {
        switch self {
        case .created: return "Undo Create"
        case .copied: return "Undo Copy"
        case .moved: return "Undo Move"
        case .renamed: return "Undo Rename"
        case .trashed: return "Undo Move to Trash"
        case .extracted: return "Undo Extract"
        }
    }
}
```

- [ ] **Step 5: Add undo stack to `ExplorerStore`**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

- Add `@Published public private(set) var undoStack: [FileUndoAction]`.
- Add `public var canUndo: Bool { !undoStack.isEmpty }`.
- Initialize `undoStack = []`.
- Add `private func recordUndo(_ action: FileUndoAction?)`.
- Convert operation results into undo actions:
  - create folder: `.created(result.createdURLs)`
  - rename: `.renamed(record)`
  - duplicate/copy: `.copied(result.createdURLs)`
  - move: `.moved(result.movedItems)`
  - trash: `.trashed(result.trashedItems)`
- Implement `private func undoLatest() async throws`.

Undo execution rules:

```swift
private func undoLatest() async throws {
    guard let action = undoStack.popLast() else { return }
    switch action {
    case .created(let urls), .copied(let urls), .extracted(let urls):
        _ = try await fileOperationService.moveToTrash(urls)
    case .moved(let records):
        for record in records.reversed() {
            _ = try await fileOperationService.moveItems([record.destination], to: record.source.deletingLastPathComponent())
        }
    case .renamed(let record):
        _ = try await fileOperationService.rename(record.destination, to: record.source.lastPathComponent)
    case .trashed(let records):
        for record in records {
            _ = try await fileOperationService.moveItems([record.trashed], to: record.original.deletingLastPathComponent())
            let restored = record.original.deletingLastPathComponent().appendingPathComponent(record.trashed.lastPathComponent)
            if restored.standardizedFileURL != record.original.standardizedFileURL {
                _ = try await fileOperationService.rename(restored, to: record.original.lastPathComponent)
            }
        }
    }
}
```

- [ ] **Step 6: Add command case but keep UI wiring for Task 4**

Modify `ExplorerCommand` with `case undo`, title `Undo`, and enablement `return canUndo` through a new overload:

```swift
public func isEnabled(
    selectionCount: Int,
    canPaste: Bool,
    canUndo: Bool,
    selectedEntries: [FileEntry],
    isArchiveLocation: Bool
) -> Bool
```

Keep existing overloads delegating with `canUndo: false` so older tests compile.

- [ ] **Step 7: Run undo tests and related command tests**

Run:

```bash
swift test --filter FileUndoActionTests
swift test --filter ExplorerUndoCommandTests
swift test --filter ExplorerCommandTests
swift test --filter ExplorerStoreTests
```

Expected: all listed tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/MyMacFinder/Domain/FileUndoAction.swift Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/FileUndoActionTests.swift Tests/MyMacFinderTests/ExplorerUndoCommandTests.swift
git commit -m "feat: add undo stack for file operations"
```

---

### Task 4: Undo Command UI and Shortcut Wiring

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`

- [ ] **Step 1: Write failing shortcut and command tests**

Add to `ExplorerKeyboardShortcutTests.testCommandShortcutsMapToFileCommands`:

```swift
XCTAssertEqual(
    ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "z", modifiers: [.command])),
    .undo
)
```

Add to `ExplorerCommandTests`:

```swift
func testUndoDependsOnUndoState() {
    XCTAssertFalse(
        ExplorerCommand.undo.isEnabled(
            selectionCount: 0,
            canPaste: false,
            canUndo: false,
            selectedEntries: [],
            isArchiveLocation: false
        )
    )
    XCTAssertTrue(
        ExplorerCommand.undo.isEnabled(
            selectionCount: 0,
            canPaste: false,
            canUndo: true,
            selectedEntries: [],
            isArchiveLocation: false
        )
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
swift test --filter ExplorerCommandTests
```

Expected: shortcut test fails until key mapping is added; command test fails until enablement is wired.

- [ ] **Step 3: Implement shortcut mapping**

Modify `ExplorerKeyboardShortcut.command(for:)` so:

```swift
case ExplorerShortcut(key: "z", modifiers: [.command]):
    return .undo
```

Use the file's existing switch/dictionary style.

- [ ] **Step 4: Wire menu bar Undo**

Modify `MyMacFinderApp.isEnabled(_:)` to call the new overload with `canUndo: explorerStore.canUndo`.

Add near the top of `CommandMenu("Explorer")`:

```swift
Button("Undo") {
    perform(.undo)
}
.keyboardShortcut("z", modifiers: [.command])
.disabled(!isEnabled(.undo))

Divider()
```

- [ ] **Step 5: Wire context menu Undo**

Modify `FileTableView`:

- Add `var canUndo: Bool`.
- Pass `canUndo` from `RootView`.
- In `itemMenu()` and `emptyMenu()`, add Undo before write operations:

```swift
addMenuItem(to: menu, command: .undo, selectionCount: currentSelectionCount)
menu.addItem(.separator())
```

- Update `addMenuItem` enablement call to pass `canUndo: parent.canUndo`.

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
swift test --filter ExplorerCommandTests
swift test --filter ExplorerUndoCommandTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/RootView.swift Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift
git commit -m "feat: wire undo command UI"
```

---

### Task 5: ZIP Extraction Service

**Files:**
- Create: `Sources/MyMacFinder/Services/ZipExtractionService.swift`
- Create: `Tests/MyMacFinderTests/ZipExtractionServiceTests.swift`

- [ ] **Step 1: Write failing extraction tests**

Create `Tests/MyMacFinderTests/ZipExtractionServiceTests.swift`:

```swift
import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ZipExtractionServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderExtract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testExtractsZipIntoNamedFolder() async throws {
        let zipURL = try makeArchive(named: "sample.zip")
        let service = ZipExtractionService()

        let result = try await service.extract([zipURL], to: tempDirectory)

        let extractedFolder = tempDirectory.appendingPathComponent("sample", isDirectory: true)
        XCTAssertEqual(result.createdURLs, [extractedFolder.standardizedFileURL])
        XCTAssertEqual(try String(contentsOf: extractedFolder.appendingPathComponent("docs/readme.txt"), encoding: .utf8), "hello")
    }

    func testExtractionUsesKeepBothForDestinationCollision() async throws {
        let zipURL = try makeArchive(named: "sample.zip")
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("sample", isDirectory: true), withIntermediateDirectories: true)
        let service = ZipExtractionService(conflictResolver: DefaultFileConflictResolver(decision: .keepBoth))

        let result = try await service.extract([zipURL], to: tempDirectory)

        XCTAssertEqual(result.createdURLs.first?.lastPathComponent, "sample copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("sample copy/docs/readme.txt").path))
    }

    private func makeArchive(named name: String) throws -> URL {
        let source = tempDirectory.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
        try "hello".write(to: source.appendingPathComponent("docs/readme.txt"), atomically: true, encoding: .utf8)
        let archiveURL = tempDirectory.appendingPathComponent(name)
        try FileManager.default.zipItem(at: source, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        return archiveURL
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ZipExtractionServiceTests
```

Expected: compile fails because `ZipExtractionService` does not exist.

- [ ] **Step 3: Implement extraction service**

Create `Sources/MyMacFinder/Services/ZipExtractionService.swift`:

```swift
import Foundation
import ZIPFoundation

public protocol ZipExtracting: Sendable {
    func extract(_ zipURLs: [URL], to destinationFolder: URL) async throws -> FileOperationResult
}

public struct ZipExtractionService: ZipExtracting, @unchecked Sendable {
    private let fileManager: FileManager
    private let conflictResolver: any FileConflictResolving

    public init(
        fileManager: FileManager = .default,
        conflictResolver: any FileConflictResolving = DefaultFileConflictResolver()
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
    }

    public func extract(_ zipURLs: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        var created: [URL] = []
        var skipped: [URL] = []

        for (index, zipURL) in zipURLs.enumerated() {
            guard zipURL.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame else {
                skipped.append(zipURL.standardizedFileURL)
                continue
            }

            let baseName = zipURL.deletingPathExtension().lastPathComponent
            let proposedFolder = destinationFolder.appendingPathComponent(baseName, isDirectory: true)
            guard let extractionFolder = try await resolvedExtractionFolder(
                zipURL: zipURL,
                proposedFolder: proposedFolder,
                index: index,
                count: zipURLs.count
            ) else {
                skipped.append(zipURL.standardizedFileURL)
                continue
            }

            try fileManager.createDirectory(at: extractionFolder, withIntermediateDirectories: true)
            let archive: Archive
            do {
                archive = try Archive(url: zipURL, accessMode: .read)
            } catch {
                throw ExplorerError.readFailed("ZIP archive could not be read: \(zipURL.path)")
            }
            for entry in archive {
                let destination = extractionFolder.appendingPathComponent(entry.path)
                if entry.type == .directory {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: destination)
                }
            }
            created.append(extractionFolder.standardizedFileURL)
        }

        return FileOperationResult(createdURLs: created, skippedURLs: skipped)
    }

    private func resolvedExtractionFolder(zipURL: URL, proposedFolder: URL, index: Int, count: Int) async throws -> URL? {
        guard fileManager.fileExists(atPath: proposedFolder.path) else { return proposedFolder }
        let decision = try await conflictResolver.resolve(
            FileConflict(operation: .extract, sourceURL: zipURL, destinationURL: proposedFolder, itemIndex: index, itemCount: count)
        )
        switch decision {
        case .replace:
            var trashedURL: NSURL?
            try fileManager.trashItem(at: proposedFolder, resultingItemURL: &trashedURL)
            return proposedFolder
        case .keepBoth:
            return uniqueURL(in: proposedFolder.deletingLastPathComponent(), baseName: proposedFolder.lastPathComponent)
        case .skip:
            return nil
        case .cancel:
            throw FileOperationCancellation(operation: .extract)
        }
    }

    private func uniqueURL(in parent: URL, baseName: String) -> URL {
        var candidate = parent.appendingPathComponent("\(baseName) copy", isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) copy \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run extraction tests**

Run:

```bash
swift test --filter ZipExtractionServiceTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Services/ZipExtractionService.swift Tests/MyMacFinderTests/ZipExtractionServiceTests.swift
git commit -m "feat: add zip extraction service"
```

---

### Task 6: Extract ZIP Store, Menu, Context Menu

**Files:**
- Create: `Tests/MyMacFinderTests/ExplorerZipExtractionCommandTests.swift`
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`

- [ ] **Step 1: Write failing command/store tests**

Create `Tests/MyMacFinderTests/ExplorerZipExtractionCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

private final class CapturingZipExtractor: ZipExtracting, @unchecked Sendable {
    var result: FileOperationResult
    private(set) var capturedURLs: [URL] = []
    private(set) var capturedDestination: URL?

    init(result: FileOperationResult) {
        self.result = result
    }

    func extract(_ zipURLs: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        capturedURLs = zipURLs
        capturedDestination = destinationFolder
        return result
    }
}

@MainActor
final class ExplorerZipExtractionCommandTests: XCTestCase {
    func testExtractZipRequiresFileSystemZipSelection() {
        let zip = FileEntry(url: URL(fileURLWithPath: "/tmp/a.zip"), name: "a.zip", kind: .file, typeDescription: "ZIP Archive", fileExtension: "zip", size: 1, dateModified: nil, dateCreated: nil, dateAccessed: nil, isHidden: false, isDirectoryLike: false, isReadable: true)
        let text = FileEntry(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", kind: .file, typeDescription: "Text", fileExtension: "txt", size: 1, dateModified: nil, dateCreated: nil, dateAccessed: nil, isHidden: false, isDirectoryLike: false, isReadable: true)

        XCTAssertTrue(ExplorerCommand.extractZip.isEnabled(selectionCount: 1, canPaste: false, canUndo: false, selectedEntries: [zip], isArchiveLocation: false))
        XCTAssertFalse(ExplorerCommand.extractZip.isEnabled(selectionCount: 1, canPaste: false, canUndo: false, selectedEntries: [text], isArchiveLocation: false))
        XCTAssertFalse(ExplorerCommand.extractZip.isEnabled(selectionCount: 1, canPaste: false, canUndo: false, selectedEntries: [zip], isArchiveLocation: true))
    }

    func testStoreExtractsSelectedZipAndRecordsUndo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderExtractStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let zipURL = tempDirectory.appendingPathComponent("a.zip")
        try "zip data".write(to: zipURL, atomically: true, encoding: .utf8)
        let extracted = tempDirectory.appendingPathComponent("a", isDirectory: true)
        let extractor = CapturingZipExtractor(result: FileOperationResult(createdURLs: [extracted]))
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil, zipExtractor: extractor)
        await store.refresh()
        store.updateSelection([zipURL.standardizedFileURL])

        await store.perform(.extractZip)

        XCTAssertEqual(extractor.capturedURLs, [zipURL.standardizedFileURL])
        XCTAssertEqual(extractor.capturedDestination, tempDirectory.standardizedFileURL)
        XCTAssertTrue(store.canUndo)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ExplorerZipExtractionCommandTests
```

Expected: compile fails because `ExplorerCommand.extractZip` and `ExplorerStore` zip extractor injection do not exist.

- [ ] **Step 3: Add command availability**

Modify `ExplorerCommand`:

- Add `case extractZip`.
- Title: `Extract ZIP`.
- In archive locations, return false for `.extractZip`.
- In file-system locations, enable only when `selectedEntries` contains at least one non-archive-backed `.zip` file.

- [ ] **Step 4: Inject and run ZIP extraction in store**

Modify `ExplorerStore`:

- Add `private let zipExtractor: any ZipExtracting`.
- Add init parameter `zipExtractor: any ZipExtracting = ZipExtractionService()`.
- In `perform(_:)`, add:

```swift
case .extractZip:
    try await extractSelectedZips()
```

- Add:

```swift
private func extractSelectedZips() async throws {
    guard let currentURL = activePane.location.fileSystemURL else {
        throw ExplorerError.readFailed("Cannot extract ZIP files inside ZIP archives.")
    }
    let zipURLs = activePane.selectedEntries
        .filter { !$0.isArchiveBacked && $0.fileExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame }
        .map(\.url.standardizedFileURL)
    guard !zipURLs.isEmpty else { return }
    let result = try await zipExtractor.extract(zipURLs, to: currentURL.standardizedFileURL)
    if !result.createdURLs.isEmpty {
        recordUndo(.extracted(result.createdURLs))
    }
    await refresh()
}
```

- [ ] **Step 5: Wire menus**

Modify `MyMacFinderApp` and `FileTableView`:

- Add `Extract ZIP` near `Quick Look` or after `Duplicate`.
- Disable with `isEnabled(.extractZip)`.
- Add to item context menu when a row is selected.

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift test --filter ExplorerZipExtractionCommandTests
swift test --filter ExplorerArchiveCommandTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Sources/MyMacFinder/UI/FileTableView.swift Tests/MyMacFinderTests/ExplorerZipExtractionCommandTests.swift
git commit -m "feat: wire zip extraction command"
```

---

### Task 7: AppKit Conflict Dialog

**Files:**
- Create: `Sources/MyMacFinder/Services/AppKitFileConflictResolver.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Build-only verification.

- [ ] **Step 1: Implement AppKit resolver**

Create `Sources/MyMacFinder/Services/AppKitFileConflictResolver.swift`:

```swift
import AppKit
import Foundation

@MainActor
public final class AppKitFileConflictResolver: FileConflictResolving, @unchecked Sendable {
    public init() {}

    public func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        let alert = NSAlert()
        alert.messageText = "\(conflict.operation.title) Conflict"
        alert.informativeText = """
        An item named "\(conflict.destinationURL.lastPathComponent)" already exists in "\(conflict.destinationURL.deletingLastPathComponent().path)".

        Item \(conflict.progressDescription): \(conflict.displayName)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Keep Both")
        if conflict.operation != .rename {
            alert.addButton(withTitle: "Skip")
        }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .keepBoth
        case .alertThirdButtonReturn where conflict.operation != .rename:
            return .skip
        default:
            throw FileOperationCancellation(operation: conflict.operation)
        }
    }
}
```

- [ ] **Step 2: Use AppKit resolver in the app entry point**

Keep `ExplorerStore` test-friendly by preserving deterministic service defaults. Change `MyMacFinderApp` state initialization to inject AppKit-backed conflict decisions for real app usage:

```swift
@StateObject private var explorerStore = ExplorerStore(
    fileOperationService: FileOperationService(conflictResolver: AppKitFileConflictResolver()),
    zipExtractor: ZipExtractionService(conflictResolver: AppKitFileConflictResolver())
)
```

- [ ] **Step 3: Build and run targeted tests**

Run:

```bash
swift test --filter FileOperationServiceTests
swift test --filter ZipExtractionServiceTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MyMacFinder/Services/AppKitFileConflictResolver.swift Sources/MyMacFinder/App/MyMacFinderApp.swift
git commit -m "feat: add file conflict dialog"
```

---

### Task 8: Manual QA Fixture and Checklist

**Files:**
- Create: `scripts/create-file-operations-qa-fixture.sh`
- Create: `docs/qa/file-operations-stabilization-manual-qa.md`

- [ ] **Step 1: Add fixture script**

Create `scripts/create-file-operations-qa-fixture.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

target="${1:-${TMPDIR:-/tmp}/mymacfinder-file-ops-qa}"
rm -rf "$target"
mkdir -p "$target/source" "$target/dest" "$target/drag-target" "$target/zips/nested"

printf "source alpha\n" > "$target/source/alpha.txt"
printf "source collide\n" > "$target/source/collide.txt"
printf "destination collide\n" > "$target/dest/collide.txt"
printf "rename original\n" > "$target/source/rename-me.txt"
printf "duplicate original\n" > "$target/source/duplicate-me.txt"
mkdir -p "$target/source/folder-a/child"
printf "folder child\n" > "$target/source/folder-a/child/file.txt"

printf "zip readme\n" > "$target/zips/nested/readme.txt"
printf "zip collide\n" > "$target/zips/collide.txt"
(
  cd "$target/zips"
  /usr/bin/zip -qr "$target/source/archive.zip" nested collide.txt
)
mkdir -p "$target/source/archive"
printf "existing archive folder\n" > "$target/source/archive/existing.txt"

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-large-folder-fixture.sh" "$target/large" 1500 100 >/dev/null

echo "$target"
```

Make it executable:

```bash
chmod +x scripts/create-file-operations-qa-fixture.sh
```

- [ ] **Step 2: Add QA checklist**

Create `docs/qa/file-operations-stabilization-manual-qa.md` with these sections:

```markdown
# File Operations Stabilization Manual QA

## Setup

Run:

```bash
fixture="$(scripts/create-file-operations-qa-fixture.sh)"
scripts/create-app-bundle.sh --configuration debug
open .build/app/MyMacFinder.app
```

Navigate the app to `$fixture/source`.

## Collision Handling

1. Copy `collide.txt`.
2. Navigate to `$fixture/dest`.
3. Paste.
4. In the conflict dialog choose `Keep Both`.
5. Expected: `$fixture/dest/collide.txt` still contains `destination collide`; `$fixture/dest/collide copy.txt` contains `source collide`.

Repeat the same copy flow and choose `Replace`.
Expected: `$fixture/dest/collide.txt` contains `source collide`.

Repeat the same copy flow and choose `Skip`.
Expected: destination files do not change.

Repeat the same copy flow and choose `Cancel`.
Expected: destination files do not change and no alert appears.

## Undo

1. Create a new folder.
2. Press `Cmd+Z`.
3. Expected: new folder disappears.

1. Rename `rename-me.txt` to `renamed.txt`.
2. Press `Cmd+Z`.
3. Expected: `rename-me.txt` is restored.

1. Duplicate `duplicate-me.txt`.
2. Press `Cmd+Z`.
3. Expected: duplicate disappears and original remains.

1. Cut `alpha.txt`, navigate to `$fixture/dest`, paste.
2. Press `Cmd+Z`.
3. Expected: `alpha.txt` returns to `$fixture/source`.

1. Move `duplicate-me.txt` to Trash.
2. Press `Cmd+Z`.
3. Expected: `duplicate-me.txt` is restored in `$fixture/source`.

## ZIP Extraction

1. Select `archive.zip`.
2. Run `Extract ZIP`.
3. Choose `Keep Both` when prompted for existing `archive` folder.
4. Expected: `archive copy/nested/readme.txt` exists and contains `zip readme`.
5. Press `Cmd+Z`.
6. Expected: `archive copy` disappears.

## Drag and Drop

1. Drag `folder-a` onto `$fixture/drag-target` in the app.
2. Expected: folder moves or copies according to the shown operation.
3. Press `Cmd+Z`.
4. Expected: operation is reverted.

## External Sync

Run:

```bash
printf "external\n" > "$fixture/source/external-created.txt"
mv "$fixture/source/external-created.txt" "$fixture/source/external-renamed.txt"
rm "$fixture/source/external-renamed.txt"
```

Expected: app updates without manual refresh after each operation.

## Large Folder Smoke

Navigate to `$fixture/large`.
Expected: table remains scrollable and selection works.

## Cleanup

Run:

```bash
rm -rf "$fixture"
```
```

- [ ] **Step 3: Run fixture script**

Run:

```bash
scripts/create-file-operations-qa-fixture.sh /tmp/mymacfinder-file-ops-qa-check
test -f /tmp/mymacfinder-file-ops-qa-check/source/archive.zip
rm -rf /tmp/mymacfinder-file-ops-qa-check
```

Expected: commands exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/create-file-operations-qa-fixture.sh docs/qa/file-operations-stabilization-manual-qa.md
git commit -m "docs: add file operations manual qa"
```

---

### Task 9: Full Verification and Manual QA

**Files:**
- No source changes unless QA finds bugs.

- [ ] **Step 1: Run automated verification**

Run:

```bash
scripts/verify-app-icon.sh
swift test
swift build -c release
git diff --check
```

Expected:

- App icon verification prints `App icon verification passed`.
- `swift test` reports 0 failures.
- Release build exits 0.
- `git diff --check` exits 0.

- [ ] **Step 2: Build QA app bundle**

Run:

```bash
scripts/create-app-bundle.sh --configuration debug
```

Expected: prints `.build/app/MyMacFinder.app`.

- [ ] **Step 3: Run manual QA checklist**

Follow `docs/qa/file-operations-stabilization-manual-qa.md` exactly.

Expected: every expected filesystem result matches the checklist.

- [ ] **Step 4: Fix bugs found by manual QA**

For each bug:

1. Write a failing automated test that reproduces the behavior when possible.
2. Run the test and verify RED.
3. Implement the minimal fix.
4. Run the test and verify GREEN.
5. Re-run the relevant manual QA section.

- [ ] **Step 5: Final status check**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: worktree is clean after any final bugfix commit.

---

## Self-Review

- Spec coverage: collision handling is covered by Tasks 1, 2, and 7; undo by Tasks 3 and 4; ZIP extraction by Tasks 5 and 6; manual QA by Tasks 8 and 9.
- Scope check: tabs, advanced search, sandboxing, network volumes, and ZIP in-place editing remain separate future phases as specified.
- Type consistency: `FileConflictDecision`, `FileOperationResult`, `FileUndoAction`, `ZipExtracting`, `ExplorerCommand.undo`, and `ExplorerCommand.extractZip` are used consistently across tasks.
