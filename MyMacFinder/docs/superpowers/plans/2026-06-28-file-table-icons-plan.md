# File Table Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact file/folder icons to the Name column in the main file table and verify the result with automated tests plus an app E2E pass.

**Architecture:** Keep the change inside `FileTableView`'s existing AppKit bridge. Name cells become `NSImageView + NSTextField`; all other columns remain text-only reusable cells. Real filesystem entries use `NSWorkspace` icons and archive-backed entries use safe fallback symbols.

**Tech Stack:** Swift 6.1, AppKit `NSTableView`, `NSWorkspace`, XCTest, existing shell build scripts, Computer Use for manual E2E.

---

### Task 1: Add Failing Table Icon Tests

**Files:**
- Modify: `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`

- [ ] **Step 1: Add a test that expects Name cells to expose an icon**

Insert a test in `FileTableViewReuseTests` that creates a folder `FileEntry`, renders the `name` column, and asserts `cell.imageView?.image` is not nil.

- [ ] **Step 2: Add a test that expects non-name cells to stay text-only**

Render the `kind` column and assert `cell.imageView` is nil while `cell.textField?.stringValue` remains the kind description.

- [ ] **Step 3: Add a test for archive-backed fallback icons**

Create a `FileEntry` with `kind: .zipVirtualFile` and `source: .archive(...)`, render the `name` column, and assert `cell.imageView?.image` is not nil.

- [ ] **Step 4: Run the focused test and confirm RED**

Run:

```bash
swift test --filter FileTableViewReuseTests
```

Expected: the new icon tests fail because current name cells have no `imageView`.

### Task 2: Implement Name Cell Icons

**Files:**
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`

- [ ] **Step 1: Split reusable cell creation**

Change `tableView(_:viewFor:row:)` so the `name` column calls a `makeReusableNameCell(identifier:)` helper and other columns call the existing text helper.

- [ ] **Step 2: Add the name cell layout**

The name cell contains:

```swift
let imageView = NSImageView()
imageView.imageScaling = .scaleProportionallyDown
imageView.translatesAutoresizingMaskIntoConstraints = false
cell.imageView = imageView

let textField = NSTextField(labelWithString: "")
textField.lineBreakMode = .byTruncatingMiddle
textField.maximumNumberOfLines = 1
textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
textField.translatesAutoresizingMaskIntoConstraints = false
cell.textField = textField
```

Constraints: icon 16x16, leading 6, text leading 6 after icon, trailing -6, both centered vertically.

- [ ] **Step 3: Resolve icons**

Add `icon(for entry: FileEntry) -> NSImage` in the coordinator. For non-archive entries, use `NSWorkspace.shared.icon(forFile: entry.url.path)` and set size to 16x16. For archive-backed entries and missing fallback cases, use `NSImage(systemSymbolName:accessibilityDescription:)` with a document/folder fallback.

- [ ] **Step 4: Assign icon only for Name column**

Set `cell.imageView?.image = icon(for: entry)` when `identifier == "name"`. For other columns, keep `cell.imageView` nil.

- [ ] **Step 5: Run the focused test and confirm GREEN**

Run:

```bash
swift test --filter FileTableViewReuseTests
```

Expected: all `FileTableViewReuseTests` pass.

### Task 3: Full Verification And E2E

**Files:**
- Create: `docs/qa/file-table-icons-manual-qa.md`

- [ ] **Step 1: Run full automated verification**

Run:

```bash
swift test
swift build
git diff --check
```

Expected: tests pass, build succeeds, diff check prints no errors.

- [ ] **Step 2: Build the app bundle**

Run:

```bash
./scripts/build_app.sh
```

Expected: `build/MyMacFinder.app` is created.

- [ ] **Step 3: Create E2E fixture**

Create `$HOME/MyMacFinderIconQA` containing a folder, `image.png`, `script.js`, `component.ts`, `paper.pdf`, `archive.zip`, and `notes.txt`.

- [ ] **Step 4: Launch and inspect the app**

Open `build/MyMacFinder.app`, navigate to `$HOME/MyMacFinderIconQA`, and confirm icons appear before each name in the table.

- [ ] **Step 5: Record QA results**

Write `docs/qa/file-table-icons-manual-qa.md` with fixture, automated commands, and manual E2E observations.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/MyMacFinder/UI/FileTableView.swift Tests/MyMacFinderTests/FileTableViewReuseTests.swift docs/qa/file-table-icons-manual-qa.md
git commit -m "feat: show file icons in table"
```

Expected: commit succeeds with only icon feature files staged.

### Self-Review

- Spec coverage: Task 1 covers tests, Task 2 covers UI implementation, Task 3 covers E2E and QA docs.
- Placeholder scan: no TBD/TODO/fill-in steps remain.
- Type consistency: file paths and APIs match current `FileTableView` and `FileEntry` usage.
