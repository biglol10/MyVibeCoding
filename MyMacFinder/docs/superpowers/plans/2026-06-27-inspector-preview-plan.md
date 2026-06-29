# Inspector Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the inspector with native preview/icon rendering, richer metadata, actionable buttons, explicit folder size calculation, and multi-selection summaries.

**Architecture:** Keep formatting and selection summaries in a testable domain model, side effects in `ExplorerStore`, native Quick Look in a focused service, and rendering in SwiftUI/AppKit-adjacent UI files. Inspector buttons reuse `ExplorerCommand` so menus, shortcuts, and inspector actions stay on the same command path.

**Tech Stack:** Swift 6.1, macOS 15 SDK, SwiftUI, AppKit, QuickLook, QuickLookThumbnailing, XCTest, FileManager.

---

## File Structure

- Create: `Sources/MyMacFinder/Domain/InspectorModels.swift`
  - Formats single-entry details and multi-selection summaries.
- Create: `Sources/MyMacFinder/Services/FolderSizeService.swift`
  - Recursively calculates folder size only when explicitly called.
- Create: `Sources/MyMacFinder/Services/QuickLookPreviewService.swift`
  - Owns `QLPreviewPanel` data source behavior for selected URLs.
- Create: `Sources/MyMacFinder/UI/FilePreviewView.swift`
  - Loads Quick Look thumbnails and falls back to real macOS file icons.
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
  - Adds `quickLook` and `calculateFolderSize` commands and availability rules.
