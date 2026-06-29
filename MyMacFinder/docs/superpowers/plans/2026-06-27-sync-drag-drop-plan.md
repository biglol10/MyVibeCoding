# Sync And Drag Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add active-folder filesystem synchronization and native file table drag/drop for copy and move operations.

**Architecture:** Add a small drop model/validator, route all drop mutations through `ExplorerStore.performDrop`, and add a one-folder watcher abstraction that `ExplorerStore` owns. `FileTableView` remains the only AppKit drag/drop surface and forwards validated drops to the store instead of touching the filesystem directly.

**Tech Stack:** Swift 6.1, macOS 15 SDK, SwiftUI, AppKit `NSTableView`, XCTest, `FileManager`, `NSPasteboard`, `FSEvents`.

---

## File Structure

- Create: `Sources/MyMacFinder/Domain/FileDropModels.swift`
  - Owns `DropOperation`, `DropSource`, and pure drop operation selection.
- Create: `Sources/MyMacFinder/Services/FileDropValidator.swift`
  - Validates empty drops, self drops, descendant moves, non-directory destinations, and reusable drop destination rules.
- Create: `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`
  - Defines `DirectoryWatching` protocol and real `FSEvents` implementation.
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Adds watcher lifecycle, debounced external refresh, and `performDrop`.
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
  - Adds file URL drag writer, drop validation, drop acceptance, and drop callback.
- Modify: `Sources/MyMacFinder/App/RootView.swift`
  - Passes `currentURL` and `onDropItems` into `FileTableView`.
- Test: `Tests/MyMacFinderTests/FileDropModelTests.swift`
- Test: `Tests/MyMacFinderTests/FileDropValidatorTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerStoreDropTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`

## Task 1: Drop Models And Operation Resolution

**Files:**
- Create: `Sources/MyMacFinder/Domain/FileDropModels.swift`
- Test: `Tests/MyMacFinderTests/FileDropModelTests.swift`

- [ ] **Step 1: Write failing drop model tests**

Create `Tests/MyMacFinderTests/FileDropModelTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileDropModelTests: XCTestCase {
    func testOptionModifierForcesCopy() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .local, optionKeyPressed: true, proposedOperation: nil),
            .copy
        )
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: true, proposedOperation: .move),
            .copy
        )
    }

    func testLocalDropDefaultsToMove() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .local, optionKeyPressed: false, proposedOperation: nil),
            .move
        )
    }

    func testExternalDropDefaultsToCopy() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: false, proposedOperation: nil),
            .copy
        )
    }

    func testExternalDropHonorsExplicitMove() {
        XCTAssertEqual(
            FileDropOperationResolver.operation(source: .external, optionKeyPressed: false, proposedOperation: .move),
            .move
        )
    }
}
```

- [ ] **Step 2: Run model tests and verify RED**

Run:

```bash
swift test --filter FileDropModelTests
```

Expected: FAIL with `cannot find 'FileDropOperationResolver' in scope`.

- [ ] **Step 3: Implement drop model**

Create `Sources/MyMacFinder/Domain/FileDropModels.swift`:

```swift
import Foundation

public enum DropOperation: String, Equatable, Sendable {
    case copy
    case move
}

public enum DropSource: String, Equatable, Sendable {
    case local
    case external
}

public enum FileDropOperationResolver {
    public static func operation(
        source: DropSource,
        optionKeyPressed: Bool,
        proposedOperation: DropOperation?
    ) -> DropOperation {
        if optionKeyPressed {
            return .copy
        }

        if let proposedOperation {
            return proposedOperation
        }

        switch source {
        case .local:
            return .move
        case .external:
            return .copy
        }
    }
}
```

- [ ] **Step 4: Run model tests and verify GREEN**

Run:

