# MyMacClean Safety and Utility Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden deletion and matching, expose incomplete scan coverage, discover nested apps, add safe App Reset, and let Large Files scan one user-selected folder.

**Architecture:** Add structured scan results beside the existing core scanners, then publish issues through the current `@MainActor` view models and a reusable native warning banner. Keep all destructive work inside `DeletionPlanner`, `DeletionExecutor`, `DeletionVerifier`, and `DeletionReceiptStore`; App Reset and custom Large Files scanning only supply narrower plans and purpose-specific protection policies.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI and AppKit on macOS 14+, XCTest, native `FileManager`, `NSOpenPanel`, existing JSONL receipts.

## Global Constraints

- Trash remains the default for Applications and Orphan Files.
- App Reset and Large Files are Trash-only and do not expose force deletion.
- Every destructive action requires explicit selection and typed confirmation.
- Finder Automation fallback remains limited to `.app` bundles moved to Trash.
- No privileged helper, `sudo`, `launchctl`, persistence of arbitrary folder access, or new third-party dependency.
- Existing public methods remain as compatibility wrappers where changing every caller would not improve safety.
- Production behavior changes must follow red-green-refactor with a focused failing test first.
- The UI remains a restrained Finder/System Settings-style native inspector.

---

### Task 1: Make Candidate Matching and Protection Fail Closed

**Files:**
- Modify: `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`
- Modify: `Sources/MyMacCleanCore/Safety/ProtectionPolicy.swift`
- Modify: `Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift`
- Test: `Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift`
- Test: `Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift`
- Test: `Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift`

**Interfaces:**
- Consumes: existing `CandidateMatcher.match`, `ProtectionPolicy.isProtected`, and `UserFileCleanupPolicy.isProtected`.
- Produces: `UserFileCleanupPolicy.accepts(root:) -> Bool` for later Large Files root validation; all existing initializers remain source-compatible.

- [ ] **Step 1: Write failing matcher tests**

Add tests proving that `com.example.EditorPlus` and `xcom.example.Editor` are not bundle-ID matches for `com.example.Editor`, while `group.com.example.Editor` and `com.example.Editor.helper` remain strong matches. Add a single-token test proving that the app name `Cursor` does not match `cli-cursor`, `cursor-theme`, or `restore-cursor`, but still matches a folder named exactly `Cursor`.

```swift
func testBundleIdentifierRequiresIdentifierBoundaries() {
    let app = makeApp(name: "Editor", bundleIdentifier: "com.example.Editor")

    XCTAssertNil(CandidateMatcher().match(
        url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.EditorPlus"),
        app: app,
        kind: .cache
    ))
    XCTAssertNil(CandidateMatcher().match(
        url: URL(fileURLWithPath: "/Users/me/Library/Caches/xcom.example.Editor"),
        app: app,
        kind: .cache
    ))
    XCTAssertEqual(
        CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Group Containers/group.com.example.Editor"),
            app: app,
            kind: .groupContainer
        )?.confidence,
        .high
    )
}

func testSingleTokenAppNameDoesNotMatchUnrelatedCompoundNames() {
    let app = makeApp(name: "Cursor", bundleIdentifier: nil)

    for name in ["cli-cursor", "cursor-theme", "restore-cursor"] {
        XCTAssertNil(CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/\(name)"),
            app: app,
            kind: .applicationSupport
        ))
    }
    XCTAssertNotNil(CandidateMatcher().match(
        url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Cursor"),
        app: app,
        kind: .applicationSupport
    ))
}
```

- [ ] **Step 2: Run matcher tests and verify the expected failures**

Run: `swift test --filter CandidateMatcherTests`

Expected: failures show substring bundle IDs and compound single-token names currently match.

- [ ] **Step 3: Implement bounded matching**

Replace `fullPath.contains(bundleIdentifier)` with a helper that inspects the characters immediately before and after each occurrence. A boundary is start/end or a character other than a letter, digit, hyphen, or underscore. Replace single-token contiguous matching with complete token-sequence equality; keep contiguous/compact matching for two or more app-name tokens.

