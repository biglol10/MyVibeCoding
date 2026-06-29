# Sidebar Editable Favorites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hard-coded sidebar favorites with persisted, user-editable favorites and recent folders while keeping mounted volumes in Locations.

**Architecture:** Add focused sidebar domain models plus a UserDefaults-backed store for favorite and recent folder state. `ExplorerStore` owns sidebar state and exposes safe navigation, add, remove, and reorder operations to `SidebarView` and file-table commands.

**Tech Stack:** Swift, SwiftUI, AppKit `NSTableView` context menus, XCTest, UserDefaults JSON persistence.

---

## File Structure

- Create `Sources/MyMacFinder/Domain/SidebarModels.swift`
  - Defines `SidebarFavorite`, `SidebarFavoriteItem`, `SidebarRecentFolder`, and `SidebarState`.
- Create `Sources/MyMacFinder/Services/SidebarFavoritesStore.swift`
  - Defines `SidebarFavoritesStoring` and `UserDefaultsSidebarFavoritesStore`.
- Modify `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
  - Adds `addToFavorites` with enablement limited to one selected filesystem folder.
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Injects sidebar store, publishes favorites/recent folders, records recent successful filesystem navigations, and implements favorite mutations.
- Modify `Sources/MyMacFinder/UI/SidebarView.swift`
  - Renders persisted favorites, Recent Folders, and Locations; supports remove and drag reorder.
- Modify `Sources/MyMacFinder/UI/FileTableView.swift`
  - Adds Add to Favorites to item context menu.
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`
  - Adds Add to Favorites to Explorer menu.
- Add `Tests/MyMacFinderTests/SidebarFavoritesStoreTests.swift`
- Add `Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift`
- Update `Tests/MyMacFinderTests/ExplorerCommandTests.swift`
- Add `docs/qa/sidebar-editable-favorites-manual-qa.md`

## Task 1: Sidebar Models And Persistence

**Files:**
- Create: `Sources/MyMacFinder/Domain/SidebarModels.swift`
- Create: `Sources/MyMacFinder/Services/SidebarFavoritesStore.swift`
- Test: `Tests/MyMacFinderTests/SidebarFavoritesStoreTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class SidebarFavoritesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "SidebarFavoritesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
    }

    func testDefaultsStoreSavesAndLoadsSidebarState() {
        let state = SidebarState(
            favorites: [
                SidebarFavorite(title: "Projects", url: URL(fileURLWithPath: "/Users/biglol/Projects", isDirectory: true))
            ],
            recentFolders: [
                SidebarRecentFolder(url: URL(fileURLWithPath: "/Users/biglol/Downloads", isDirectory: true))
            ]
        )

        UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").save(state)
        let loaded = UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").load()

        XCTAssertEqual(loaded, state)
    }

    func testDefaultsStoreSeedsDefaultFavoritesWhenMissing() {
        let loaded = UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").load()

        XCTAssertEqual(loaded.favorites.map(\.title), ["Home", "Desktop", "Documents", "Downloads", "Applications"])
        XCTAssertTrue(loaded.recentFolders.isEmpty)
    }

    func testDefaultsStoreFallsBackToDefaultFavoritesWhenDataIsCorrupt() {
        defaults.set(Data("not json".utf8), forKey: "sidebar")

        let loaded = UserDefaultsSidebarFavoritesStore(defaults: defaults, key: "sidebar").load()

        XCTAssertEqual(loaded.favorites.map(\.title), ["Home", "Desktop", "Documents", "Downloads", "Applications"])
        XCTAssertTrue(loaded.recentFolders.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SidebarFavoritesStoreTests`

Expected: FAIL because `SidebarState`, `SidebarFavorite`, `SidebarRecentFolder`, and `UserDefaultsSidebarFavoritesStore` do not exist.

- [ ] **Step 3: Implement sidebar models and persistence**

Create `SidebarModels.swift` with:

```swift
import Foundation

public struct SidebarFavorite: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var systemImageName: String

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        systemImageName: String = "folder"
    ) {
        self.id = id
        self.title = title
        self.url = url.standardizedFileURL
        self.systemImageName = systemImageName
    }
}

public struct SidebarFavoriteItem: Equatable, Identifiable, Sendable {
    public var favorite: SidebarFavorite
    public var isMissing: Bool

    public init(favorite: SidebarFavorite, isMissing: Bool) {
        self.favorite = favorite
        self.isMissing = isMissing
    }

    public var id: UUID { favorite.id }
}

public struct SidebarRecentFolder: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String? = nil) {
        let standardizedURL = url.standardizedFileURL
        self.url = standardizedURL
        self.title = title ?? standardizedURL.lastPathComponent
    }

    public var id: String { url.path }
}

public struct SidebarState: Codable, Equatable, Sendable {
    public var favorites: [SidebarFavorite]
    public var recentFolders: [SidebarRecentFolder]

    public init(
        favorites: [SidebarFavorite] = SidebarState.defaultFavorites(),
        recentFolders: [SidebarRecentFolder] = []
    ) {
        self.favorites = favorites
        self.recentFolders = recentFolders
    }

    public static func defaultFavorites(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SidebarFavorite] {
        [
            SidebarFavorite(title: "Home", url: homeDirectory, systemImageName: "house"),
            SidebarFavorite(title: "Desktop", url: homeDirectory.appendingPathComponent("Desktop", isDirectory: true), systemImageName: "desktopcomputer"),
            SidebarFavorite(title: "Documents", url: homeDirectory.appendingPathComponent("Documents", isDirectory: true), systemImageName: "doc"),
            SidebarFavorite(title: "Downloads", url: homeDirectory.appendingPathComponent("Downloads", isDirectory: true), systemImageName: "arrow.down.circle"),
            SidebarFavorite(title: "Applications", url: URL(fileURLWithPath: "/Applications", isDirectory: true), systemImageName: "a.square")
        ]
    }
}
```

Create `SidebarFavoritesStore.swift` with:

```swift
import Foundation

public protocol SidebarFavoritesStoring: AnyObject {
    func load() -> SidebarState
    func save(_ state: SidebarState)
}

public final class UserDefaultsSidebarFavoritesStore: SidebarFavoritesStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.SidebarState"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> SidebarState {
        guard let data = defaults.data(forKey: key) else {
            return SidebarState()
        }

        do {
            return try JSONDecoder().decode(SidebarState.self, from: data)
        } catch {
            return SidebarState()
        }
    }

    public func save(_ state: SidebarState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SidebarFavoritesStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Domain/SidebarModels.swift Sources/MyMacFinder/Services/SidebarFavoritesStore.swift Tests/MyMacFinderTests/SidebarFavoritesStoreTests.swift
git commit -m "feat: add editable sidebar persistence"
```

## Task 2: ExplorerStore Favorites And Recents

**Files:**
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Test: `Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`

- [ ] **Step 1: Write failing store and command tests**

