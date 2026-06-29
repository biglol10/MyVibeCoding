# Finder Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read, show, search, and edit Finder tags for normal filesystem entries without exposing tag editing for ZIP-backed virtual entries.

**Architecture:** Add a small `FinderTag` domain model and a `FinderTagServicing` boundary around macOS URL resource metadata. `FileSystemService` reads tags into `FileEntry`, search criteria can match tag names, and `ExplorerStore` owns the edit command so menus, context menus, and inspector actions all route through one command path.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation URL resource values, XCTest, Swift Package Manager.

---

### Task 1: Finder Tag Domain And Service

**Files:**
- Create: `Sources/MyMacFinder/Domain/FinderTag.swift`
- Create: `Sources/MyMacFinder/Services/FinderTagService.swift`
- Test: `Tests/MyMacFinderTests/FinderTagTests.swift`
- Test: `Tests/MyMacFinderTests/FinderTagServiceTests.swift`

- [ ] **Step 1: Write the failing normalization tests**

```swift
func testNormalizesTagsByTrimmingSortingAndDeduplicatingCaseInsensitively() {
    let tags = FinderTag.normalized(["  Work ", "red", "WORK", "", "Client"])

    XCTAssertEqual(tags.map(\.name), ["Client", "red", "Work"])
}
```

Expected failure: `Cannot find 'FinderTag' in scope`.

- [ ] **Step 2: Implement `FinderTag` minimally**

```swift
public struct FinderTag: Codable, Hashable, Comparable, Identifiable, Sendable {
    public var name: String
    public var id: String { name.lowercased() }

    public init(_ name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalized(_ names: [String]) -> [FinderTag] {
        var seen = Set<String>()
        return names.compactMap { rawName in
            let tag = FinderTag(rawName)
            guard !tag.name.isEmpty else { return nil }
            guard seen.insert(tag.id).inserted else { return nil }
            return tag
        }
        .sorted()
    }

    public static func < (lhs: FinderTag, rhs: FinderTag) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
```

- [ ] **Step 3: Write Finder tag service read/write tests**

```swift
func testReadsAndWritesFinderTagsOnAFile() throws {
    let fileURL = tempDirectory.appendingPathComponent("tagged.txt")
    try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)

    let service = FinderTagService()
    try service.setTags([FinderTag("Work"), FinderTag("Red")], for: fileURL)

    XCTAssertEqual(try service.tags(for: fileURL).map(\.name), ["Red", "Work"])
}
```

Expected failure: `Cannot find 'FinderTagService' in scope`.

- [ ] **Step 4: Implement `FinderTagService`**

```swift
public protocol FinderTagServicing: Sendable {
    func tags(for url: URL) throws -> [FinderTag]
    func setTags(_ tags: [FinderTag], for url: URL) throws
}

public struct FinderTagService: FinderTagServicing, Sendable {
    public init() {}

    public func tags(for url: URL) throws -> [FinderTag] {
        let values = try url.resourceValues(forKeys: [URLResourceKey.tagNamesKey])
        return FinderTag.normalized(values.tagNames ?? [])
    }

    public func setTags(_ tags: [FinderTag], for url: URL) throws {
        try (url as NSURL).setResourceValue(
            FinderTag.normalized(tags.map(\.name)).map(\.name),
            forKey: URLResourceKey.tagNamesKey
        )
    }
}
```

- [ ] **Step 5: Run targeted tests and commit**

Run:

```bash
swift test --filter FinderTag
git add Sources/MyMacFinder/Domain/FinderTag.swift Sources/MyMacFinder/Services/FinderTagService.swift Tests/MyMacFinderTests/FinderTagTests.swift Tests/MyMacFinderTests/FinderTagServiceTests.swift
git commit -m "feat: add finder tag service"
```

### Task 2: File Entries Read Finder Tags

**Files:**
- Modify: `Sources/MyMacFinder/Domain/FileEntry.swift`
- Modify: `Sources/MyMacFinder/Services/FileSystemService.swift`
- Test: `Tests/MyMacFinderTests/FileSystemServiceTests.swift`

- [ ] **Step 1: Write failing tests for entry tags and tag read failure fallback**

```swift
func testReadsFinderTagsIntoFileEntries() async throws {
    try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
    let service = FileSystemService(finderTagService: StubFinderTagService(tagsByLastPathComponent: ["note.txt": [FinderTag("Work")]]))

    let entry = try XCTUnwrap(try await service.contentsOfDirectory(at: tempDirectory).first { $0.name == "note.txt" })

    XCTAssertEqual(entry.finderTags.map(\.name), ["Work"])
}

func testTreatsFinderTagReadFailureAsEmptyTags() async throws {
    try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
    let service = FileSystemService(finderTagService: ThrowingFinderTagService())

    let entry = try XCTUnwrap(try await service.contentsOfDirectory(at: tempDirectory).first { $0.name == "note.txt" })

    XCTAssertEqual(entry.finderTags, [])
}
```