```swift
private func containsBoundedIdentifier(_ identifier: String, in value: String) -> Bool {
    var searchStart = value.startIndex
    while searchStart < value.endIndex,
          let range = value.range(of: identifier, range: searchStart..<value.endIndex) {
        let beforeIsBoundary = range.lowerBound == value.startIndex
            || isIdentifierBoundary(value[value.index(before: range.lowerBound)])
        let afterIsBoundary = range.upperBound == value.endIndex
            || isIdentifierBoundary(value[range.upperBound])
        if beforeIsBoundary && afterIsBoundary { return true }
        searchStart = range.upperBound
    }
    return false
}

private func isIdentifierBoundary(_ character: Character) -> Bool {
    !character.isLetter && !character.isNumber && character != "-" && character != "_"
}

private func fullNameMatch(_ sequence: [String], candidateTokens: [String], candidateCompact: String) -> Bool {
    if sequence.count == 1 { return candidateTokens == sequence }
    return candidateTokens.containsContiguous(sequence) || compactNameMatch(sequence, in: candidateCompact)
}
```

- [ ] **Step 4: Write failing protection-policy tests**

Add tests proving app cleanup protects `~/Projects/com.example.Editor`, permits `/Applications/Editor.app`, and still permits known user Library app data. Add tests proving broad roots are rejected while a concrete user folder is accepted.

```swift
func testProtectsArbitraryUserPathsOutsideKnownCleanupRoots() {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let policy = ProtectionPolicy(homeDirectory: home)

    XCTAssertTrue(policy.isProtected(home.appendingPathComponent("Projects/com.example.Editor")))
    XCTAssertFalse(policy.isProtected(URL(fileURLWithPath: "/Applications/Editor.app", isDirectory: true)))
}

func testRejectsBroadUserFileCleanupRoots() {
    for path in ["/", "/Users", "/Applications", "/Library", "/private", "/var"] {
        XCTAssertFalse(UserFileCleanupPolicy.accepts(root: URL(fileURLWithPath: path, isDirectory: true)))
    }
    XCTAssertTrue(UserFileCleanupPolicy.accepts(
        root: URL(fileURLWithPath: "/Users/tester/Downloads", isDirectory: true)
    ))
}
```

- [ ] **Step 5: Run policy tests and verify the expected failures**

Run: `swift test --filter 'ProtectionPolicyTests|UserFileCleanupPolicyTests'`

Expected: arbitrary paths and broad roots are currently allowed.

- [ ] **Step 6: Implement allowlisted app cleanup and validated user roots**

Store the current home directory in `ProtectionPolicy`. Permit known Library roots, temporary roots, `~/Applications`, and `.app` bundles directly under `/Applications` or its ordinary subfolders. Return protected for all other paths. In `UserFileCleanupPolicy`, filter its internal allowlist through `accepts(root:)` and block broad root paths exactly.

```swift
public static func accepts(root: URL) -> Bool {
    let path = root.resolvingSymlinksInPath().standardizedFileURL.path
    let rejected = ["/", "/Users", "/Applications", "/Library", "/System", "/bin", "/sbin", "/usr", "/private", "/var"]
    return !rejected.contains(path)
}
```

The app-bundle exception must require `pathExtension.lowercased() == "app"`; it must not allow arbitrary files under `/Applications`.

- [ ] **Step 7: Run focused and full tests**

Run: `swift test --filter 'CandidateMatcherTests|ProtectionPolicyTests|UserFileCleanupPolicyTests|DeletionExecutorTests|RelatedFileScannerTests'`

Expected: all focused suites pass with no regression in executor safety.

- [ ] **Step 8: Commit Task 1**

```bash
git add Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift Sources/MyMacCleanCore/Safety/ProtectionPolicy.swift Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift
git commit -m "fix: harden cleanup matching and path policy"
```

---

### Task 2: Add Structured Scan Results and Nested App Discovery