- Modify: `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
  - Maps `Space` to Quick Look.
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Injects folder size and Quick Look services, stores calculated folder sizes, and handles new commands.
- Modify: `Sources/MyMacFinder/UI/InspectorView.swift`
  - Renders preview, action row, detail grid, folder size state, and multi-selection summary.
- Modify: `Sources/MyMacFinder/App/RootView.swift`
  - Passes inspector command callbacks and calculated folder size state.
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
  - Adds Explorer menu item and shortcut for Quick Look.
- Test: `Tests/MyMacFinderTests/InspectorModelsTests.swift`
- Test: `Tests/MyMacFinderTests/FolderSizeServiceTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift`

## Task 1: Inspector Details And Selection Summary Models

**Files:**
- Create: `Sources/MyMacFinder/Domain/InspectorModels.swift`
- Test: `Tests/MyMacFinderTests/InspectorModelsTests.swift`

- [ ] **Step 1: Write failing inspector model tests**

Create `Tests/MyMacFinderTests/InspectorModelsTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class InspectorModelsTests: XCTestCase {
    func testSingleItemDetailsFormatMissingValuesAndBooleans() {
        let entry = makeEntry(
            name: ".config",
            kind: .file,
            typeDescription: "Plain Text",
            fileExtension: "",
            size: nil,
            dateCreated: nil,
            dateModified: Date(timeIntervalSince1970: 1_704_067_200),
            dateAccessed: nil,
            isHidden: true,
            isDirectoryLike: false,
            isReadable: false
        )

        let details = InspectorItemDetails(entry: entry)

        XCTAssertEqual(details.name, ".config")
        XCTAssertEqual(details.kind, "Plain Text")
        XCTAssertEqual(details.fileExtension, "--")
        XCTAssertEqual(details.sizeText, "--")
        XCTAssertEqual(details.dateCreatedText, "--")
        XCTAssertEqual(details.dateModifiedText, "2024-01-01 00:00")
        XCTAssertEqual(details.dateAccessedText, "--")
        XCTAssertEqual(details.path, entry.url.path)
        XCTAssertEqual(details.isHiddenText, "Yes")
        XCTAssertEqual(details.isReadableText, "No")
        XCTAssertFalse(details.isDirectoryLike)
    }

    func testSingleItemDetailsUseCalculatedFolderSizeWhenProvided() {
        let folder = makeEntry(
            name: "Project",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            dateCreated: nil,
            dateModified: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: true,
            isReadable: true
        )

        let details = InspectorItemDetails(entry: folder, calculatedFolderSize: 12_345)

        XCTAssertEqual(details.sizeText, "12 KB")
        XCTAssertTrue(details.isDirectoryLike)
    }

    func testSelectionSummaryCountsFilesFoldersAndKnownFileSizes() {
        let parent = URL(fileURLWithPath: "/tmp/MyMacFinderSummary", isDirectory: true)
        let file = makeEntry(
            url: parent.appendingPathComponent("note.txt"),
            name: "note.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 10,
            isDirectoryLike: false
        )
        let folder = makeEntry(
            url: parent.appendingPathComponent("Sources", isDirectory: true),
            name: "Sources",
            kind: .folder,
            typeDescription: "Folder",
            fileExtension: "",
            size: nil,
            isDirectoryLike: true
        )

        let summary = InspectorSelectionSummary(entries: [file, folder])

        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.folderCount, 1)
        XCTAssertEqual(summary.knownTotalSizeText, "10 bytes")
        XCTAssertEqual(summary.commonParentPath, parent.path)
        XCTAssertEqual(summary.previewNames, ["note.txt", "Sources"])
    }

    func testSelectionSummaryOmitsCommonParentWhenParentsDiffer() {
        let first = makeEntry(
            url: URL(fileURLWithPath: "/tmp/one/a.txt"),
            name: "a.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 1,
            isDirectoryLike: false
        )
        let second = makeEntry(
            url: URL(fileURLWithPath: "/tmp/two/b.txt"),
            name: "b.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 2,
            isDirectoryLike: false
        )

        let summary = InspectorSelectionSummary(entries: [first, second])

        XCTAssertNil(summary.commonParentPath)
        XCTAssertEqual(summary.knownTotalSizeText, "3 bytes")
    }

    private func makeEntry(
        url: URL = URL(fileURLWithPath: "/tmp/item"),
        name: String,
        kind: FileEntryKind,
        typeDescription: String,
        fileExtension: String,
        size: Int64? = nil,
        dateCreated: Date? = nil,
        dateModified: Date? = nil,
        dateAccessed: Date? = nil,
        isHidden: Bool = false,
        isDirectoryLike: Bool,
        isReadable: Bool = true
    ) -> FileEntry {
        FileEntry(
            url: url,
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: fileExtension,
            size: size,
            dateModified: dateModified,
            dateCreated: dateCreated,
            dateAccessed: dateAccessed,
            isHidden: isHidden,
            isDirectoryLike: isDirectoryLike,
            isReadable: isReadable
        )
    }
}
```

- [ ] **Step 2: Run model tests and verify RED**

Run:

```bash
swift test --filter InspectorModelsTests
```

Expected: FAIL with errors containing `cannot find 'InspectorItemDetails' in scope` and `cannot find 'InspectorSelectionSummary' in scope`.

- [ ] **Step 3: Implement inspector models**

Create `Sources/MyMacFinder/Domain/InspectorModels.swift`:

```swift
import Foundation