```bash
swift test --filter FileDropModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit drop model**

Run:

```bash
git add Sources/MyMacFinder/Domain/FileDropModels.swift Tests/MyMacFinderTests/FileDropModelTests.swift
git commit -m "feat: add file drop operation model"
```

Expected: commit succeeds.

## Task 2: Drop Validation

**Files:**
- Create: `Sources/MyMacFinder/Services/FileDropValidator.swift`
- Test: `Tests/MyMacFinderTests/FileDropValidatorTests.swift`

- [ ] **Step 1: Write failing drop validator tests**

Create `Tests/MyMacFinderTests/FileDropValidatorTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FileDropValidatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderDropValidator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testRejectsEmptyDrop() {
        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [], destinationFolder: tempDirectory, operation: .copy)
        )
    }

    func testRejectsMovingItemOntoItself() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: folder, operation: .move)
        )
    }

    func testRejectsMovingFolderIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [folder], destinationFolder: child, operation: .move)
        )
    }

    func testAllowsCopyingFolderIntoDescendant() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        XCTAssertNoThrow(
            try FileDropValidator.validate(urls: [folder], destinationFolder: child, operation: .copy)
        )
    }

    func testRejectsNonDirectoryDestination() throws {
        let source = tempDirectory.appendingPathComponent("source.txt")
        let destination = tempDirectory.appendingPathComponent("destination.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "destination".write(to: destination, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try FileDropValidator.validate(urls: [source], destinationFolder: destination, operation: .copy)
        )
    }
}
```

- [ ] **Step 2: Run validator tests and verify RED**

Run:

```bash
swift test --filter FileDropValidatorTests
```

Expected: FAIL with `cannot find 'FileDropValidator' in scope`.

- [ ] **Step 3: Implement validator**

Create `Sources/MyMacFinder/Services/FileDropValidator.swift`:

```swift
import Foundation

public enum FileDropValidator {
    public static func validate(
        urls: [URL],
        destinationFolder: URL,
        operation: DropOperation,
        fileManager: FileManager = .default
    ) throws {
        guard !urls.isEmpty else {
            throw ExplorerError.invalidPath("No dropped files.")
        }

        let destination = destinationFolder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExplorerError.notDirectory(destination.path)
        }

        for url in urls.map(\.standardizedFileURL) {
            if url == destination {
                throw ExplorerError.readFailed("Cannot drop an item onto itself.")
            }

            if operation == .move && isDescendant(destination, of: url) {
                throw ExplorerError.readFailed("Cannot move a folder into itself.")
            }
        }
    }

    private static func isDescendant(_ possibleChild: URL, of possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        guard childPath != parentPath else {
            return false
        }
        return childPath.hasPrefix(parentPath + "/")
    }
}
```

- [ ] **Step 4: Run validator tests and verify GREEN**

Run:

```bash
swift test --filter FileDropValidatorTests
```

Expected: PASS.

- [ ] **Step 5: Commit validator**

Run:

```bash
git add Sources/MyMacFinder/Services/FileDropValidator.swift Tests/MyMacFinderTests/FileDropValidatorTests.swift
git commit -m "feat: validate file drops"
```

Expected: commit succeeds.

## Task 3: Store Drop Execution

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerStoreDropTests.swift`

- [ ] **Step 1: Write failing store drop tests**

Create `Tests/MyMacFinderTests/ExplorerStoreDropTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerStoreDropTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderStoreDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testPerformDropCopiesFilesIntoCurrentFolder() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("note.txt")
        try "note".write(to: sourceFile, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: destFolder)
        await store.refresh()

        await store.performDrop(urls: [sourceFile], destinationFolder: destFolder, operation: .copy)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "note.txt" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    @MainActor
    func testPerformDropMovesFilesIntoFolderDestination() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let sourceFile = sourceFolder.appendingPathComponent("move.txt")
        try "move".write(to: sourceFile, atomically: true, encoding: .utf8)

        let store = ExplorerStore(initialURL: sourceFolder)
        await store.refresh()

        await store.performDrop(urls: [sourceFile], destinationFolder: destFolder, operation: .move)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("move.txt").path))
    }

    @MainActor
    func testPerformDropRejectsInvalidDescendantMove() async throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)
        await store.refresh()

        await store.performDrop(urls: [folder], destinationFolder: child, operation: .move)

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(store.visibleErrorMessage.contains("Cannot move"))
    }
}
```