**Files:**
- Create: `Sources/MyMacCleanCore/Support/ScanResult.swift`
- Modify: `Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift`
- Modify: `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`
- Test: `Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift`
- Test: `Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift`

**Interfaces:**
- Produces: `ScanIssue`, `ScanResult<Value>`, `ScanIssue.from(path:error:)`, `AppDiscoveryService.discoverAppsWithCoverage()`, and `RelatedFileScanner.scanRelatedFilesWithCoverage(for:)`.
- Compatibility: `discoverApps()` and `scanRelatedFiles(for:)` return the `.value` from the structured methods.

- [ ] **Step 1: Write failing scan-model and nested discovery tests**

Add tests for recursive discovery, package-descendant skipping, resolved-path deduplication, and metadata failures reported without dropping valid apps.

```swift
func testDiscoversNestedAppsButSkipsEmbeddedHelpers() async throws {
    let root = try TestFixtures.temporaryDirectory(named: "nested-discovery")
    let nested = root.appendingPathComponent("Vendor", isDirectory: true)
    let app = try TestFixtures.makeAppBundle(root: nested, name: "Editor", bundleIdentifier: "com.example.Editor")
    _ = try TestFixtures.makeAppBundle(
        root: app.appendingPathComponent("Contents/Library/LoginItems", isDirectory: true),
        name: "Editor Helper",
        bundleIdentifier: "com.example.Editor.Helper"
    )

    let result = await AppDiscoveryService(searchRoots: [root]).discoverAppsWithCoverage()

    XCTAssertEqual(result.value.map(\.displayName), ["Editor"])
    XCTAssertTrue(result.issues.isEmpty)
}

func testReportsUnreadableOrInvalidAppsWithoutDroppingValidApps() async throws {
    let root = try TestFixtures.temporaryDirectory(named: "discovery-issues")
    _ = try TestFixtures.makeAppBundle(root: root, name: "Valid", bundleIdentifier: "com.example.Valid")
    let broken = root.appendingPathComponent("Broken.app", isDirectory: true)
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

    let result = await AppDiscoveryService(searchRoots: [root]).discoverAppsWithCoverage()

    XCTAssertEqual(result.value.map(\.displayName), ["Valid"])
    XCTAssertEqual(result.issues.map(\.path), [broken.path])
}
```

- [ ] **Step 2: Run discovery tests and verify the expected failures**

Run: `swift test --filter AppDiscoveryServiceTests`

Expected: `discoverAppsWithCoverage` does not exist and nested apps are not found by the current direct listing.

- [ ] **Step 3: Implement structured scan models**

Create immutable Sendable models. Permission classification covers Cocoa no-permission errors and POSIX `EACCES`/`EPERM`.

```swift
public struct ScanIssue: Equatable, Identifiable, Sendable {
    public var id: String { path + "\u{0}" + message }
    public let path: String
    public let message: String
    public let permissionRelated: Bool

    public static func from(path: URL, error: Error) -> ScanIssue {
        let nsError = error as NSError
        let permissionRelated =
            (nsError.domain == NSCocoaErrorDomain && [
                CocoaError.fileReadNoPermission.rawValue,
                CocoaError.fileWriteNoPermission.rawValue
            ].contains(nsError.code))
            || (nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code))
        return ScanIssue(path: path.path, message: nsError.localizedDescription, permissionRelated: permissionRelated)
    }
}

public struct ScanResult<Value: Sendable>: Sendable {
    public let value: Value
    public let issues: [ScanIssue]
}
```

- [ ] **Step 4: Implement nested discovery with coverage**

Use `FileManager.enumerator` with `.skipsHiddenFiles` and an error handler that appends issues. When an `.app` URL is encountered, call `skipDescendants()`, read metadata, and append either the app or an issue. Deduplicate by resolved standardized path before sorting.

Keep `discoverApps() async throws -> [InstalledApp]` as:

```swift
public func discoverApps() async throws -> [InstalledApp] {
    await discoverAppsWithCoverage().value
}
```