Expected failure: `FileEntry` has no `finderTags` member or `FileSystemService` has no `finderTagService` initializer.

- [ ] **Step 2: Add `finderTags` to `FileEntry`**

Add a `public let finderTags: [FinderTag]` property and a defaulted initializer parameter:

```swift
finderTags: [FinderTag] = [],
source: FileEntrySource = .fileSystem
```

Set `self.finderTags = FinderTag.normalized(finderTags.map(\.name))`.

- [ ] **Step 3: Inject and call the tag service in `FileSystemService`**

Add `private let finderTagService: any FinderTagServicing` and initialize it with `FinderTagService()`. In `makeEntry`, read:

```swift
let finderTags = (try? finderTagService.tags(for: displayURL)) ?? []
```

Pass `finderTags: finderTags` into `FileEntry`.

- [ ] **Step 4: Run targeted tests and commit**

Run:

```bash
swift test --filter FileSystemServiceTests
git add Sources/MyMacFinder/Domain/FileEntry.swift Sources/MyMacFinder/Services/FileSystemService.swift Tests/MyMacFinderTests/FileSystemServiceTests.swift
git commit -m "feat: read finder tags into file entries"
```

### Task 3: Tag Search Criteria

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerModels.swift`
- Modify: `Sources/MyMacFinder/Domain/FileEntrySearchFilter.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/UI/ToolbarPathView.swift`
- Test: `Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerAdvancedSearchStoreTests.swift`

- [ ] **Step 1: Write failing filter tests**

```swift
func testQueryMatchesFinderTags() {
    let entries = [
        entry("Report.pdf", finderTags: [FinderTag("Work")]),
        entry("Notes.txt", finderTags: [FinderTag("Personal")])
    ]

    XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "work").map(\.name), ["Report.pdf"])
}

func testCriteriaFiltersByTag() {
    let entries = [
        entry("Report.pdf", finderTags: [FinderTag("Work")]),
        entry("Notes.txt", finderTags: [FinderTag("Personal")])
    ]

    XCTAssertEqual(
        FileEntrySearchFilter.filtered(entries, criteria: FileEntrySearchCriteria(tagQuery: "work")).map(\.name),
        ["Report.pdf"]
    )
}
```

Expected failure: criteria and helper signatures do not support tags yet.

- [ ] **Step 2: Extend search options and criteria**

Add `finderTagQuery: String` to `ExplorerSearchOptions` and `FileEntrySearchCriteria`, normalized by trimming whitespace. Add `setSearchFinderTagQuery(_:)` in `ExplorerStore`.

- [ ] **Step 3: Update search matching**

Include `entry.finderTags.map(\.name)` in searchable fields. Add a tag-specific guard:

```swift
guard matchesTagQuery(entry, tagQuery: criteria.finderTagQuery) else {
    return false
}
```

- [ ] **Step 4: Wire the search options popover**

Add a `TextField("Tag", text: finderTagQuery)` below the extension field and pass a binding from `ToolbarPathView`.

- [ ] **Step 5: Run targeted tests and commit**

Run:

```bash
swift test --filter FileEntrySearchFilterTests
swift test --filter ExplorerAdvancedSearchStoreTests
git add Sources/MyMacFinder/Domain/ExplorerModels.swift Sources/MyMacFinder/Domain/FileEntrySearchFilter.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/UI/ToolbarPathView.swift Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift Tests/MyMacFinderTests/ExplorerAdvancedSearchStoreTests.swift
git commit -m "feat: search by finder tags"
```

### Task 4: Edit Tags Command

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerFinderTagCommandTests.swift`

- [ ] **Step 1: Write command enablement tests**

```swift
func testEditTagsRequiresSingleFilesystemEntry() {
    XCTAssertTrue(ExplorerCommand.editTags.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [fileEntry], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.editTags.isEnabled(selectionCount: 0, canPaste: false, selectedEntries: [], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.editTags.isEnabled(selectionCount: 2, canPaste: false, selectedEntries: [fileEntry, fileEntry], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.editTags.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [archiveEntry], isArchiveLocation: true))
}
```

Expected failure: `ExplorerCommand.editTags` does not exist.

- [ ] **Step 2: Add `editTags` to `ExplorerCommand`**

Add case, title `Edit Tags`, enablement `selectionCount == 1 && selectedEntries.first?.isArchiveBacked == false` outside archives, and disabled inside archives.

- [ ] **Step 3: Write store test for editing tags through injected prompt**