- [ ] **Step 2: Run store drop tests and verify RED**

Run:

```bash
swift test --filter ExplorerStoreDropTests
```

Expected: FAIL with `value of type 'ExplorerStore' has no member 'performDrop'`.

- [ ] **Step 3: Implement `performDrop`**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift` by adding this public method near `perform(_:)`:

```swift
public func performDrop(
    urls: [URL],
    destinationFolder: URL,
    operation: DropOperation
) async {
    do {
        try FileDropValidator.validate(
            urls: urls,
            destinationFolder: destinationFolder,
            operation: operation
        )

        switch operation {
        case .copy:
            _ = try fileOperationService.copyItems(urls, to: destinationFolder)
        case .move:
            _ = try fileOperationService.moveItems(urls, to: destinationFolder)
        }

        await refresh()
    } catch let error as ExplorerError {
        visibleError = error
    } catch {
        visibleError = .readFailed(error.localizedDescription)
    }
}
```

- [ ] **Step 4: Run store drop tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerStoreDropTests
```

Expected: PASS.

- [ ] **Step 5: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit store drop execution**

Run:

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerStoreDropTests.swift
git commit -m "feat: route file drops through explorer store"
```

Expected: commit succeeds.

## Task 4: Watcher Abstraction And Store Refresh Hook

**Files:**
- Create: `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`

- [ ] **Step 1: Write failing watcher/store tests**

Create `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
private final class TestDirectoryWatcher: DirectoryWatching {
    private(set) var watchedURLs: [URL] = []
    private var onChange: (@Sendable () -> Void)?

    func startWatching(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        watchedURLs.append(url.standardizedFileURL)
        self.onChange = onChange
    }

    func stopWatching() {
        onChange = nil
    }

    func triggerChange() {
        onChange?()
    }
}

final class ExplorerStoreWatcherTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderWatcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testLoadInitialDirectoryStartsWatcher() async {
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: watcher, watcherDebounceNanoseconds: 0)

        await store.loadInitialDirectory()

        XCTAssertEqual(watcher.watchedURLs.map(\.path), [tempDirectory.standardizedFileURL.path])
    }

    @MainActor
    func testNavigateRestartsWatcherForNewFolder() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: watcher, watcherDebounceNanoseconds: 0)

        await store.loadInitialDirectory()
        await store.navigate(to: child)

        XCTAssertEqual(watcher.watchedURLs.map(\.path), [
            tempDirectory.standardizedFileURL.path,
            child.standardizedFileURL.path
        ])
    }

    @MainActor
    func testWatcherChangeRefreshesEntries() async throws {
        let watcher = TestDirectoryWatcher()
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: watcher, watcherDebounceNanoseconds: 0)
        await store.loadInitialDirectory()

        let externalFile = tempDirectory.appendingPathComponent("external.txt")
        try "external".write(to: externalFile, atomically: true, encoding: .utf8)
        watcher.triggerChange()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.activePane.entries.contains { $0.name == "external.txt" })
    }
}
```

- [ ] **Step 2: Run watcher tests and verify RED**

Run:

```bash
swift test --filter ExplorerStoreWatcherTests
```

Expected: FAIL with `cannot find type 'DirectoryWatching' in scope` or `extra arguments at positions ... in call`.

- [ ] **Step 3: Add watcher protocol and FSEvents implementation**

Create `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`:

```swift
import CoreServices
import Foundation

@MainActor
public protocol DirectoryWatching: AnyObject {
    func startWatching(_ url: URL, onChange: @escaping @Sendable () -> Void)
    func stopWatching()
}