- [ ] **Step 5: Write failing related-scan coverage tests**

Update the unreadable-root fixture to call `scanRelatedFilesWithCoverage(for:)` and assert both the valid cache candidate and an issue for the unreadable root. Assert the compatibility method still returns candidates.

```swift
let result = await scanner.scanRelatedFilesWithCoverage(for: app)
XCTAssertTrue(result.value.contains { $0.url == cache })
XCTAssertTrue(result.issues.contains { $0.path == unreadableRoot.path })
```

- [ ] **Step 6: Run related scanner tests and verify the expected failure**

Run: `swift test --filter RelatedFileScannerTests`

Expected: the structured method does not exist and `try?` currently discards the listing error.

- [ ] **Step 7: Implement related-file coverage**

Replace `childURLs(in:) -> [URL]` with a helper returning `Result<[URL], Error>`. `scanRelatedFilesWithCoverage` collects failures and still returns the app-bundle candidate plus successful roots. Deduplicate issues by `id`, preserve deterministic path order, and keep `scanRelatedFiles(for:)` as a `.value` wrapper.

- [ ] **Step 8: Run focused tests and commit Task 2**

Run: `swift test --filter 'AppDiscoveryServiceTests|RelatedFileScannerTests|Scan'`

```bash
git add Sources/MyMacCleanCore/Support/ScanResult.swift Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift
git commit -m "feat: report scan coverage and discover nested apps"
```

---

### Task 3: Extend Coverage Reporting to Remaining Scanners and View Models

**Files:**
- Modify: `Sources/MyMacCleanCore/Orphans/OrphanFileScanner.swift`
- Modify: `Sources/MyMacCleanCore/LargeFiles/LargeFileScanner.swift`
- Modify: `Sources/MyMacCleanCore/DeveloperCache/DeveloperCacheScanner.swift`
- Modify: `Sources/MyMacCleanCore/StartupItems/StartupItemScanner.swift`
- Modify: `Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/OrphanFilesViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/DeveloperCacheViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/StartupItemsViewModel.swift`
- Test: scanner and view-model test files matching the modified types.

**Interfaces:**
- Each scanner produces `scanWithCoverage() -> ScanResult<[Candidate]>` while its existing `scan()` remains a value wrapper.
- Each view model produces one or two public `[ScanIssue]` properties representing the active screen's latest scan.

- [ ] **Step 1: Write failing scanner coverage tests**

For each scanner, add one fixture where one existing root or item cannot be read and another succeeds. Assert usable values remain and the issue path is present. For Startup Items, use one valid plist and one malformed plist; for Developer Cache, inject a target directory whose size enumeration fails.

```swift
let result = await OrphanFileScanner(homeDirectory: home, installedApps: []).scanWithCoverage()
XCTAssertEqual(result.value.first?.inferredIdentifier, "com.example.Valid")
XCTAssertTrue(result.issues.contains { $0.path == unreadablePreferences.path })
```

Large Files' enumerator error handler must append descendant-level errors instead of returning `true` without evidence.

- [ ] **Step 2: Run the four core scanner suites and verify failures**

Run: `swift test --filter 'OrphanFileScannerTests|LargeFileScannerTests|DeveloperCacheScannerTests|StartupItemScannerTests'`

Expected: each new structured method or issue assertion fails against the current silent-skip implementation.

- [ ] **Step 3: Implement coverage in each scanner**

Use the same rules everywhere:

- missing optional roots produce no issue;
- an existing root that cannot be listed produces one root issue;
- an unreadable item produces an item issue and does not stop siblings;
- a size-calculation failure records an issue and does not report a misleading zero-byte candidate;
- issues are deduplicated and sorted by path;
- compatibility `scan()` methods return `.value`.

- [ ] **Step 4: Write failing view-model state tests**

Add these Sendable scanner clients instead of constructing core scanners
inside view-model methods:

```swift
public struct ApplicationDiscovering: Sendable {
    public let discover: @Sendable () async -> ScanResult<[InstalledApp]>
}

public struct RelatedFileScanning: Sendable {
    public let scan: @Sendable (InstalledApp) async -> ScanResult<[RelatedFileCandidate]>
}

public struct OrphanFileScanning: Sendable {
    public let scan: @Sendable ([InstalledApp]) async -> ScanResult<[OrphanFileGroup]>
}

public struct LargeFileScanning: Sendable {
    public let scan: @Sendable ([URL], Int64, Bool) async -> ScanResult<[LargeFileCandidate]>
}

public struct DeveloperCacheScanning: Sendable {
    public let scan: @Sendable () async -> ScanResult<[DeveloperCacheCandidate]>
}

public struct StartupItemScanning: Sendable {
    public let scan: @Sendable () async -> ScanResult<[StartupItem]>
}
```

Each client has a `.live` factory that captures the same constructor arguments
currently held by its view model. Tests inject deterministic clients. Tests
must prove issues replace old issues on scan, clear when the next scan is
complete, and coexist with usable results.

```swift
XCTAssertEqual(viewModel.candidates.count, 1)
XCTAssertEqual(viewModel.scanIssues, [issue])
await viewModel.scan()
XCTAssertTrue(viewModel.scanIssues.isEmpty)
```

`ApplicationListViewModel` uses `applicationDiscoveryIssues` for app loading and `relatedFileScanIssues` for the selected app scan. Other view models use `scanIssues`.

- [ ] **Step 5: Run view-model tests and verify failures**

Run: `swift test --filter 'ApplicationListViewModelTests|OrphanFilesViewModelTests|LargeFilesViewModelTests|DeveloperCacheViewModelTests|StartupItemsViewModelTests'`

Expected: issue state and injectable scan clients do not exist.

- [ ] **Step 6: Implement scanner clients and issue state**

Implement the six scanner clients with the exact signatures from Step 4. The
live closures construct core scanners. View models clear stale values before
scanning, then assign `result.value` and `result.issues` independently.

- [ ] **Step 7: Run all scanner and view-model tests**

Run: `swift test --filter 'ScannerTests|ViewModelTests'`

Expected: all modified scanner and view-model suites pass.

- [ ] **Step 8: Commit Task 3**

```bash
git add Sources/MyMacCleanCore/Orphans Sources/MyMacCleanCore/LargeFiles Sources/MyMacCleanCore/DeveloperCache Sources/MyMacCleanCore/StartupItems Sources/MyMacCleanAppSupport Tests/MyMacCleanCoreTests Tests/MyMacCleanAppSupportTests
git commit -m "feat: surface partial scan results across cleaners"
```

---

### Task 4: Add the Native Scan Coverage Banner

**Files:**
- Create: `Sources/MyMacCleanAppSupport/ScanCoveragePresentation.swift`
- Create: `Tests/MyMacCleanAppSupportTests/ScanCoveragePresentationTests.swift`
- Modify: `Sources/MyMacCleanApp/Views/Components.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`

**Interfaces:**
- Produces: `ScanCoveragePresentation`, reusable `ScanCoverageBanner`, copy-details callback, and Full Disk Access callback.
- Consumes: issue state created in Task 3 and existing settings URL helpers.

- [ ] **Step 1: Write failing presentation tests**

```swift
func testCoveragePresentationSummarizesAndSortsIssues() {
    let presentation = ScanCoveragePresentation(issues: [permissionIssue, corruptIssue])

    XCTAssertEqual(presentation.title, "Scan incomplete")
    XCTAssertEqual(presentation.summary, "2 locations could not be inspected.")
    XCTAssertTrue(presentation.showsFullDiskAccessAction)
    XCTAssertEqual(presentation.detailLines, presentation.detailLines.sorted())
}
```

Also test singular copy and that a non-permission issue does not show the settings action.

- [ ] **Step 2: Run the presentation test and verify failure**

Run: `swift test --filter ScanCoveragePresentationTests`

Expected: the presentation type does not exist.