Create `ExplorerSidebarStoreTests.swift` with:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerSidebarStoreTests: XCTestCase {
    func testAddSelectedFolderToFavoritesPersistsAndAvoidsDuplicates() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            sidebarFavoritesStore: sidebarStore
        )
        await store.loadInitialDirectory()
        store.updateSelection([selected])

        await store.addSelectedFolderToFavorites()
        await store.addSelectedFolderToFavorites()

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.url), [selected.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.url), [selected.standardizedFileURL])
    }

    func testAddSelectedFolderIgnoresFilesAndMultipleSelection() async throws {
        let root = try makeFixture()
        let file = root.appendingPathComponent("file.txt")
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            sidebarFavoritesStore: sidebarStore
        )
        await store.loadInitialDirectory()

        store.updateSelection([file])
        await store.addSelectedFolderToFavorites()
        store.updateSelection([file, selected])
        await store.addSelectedFolderToFavorites()

        XCTAssertTrue(store.favoriteSidebarItems.isEmpty)
        XCTAssertTrue(sidebarStore.savedStates.isEmpty)
    }

    func testRemoveAndReorderFavoritesPersist() async throws {
        let root = try makeFixture()
        let first = SidebarFavorite(title: "First", url: root.appendingPathComponent("Selected", isDirectory: true))
        let second = SidebarFavorite(title: "Second", url: root)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [first, second], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            sidebarFavoritesStore: sidebarStore
        )

        store.moveFavorite(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        store.removeFavorite(id: second.id)

        XCTAssertEqual(store.favoriteSidebarItems.map(\.favorite.id), [first.id])
        XCTAssertEqual(sidebarStore.savedStates.last?.favorites.map(\.id), [first.id])
    }

    func testMissingFavoritePublishesMissingItemWithoutCrashing() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let favorite = SidebarFavorite(title: "Missing", url: missing)
        let store = ExplorerStore(
            initialURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            sidebarFavoritesStore: InMemorySidebarFavoritesStore(state: SidebarState(favorites: [favorite], recentFolders: []))
        )

        XCTAssertEqual(store.favoriteSidebarItems, [SidebarFavoriteItem(favorite: favorite, isMissing: true)])
    }

    func testSuccessfulFilesystemNavigationRecordsRecentFolders() async throws {
        let root = try makeFixture()
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        let sidebarStore = InMemorySidebarFavoritesStore(state: SidebarState(favorites: [], recentFolders: []))
        let store = ExplorerStore(
            initialURL: root,
            settingsStore: InMemoryExplorerSettingsStore(),
            directoryWatcher: nil,
            sidebarFavoritesStore: sidebarStore
        )
        await store.loadInitialDirectory()

        await store.navigate(to: selected)
        await store.navigate(to: root)

        XCTAssertEqual(store.recentFolders.map(\.url), [root.standardizedFileURL, selected.standardizedFileURL])
        XCTAssertEqual(sidebarStore.savedStates.last?.recentFolders.map(\.url), [root.standardizedFileURL, selected.standardizedFileURL])
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplorerSidebarStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Selected", isDirectory: true), withIntermediateDirectories: true)
        try Data("file".utf8).write(to: root.appendingPathComponent("file.txt"))
        return root
    }
}

private final class InMemorySidebarFavoritesStore: SidebarFavoritesStoring {
    private var state: SidebarState
    var savedStates: [SidebarState] = []

    init(state: SidebarState) {
        self.state = state
    }

    func load() -> SidebarState {
        state
    }

    func save(_ state: SidebarState) {
        self.state = state
        savedStates.append(state)
    }
}

private final class InMemoryExplorerSettingsStore: ExplorerSettingsStoring {
    var settings = ExplorerSettings()

    func load() -> ExplorerSettings {
        settings
    }

    func save(_ settings: ExplorerSettings) {
        self.settings = settings
    }
}
```

Add to `ExplorerCommandTests`:

```swift
func testAddToFavoritesRequiresSingleFilesystemFolder() {
    let folder = FileEntry(
        url: URL(fileURLWithPath: "/tmp/Folder", isDirectory: true),
        name: "Folder",
        isDirectory: true
    )
    let file = FileEntry(
        url: URL(fileURLWithPath: "/tmp/file.txt"),
        name: "file.txt",
        isDirectory: false
    )

    XCTAssertTrue(ExplorerCommand.addToFavorites.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folder], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.addToFavorites.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [file], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.addToFavorites.isEnabled(selectionCount: 2, canPaste: false, selectedEntries: [folder, file], isArchiveLocation: false))
    XCTAssertFalse(ExplorerCommand.addToFavorites.isEnabled(selectionCount: 1, canPaste: false, selectedEntries: [folder], isArchiveLocation: true))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExplorerSidebarStoreTests --filter ExplorerCommandTests`

Expected: FAIL because `ExplorerStore` lacks sidebar store injection and favorite methods, and `ExplorerCommand.addToFavorites` does not exist.

- [ ] **Step 3: Implement store behavior**

Modify `ExplorerStore`:

- Add published properties:

```swift
@Published public private(set) var favoriteSidebarItems: [SidebarFavoriteItem]
@Published public private(set) var recentFolders: [SidebarRecentFolder]
```

- Add dependencies and state:

```swift
private let sidebarFavoritesStore: SidebarFavoritesStoring
private var sidebarState: SidebarState
private let maxRecentFolders = 10
```

- Add init parameter:

```swift
sidebarFavoritesStore: SidebarFavoritesStoring = UserDefaultsSidebarFavoritesStore(),
```

- Load and publish state in init:

```swift
let sidebarState = sidebarFavoritesStore.load()
self.sidebarState = sidebarState
self.favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites)
self.recentFolders = sidebarState.recentFolders
self.sidebarFavoritesStore = sidebarFavoritesStore
```

- Add public methods:

```swift
public func addSelectedFolderToFavorites() async {
    guard
        activeSelectedEntries.count == 1,
        let entry = activeSelectedEntries.first,
        !entry.isArchiveBacked,
        entry.isDirectoryLike
    else {
        return
    }

    addFavorite(url: entry.url, title: entry.name)
}