public struct InspectorItemDetails: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var fileExtension: String
    public var sizeText: String
    public var dateCreatedText: String
    public var dateModifiedText: String
    public var dateAccessedText: String
    public var path: String
    public var isHiddenText: String
    public var isReadableText: String
    public var isDirectoryLike: Bool

    public init(entry: FileEntry, calculatedFolderSize: Int64? = nil) {
        self.name = entry.name
        self.kind = entry.typeDescription
        self.fileExtension = entry.fileExtension.isEmpty ? "--" : entry.fileExtension
        self.sizeText = Self.sizeText(calculatedFolderSize ?? entry.size)
        self.dateCreatedText = Self.dateText(entry.dateCreated)
        self.dateModifiedText = Self.dateText(entry.dateModified)
        self.dateAccessedText = Self.dateText(entry.dateAccessed)
        self.path = entry.url.path
        self.isHiddenText = entry.isHidden ? "Yes" : "No"
        self.isReadableText = entry.isReadable ? "Yes" : "No"
        self.isDirectoryLike = entry.isDirectoryLike
    }

    public static func sizeText(_ size: Int64?) -> String {
        guard let size else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public static func dateText(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

public struct InspectorSelectionSummary: Equatable, Sendable {
    public var itemCount: Int
    public var fileCount: Int
    public var folderCount: Int
    public var knownTotalSizeText: String
    public var commonParentPath: String?
    public var previewNames: [String]

    public init(entries: [FileEntry]) {
        self.itemCount = entries.count
        self.fileCount = entries.filter { !$0.isDirectoryLike }.count
        self.folderCount = entries.filter(\.isDirectoryLike).count

        let knownSize = entries
            .filter { !$0.isDirectoryLike }
            .compactMap(\.size)
            .reduce(Int64(0), +)
        self.knownTotalSizeText = InspectorItemDetails.sizeText(knownSize)

        let parents = Set(entries.map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
        self.commonParentPath = parents.count == 1 ? parents.first : nil

        self.previewNames = Array(entries.map(\.name).prefix(8))
    }
}
```

- [ ] **Step 4: Run model tests and verify GREEN**

Run:

```bash
swift test --filter InspectorModelsTests
```

Expected: PASS with `InspectorModelsTests` reporting 4 tests and 0 failures.

- [ ] **Step 5: Commit inspector models**

Run:

```bash
git add Sources/MyMacFinder/Domain/InspectorModels.swift Tests/MyMacFinderTests/InspectorModelsTests.swift
git commit -m "feat: add inspector metadata models"
```

Expected: commit succeeds.

## Task 2: Folder Size Service

**Files:**
- Create: `Sources/MyMacFinder/Services/FolderSizeService.swift`
- Test: `Tests/MyMacFinderTests/FolderSizeServiceTests.swift`

- [ ] **Step 1: Write failing folder size tests**

Create `Tests/MyMacFinderTests/FolderSizeServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FolderSizeServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderFolderSize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCalculatesNestedFolderSize() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 7).write(to: folder.appendingPathComponent("root.bin"))
        try Data(repeating: 2, count: 11).write(to: child.appendingPathComponent("nested.bin"))

        let service = FolderSizeService()

        XCTAssertEqual(try service.size(of: folder), 18)
    }

    func testRejectsFileInput() throws {
        let file = tempDirectory.appendingPathComponent("file.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)

        let service = FolderSizeService()

        XCTAssertThrowsError(try service.size(of: file)) { error in
            XCTAssertEqual(error as? ExplorerError, .notDirectory(file.path))
        }
    }
}
```

- [ ] **Step 2: Run folder size tests and verify RED**

Run:

```bash
swift test --filter FolderSizeServiceTests
```

Expected: FAIL with `cannot find 'FolderSizeService' in scope`.

- [ ] **Step 3: Implement folder size service**

Create `Sources/MyMacFinder/Services/FolderSizeService.swift`:

```swift
import Foundation

public protocol FolderSizeCalculating: Sendable {
    func size(of folder: URL) throws -> Int64
}

public struct FolderSizeService: FolderSizeCalculating, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func size(of folder: URL) throws -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExplorerError.notDirectory(folder.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, _ in
                return false
            }
        ) else {
            throw ExplorerError.permissionDenied(folder.path)
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
```

- [ ] **Step 4: Run folder size tests and verify GREEN**

Run:

```bash
swift test --filter FolderSizeServiceTests
```

Expected: PASS with `FolderSizeServiceTests` reporting 2 tests and 0 failures.

- [ ] **Step 5: Commit folder size service**

Run:

```bash
git add Sources/MyMacFinder/Services/FolderSizeService.swift Tests/MyMacFinderTests/FolderSizeServiceTests.swift
git commit -m "feat: add folder size service"
```

Expected: commit succeeds.

## Task 3: Inspector Commands, Quick Look Service, And Store State

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify: `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- Create: `Sources/MyMacFinder/Services/QuickLookPreviewService.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Test: `Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift`

- [ ] **Step 1: Write failing command and store tests**

Create `Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerInspectorCommandTests: XCTestCase {
    func testQuickLookCommandRequiresSelection() {
        XCTAssertFalse(ExplorerCommand.quickLook.isEnabled(selectionCount: 0, canPaste: false, selectedEntries: []))
        XCTAssertTrue(ExplorerCommand.quickLook.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folderEntry()]))
    }

    func testCalculateFolderSizeRequiresSingleFolder() {
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 0, canPaste: false, selectedEntries: []))
        XCTAssertTrue(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folderEntry()]))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [fileEntry()]))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 2, canPaste: false, selectedEntries: [folderEntry(), fileEntry()]))
    }

    func testSpaceMapsToQuickLook() {
        XCTAssertEqual(
            ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "space", modifiers: [])),
            .quickLook
        )
    }

    func testQuickLookCommandPassesSelectedURLsToService() async throws {
        let quickLook = SpyQuickLookService()
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp"),
            fileSystemService: StubFileSystemService(entries: [fileEntry()]),
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            quickLookService: quickLook
        )
        await store.loadInitialDirectory()
        store.updateSelection([fileEntry().url])

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.previewedURLs, [fileEntry().url])
    }

    func testCalculateFolderSizeStoresResultForSelectedFolder() async throws {
        let folder = folderEntry()
        let folderSize = StubFolderSizeService(size: 42)
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: "/tmp"),
            fileSystemService: StubFileSystemService(entries: [folder]),
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            folderSizeService: folderSize
        )
        await store.loadInitialDirectory()
        store.updateSelection([folder.url])

        await store.perform(.calculateFolderSize)

        XCTAssertEqual(store.calculatedFolderSize(for: folder.url), 42)
        XCTAssertEqual(folderSize.requestedURL, folder.url)
    }

    private func folderEntry() -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/Folder", isDirectory: true),
            name: "Folder",
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
    }

    private func fileEntry() -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            kind: .file,
            typeDescription: "Text",
            fileExtension: "txt",
            size: 5,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )
    }
}