- [ ] **Step 3: Implement the presentation model**

Map issues into title, singular/plural summary, deterministic detail lines in `path - message` form, and `showsFullDiskAccessAction`.

- [ ] **Step 4: Implement `ScanCoverageBanner`**

Use an unframed amber-tinted band, `DisclosureGroup`, selectable monospaced full paths, icon-only Copy Details button with tooltip, and an `Open Full Disk Access` button only when requested. Keep text at callout/caption sizes and use an 8-point corner radius.

- [ ] **Step 5: Wire the banner into every active workflow**

- Applications list: discovery issues below the toolbar.
- Applications inspector: related-file issues above candidates.
- Orphan Files, Large Files, Developer Cache, Startup Items: issue banner between toolbar and result list.

Do not route partial issues through `currentErrorMessage`; modal alerts remain for operation-stopping errors.

- [ ] **Step 6: Build and visually inspect both normal and fixture issue states**

Run: `swift build`

Use an inaccessible disposable Large Files fixture root to produce a real issue
state in the running app. Verify long paths wrap or truncate without
overlapping controls at narrow and wide window widths. Do not commit a
test-only production code path.

- [ ] **Step 7: Run all tests and commit Task 4**

Run: `swift test`

```bash
git add Sources/MyMacCleanAppSupport/ScanCoveragePresentation.swift Sources/MyMacCleanApp/Views/Components.swift Sources/MyMacCleanApp/Views/ContentView.swift Tests/MyMacCleanAppSupportTests/ScanCoveragePresentationTests.swift
git commit -m "feat: show incomplete scan coverage"
```

---

### Task 5: Add Trash-Only App Reset

**Files:**
- Modify: `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`
- Modify: `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift`
- Modify: `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`
- Create: `Sources/MyMacCleanAppSupport/ApplicationCleanupMode.swift`
- Modify: `Sources/MyMacCleanAppSupport/ApplicationListViewModel.swift`
- Modify: `Sources/MyMacCleanAppSupport/DeletionHistoryReceiptSummary.swift`
- Modify: `Sources/MyMacCleanAppSupport/DeletionReportViewModel.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: corresponding core and app-support test files.

**Interfaces:**
- `DeletionExecutor.execute(..., requiredConfirmation: String = "DELETE")`.
- `DeletionAction.appReset`.
- `ApplicationCleanupMode.uninstall` and `.resetData`.
- `ApplicationListViewModel.resetSelectedData(confirmation:)`.

- [ ] **Step 1: Write failing executor confirmation tests**

```swift
func testExecutorSupportsOperationSpecificConfirmation() async throws {
    let result = await executor.execute(
        plan: plan,
        confirmation: "DELETE",
        mode: .moveToTrash,
        requiredConfirmation: "RESET"
    )

    XCTAssertEqual(result.first?.errorMessage, DeletionExecutionErrorMessage.confirmationMismatch)
    XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.path))
}
```

Add the matching `RESET` success assertion and verify the existing default still requires `DELETE`.

- [ ] **Step 2: Run executor tests and verify failure**

Run: `swift test --filter DeletionExecutorTests`

Expected: the `requiredConfirmation` argument does not exist.

- [ ] **Step 3: Implement operation-specific confirmation**

Add the defaulted argument after `mode` and compare against it before mapping candidates. Preserve `requiredConfirmationPhrase(for:)` as the default source for existing callers.

- [ ] **Step 4: Write failing App Reset view-model tests**

Tests must prove:

- reset candidates exclude `.appBundle`;
- protected items cannot enter the plan;
- a running app blocks reset;
- `DELETE` fails while `RESET` succeeds;
- verified data paths disappear, the app remains selected, and a rescan occurs;
- receipt action is `.appReset` and the app bundle remains on disk;
- receipt-write failure does not hide a verified reset result.

```swift
let report = await viewModel.resetSelectedData(confirmation: "RESET")