public func addActiveFolderToFavorites() {
    guard let url = activePane.location.fileSystemURL else {
        return
    }
    addFavorite(url: url, title: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
}

public func removeFavorite(id: SidebarFavorite.ID) {
    sidebarState.favorites.removeAll { $0.id == id }
    persistSidebarState()
}

public func moveFavorite(fromOffsets source: IndexSet, toOffset destination: Int) {
    sidebarState.favorites.move(fromOffsets: source, toOffset: destination)
    persistSidebarState()
}
```

- Add helpers:

```swift
private func addFavorite(url: URL, title: String) {
    let standardizedURL = url.standardizedFileURL
    guard !sidebarState.favorites.contains(where: { $0.url == standardizedURL }) else {
        return
    }

    sidebarState.favorites.append(
        SidebarFavorite(
            title: title.isEmpty ? standardizedURL.path : title,
            url: standardizedURL
        )
    )
    persistSidebarState()
}

private func recordRecentFolder(_ url: URL) {
    let standardizedURL = url.standardizedFileURL
    sidebarState.recentFolders.removeAll { $0.url == standardizedURL }
    sidebarState.recentFolders.insert(SidebarRecentFolder(url: standardizedURL), at: 0)
    if sidebarState.recentFolders.count > maxRecentFolders {
        sidebarState.recentFolders = Array(sidebarState.recentFolders.prefix(maxRecentFolders))
    }
    persistSidebarState()
}

private func persistSidebarState() {
    favoriteSidebarItems = Self.favoriteItems(from: sidebarState.favorites)
    recentFolders = sidebarState.recentFolders
    sidebarFavoritesStore.save(sidebarState)
}

private static func favoriteItems(from favorites: [SidebarFavorite]) -> [SidebarFavoriteItem] {
    favorites.map { favorite in
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: favorite.url.path, isDirectory: &isDirectory)
        return SidebarFavoriteItem(favorite: favorite, isMissing: !exists || !isDirectory.boolValue)
    }
}
```

- In successful filesystem `loadLocation`, call `recordRecentFolder(url)` after pane state is updated.

- In `perform(_:)`, add:

```swift
case .addToFavorites:
    await addSelectedFolderToFavorites()
```

Modify `ExplorerCommand`:

- Add `case addToFavorites`
- Title: `"Add to Favorites"`
- Enabled only for one selected non-archive directory-like entry.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ExplorerSidebarStoreTests --filter ExplorerCommandTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/Domain/ExplorerCommand.swift Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift
git commit -m "feat: manage editable sidebar favorites"
```

## Task 3: Sidebar UI And Menus

**Files:**
- Modify: `Sources/MyMacFinder/UI/SidebarView.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`

- [ ] **Step 1: Wire the file-table context menu**

In `FileTableView.itemMenu()`, add `addMenuItem(to: menu, command: .addToFavorites)` after `Open` and before the first separator.