public final class DirectoryWatcherService: DirectoryWatching {
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?

    public init() {}

    deinit {
        stopWatching()
    }

    public func startWatching(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        stopWatching()

        let callbackBox = CallbackBox(onChange: onChange)
        self.callbackBox = callbackBox
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox).toOpaque())
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, contextInfo, _, _, _, _ in
                guard let contextInfo else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(contextInfo).takeUnretainedValue()
                box.onChange()
            },
            &streamContext,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stopWatching() {
        guard let stream else {
            callbackBox = nil
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        callbackBox = nil
    }

    private final class CallbackBox {
        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }
    }
}
```

- [ ] **Step 4: Inject watcher into store and schedule refreshes**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

Add stored properties:

```swift
private let directoryWatcher: DirectoryWatching?
private let watcherDebounceNanoseconds: UInt64
private var watcherRefreshTask: Task<Void, Never>?
private var watchedDirectoryURL: URL?
```

Extend `init` with parameters:

```swift
directoryWatcher: DirectoryWatching? = DirectoryWatcherService(),
watcherDebounceNanoseconds: UInt64 = 250_000_000,
```

Assign them:

```swift
self.directoryWatcher = directoryWatcher
self.watcherDebounceNanoseconds = watcherDebounceNanoseconds
self.watcherRefreshTask = nil
self.watchedDirectoryURL = nil
```

Keep `loadInitialDirectory()` as a normal load call. `loadDirectory(_:pushHistory:)` will start or replace the watcher after every successful directory load, and the watcher helper will ignore duplicate starts for the same URL:

```swift
public func loadInitialDirectory() async {
    await loadCurrentDirectory()
}
```

Add these private methods:

```swift
private func startWatchingActiveDirectory() {
    let currentURL = activePane.currentURL.standardizedFileURL
    guard watchedDirectoryURL != currentURL else {
        return
    }

    watchedDirectoryURL = currentURL
    directoryWatcher?.startWatching(activePane.currentURL) { [weak self] in
        Task { @MainActor [weak self] in
            self?.scheduleExternalRefresh()
        }
    }
}

private func scheduleExternalRefresh() {
    watcherRefreshTask?.cancel()
    watcherRefreshTask = Task { @MainActor [weak self] in
        guard let self else { return }
        if watcherDebounceNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: watcherDebounceNanoseconds)
        }
        guard !Task.isCancelled else { return }
        await self.refresh()
    }
}
```

At the end of `loadDirectory(_:pushHistory:)`, after `pathInput = url.path`, add:

```swift
startWatchingActiveDirectory()
```

This starts the watcher after initial load, restarts it after navigation, and avoids restarting it on every refresh when the directory has not changed.

- [ ] **Step 5: Run watcher tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerStoreWatcherTests
```

Expected: PASS.

- [ ] **Step 6: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit watcher integration**

Run:

```bash
git add Sources/MyMacFinder/Services/DirectoryWatcherService.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift
git commit -m "feat: refresh active folder from filesystem events"
```

Expected: commit succeeds.

## Task 5: Table Drag And Drop Wiring