XCTAssertEqual(report?.receipt.action, .appReset)
XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
XCTAssertEqual(viewModel.selectedApp?.bundleURL, appURL)
```

- [ ] **Step 5: Run ApplicationListViewModel tests and verify failures**

Run: `swift test --filter ApplicationListViewModelTests`

Expected: cleanup mode and reset operation do not exist.

- [ ] **Step 6: Implement reset planning, execution, reconciliation, and receipts**

`ApplicationCleanupMode` supplies the visible title and confirmation phrase. In reset mode, selection helpers ignore `.appBundle`. `resetSelectedData` blocks running apps, builds a plan from non-bundle candidates, calls the executor with `.moveToTrash` and `RESET`, verifies, appends an `.appReset` receipt, removes only verified data paths, and calls the injected related scanner again while retaining `selectedApp`.

- [ ] **Step 7: Add history and toast presentation tests**

Assert `.appReset` displays `App Data Reset`, uses changed/deleted counts consistently, includes expandable path-level errors, and remains searchable by app/path.

- [ ] **Step 8: Implement the Applications UI**

Add a segmented `Picker` for Uninstall / Reset Data after a scan. Reset mode hides the app-bundle checkbox, changes helper copy, uses `RESET`, hides permanent/force controls, and labels the destructive button `Move App Data to Trash`. Add a distinct confirmation enum case so asynchronous completion cannot read the wrong mode.

- [ ] **Step 9: Run focused and full tests, then commit Task 5**

Run: `swift test --filter 'DeletionExecutorTests|ApplicationListViewModelTests|DeletionHistoryReceiptSummaryTests|DeletionReportViewModelTests|DeleteHistoryViewModelTests'`

Run: `swift test`

```bash
git add Sources/MyMacCleanCore Sources/MyMacCleanAppSupport Sources/MyMacCleanApp/Views/ContentView.swift Tests
git commit -m "feat: add safe app data reset"
```

---

### Task 6: Add User-Selected Large Files Folder and Recursive Toggle

**Files:**
- Modify: `Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: `Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift`
- Test: `Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift`

**Interfaces:**
- `LargeFilesViewModel.activeScanRoot: URL`.
- `LargeFilesViewModel.includeSubfolders: Bool`.
- `LargeFilesViewModel.setScanRoot(_:) -> Bool`.
- Existing `scan()` uses the active root and recursion state.

- [ ] **Step 1: Write failing root-change and recursion tests**

```swift
func testChangingScanRootClearsStaleResultsAndSelection() async throws {
    let viewModel = LargeFilesViewModel(scanRoots: [firstRoot], minimumSize: 1)
    await viewModel.scan()
    viewModel.selectedCandidateIDs = Set(viewModel.candidates.map(\.id))

    XCTAssertTrue(viewModel.setScanRoot(secondRoot))
    XCTAssertEqual(viewModel.activeScanRoot, secondRoot)
    XCTAssertTrue(viewModel.candidates.isEmpty)
    XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
    XCTAssertFalse(viewModel.hasScanned)
}

func testRejectsBroadRootWithoutReplacingCurrentRoot() {
    let viewModel = LargeFilesViewModel(scanRoots: [downloads])

    XCTAssertFalse(viewModel.setScanRoot(URL(fileURLWithPath: "/", isDirectory: true)))
    XCTAssertEqual(viewModel.activeScanRoot, downloads)
    XCTAssertNotNil(viewModel.errorMessage)
}
```

Add a view-model scan test showing a nested fixture appears only when `includeSubfolders` is true.

- [ ] **Step 2: Run Large Files tests and verify failures**

Run: `swift test --filter 'LargeFileScannerTests|LargeFilesViewModelTests'`

Expected: active root, root validation, and recursion state do not exist.

- [ ] **Step 3: Implement active-root state and dynamic protection**

Keep the initializer source-compatible by selecting the first configured root or the default Downloads root. `setScanRoot` validates with `UserFileCleanupPolicy.accepts(root:)`, clears stale scan state only after validation succeeds, and does nothing on cancellation because cancellation never calls it.

