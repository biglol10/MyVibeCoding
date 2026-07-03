# Developer Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a complete Developer Cache screen that scans known developer cache roots, classifies cleanup safety, default-selects only safe cache groups, and moves selected cache folders to Trash through the existing verified deletion pipeline.

**Architecture:** Add focused Developer Cache domain types and scanner in `MyMacCleanCore`, a `DeveloperCacheViewModel` in `MyMacCleanAppSupport`, and replace the Maintenance placeholder with a real SwiftUI screen. Reuse `FileSizeCalculator`, `UserFileCleanupPolicy`, `DeletionExecutor`, `DeletionVerifier`, `DeletionReceiptStore`, confirmation sheets, and `DeleteActionButton`.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, macOS file APIs.

---

## File Structure

- `Sources/MyMacCleanCore/DeveloperCache/DeveloperCacheCandidate.swift`: candidate, tool, safety, sort types.
- `Sources/MyMacCleanCore/DeveloperCache/DeveloperCacheScanner.swift`: known target discovery, recursive sizing, safety classification.
- `Sources/MyMacCleanAppSupport/DeveloperCacheViewModel.swift`: scan/search/sort/selection/delete state.
- `Sources/MyMacCleanAppSupport/SidebarDestination.swift`: Maintenance title/action becomes Developer Cache.
- `Sources/MyMacCleanApp/Views/ContentView.swift`: Developer Cache content/detail and confirmation routing.
- `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`: add `developerCacheCleanup`.
- Tests mirror the new core and app-support files.

## Task 1: Developer Cache Scanner

**Files:**
- Create: `Sources/MyMacCleanCore/DeveloperCache/DeveloperCacheCandidate.swift`
- Create: `Sources/MyMacCleanCore/DeveloperCache/DeveloperCacheScanner.swift`
- Test: `Tests/MyMacCleanCoreTests/DeveloperCacheScannerTests.swift`

- [ ] **Step 1: Write failing scanner tests**

Create tests that prove:

```swift
func testScannerFindsExistingKnownTargetsWithSafetyAndSize() async throws
func testScannerSkipsMissingTargets() async throws
func testScannerReportsDockerTargetAsReadOnly() async throws
```

Expected behavior:
- DerivedData, SwiftPM, npm, yarn, and pnpm are `.safe`.
- Archives, DeviceSupport, CocoaPods, and Gradle are `.review`.
- Docker is `.readOnly` and not deletable by default.
- Missing directories are omitted.
- Recursive sizes are calculated.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter DeveloperCacheScannerTests`

Expected: FAIL because the types do not exist.

- [ ] **Step 3: Implement scanner types**

Add:
- `DeveloperCacheTool`
- `DeveloperCacheSafety`
- `DeveloperCacheCandidate`
- `DeveloperCacheSort`
- `DeveloperCacheScanner`

The scanner accepts `homeDirectory` and optional `dockerStorageURL` so tests can use fixtures without touching real user cache folders.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter DeveloperCacheScannerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/DeveloperCache Tests/MyMacCleanCoreTests/DeveloperCacheScannerTests.swift
git commit -m "feat: add developer cache scanner"
```

## Task 2: Developer Cache Deletion Flow

**Files:**
- Modify: `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`
- Create: `Sources/MyMacCleanAppSupport/DeveloperCacheViewModel.swift`
- Test: `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`
- Test: `Tests/MyMacCleanAppSupportTests/DeveloperCacheViewModelTests.swift`

- [ ] **Step 1: Write failing view model and receipt tests**

Create tests that prove:

```swift
func testScanDefaultSelectsOnlySafeCandidates() async throws
func testFilterAndSortVisibleCandidates() async throws
func testMoveSelectedCachesToTrashRecordsReceiptAndRemovesVerifiedItems() async throws
func testDeveloperCacheReceiptActionRoundTrips() throws
```

Expected behavior:
- Safe items are selected after scan.
- Review and read-only items are not selected.
- Read-only items cannot be selected for deletion.
- Successful Trash cleanup records `.developerCacheCleanup`.
- Verified deleted items disappear from the list.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter DeveloperCacheViewModelTests`

Expected: FAIL because the view model does not exist.

- [ ] **Step 3: Implement deletion flow**

`DeveloperCacheViewModel` should:
- scan with `DeveloperCacheScanner`
- expose `visibleCandidates`, `selectedCandidates`, `selectedBytes`, `totalBytes`
- default-select `.safe`
- refuse `.readOnly`
- map selected cache candidates to `RelatedFileCandidate`
- use `DeletionExecutor` in `.moveToTrash` mode
- write `.developerCacheCleanup` receipts

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter DeveloperCacheViewModelTests && swift test --filter DeletionReceiptStoreTests/testSupportsDeveloperCacheCleanupReceipts`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanAppSupport/DeveloperCacheViewModel.swift Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift Tests/MyMacCleanAppSupportTests/DeveloperCacheViewModelTests.swift Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift
git commit -m "feat: add developer cache cleanup flow"
```

## Task 3: Sidebar And SwiftUI Screen

**Files:**
- Modify: `Sources/MyMacCleanAppSupport/SidebarDestination.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift`
- Test: `Tests/MyMacCleanAppSupportTests/SidebarNavigationStateTests.swift`

- [ ] **Step 1: Write failing navigation tests**

Update tests so `.maintenance` exposes:
- title: `Developer Cache`
- subtitle: `Review build caches that can be regenerated.`
- action: `Scan Developer Caches`

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SidebarDestinationTests && swift test --filter SidebarNavigationStateTests`

Expected: FAIL while Maintenance still reports old copy.

- [ ] **Step 3: Implement UI**

Add:
- `@State private var developerCacheViewModel`
- `developerCacheContent`
- `developerCacheDetail`
- confirmation mode `.developerCache`
- Trash-only confirmation behavior like Large Files

The screen lists grouped tool rows, safety badges, size, path, and uses `DeleteActionButton`.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter SidebarDestinationTests && swift test --filter SidebarNavigationStateTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanApp/Views/ContentView.swift Sources/MyMacCleanAppSupport/SidebarDestination.swift Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift Tests/MyMacCleanAppSupportTests/SidebarNavigationStateTests.swift
git commit -m "feat: add developer cache screen"
```

## Task 4: Full Verification

- [ ] Run `swift test`
- [ ] Run `scripts/create-dmg.sh`
- [ ] Run `codesign --verify --deep --strict --verbose=2 dist/MyMacClean.app`
- [ ] Launch `dist/MyMacClean.app`
- [ ] Confirm Developer Cache appears in the sidebar.
- [ ] Confirm Scan Developer Caches returns real rows or an empty state without hanging.
- [ ] Confirm safe items are selected by default and read-only Docker rows are not selected.
- [ ] Do not delete real user cache folders during manual verification.
