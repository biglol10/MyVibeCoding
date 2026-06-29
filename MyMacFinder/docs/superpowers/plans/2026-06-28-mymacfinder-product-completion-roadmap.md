# MyMacFinder Product Completion Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn MyMacFinder from a working Finder-style MVP into a production-grade local file manager through ordered, independently verifiable phases.

**Architecture:** Keep the app SwiftUI + AppKit hybrid. File mutations remain centralized in services and coordinated by `ExplorerStore`; UI surfaces consume typed state rather than touching the filesystem directly. Each major feature gets its own focused service/model/store tests before UI wiring, and every phase ends with automated verification plus release-app manual QA.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Foundation FileManager, FSEvents, QuickLookThumbnailing, ZIPFoundation, XCTest, shell packaging scripts.

---

## Scope Split

The requested work contains ten independent subsystems. Do not implement them as one giant branch. Execute them in this order:

1. Phase 0: Current changes cleanup and commits
2. Phase 1: Large file operation UX
3. Phase 2: Permission policy
4. Phase 3: Shortcut and menu parity
5. Phase 4: Sidebar and editable favorites
6. Phase 5: Finder Tags
7. Phase 6: View modes
8. Phase 7: Operation queue and Activity View
9. Phase 8: Advanced dual-pane workflows
10. Phase 9: Advanced archive workflows

Every phase must produce a usable app. If a phase becomes too large, split it into a backend service plan and a UI wiring plan before implementation.

## Global Completion Gates

Each phase must finish with:

- `swift test`
- `git diff --check`
- `./scripts/build_app.sh`
- release app launch from `build/MyMacFinder.app`
- a focused manual QA pass against the feature added in that phase
- a commit with a narrow message and no unrelated source changes

For destructive file operations, manual QA must use generated fixture folders only. Do not run delete/move/rename tests against real user files.

## Phase 0: Current Changes Cleanup And Commits

**Goal:** Separate the existing uncommitted work into coherent commits before starting larger feature work.

**Current dirty files:**

- `.gitignore`
- `README.md`
- `scripts/build_app.sh`
- `scripts/package_personal.sh`
- `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`
- `Sources/MyMacFinder/Services/FileSystemService.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Sources/MyMacFinder/UI/FileTableView.swift`
- `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`
- `Tests/MyMacFinderTests/FileSystemServiceTests.swift`
- `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`

### Task 0.1: Verify Current Worktree

**Files:** none

- [ ] **Step 1: Inspect current diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only the files listed above plus this roadmap file are changed.

- [ ] **Step 2: Run full verification**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

Expected: tests pass, diff check prints no errors, and `build/MyMacFinder.app` is recreated.

- [ ] **Step 3: Launch the built app**

Run:

```bash
open build/MyMacFinder.app
```

Manual QA:

- App opens.
- The home folder table renders.
- Selecting a folder and pressing Return opens it.
- The app can be closed cleanly.

### Task 0.2: Commit Packaging And Run Documentation

**Files:**

- `.gitignore`
- `README.md`
- `scripts/build_app.sh`
- `scripts/package_personal.sh`

- [ ] **Step 1: Stage packaging files**

Run:

```bash
git add .gitignore README.md scripts/build_app.sh scripts/package_personal.sh
git diff --cached --stat
```

Expected: only packaging and README files are staged.

- [ ] **Step 2: Commit**

Run:

```bash
git commit -m "chore: add app run and personal packaging scripts"
```

Expected: commit succeeds.

### Task 0.3: Commit Filesystem Sync And Symlink Stabilization

**Files:**

- `Sources/MyMacFinder/Services/DirectoryWatcherService.swift`
- `Sources/MyMacFinder/Services/FileSystemService.swift`
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- `Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift`
- `Tests/MyMacFinderTests/FileSystemServiceTests.swift`

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --filter ExplorerStoreWatcherTests --filter FileSystemServiceTests
```

Expected: watcher and filesystem tests pass.

- [ ] **Step 2: Stage files**

Run:

```bash
git add Sources/MyMacFinder/Services/DirectoryWatcherService.swift \
  Sources/MyMacFinder/Services/FileSystemService.swift \
  Sources/MyMacFinder/Stores/ExplorerStore.swift \
  Tests/MyMacFinderTests/ExplorerStoreWatcherTests.swift \
  Tests/MyMacFinderTests/FileSystemServiceTests.swift