- [ ] **Step 2: Wire the app menu**

In `MyMacFinderApp.CommandMenu("Explorer")`, add:

```swift
Button("Add to Favorites") {
    perform(.addToFavorites)
}
.disabled(!isEnabled(.addToFavorites))
```

Place it near Open/Quick Look so selection-based actions stay grouped.

- [ ] **Step 3: Replace SidebarView hard-coded sections**

Render:

- `Favorites` section from `explorerStore.favoriteSidebarItems`.
- Add button in the Favorites header that calls `explorerStore.addActiveFolderToFavorites()`.
- Remove context menu on each favorite.
- `.onMove` on favorites to call `explorerStore.moveFavorite(fromOffsets:toOffset:)`.
- `Recent Folders` section from `explorerStore.recentFolders`.
- Existing `Locations` section from mounted volumes.

Use disabled styling for missing favorites:

```swift
.disabled(item.isMissing)
.foregroundStyle(item.isMissing ? .secondary : .primary)
.help(item.isMissing ? "Missing path: \(item.favorite.url.path)" : item.favorite.url.path)
```

- [ ] **Step 4: Run focused UI compile tests**

Run: `swift test --filter ExplorerCommandTests --filter ExplorerSidebarStoreTests --filter SidebarFavoritesStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/UI/SidebarView.swift Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/MyMacFinderApp.swift
git commit -m "feat: wire editable sidebar UI"
```

## Task 4: Verification And Manual QA

**Files:**
- Create: `docs/qa/sidebar-editable-favorites-manual-qa.md`

- [ ] **Step 1: Run automated verification**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

Expected:
- `swift test`: all tests pass.
- `git diff --check`: no output and exit 0.
- build script: produces `build/MyMacFinder.app`.

- [ ] **Step 2: Add manual QA doc**

Create `docs/qa/sidebar-editable-favorites-manual-qa.md` with fixture setup, manual steps, pass criteria, and a dated result section that is completed after the manual run in Step 4.

- [ ] **Step 3: Run manual QA**

Fixture:

```bash
fixture="$HOME/MyMacFinderSidebarQA"
rm -rf "$fixture"
mkdir -p "$fixture/Parent/Child" "$fixture/MissingThenRemove"
printf "alpha\n" > "$fixture/Parent/alpha.txt"
```

Manual checks:

1. Launch `build/MyMacFinder.app`.
2. Navigate to `$HOME/MyMacFinderSidebarQA/Parent`.
3. Select `Child`, right-click, choose Add to Favorites. Expected: Child appears in Favorites.
4. Use the Favorites plus button while in `Parent`. Expected: Parent appears in Favorites.
5. Drag favorites to reorder. Expected: order changes and persists after relaunch.
6. Remove a favorite from its context menu. Expected: row disappears and persists after relaunch.
7. Navigate between `Parent` and `Child`. Expected: Recent Folders shows recent folders with most recent first.
8. Create a favorite for `$HOME/MyMacFinderSidebarQA/MissingThenRemove`, delete that folder externally, relaunch. Expected: favorite is disabled/secondary with missing-path help and app does not crash.
9. Locations still shows mounted volumes separately.

- [ ] **Step 4: Record observed manual QA result**

Append the result to the QA doc with date and pass/fail notes.

- [ ] **Step 5: Commit**

```bash
git add docs/qa/sidebar-editable-favorites-manual-qa.md
git commit -m "docs: add sidebar favorites manual qa"
```

## Self-Review

- Phase 4 requirements are covered:
  - Add selected folder to Favorites: Task 2 and Task 3.
  - Remove favorite: Task 2 and Task 3.
  - Reorder favorites: Task 2 and Task 3.
  - Show Recent Folders: Task 2 and Task 3.
  - Mounted volumes separate Locations: Task 3.
  - Missing paths disabled/error state: Task 2 and Task 3.
- The manual QA result section is explicitly written during Task 4 after the app is exercised.
- Types used in UI tasks match the model names defined in Task 1.