private final class StubFolderSizeService: FolderSizeCalculating, @unchecked Sendable {
    var size: Int64
    var requestedURL: URL?

    init(size: Int64) {
        self.size = size
    }

    func size(of folder: URL) throws -> Int64 {
        requestedURL = folder
        return size
    }
}

@MainActor
private final class SpyQuickLookService: QuickLooking {
    var previewedURLs: [URL] = []

    func preview(_ urls: [URL]) throws {
        previewedURLs = urls
    }
}

private struct StubFileSystemService: FileSystemServicing {
    var entries: [FileEntry]

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        entries
    }
}

private final class InMemoryExplorerSettingsStore: ExplorerSettingsStoring {
    private var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
```

- [ ] **Step 2: Run command tests and verify RED**

Run:

```bash
swift test --filter ExplorerInspectorCommandTests
```

Expected: FAIL with missing `quickLook`, `calculateFolderSize`, `FolderSizeCalculating`, `QuickLooking`, and `FileSystemServicing`.

- [ ] **Step 3: Introduce service protocols needed by store tests**

Modify `Sources/MyMacFinder/Services/FileSystemService.swift` so `ExplorerStore` can receive a stub:

```swift
public protocol FileSystemServicing: Sendable {
    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry]
}
```

Place the protocol above `FileSystemService`, then change the existing declaration line from:

```swift
public struct FileSystemService: @unchecked Sendable {
```

to:

```swift
public struct FileSystemService: FileSystemServicing, @unchecked Sendable {
```

Do not change the existing behavior of `FileSystemService.contentsOfDirectory`.

- [ ] **Step 4: Add command cases and availability rules**

Modify `Sources/MyMacFinder/Domain/ExplorerCommand.swift`:

```swift
public enum ExplorerCommand: String, CaseIterable, Identifiable {
    case open
    case quickLook
    case revealInFinder
    case copyPath
    case newFolder
    case rename
    case duplicate
    case copy
    case cut
    case paste
    case moveToTrash
    case calculateFolderSize
    case refresh
```

Add titles:

```swift
case .quickLook: return "Quick Look"
case .calculateFolderSize: return "Calculate Size"
```

Replace `isEnabled(selectionCount:canPaste:)` with overloads that keep existing call sites valid:

```swift
public func isEnabled(selectionCount: Int, canPaste: Bool) -> Bool {
    isEnabled(selectionCount: selectionCount, canPaste: canPaste, selectedEntries: [])
}

public func isEnabled(selectionCount: Int, canPaste: Bool, selectedEntries: [FileEntry]) -> Bool {
    switch self {
    case .newFolder, .refresh:
        return true
    case .paste:
        return canPaste
    case .rename:
        return selectionCount == 1
    case .calculateFolderSize:
        return selectionCount == 1 && selectedEntries.first?.isDirectoryLike == true
    case .open, .quickLook, .revealInFinder, .copyPath, .duplicate, .copy, .cut, .moveToTrash:
        return selectionCount > 0
    }
}
```

- [ ] **Step 5: Add keyboard shortcut mapping**

Modify `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift` in the empty modifier branch:

```swift
case []:
    switch shortcut.key {
    case "return":
        return .rename
    case "space":
        return .quickLook
    default:
        return nil
    }
```

- [ ] **Step 6: Implement Quick Look service**

Create `Sources/MyMacFinder/Services/QuickLookPreviewService.swift`:

```swift
import Foundation
import QuickLook

@MainActor
public protocol QuickLooking: AnyObject {
    func preview(_ urls: [URL]) throws
}

@MainActor
public final class QuickLookPreviewService: NSObject, QuickLooking, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var urls: [URL] = []