```swift
func testEditTagsCommandWritesPromptedTagsAndRefreshesSelection() async throws {
    let fileURL = tempDirectory.appendingPathComponent("tagged.txt")
    try "tagged".write(to: fileURL, atomically: true, encoding: .utf8)
    let tagService = CapturingFinderTagService()
    let store = ExplorerStore(
        initialURL: tempDirectory,
        fileSystemService: FileSystemService(finderTagService: tagService),
        finderTagService: tagService,
        directoryWatcher: nil,
        finderTagPrompt: { _ in [FinderTag("Work"), FinderTag("Red")] }
    )
    await store.loadInitialDirectory()
    store.updateSelection([fileURL.standardizedFileURL])

    await store.perform(.editTags)

    XCTAssertEqual(tagService.writtenTagsByURL[fileURL.standardizedFileURL]?.map(\.name), ["Red", "Work"])
    XCTAssertEqual(store.activePane.selectedURLs, [fileURL.standardizedFileURL])
}
```

Expected failure: `ExplorerStore` has no `finderTagService` or `finderTagPrompt`.

- [ ] **Step 4: Implement store editing**

Add `finderTagService` and `finderTagPrompt` to the initializer. In `perform(.editTags)`, get the single selected filesystem entry, prompt for tags, call `setTags`, refresh, and restore selection.

- [ ] **Step 5: Run targeted tests and commit**

Run:

```bash
swift test --filter ExplorerCommandTests
swift test --filter ExplorerArchiveCommandTests
swift test --filter ExplorerFinderTagCommandTests
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift Tests/MyMacFinderTests/ExplorerFinderTagCommandTests.swift
git commit -m "feat: edit finder tags"
```

### Task 5: Table, Inspector, And Menu Wiring

**Files:**
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/UI/InspectorView.swift`
- Modify: `Sources/MyMacFinder/Domain/InspectorModels.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Test: `Tests/MyMacFinderTests/InspectorModelsTests.swift`
- Test: `Tests/MyMacFinderTests/InspectorViewWiringTests.swift`
- Test: `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`

- [ ] **Step 1: Write inspector model tag tests**

```swift
func testSingleItemDetailsFormatsFinderTags() {
    let entry = makeEntry(name: "tagged.txt", kind: .file, typeDescription: "Text", fileExtension: "txt", finderTags: [FinderTag("Work"), FinderTag("Red")], isDirectoryLike: false)

    let details = InspectorItemDetails(entry: entry)

    XCTAssertEqual(details.finderTagsText, "Red, Work")
}
```

Expected failure: `InspectorItemDetails` has no `finderTagsText`.

- [ ] **Step 2: Add tag formatting**

Add `finderTagsText` to `InspectorItemDetails` and set it to `"--"` when empty or a comma-separated sorted list when present.

- [ ] **Step 3: Wire UI**

Add a `Tags` table column with middle truncation and `entry.finderTags.map(\.name).joined(separator: ", ")`. Add an inspector `Tags` detail row and an `Edit Tags` button when the single selection is not archive-backed. Add the command to app menu and item context menu.

- [ ] **Step 4: Run targeted tests and commit**

Run:

```bash
swift test --filter InspectorModelsTests
swift test --filter InspectorViewWiringTests
swift test --filter FileTableViewReuseTests
git add Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/UI/InspectorView.swift Sources/MyMacFinder/Domain/InspectorModels.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Tests/MyMacFinderTests/InspectorModelsTests.swift Tests/MyMacFinderTests/InspectorViewWiringTests.swift Tests/MyMacFinderTests/FileTableViewReuseTests.swift
git commit -m "feat: show finder tags in ui"
```

### Task 6: Full Verification And Manual QA

**Files:**
- Create: `docs/qa/finder-tags-manual-qa.md`

- [ ] **Step 1: Run automated verification**

Run:

```bash
swift test
swift build
```

- [ ] **Step 2: Launch the app for manual QA**

Run:

```bash
swift run MyMacFinder
```

Use a fixture folder under `$HOME/MyMacFinderTagsQA` with at least two text files and one ZIP archive.

- [ ] **Step 3: Manual checks**

Record results in `docs/qa/finder-tags-manual-qa.md`:

- Finder tags appear in the table and inspector for a normal file.
- `Edit Tags` adds tags to a selected normal file.
- `Edit Tags` removes tags when the prompt is submitted empty.
- Search query matches tag names.
- Search options `Tag` field filters by tag.
- ZIP-backed virtual entries show no tag editing action.
- Refresh preserves tag display after external Finder tag changes.

- [ ] **Step 4: Commit QA doc and final state**

Run:

```bash
git add docs/qa/finder-tags-manual-qa.md
git commit -m "docs: add finder tags manual qa"
git status --short --branch
```