**Files:**
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`

- [ ] **Step 1: Build before UI changes**

Run:

```bash
swift test
```

Expected: PASS. This establishes the AppKit wiring starts from a green state.

- [ ] **Step 2: Add drop callback inputs**

Modify `FileTableView` stored properties:

```swift
var currentURL: URL
var onDropItems: ([URL], URL, DropOperation) -> Void
```

Update `RootView` `FileTableView(...)` call:

```swift
FileTableView(
    entries: explorerStore.activePane.entries,
    selectedURLs: explorerStore.activePane.selectedURLs,
    canPaste: explorerStore.canPaste,
    currentURL: explorerStore.activePane.currentURL,
    onSelectionChange: { urls in
        explorerStore.updateSelection(urls)
    },
    onOpen: { url in
        Task { await explorerStore.open(url) }
    },
    onCommand: { command in
        Task { await explorerStore.perform(command) }
    },
    onDropItems: { urls, destinationFolder, operation in
        Task {
            await explorerStore.performDrop(
                urls: urls,
                destinationFolder: destinationFolder,
                operation: operation
            )
        }
    }
)
```

- [ ] **Step 3: Register table for file URL dragging**

In `makeNSView(context:)`, after setting `menuProvider`:

```swift
tableView.dragDropProvider = context.coordinator
tableView.registerForDraggedTypes([.fileURL])
tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
```

Rename `ContextMenuTableView.menuProvider` to keep existing behavior and add:

```swift
weak var dragDropProvider: Coordinator?
```

- [ ] **Step 4: Add pasteboard writer**

Extend `Coordinator` with `NSTableViewDataSource` method:

```swift
func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    guard row >= 0, row < parent.entries.count else {
        return nil
    }
    return parent.entries[row].url as NSURL
}
```

- [ ] **Step 5: Add drop validation helpers**

Add to `Coordinator`:

```swift
func validateDrop(_ info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    guard
        let drop = makeDrop(info: info, row: row, dropOperation: dropOperation),
        canDrop(drop)
    else {
        return []
    }

    return drop.operation == .copy ? .copy : .move
}

func acceptDrop(_ info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    guard
        let drop = makeDrop(info: info, row: row, dropOperation: dropOperation),
        canDrop(drop)
    else {
        return false
    }

    parent.onDropItems(drop.urls, drop.destinationFolder, drop.operation)
    return true
}

private struct PendingDrop {
    var urls: [URL]
    var destinationFolder: URL
    var operation: DropOperation
}

private func makeDrop(
    info: NSDraggingInfo,
    row: Int,
    dropOperation: NSTableView.DropOperation
) -> PendingDrop? {
    let urls = fileURLs(from: info.draggingPasteboard)
    guard !urls.isEmpty else { return nil }

    let destination = destinationFolder(row: row, dropOperation: dropOperation)
    guard let destination else { return nil }

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

private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]
    let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] ?? []
    return objects.map { $0 as URL }
}
```

- [ ] **Step 6: Forward `NSTableView` drop delegate methods**

Add to `Coordinator`:

```swift
func tableView(
    _ tableView: NSTableView,
    validateDrop info: NSDraggingInfo,
    proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
) -> NSDragOperation {
    validateDrop(info, proposedRow: row, proposedDropOperation: dropOperation)
}

func tableView(
    _ tableView: NSTableView,
    acceptDrop info: NSDraggingInfo,
    row: Int,
    dropOperation: NSTableView.DropOperation
) -> Bool {
    acceptDrop(info, row: row, dropOperation: dropOperation)
}
```

- [ ] **Step 7: Run build and tests**

Run:

```bash
swift test
swift build -c release
```

Expected: both pass.

- [ ] **Step 8: Commit drag/drop UI wiring**

Run:

```bash
git add Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/RootView.swift
git commit -m "feat: add file table drag and drop"
```

Expected: commit succeeds.

## Task 6: Manual QA

**Files:**
- No source changes expected.

- [ ] **Step 1: Prepare QA folders**

Run:

```bash
QA_DIR="/tmp/MyMacFinderDnDQA-$(date +%Y%m%d%H%M%S)"
mkdir -p "$QA_DIR/source" "$QA_DIR/dest" "$QA_DIR/dest/FolderTarget"
printf 'alpha' > "$QA_DIR/source/alpha.txt"
printf 'beta' > "$QA_DIR/source/beta.txt"
printf 'external' > "$QA_DIR/dest/existing.txt"
echo "$QA_DIR"
```

Expected: prints QA directory path.

- [ ] **Step 2: Launch app as a QA bundle**

Run:

```bash
rm -rf .build/qa/MyMacFinder.app
mkdir -p .build/qa/MyMacFinder.app/Contents/MacOS
cp .build/arm64-apple-macosx/debug/MyMacFinder .build/qa/MyMacFinder.app/Contents/MacOS/MyMacFinder
/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string MyMacFinder' \
  -c 'Add :CFBundleIdentifier string com.local.mymacfinder.qa' \
  -c 'Add :CFBundleName string MyMacFinder' \
  -c 'Add :CFBundleDisplayName string MyMacFinder' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :CFBundleShortVersionString string 0.1.0' \
  -c 'Add :CFBundleVersion string 1' \
  -c 'Add :LSMinimumSystemVersion string 15.0' \
  -c 'Add :NSHighResolutionCapable bool true' \
  .build/qa/MyMacFinder.app/Contents/Info.plist