git diff --cached --stat
```

Expected: only watcher, store refresh, symlink handling, and their tests are staged.

- [ ] **Step 3: Commit**

Run:

```bash
git commit -m "fix: sync visible panes and support folder symlinks"
```

Expected: commit succeeds.

### Task 0.4: Commit Table UX And Return-Open Behavior

**Files:**

- `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- `Sources/MyMacFinder/UI/FileTableView.swift`
- `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`
- `Tests/MyMacFinderTests/ExplorerStoreTests.swift`
- `Tests/MyMacFinderTests/FileTableViewReuseTests.swift`

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests --filter ExplorerStoreTests/testOpenCommandNavigatesIntoSelectedFolder --filter FileTableViewReuseTests
```

Expected: shortcut, open command, and table reuse/column tests pass.

- [ ] **Step 2: Stage files**

Run:

```bash
git add Sources/MyMacFinder/App/MyMacFinderApp.swift \
  Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift \
  Sources/MyMacFinder/UI/FileTableView.swift \
  Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift \
  Tests/MyMacFinderTests/ExplorerStoreTests.swift \
  Tests/MyMacFinderTests/FileTableViewReuseTests.swift
git diff --cached --stat
```

Expected: only table UX and Return-open behavior files are staged.

- [ ] **Step 3: Commit**

Run:

```bash
git commit -m "fix: make return open items and stabilize table columns"
```

Expected: commit succeeds.

### Task 0.5: Commit Roadmap

**Files:**

- `docs/superpowers/plans/2026-06-28-mymacfinder-product-completion-roadmap.md`

- [ ] **Step 1: Stage roadmap**

Run:

```bash
git add docs/superpowers/plans/2026-06-28-mymacfinder-product-completion-roadmap.md
git diff --cached --stat
```

Expected: only this roadmap file is staged.

- [ ] **Step 2: Commit**

Run:

```bash
git commit -m "docs: plan MyMacFinder product completion roadmap"
```

Expected: commit succeeds.

### Task 0.6: Final Phase 0 Verification

**Files:** none

- [ ] **Step 1: Verify clean state**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
git status --short
```

Expected: tests pass, diff check prints no errors, app bundle builds, and no unstaged source changes remain.

## Phase 1: Large File Operation UX

**Goal:** Make long-running copy, move, duplicate, trash, zip extraction, and compression operations observable and cancellable enough for large folders.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Domain/FileOperationProgress.swift`
- Create `Sources/MyMacFinder/Services/FileOperationProgressReporter.swift`
- Modify `Sources/MyMacFinder/Services/FileOperationService.swift`
- Modify `Sources/MyMacFinder/Services/ZipCompressionService.swift`
- Modify `Sources/MyMacFinder/Services/ZipExtractionService.swift`
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify `Sources/MyMacFinder/App/RootView.swift`
- Create `Sources/MyMacFinder/UI/OperationProgressBanner.swift`
- Add tests under `Tests/MyMacFinderTests/`

**Required behavior:**

- Operations expose a stable operation id, title, phase, current item, completed item count, total item count when known, byte progress when cheaply available, cancellation state, and final result.
- `ExplorerStore` owns active operation state.
- File mutation services accept a progress reporter and cancellation check.
- UI shows a compact progress banner for the active operation.
- Cancel requests stop before the next file item starts and leave already completed filesystem changes intact.
- Errors are surfaced through the existing alert path and stored in operation result state.

**Verification:**

- Unit tests prove progress snapshots advance for multi-item copy/move.
- Unit tests prove cancellation stops before all fixture files are processed.
- Manual QA uses a generated large folder fixture and confirms the UI does not look frozen while copying/compressing.

## Phase 2: Permission Policy

**Goal:** Move from passive permission error guidance to an explicit macOS access model.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`
- Create `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`
- Modify `Sources/MyMacFinder/Domain/PermissionGuidance.swift`
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Add settings UI for granted folders and access reset
- Add permission tests with mock bookmark storage

**Required behavior:**

- User can choose a folder through `NSOpenPanel`.
- Access grants are stored as security-scoped bookmarks when sandboxed.
- Permission errors offer a concrete "Choose Folder..." recovery action.
- Settings shows sandbox state and granted locations.
- Non-sandboxed personal builds keep working without requiring bookmarks.

## Phase 3: Shortcut And Menu Parity

**Goal:** Align daily keyboard and menu behavior with Finder and Windows-style expectations without breaking text-field editing.

**Primary files to create or modify:**

- Modify `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify `Sources/MyMacFinder/UI/FileTableView.swift`
- Add or update shortcut tests

**Required behavior:**

- Add Select All.
- Add F2 Rename.
- Keep Return as Open.
- Add Command-O as Open.
- Add Command-Down as Open and Command-Up as parent folder.
- Add Command-I to toggle or focus inspector.
- Add Command-Left and Command-Right navigation where it does not conflict with text fields.
- Add clear menu labels and disabled states.
- Preserve native editing shortcuts in path/search fields.

## Phase 4: Sidebar And Editable Favorites

**Goal:** Make the sidebar user-owned instead of hard-coded.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Domain/SidebarModels.swift`
- Create `Sources/MyMacFinder/Services/SidebarFavoritesStore.swift`
- Modify `Sources/MyMacFinder/UI/SidebarView.swift`
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Add tests for persistence, ordering, and missing path handling

**Required behavior:**