    public override init() {
        super.init()
    }

    public func preview(_ urls: [URL]) throws {
        guard !urls.isEmpty else {
            return
        }

        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else {
            throw ExplorerError.readFailed("Quick Look is unavailable.")
        }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
```

- [ ] **Step 7: Wire new services and state into ExplorerStore**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

Add published state:

```swift
@Published public private(set) var calculatedFolderSizes: [URL: Int64]
```

Add dependencies:

```swift
private let folderSizeService: FolderSizeCalculating
private let quickLookService: QuickLooking?
```

Change the initializer signature:

```swift
fileSystemService: FileSystemServicing = FileSystemService(),
folderSizeService: FolderSizeCalculating = FolderSizeService(),
quickLookService: QuickLooking? = QuickLookPreviewService(),
```

Initialize:

```swift
self.calculatedFolderSizes = [:]
self.folderSizeService = folderSizeService
self.quickLookService = quickLookService
```

Add lookup helper:

```swift
public func calculatedFolderSize(for url: URL) -> Int64? {
    calculatedFolderSizes[url.standardizedFileURL]
}
```

Add `perform(_:)` cases:

```swift
case .quickLook:
    try quickLookService?.preview(selectedURLs)
case .calculateFolderSize:
    try calculateSelectedFolderSize()
```

Add helper:

```swift
private func calculateSelectedFolderSize() throws {
    guard
        activePane.selectedURLs.count == 1,
        let url = selectedURLs.first,
        activePane.entries.first(where: { $0.url == url })?.isDirectoryLike == true
    else {
        return
    }

    let size = try folderSizeService.size(of: url)
    calculatedFolderSizes[url.standardizedFileURL] = size
}
```

- [ ] **Step 8: Add menu command for Quick Look**

Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift` inside `CommandMenu("Explorer")` after `Button("Open")`:

```swift
Button("Quick Look") {
    perform(.quickLook)
}
.keyboardShortcut(.space, modifiers: [])
.disabled(!isEnabled(.quickLook))
```

Modify `isEnabled(_:)`:

```swift
private func isEnabled(_ command: ExplorerCommand) -> Bool {
    command.isEnabled(
        selectionCount: explorerStore.activePane.selectedURLs.count,
        canPaste: explorerStore.canPaste,
        selectedEntries: explorerStore.activePane.selectedEntries
    )
}
```

- [ ] **Step 9: Run command tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerInspectorCommandTests
```

Expected: PASS with `ExplorerInspectorCommandTests` reporting 5 tests and 0 failures.

- [ ] **Step 10: Run existing command tests**

Run:

```bash
swift test --filter ExplorerCommandTests
swift test --filter ExplorerKeyboardShortcutTests
```

Expected: PASS. If existing tests need updated command lists, update only expected behavior for the new Quick Look command.

- [ ] **Step 11: Commit command and store integration**

Run:

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift Sources/MyMacFinder/Services/FileSystemService.swift Sources/MyMacFinder/Services/QuickLookPreviewService.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Tests/MyMacFinderTests/ExplorerInspectorCommandTests.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift
git commit -m "feat: route inspector commands through explorer store"
```

Expected: commit succeeds.

## Task 4: Inspector UI And Preview Rendering

**Files:**
- Create: `Sources/MyMacFinder/UI/FilePreviewView.swift`
- Modify: `Sources/MyMacFinder/UI/InspectorView.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`

- [ ] **Step 1: Build after previous command work**

Run:

```bash
swift build
```

Expected: PASS before starting UI changes.

- [ ] **Step 2: Add thumbnail/icon preview view**

Create `Sources/MyMacFinder/UI/FilePreviewView.swift`:

```swift
import AppKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreviewView: View {
    let entry: FileEntry
    @State private var previewImage: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .opacity(entry.isHidden ? 0.55 : 1)
            }
        }
        .frame(height: 150)
        .task(id: entry.url) {
            previewImage = await loadPreviewImage(for: entry.url)
        }
    }

    private func loadPreviewImage(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 240),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .icon]
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
    }
}
```

- [ ] **Step 3: Replace InspectorView with richer layout**

Replace `Sources/MyMacFinder/UI/InspectorView.swift` with:

```swift
import SwiftUI

struct InspectorView: View {
    let selection: [FileEntry]
    let calculatedFolderSizes: [URL: Int64]
    let onCommand: (ExplorerCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if selection.isEmpty {
                    noSelectionView
                } else if selection.count == 1, let entry = selection.first {
                    singleSelectionView(entry)
                } else {
                    multiSelectionView
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(.bar)
    }

    private var noSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Selection")
                .font(.headline)
            Text("Select a file or folder to view details.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func singleSelectionView(_ entry: FileEntry) -> some View {
        let details = InspectorItemDetails(
            entry: entry,
            calculatedFolderSize: calculatedFolderSizes[entry.url.standardizedFileURL]
        )

        return VStack(alignment: .leading, spacing: 14) {
            FilePreviewView(entry: entry)

            Text(details.name)
                .font(.headline)
                .lineLimit(3)
                .textSelection(.enabled)

            actionRow(for: entry)

            detailsGrid(details)
        }
    }

    private func actionRow(for entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                inspectorButton("Open", systemImage: "arrow.up.forward.square", command: .open)
                inspectorButton("Quick Look", systemImage: "eye", command: .quickLook)
            }
            HStack(spacing: 8) {
                inspectorButton("Reveal", systemImage: "finder", command: .revealInFinder)
                inspectorButton("Copy Path", systemImage: "doc.on.doc", command: .copyPath)
            }
            if entry.isDirectoryLike {
                inspectorButton("Calculate Size", systemImage: "sum", command: .calculateFolderSize)
            }
        }
    }

    private func inspectorButton(_ title: String, systemImage: String, command: ExplorerCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func detailsGrid(_ details: InspectorItemDetails) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            detailRow("Kind", details.kind)
            detailRow("Extension", details.fileExtension)
            detailRow("Size", details.sizeText)
            detailRow("Created", details.dateCreatedText)
            detailRow("Modified", details.dateModifiedText)
            detailRow("Accessed", details.dateAccessedText)
            detailRow("Hidden", details.isHiddenText)
            detailRow("Readable", details.isReadableText)
            detailRow("Path", details.path, lineLimit: 4)
        }
        .font(.caption)
    }

    private func detailRow(_ label: String, _ value: String, lineLimit: Int = 2) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
        }
    }

    private var multiSelectionView: some View {
        let summary = InspectorSelectionSummary(entries: selection)

        return VStack(alignment: .leading, spacing: 12) {
            Text("\(summary.itemCount) Items Selected")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                detailRow("Files", "\(summary.fileCount)")
                detailRow("Folders", "\(summary.folderCount)")
                detailRow("Known Size", summary.knownTotalSizeText)
                if let commonParentPath = summary.commonParentPath {
                    detailRow("Parent", commonParentPath, lineLimit: 3)
                }
            }
            .font(.caption)

            Divider()

            ForEach(summary.previewNames, id: \.self) { name in
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}
```

- [ ] **Step 4: Pass inspector callbacks from RootView**

Modify `Sources/MyMacFinder/App/RootView.swift` where `InspectorView` is created:

```swift
InspectorView(
    selection: explorerStore.activePane.selectedEntries,
    calculatedFolderSizes: explorerStore.calculatedFolderSizes,
    onCommand: { command in
        Task { await explorerStore.perform(command) }
    }
)
.frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
```

- [ ] **Step 5: Run build for UI changes**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit inspector UI**

Run:

```bash
git add Sources/MyMacFinder/UI/FilePreviewView.swift Sources/MyMacFinder/UI/InspectorView.swift Sources/MyMacFinder/App/RootView.swift
git commit -m "feat: enrich inspector preview panel"
```

Expected: commit succeeds.

## Task 5: Full Verification And Manual QA

**Files:**
- No source files should be edited in this task unless verification exposes a bug.

- [ ] **Step 1: Run full automated tests**

Run:

```bash
swift test
```

Expected: PASS with all test suites reporting 0 failures.

- [ ] **Step 2: Run release build**

Run:

```bash
swift build -c release
```

Expected: PASS with `Build complete!`.

- [ ] **Step 3: Create or refresh the QA app bundle**

Run:

```bash
rm -rf .build/qa/MyMacFinder.app
mkdir -p .build/qa/MyMacFinder.app/Contents/MacOS
mkdir -p .build/qa/MyMacFinder.app/Contents/Resources
cp .build/release/MyMacFinder .build/qa/MyMacFinder.app/Contents/MacOS/MyMacFinder
/usr/libexec/PlistBuddy -c "Clear dict" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleName string MyMacFinder" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string MyMacFinder" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.local.mymacfinder.qa" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1" .build/qa/MyMacFinder.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" .build/qa/MyMacFinder.app/Contents/Info.plist
```

Expected: `.build/qa/MyMacFinder.app` exists.

- [ ] **Step 4: Launch the QA app**

Run:

```bash
pkill -f '/MyMacFinder.app/Contents/MacOS/MyMacFinder' || true
open -n .build/qa/MyMacFinder.app
```

Expected: MyMacFinder opens as a macOS app bundle.

- [ ] **Step 5: Manual QA no selection**

Use the launched app:

- Confirm the inspector shows `No Selection`.
- Confirm there is no blank preview error or layout overlap.

- [ ] **Step 6: Manual QA single file**

Use the launched app:

- Select a regular file.
- Confirm a thumbnail or native file icon appears.
- Confirm details show name, kind, extension, size, dates, path, hidden, and readable.
- Click `Copy Path`, then run `pbpaste` in Terminal and confirm the selected file path is copied.
- Click `Reveal` and confirm Finder opens/selects the file.

- [ ] **Step 7: Manual QA Quick Look**

Use the launched app:

- Select a regular file.
- Press `Space` and confirm the system Quick Look panel opens.
- Close Quick Look.
- Click the inspector `Quick Look` button and confirm the same behavior.

- [ ] **Step 8: Manual QA folder size**

Use the launched app:

- Select a folder.
- Confirm the size is `--` before explicit calculation.
- Click `Calculate Size`.
- Confirm the size field updates to a real byte count.

- [ ] **Step 9: Manual QA multiple selection**

Use the launched app:

- Select at least one file and one folder.
- Confirm item count, file count, folder count, known size, parent path, and preview names are shown.
- Confirm action buttons from single-selection mode are not shown.

- [ ] **Step 10: Manual QA layout modes**

Use the launched app:

- Open Settings with `Cmd+,`.
- Switch to Dual Pane.
- Select files in each pane and confirm the inspector follows the active pane.
- Switch back to Single Pane and confirm inspector layout remains stable.

- [ ] **Step 11: Final repository checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors. `git status --short` is empty after the final commit.

- [ ] **Step 12: Report verification evidence**

Final response must include:

- Final commit hash.
- `swift test` result.
- `swift build -c release` result.
- Manual QA items completed.
- Any known limitations, especially preview fallback behavior.