open .build/qa/MyMacFinder.app
```

Expected: app appears as `MyMacFinder` to Accessibility.

- [ ] **Step 3: Verify external create auto-sync**

In the app path field, navigate to `$QA_DIR/dest`.

Run in Terminal:

```bash
printf 'created' > "$QA_DIR/dest/created-outside.txt"
```

Expected: `created-outside.txt` appears in the table without pressing Refresh.

- [ ] **Step 4: Verify external rename auto-sync**

Run:

```bash
mv "$QA_DIR/dest/created-outside.txt" "$QA_DIR/dest/renamed-outside.txt"
```

Expected: table removes `created-outside.txt` and shows `renamed-outside.txt` without pressing Refresh.

- [ ] **Step 5: Verify external delete auto-sync**

Run:

```bash
rm "$QA_DIR/dest/renamed-outside.txt"
```

Expected: table removes `renamed-outside.txt` without pressing Refresh.

- [ ] **Step 6: Verify Finder-to-app drop copy**

Open Finder to `$QA_DIR/source`, drag `alpha.txt` into empty space in MyMacFinder while MyMacFinder is showing `$QA_DIR/dest`.

Expected:

```bash
test -f "$QA_DIR/source/alpha.txt"
test -f "$QA_DIR/dest/alpha.txt"
```

Both commands exit 0.

- [ ] **Step 7: Verify app row to folder row move**

In MyMacFinder showing `$QA_DIR/dest`, drag `alpha.txt` onto `FolderTarget`.

Expected:

```bash
test ! -e "$QA_DIR/dest/alpha.txt"
test -f "$QA_DIR/dest/FolderTarget/alpha.txt"
```

Both commands exit 0.

- [ ] **Step 8: Verify invalid self/descendant drop rejection**

Create nested folders:

```bash
mkdir -p "$QA_DIR/dest/Parent/Child"
```

Refresh or wait for sync. Drag `Parent` onto `Child`.

Expected:

```bash
test -d "$QA_DIR/dest/Parent"
test -d "$QA_DIR/dest/Parent/Child"
```

Both commands exit 0 and no duplicate `Parent` appears under `Child`.

- [ ] **Step 9: Final automated verification**

Run:

```bash
swift test
swift build -c release
git status --short
```

Expected:

- `swift test`: all tests pass.
- `swift build -c release`: exit 0.
- `git status --short`: no source changes unless QA bundle changed ignored build output only.

## Self-Review Checklist

- Spec coverage:
  - Active folder watcher: Task 4.
  - Debounced external refresh: Task 4.
  - Store drop API: Task 3.
  - Empty-space and folder-row drops: Task 5.
  - Finder file URL drops: Task 5 and Task 6.
  - Invalid self/descendant rejection: Task 2, Task 3, Task 6.
  - Manual QA: Task 6.
- Placeholder scan:
  - No unresolved implementation markers or missing code steps.
- Type consistency:
  - `DropOperation`, `DropSource`, `FileDropOperationResolver`, `FileDropValidator`, and `DirectoryWatching` are introduced before use.
  - `ExplorerStore.performDrop(urls:destinationFolder:operation:)` signature is consistent across tests, RootView, and FileTableView.