- Add selected folder to Favorites.
- Remove favorite.
- Reorder favorites.
- Show Recent Folders.
- Keep mounted volumes in a separate Locations section.
- Missing favorite paths display disabled/error state instead of crashing.

## Phase 5: Finder Tags

**Goal:** Read, show, filter, and edit Finder tags for normal filesystem entries.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Domain/FinderTag.swift`
- Create `Sources/MyMacFinder/Services/FinderTagService.swift`
- Modify `Sources/MyMacFinder/Domain/FileEntry.swift`
- Modify `Sources/MyMacFinder/Services/FileSystemService.swift`
- Modify `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify `Sources/MyMacFinder/UI/InspectorView.swift`
- Add tag filter/search tests

**Required behavior:**

- Display tags in inspector and optional table column.
- Add/remove tags for selected files.
- Filter/search by tag.
- Do not expose tag editing for archive-backed virtual entries.
- Handle missing tag metadata as an empty tag list.

## Phase 6: View Modes

**Goal:** Support more than list/table browsing.

**Primary files to create or modify:**

- Extend `ExplorerSettings` with view mode.
- Create `Sources/MyMacFinder/Domain/ExplorerViewMode.swift`
- Create `Sources/MyMacFinder/UI/IconGridView.swift`
- Create `Sources/MyMacFinder/UI/ColumnBrowserView.swift` in a follow-up sub-plan after icon grid selection behavior is stable.
- Modify `Sources/MyMacFinder/App/RootView.swift`
- Modify settings and menu commands
- Add view mode persistence tests

**Required behavior:**

- Existing table/list mode remains default.
- Icon grid mode supports selection, open, context menu, drag/drop, and large folder scrolling.
- View mode persists globally.
- Keyboard navigation remains usable.

## Phase 7: Operation Queue And Activity View

**Goal:** Promote the Phase 1 active-operation banner into a full queue and history surface.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Domain/ActivityModels.swift`
- Create `Sources/MyMacFinder/Stores/ActivityStore.swift`
- Create `Sources/MyMacFinder/UI/ActivityView.swift`
- Modify `ExplorerStore` to enqueue operations
- Add retry and clear history commands
- Add tests for queue ordering, retry eligibility, and cancellation

**Required behavior:**

- Multiple operations queue and run predictably.
- Activity View shows running, queued, completed, failed, canceled.
- Failed operations retain readable error messages.
- Retry is available only for operations with stable inputs.
- Clear completed does not remove running operations.

## Phase 8: Advanced Dual-Pane Workflows

**Goal:** Make dual pane more than two independent lists.

**Primary files to create or modify:**

- Create `Sources/MyMacFinder/Domain/DualPaneAction.swift`
- Create `Sources/MyMacFinder/Services/FolderComparisonService.swift`
- Modify `Sources/MyMacFinder/App/RootView.swift`
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Add tests for pane-targeted copy/move commands

**Required behavior:**

- Copy selected left-to-right and right-to-left.
- Move selected left-to-right and right-to-left.
- Swap panes.
- Sync browsing option keeps relative navigation aligned.
- Compare folders by name, size, modified date, and missing/excess items.
- Folder sync plan preview is shown before mutations.

## Phase 9: Advanced Archive Workflows

**Goal:** Expand ZIP support from read/browse/extract/compress to practical archive management.

**Primary files to create or modify:**

- Extend archive domain models with writable operations.
- Create `Sources/MyMacFinder/Services/ArchiveMutationService.swift`
- Modify `ArchiveBrowsingService`.
- Modify file table drag/drop support for archive-backed destinations and sources.
- Add tests for add, delete, replace, drag-out, and conflict behavior.

**Required behavior:**

- Drag files out of ZIP virtual folders.
- Add files into ZIP archives.
- Delete archive entries after confirmation.
- Replace archive entries through conflict handling.
- Preserve read-only safeguards for unsupported archive types.
- Keep password-protected or unsupported formats as readable errors until a dedicated engine is selected.

## Execution Strategy

Use this roadmap as the controlling order. Before implementing each phase after Phase 0, create a dedicated implementation plan in `docs/superpowers/plans/` with exact test cases, file-level code changes, and manual QA steps for that phase.

Recommended branch discipline:

- Phase 0 commits current work on `master`.
- Each later phase starts from clean `master`.
- Each phase uses focused commits and ends with green verification.
- Do not start a later phase while the previous phase has uncommitted source changes.

## Self-Review

- Spec coverage: every requested item maps to one phase in the same order as the user request.
- Red-flag scan: the roadmap avoids unresolved filler tokens and defines concrete required behavior for each phase.
- Type consistency: planned file and type names follow existing project naming patterns such as `ExplorerStore`, `ExplorerCommand`, `FileOperationService`, and focused domain/service/UI files.
- Scope check: this is intentionally a controlling roadmap, not a monolithic implementation plan. Dedicated phase plans are required before coding Phases 1-9.
