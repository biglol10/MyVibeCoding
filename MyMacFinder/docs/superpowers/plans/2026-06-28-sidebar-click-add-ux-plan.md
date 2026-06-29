# Sidebar Click And Add UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sidebar rows fully clickable and make adding the current folder to Favorites obvious without allowing duplicate favorite actions.

**Architecture:** Keep sidebar ownership in `ExplorerStore` and presentation in `SidebarView`. Add a computed enablement property to the store, then bind both the Favorites header plus button and the new visible add row to that single rule.

**Tech Stack:** Swift, SwiftUI, XCTest, macOS manual QA.

---

## File Structure

- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Add `canAddActiveFolderToFavorites` and reuse it in `addActiveFolderToFavorites()`.
- Modify `Sources/MyMacFinder/UI/SidebarView.swift`
  - Add full-width sidebar labels and the visible "Add Current Folder" row.
- Modify `Tests/MyMacFinderTests/ExplorerSidebarStoreTests.swift`
  - Add a focused test for active-folder favorite enablement and duplicate prevention.
- Create `docs/qa/sidebar-click-add-ux-manual-qa.md`
  - Record manual verification steps and result.

## Tasks

- [ ] Write `testCanAddActiveFolderToFavoritesReflectsActiveFolderDuplicateState`.
- [ ] Run `swift test --filter ExplorerSidebarStoreTests/testCanAddActiveFolderToFavoritesReflectsActiveFolderDuplicateState` and confirm it fails because the property does not exist.
- [ ] Add `ExplorerStore.canAddActiveFolderToFavorites` and guard `addActiveFolderToFavorites()` with it.
- [ ] Update `SidebarView` so `favoriteButton` and `sidebarButton` labels fill the row and use `contentShape(Rectangle())`.
- [ ] Add a visible "Add Current Folder" row under Favorites and disable it when `canAddActiveFolderToFavorites` is false.
- [ ] Run focused tests, then `swift test`, `git diff --check`, and `./scripts/build_app.sh`.
- [ ] Launch the app and manually verify row-wide clicking plus the visible Favorites add row.
- [ ] Commit the implementation and QA notes.
