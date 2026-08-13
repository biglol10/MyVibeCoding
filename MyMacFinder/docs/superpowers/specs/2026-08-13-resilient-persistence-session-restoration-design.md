# Resilient Persistence and Session Restoration Design

**Date:** 2026-08-13
**Status:** Approved

## Goal

Prevent corrupt or failed settings/sidebar/session persistence from silently discarding user state, and optionally restore the previous tabs, panes, and locations on the next launch without making startup fragile.

## Current Behavior and Risk

- `UserDefaultsExplorerSettingsStore` and `UserDefaultsSidebarFavoritesStore` return defaults when decoding fails.
- The store interfaces cannot report load or save failures to `ExplorerStore`.
- A later settings or sidebar mutation can overwrite the unreadable original bytes, removing the only recoverable copy.
- Tabs and pane locations are runtime-only. Relaunching always starts from the configured initial URL.
- The existing file-operation, archive, Undo, search, and pane-load safety mechanisms are not part of this change and must remain unchanged.

## Product Behavior

### Persistence failures

- Missing persisted data is normal and loads defaults.
- Valid persisted data loads normally.
- Corrupt or unsupported persisted data produces a persistent warning and remains byte-for-byte unchanged.
- Once a persistence area fails to load or save, automatic writes to that area are blocked for the rest of the recovery state. This prevents an in-memory fallback from replacing user data.
- General Settings shows separate recovery rows for General Settings, Sidebar, and Previous Session when relevant.
- Each recovery row offers an explicit destructive Reset. Reset removes the unreadable value and writes the currently selected safe state only after the reset succeeds.
- A persistence warning is not represented as a file-operation failure and does not block browsing.

### Previous session restoration

- General Settings adds `Restore Previous Session`, enabled by default for new and migrated settings.
- The session snapshot stores only stable workspace state:
  - tab order and active tab index;
  - pane locations and active pane index;
  - per-pane sort and group descriptors.
- It does not store directory entries, selection, back/forward history, search text, Finder Tag queries, Undo state, clipboard state, operation progress, inline rename state, or transient errors.
- Runtime tab and pane identifiers are regenerated on launch. Persisted identifiers are not used as filesystem ownership evidence.
- Session writes are debounced so path/search focus changes cannot cause excessive `UserDefaults` writes. A scene transition away from active state flushes the latest snapshot immediately.
- Disabling restoration keeps the saved snapshot but starts future launches at the normal initial URL. Re-enabling restoration can use the most recently saved valid snapshot.

### Safe restoration

- Snapshot structure is normalized: at least one tab and one pane, no more than two panes per tab, and clamped active indices.
- A bounded payload size prevents unexpectedly large session JSON from being decoded.
- Before the initial directory load, each restored filesystem location is checked for existence, directory status, and readability.
- A restored archive location requires a present, readable ZIP host. Invalid restored locations fall back to the supplied initial URL for that pane only.
- If a location changes between validation and load, existing pane-load generation checks remain authoritative. A failed initial restored load falls back once to the initial URL and does not loop.
- Repaired session state is persisted only when the session store is writable.

## Architecture

### Throwing persistence contracts

`ExplorerSettingsStoring` and `SidebarFavoritesStoring` become throwing contracts with `load`, `save`, and `reset`. A new `ExplorerSessionStoring` contract provides the same behavior for a versioned `ExplorerSessionSnapshot`.

The concrete UserDefaults stores decode without mutating the stored value. Decode failure, oversized payload, encode failure, and injected save/reset failures are surfaced to the caller. The existing valid JSON format for settings and sidebar state remains compatible.

### ExplorerStore recovery state

`ExplorerStore` owns independent optional persistence error messages and write-block flags for settings, sidebar, and session. Load failures initialize safe in-memory defaults while preserving the failed store. Save failures set the corresponding warning and block later automatic writes.

Reset methods are explicit public commands used by Settings. They clear the failed value, clear the block only after success, establish a safe in-memory value, and persist it. A failed reset leaves the warning and block intact.

### Session coordinator behavior

Session snapshot conversion lives in focused domain/service files rather than increasing the responsibilities of file-operation services. `ExplorerStore` schedules or flushes snapshots after meaningful tab, pane, location, sort, or group state changes. Restoration and validation occur before the first pane reload.

## UI

General Settings keeps the existing native `Form` layout. A new `Startup` section contains the restore toggle. A `Saved Data Recovery` section appears only when one or more persistence areas are blocked, with concise status text and a Reset button per area. No modal is required merely because browsing can continue.

## Compatibility and Migration

- macOS 15+, Swift 6.1, SwiftUI/AppKit, SPM, and ZIPFoundation versions remain unchanged.
- Older settings decode with `restorePreviousSession = true`.
- Existing valid sidebar/settings bytes continue to decode without migration.
- No real user files, Trash contents, bookmarks, or filesystem operation data are touched by session persistence.

## Test Strategy

- Store tests verify missing, valid, corrupt, oversized, reset, and byte-preservation behavior.
- ExplorerStore tests verify corrupt loads do not get overwritten by automatic changes, save failures block retries, and explicit reset recovers the area.
- Session tests verify snapshot normalization, excluded transient state, restore toggle behavior, invalid-location fallback, archive-host fallback, and save debouncing/flush.
- Existing tab, pane load race, search context, settings, sidebar, and file-operation tests remain green.
- Release QA uses only UUID-scoped temporary folders and an isolated UserDefaults suite/bundle identifier.

## Out of Scope

- Redo, Spotlight content indexing, SMB/NFS connection creation, ZIP in-place editing, Developer ID signing, notarization, and auto-update.
- Persisting Undo, clipboard, search queries, selections, or operation progress.
- Refactoring the complete `ExplorerStore` architecture.