When no custom executor was injected, create the executor at deletion time from the current active root:

```swift
private var activeExecutor: DeletionExecutor {
    executorOverride ?? DeletionExecutor(
        deletionProtectionPolicy: UserFileCleanupPolicy(
            allowedRoots: [activeScanRoot]
        ).deletionProtectionPolicy
    )
}
```

Call `LargeFileScanner(roots: [activeScanRoot], minimumSize: minimumSize, recursive: includeSubfolders)` through the injected scanner client.

- [ ] **Step 4: Add the native folder chooser and recursive toggle**

Use `NSOpenPanel` configured with `canChooseDirectories = true`, `canChooseFiles = false`, `allowsMultipleSelection = false`, and `canCreateDirectories = false`. On `.OK`, pass the first URL to `setScanRoot` and start a scan only when accepted.

Display the active path with middle truncation, a folder icon button with `Choose Scan Folder` tooltip, and a checkbox-style `Include Subfolders` toggle. Changing the toggle invalidates previous results and does not scan automatically until the user chooses Scan Large Files.

- [ ] **Step 5: Run focused tests and build**

Run: `swift test --filter 'LargeFileScannerTests|LargeFilesViewModelTests|UserFileCleanupPolicyTests'`

Run: `swift build`

Expected: tests and build pass.

- [ ] **Step 6: Commit Task 6**

```bash
git add Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift Sources/MyMacCleanApp/Views/ContentView.swift Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift
git commit -m "feat: choose large file scan folder"
```

---

### Task 7: Documentation, Runtime QA, and Release Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-03-mymacclean-personal-cleaner-design.md`
- Modify: `docs/superpowers/README.md`

**Interfaces:**
- No production API. Produces current user-facing and maintainer documentation.

- [ ] **Step 1: Update current documentation**

Document bounded matching, fail-closed roots, coverage warnings, nested app discovery, App Reset, `RESET`, user-selected Large Files folders, non-persistence, recursive default off, and Trash-only restrictions. Mark older conflicting statements as historical instead of silently leaving them current.

- [ ] **Step 2: Run the complete automated verification**

Run: `swift test`

Expected: all tests pass with 0 failures.

Run: `swift build -c release`

Expected: release build exits 0.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 3: Build and verify personal distribution artifacts**

Run: `./scripts/create-dmg.sh`

Run: `codesign --verify --deep --strict --verbose=2 dist/MyMacClean.app`

Run: `hdiutil verify dist/MyMacClean-dev.dmg`

Expected: app signature is valid for the ad-hoc personal build and the DMG checksum is valid.

- [ ] **Step 4: Run real app smoke and interaction checks**

Launch `dist/MyMacClean.app` and verify:

- Applications loads and refreshes without stale detail;
- coverage banner expands, copies details, and opens the expected settings page;
- App Reset switches mode, excludes the bundle, requires `RESET`, keeps the disposable fixture app, clears deleted data rows, and writes history;
- Large Files folder selection and recursive toggle work with disposable fixtures;
- narrow-window text and controls do not overlap;
- no startup, scan, confirmation, toast, history, or navigation regression appears.

Use only disposable fixture files and move them to Trash; do not delete real user applications or empty Trash.

- [ ] **Step 5: Review the complete diff against the design**

Check every acceptance criterion in `docs/superpowers/specs/2026-08-13-mymacclean-safety-and-utility-expansion-design.md`. Review safety boundaries, error handling, tests, UI copy, and documentation. A review finding that changes behavior starts a new failing test and is committed with the owning task's exact file set before the documentation commit.

- [ ] **Step 6: Commit documentation and final QA adjustments**

```bash
git add README.md docs/superpowers/README.md docs/superpowers/specs/2026-07-03-mymacclean-personal-cleaner-design.md
git commit -m "docs: document safety and utility expansion"
```

- [ ] **Step 7: Confirm final repository state**

Run: `git status --short --branch`

Expected: clean working tree on the active branch with all implementation commits present.
