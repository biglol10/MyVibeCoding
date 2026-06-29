# Shortcut And Menu Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make high-frequency keyboard and menu behavior match Finder and Windows-style expectations while preserving native text-field editing.

**Architecture:** Continue routing every action through `ExplorerCommand` and `ExplorerStore.perform(_:)`. File-table key handling owns shortcuts that would conflict with text fields, while app menu commands expose safe global shortcuts and manually clickable menu actions.

**Tech Stack:** Swift 6.1, SwiftUI Commands, AppKit `NSTableView`, XCTest.

---

## File Structure

- Modify `Sources/MyMacFinder/Domain/ExplorerCommand.swift`: add command cases, titles, and enablement for selection, navigation history, and inspector toggle.
- Modify `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`: map new shortcut keys to commands.
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`: expose back/forward availability and perform new commands.
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`: add menu items and disabled states.
- Modify `Sources/MyMacFinder/App/RootView.swift`: pass navigation availability into file panes.
- Modify `Sources/MyMacFinder/UI/FileTableView.swift`: pass navigation availability and support table-focused shortcuts.
- Update `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`: shortcut mapping coverage.
- Update `Tests/MyMacFinderTests/ExplorerStoreTests.swift`: select-all, history navigation command, and inspector toggle coverage.
- Add `docs/qa/shortcut-menu-parity-manual-qa.md`: focused manual QA checklist.

## Task 1: Shortcut Mapping

**Files:**
- Modify `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- Test `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`

- [ ] **Step 1: Write failing shortcut tests**

Add assertions for:

```swift
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "a", modifiers: [.command])), .selectAll)
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f2", modifiers: [])), .rename)
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "down", modifiers: [.command])), .open)
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "left", modifiers: [.command])), .goBack)
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "right", modifiers: [.command])), .goForward)
XCTAssertEqual(ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "i", modifiers: [.command])), .toggleInspector)
```

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
```

Expected: build or tests fail because the new commands and mappings do not exist.

- [ ] **Step 3: Implement command cases and shortcut mappings**

Add `selectAll`, `goBack`, `goForward`, and `toggleInspector` to `ExplorerCommand`. Add mappings in `ExplorerKeyboardShortcut.command(for:)`.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
```

Expected: shortcut tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift \
  Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift \
  Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift
git commit -m "feat: add shortcut parity command mappings"
```

## Task 2: Store Command Behavior

**Files:**
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test `Tests/MyMacFinderTests/ExplorerStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Add tests proving:

```swift
await store.perform(.selectAll)
XCTAssertEqual(store.activePane.selectedURLs, Set(store.activePaneVisibleEntries.map(\.url)))

await store.perform(.goBack)
await store.perform(.goForward)

let initialInspectorVisibility = store.isInspectorVisible
await store.perform(.toggleInspector)
XCTAssertEqual(store.isInspectorVisible, !initialInspectorVisibility)
```

- [ ] **Step 2: Verify RED**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: build or tests fail until store behavior is implemented.

- [ ] **Step 3: Implement store behavior**

Add `canGoBack`, `canGoForward`, `selectAllVisibleEntries()`, and command routing for `.selectAll`, `.goBack`, `.goForward`, `.toggleInspector`.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: store tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerStoreTests.swift
git commit -m "feat: route shortcut parity commands in explorer store"
```

## Task 3: Menu And File Table Wiring

**Files:**
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify `Sources/MyMacFinder/App/RootView.swift`
- Modify `Sources/MyMacFinder/UI/FileTableView.swift`

- [ ] **Step 1: Wire app menu**

Add menu items for Select All, Toggle Inspector, Back, Forward, Command-O Open, and manual menu entries for table-scoped shortcuts. Do not bind Command-A or Command-Left/Right globally, because path/search fields must keep native text editing behavior.

- [ ] **Step 2: Wire file table state**

Pass `canGoBack` and `canGoForward` from `ExplorerStore` through `RootView.filePane(at:)` into `FileTableView`, then use those values in command enablement.

- [ ] **Step 3: Extend AppKit key extraction**

In `FileTableView.Coordinator.shortcut(from:)`, map:

```swift
case 120: key = "f2"
case 123: key = "left"
case 124: key = "right"
case 125: key = "down"
```

- [ ] **Step 4: Run targeted tests**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests --filter ExplorerStoreTests --filter FileTableViewReuseTests
```

Expected: targeted tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/App/MyMacFinderApp.swift \
  Sources/MyMacFinder/App/RootView.swift \
  Sources/MyMacFinder/UI/FileTableView.swift
git commit -m "feat: wire shortcut parity menus and table keys"
```

## Task 4: Manual QA And Phase Gate

**Files:**
- Create `docs/qa/shortcut-menu-parity-manual-qa.md`

- [ ] **Step 1: Add manual QA checklist**

Cover:

- Return opens selected folders/files from the table.
- F2 opens rename for a selected item.
- Command-O and Command-Down open selected items from the table.
- Command-Up goes to the parent folder.
- Command-Left/Right navigate history from the table.
- Command-I toggles inspector.
- Command-A selects all table rows.
- Command-A and Command-Left/Right still edit normally inside path/search text fields.

- [ ] **Step 2: Run full automated gate**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

Expected: tests pass, diff check prints no output, release app builds.

- [ ] **Step 3: Manual QA**

Launch:

```bash
open build/MyMacFinder.app
```

Exercise the checklist in the running app using a generated fixture folder.

- [ ] **Step 4: Commit QA doc**

```bash
git add docs/qa/shortcut-menu-parity-manual-qa.md
git commit -m "docs: add shortcut menu parity manual qa"
```

## Self-Review

- Scope matches roadmap Phase 3 only.
- Command cases, store routing, menu wiring, and manual QA are all covered.
- Text-field safety is explicit: conflicting shortcuts are table-scoped rather than global menu shortcuts.
- No placeholders or deferred requirements remain.
