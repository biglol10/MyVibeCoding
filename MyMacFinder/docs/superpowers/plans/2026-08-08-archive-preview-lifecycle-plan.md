# Archive Preview Lifecycle And Responsiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent ZIP preview temporary-file leaks, surface default-open failures, and cancel obsolete preview work without changing existing file-manager behavior.

**Architecture:** `ArchiveBrowsingService` returns owned temporary artifacts and delegates allocation, identity validation, retention, and cleanup to a dedicated actor. `ExplorerStore` treats Quick Look preparation as a transaction, retains successful external-open artifacts for 24 hours, and rejects stale preview completions. Quick Look and thumbnail generation receive explicit one-shot cancellation and release boundaries.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Foundation, QuickLook, QuickLookThumbnailing, XCTest, Swift Package Manager, ZIPFoundation 0.9.x, macOS 15+

## Global Constraints

- Keep macOS 15 as the minimum deployment target and Swift tools version 6.1.
- Do not update or add package dependencies.
- Do not change ZIP browsing, archive editing, pane, tab, search, sort, or file-operation features.
- Never clean temporary files created by another application or arbitrary contents of the system temporary directory.
- Every file-changing test must use a UUID-named directory below `FileManager.default.temporaryDirectory` and remove only that exact directory.
- Quick Look artifacts are released on panel close, replacement, preparation failure, and cancellation.
- Successfully external-opened archive artifacts remain eligible for use for 24 hours and are cleaned on a later launch.
- A cleanup target must pass canonical-root, UUID, symlink, and filesystem-identity validation before removal.
- Cancellation must remain `CancellationError`; no cancellation banner is shown.
- Do not push automatically.

## File Structure

- Create `Sources/MyMacFinder/Services/ArchiveTemporaryArtifactStore.swift`: artifact model, UUID allocation, ownership checks, external-open registry, and expiry cleanup.
- Modify `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`: managed extraction, cancellation, and partial-output cleanup.
- Modify `Sources/MyMacFinder/Services/ExternalAppLauncher.swift`: throwing default-open contract.
- Create `Sources/MyMacFinder/Services/QuickLookPreviewSession.swift`: one-shot preview ownership.
- Modify `Sources/MyMacFinder/Services/QuickLookPreviewService.swift`: replacement and close cleanup.
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`: transactional preview preparation, stale-context guard, retention, and launch cleanup.
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`: startup expiry cleanup.
- Modify `Sources/MyMacFinder/UI/FilePreviewThumbnailLoader.swift`: injectable thumbnail generator and request cancellation.
- Create `Sources/MyMacFinder/UI/FileEntryIconResolver.swift`: metadata-only fallback icon resolution.
- Modify `Sources/MyMacFinder/UI/FileTableView.swift` and `Sources/MyMacFinder/UI/FilePreviewView.swift`: shared icon resolver.
- Add focused XCTest coverage, update `README.md`, and create `docs/qa/2026-08-08-archive-preview-lifecycle-verification.md`.

---

### Task 1: Owned ZIP Extraction Artifacts

**Files:**
- Create: `Sources/MyMacFinder/Services/ArchiveTemporaryArtifactStore.swift`
- Modify: `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`
- Modify: `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`
- Create: `Tests/MyMacFinderTests/ArchiveTemporaryArtifactStoreTests.swift`
- Modify: archive-browser doubles found by `rg -l 'temporaryExtract' Tests/MyMacFinderTests`

**Interfaces:**
- Produces: `TemporaryArchiveArtifact`, `ArchiveTemporaryArtifactStore`, and managed lifecycle methods on `ArchiveBrowsing`.
- Consumes: `FileSystemPathIdentity.entryIdentity(_:)`, `ArchivePathSafety`, and ZIPFoundation extraction progress.

- [ ] **Step 1: Write failing managed-extraction and release tests**

Add this core regression and companion tests for replaced identity, escaping owner symlink, extraction failure, and cancellation:

```swift
func testTemporaryExtractReturnsOwnedArtifactAndReleaseRemovesOnlyOwnerDirectory() async throws {
    let archiveURL = try makeArchive()
    let root = tempDirectory.appendingPathComponent("preview-root", isDirectory: true)
    let sentinel = root.appendingPathComponent("unrelated.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: sentinel)
    let service = ArchiveBrowsingService(extractionRoot: root)

    let artifact = try await service.temporaryExtract(
        ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
    )
    XCTAssertEqual(try String(contentsOf: artifact.url, encoding: .utf8), "hello")
    try await service.releaseTemporaryArtifact(artifact)

    XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.ownerDirectoryURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
}
```

Required test names:

```swift
testReleaseRejectsArtifactWhoseOwnerDirectoryWasReplaced()
testReleaseRejectsOwnerSymlinkEscapingExtractionRoot()
testExtractionFailureRemovesPartialOwnerDirectory()
testCancelledExtractionRethrowsCancellationErrorAndRemovesPartialOwnerDirectory()
```

The cancellation test injects an extraction hook that blocks until its `Progress` is cancelled, then throws. It asserts `CancellationError` and no artifact directory remains.

- [ ] **Step 2: Run the focused tests and confirm failure**

```bash
swift test --filter ArchiveBrowsingServiceTests
swift test --filter ArchiveTemporaryArtifactStoreTests
```

Expected: compilation or assertion failure because extraction still returns a bare URL and has no release contract.

- [ ] **Step 3: Add the owned artifact model and store actor**

Implement these shapes:

```swift
public struct TemporaryArchiveArtifact: Equatable, Sendable {
    public let url: URL
    let ownerDirectoryURL: URL
    let ownerIdentifier: UUID
    let expectedOwnerIdentity: FileSystemPathIdentity.FileSystemEntryIdentity
}

actor ArchiveTemporaryArtifactStore {
    init(fileManager: FileManager = .default, extractionRoot: URL)
    func allocate(fileName: String, identifier: UUID = UUID()) throws -> TemporaryArchiveArtifact
    func release(_ artifact: TemporaryArchiveArtifact) throws
    func registerExternalOpen(_ artifact: TemporaryArchiveArtifact, openedAt: Date) throws
    func cleanupExpired(now: Date, retentionInterval: TimeInterval) throws
}
```

`allocate` creates `canonicalRoot/<UUID>/<sanitized leaf>`, captures the owner directory `lstat` identity, and rejects `/`, `.`, and `..` as filenames. `release` requires an immediate UUID child, a non-symlink directory, canonical containment, and unchanged identity before removing the exact owner directory.

- [ ] **Step 4: Change archive extraction to return and clean managed artifacts**

Change the protocol to:

```swift
public protocol ArchiveBrowsing: Sendable {
    func canOpen(_ url: URL) -> Bool
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry]
    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact
    func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws
    func retainTemporaryArtifactForExternalOpen(_ artifact: TemporaryArchiveArtifact, openedAt: Date) async throws
    func cleanupExpiredTemporaryArtifacts(now: Date, retentionInterval: TimeInterval) async throws
}
```

Provide no-op defaults for the three lifecycle methods so navigation-only doubles remain concise. `temporaryExtract` must allocate first, bridge task cancellation to ZIPFoundation `Progress`, normalize cancelled extraction to `CancellationError`, and release the artifact in every error path. If release also fails, throw `.operationFailed` containing both failures and the exact owner path.

- [ ] **Step 5: Run the focused lifecycle tests**

```bash
swift test --filter ArchiveBrowsingServiceTests
swift test --filter ArchiveTemporaryArtifactStoreTests
```

Expected: all pass and no UUID test artifact remains after teardown.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/MyMacFinder/Services/ArchiveTemporaryArtifactStore.swift Sources/MyMacFinder/Services/ArchiveBrowsingService.swift Tests/MyMacFinderTests
git commit -m "fix: manage archive preview artifacts"
```

### Task 2: Throwing Default Open And 24-Hour Retention

**Files:**
- Modify: `Sources/MyMacFinder/Services/ExternalAppLauncher.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `Tests/MyMacFinderTests/ExternalAppLauncherTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerStorePathInputCommandTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- Modify: `Tests/MyMacFinderTests/ArchiveTemporaryArtifactStoreTests.swift`

**Interfaces:**
- Consumes: Task 1's artifact lifecycle.
- Produces: `ExternalAppLaunching.openDefault(_:) throws` and `ExplorerStore.cleanupExpiredArchiveArtifacts(now:) async`.

- [ ] **Step 1: Add failing launcher and retention tests**

```swift
func testOpenDefaultThrowsWhenWorkspaceRejectsURL() {
    let workspace = DefaultOpenWorkspaceOpener(result: false)
    let launcher = AppKitExternalAppLauncher(workspace: workspace)
    let file = URL(fileURLWithPath: "/tmp/unopenable.fixture")

    XCTAssertThrowsError(try launcher.openDefault(file)) { error in
        XCTAssertEqual(
            error as? ExplorerError,
            .externalCommandFailed("No application could open: /tmp/unopenable.fixture")
        )
    }
}
```

Also add exact tests for unexpired retention, the 24-hour boundary, missing artifacts, corrupt registry preservation, archive-open failure cleanup, archive-open success registration before launch, path-command failure presentation, and startup cleanup that does not prevent initial listing. Use fixed `Date` values and `24 * 60 * 60`; never sleep.

- [ ] **Step 2: Run focused tests and confirm failure**

```bash
swift test --filter ExternalAppLauncherTests
swift test --filter ArchiveTemporaryArtifactStoreTests
swift test --filter ExplorerArchiveCommandTests
swift test --filter ExplorerStorePathInputCommandTests
```

Expected: default open is nonthrowing and no durable retention or startup cleanup exists.

- [ ] **Step 3: Implement throwing default open**

```swift
@MainActor
public protocol ExternalAppLaunching: AnyObject {
    func openDefault(_ url: URL) throws
    func open(_ urls: [URL], with application: OpenWithApplication) async throws
    func openTerminal(at directory: URL) async throws
    func openVSCode(at target: URL) async throws
    func applications(toOpen url: URL) -> [OpenWithApplication]
}

public func openDefault(_ url: URL) throws {
    let target = url.standardizedFileURL
    guard workspace.open(target) else {
        throw ExplorerError.externalCommandFailed("No application could open: \(target.path)")
    }
}
```

Update every launcher double to declare `throws` and support an injected error.

- [ ] **Step 4: Wire retention and launch cleanup**

For archive files, perform this exact order: extract, register with the current date, then default-open. On registration or open failure, release the exact artifact and present the original error plus any cleanup failure. Normal files and path commands call `try openDefault` inside existing error handling.

Add:

```swift
public func cleanupExpiredArchiveArtifacts(now: Date = Date()) async {
    do {
        try await archiveBrowser.cleanupExpiredTemporaryArtifacts(
            now: now,
            retentionInterval: 24 * 60 * 60
        )
    } catch {
        present(.operationFailed("Temporary preview cleanup failed: \(error.localizedDescription)"))
    }
}
```

Call cleanup before `loadInitialDirectory()` from the root app task. A cleanup failure may be shown but must not block listing.

- [ ] **Step 5: Run focused tests**

```bash
swift test --filter ExternalAppLauncherTests
swift test --filter ArchiveTemporaryArtifactStoreTests
swift test --filter ExplorerArchiveCommandTests
swift test --filter ExplorerStorePathInputCommandTests
```

Expected: all pass, including exact expiry and corrupt-data preservation.

- [ ] **Step 6: Commit Task 2**

```bash
git add Sources/MyMacFinder/Services/ExternalAppLauncher.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Tests/MyMacFinderTests
git commit -m "fix: retain externally opened archive files"
```

### Task 3: Transactional Quick Look Sessions

**Files:**
- Create: `Sources/MyMacFinder/Services/QuickLookPreviewSession.swift`
- Modify: `Sources/MyMacFinder/Services/QuickLookPreviewService.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Create: `Tests/MyMacFinderTests/QuickLookPreviewSessionTests.swift`
- Modify: `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`

**Interfaces:**
- Consumes: Task 1's `TemporaryArchiveArtifact` and release method.
- Produces: `QuickLookPreviewSession` and `QuickLooking.preview(_:) throws`.

- [ ] **Step 1: Add failing one-shot and transactional tests**

```swift
@MainActor
func testReleaseRunsExactlyOnce() {
    var releaseCount = 0
    let session = QuickLookPreviewSession(urls: [URL(fileURLWithPath: "/tmp/a")]) {
        releaseCount += 1
    }

    session.release()
    session.release()

    XCTAssertEqual(releaseCount, 1)
}
```

Add session-owner tests for replacement and panel close. Add Explorer regressions with these exact names:

```swift
testQuickLookDoesNotExtractWhenServiceIsUnavailable()
testQuickLookLaterExtractionFailureReleasesEarlierArtifactsInReverseOrder()
testQuickLookPresentationFailureReleasesPreparedArtifacts()
testQuickLookCancellationReleasesPreparedArtifactsWithoutVisibleError()
testQuickLookCompletionAfterContextChangeDoesNotPresentAndReleasesArtifacts()
testQuickLookCompletionDoesNotChangeSearchContext()
```

The stale-context test uses a suspended archive-browser double. Capture the original tab ID, pane ID, pane location, selected URLs, search scope, ordinary query, and explicit tag query; change context while suspended; resume; assert no preview and exact artifact release.

- [ ] **Step 2: Run focused tests and confirm failure**

```bash
swift test --filter QuickLookPreviewSessionTests
swift test --filter ExplorerArchiveCommandTests
```

Expected: Quick Look accepts only URLs, partial extraction is not rolled back, and stale context is not checked.

- [ ] **Step 3: Implement a one-shot preview session**

```swift
@MainActor
public final class QuickLookPreviewSession {
    public let urls: [URL]
    private var releaseAction: (@MainActor @Sendable () -> Void)?

    public init(urls: [URL], release: @escaping @MainActor @Sendable () -> Void) {
        self.urls = urls
        self.releaseAction = release
    }

    public func release() {
        let action = releaseAction
        releaseAction = nil
        action?()
    }
}
```

Change `QuickLooking` to `func preview(_ session: QuickLookPreviewSession) throws`. `QuickLookPreviewService` releases the current session before replacement, calls `release()` from `previewPanelWillClose(_:)`, clears panel ownership on close, and never retains a failed session.

- [ ] **Step 4: Make Explorer preview preparation transactional and context-safe**

Capture a private context containing active tab ID, pane ID, pane location, selected URL set, search scope, ordinary query, and explicit tag query before the first extraction. Build URLs and managed artifacts in selection order inside one `do/catch`. On error or cancellation, release in reverse order. Before presenting, require every captured value to match; otherwise release and return without a banner.

The session release action starts one cleanup task that releases artifacts in reverse order. If `quickLookService` is `nil`, return before extraction. If `preview(session)` throws, call `session.release()` before rethrowing.

- [ ] **Step 5: Run focused search and Quick Look tests**

```bash
swift test --filter QuickLookPreviewSessionTests
swift test --filter ExplorerArchiveCommandTests
swift test --filter ExplorerSearchStoreTests
swift test --filter ExplorerAdvancedSearchStoreTests
```

Expected: all pass and preview success, failure, cancellation, and stale completion leave search context unchanged.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/MyMacFinder/Services/QuickLookPreviewSession.swift Sources/MyMacFinder/Services/QuickLookPreviewService.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests
git commit -m "fix: make Quick Look sessions transactional"
```

### Task 4: Cancel Obsolete Thumbnails And Remove Path-Based Icon Lookup

**Files:**
- Modify: `Sources/MyMacFinder/UI/FilePreviewThumbnailLoader.swift`
- Create: `Sources/MyMacFinder/UI/FileEntryIconResolver.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/UI/FilePreviewView.swift`
- Modify: `Tests/MyMacFinderTests/FilePreviewThumbnailLoaderTests.swift`
- Create: `Tests/MyMacFinderTests/FileEntryIconResolverTests.swift`

**Interfaces:**
- Produces: `FilePreviewThumbnailGenerating`, `FilePreviewThumbnailRequest`, and `FileEntryIconResolver.icon(for:size:)`.
- Consumes: `QLThumbnailGenerator.generateBestRepresentation` and its request cancellation API.

- [ ] **Step 1: Add failing cancellation and icon tests**

```swift
func testCancellingLoadCancelsGeneratorRequestAndReturnsPromptly() async {
    let generator = ControlledThumbnailGenerator()
    let task = Task {
        await FilePreviewThumbnailLoader.loadPreviewImage(
            for: URL(fileURLWithPath: "/tmp/large.pdf"),
            scale: 1,
            generator: generator
        )
    }
    await generator.waitUntilStarted()

    task.cancel()
    let result = await task.value

    XCTAssertNil(result.image)
    XCTAssertEqual(await generator.cancelledRequestIDs, await generator.startedRequestIDs)
}
```

Add a late-completion-after-cancellation test to prove one-shot continuation behavior. Add resolver tests for folder, package, symlink, known extension, and extensionless file using an injected content-type icon provider; assert the provider receives a `UTType`, never a path.

- [ ] **Step 2: Run focused tests and confirm failure**

```bash
swift test --filter FilePreviewThumbnailLoaderTests
swift test --filter FileEntryIconResolverTests
```

Expected: generator injection, real cancellation, and a shared metadata resolver do not yet exist.

- [ ] **Step 3: Implement cancellable thumbnail generation**

```swift
struct FilePreviewThumbnailRequest: Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: CGSize
    let scale: CGFloat
}

protocol FilePreviewThumbnailGenerating: Sendable {
    func generate(
        _ request: FilePreviewThumbnailRequest,
        completion: @escaping @Sendable (NSImage?) -> Void
    )
    func cancel(_ request: FilePreviewThumbnailRequest)
}
```

The live client keeps a lock-protected UUID-to-`QLThumbnailGenerator.Request` map, removes requests on completion, and invokes generator cancellation when requested. The loader uses `withTaskCancellationHandler` and a lock-protected one-shot continuation state so cancellation cancels the underlying work and promptly returns a nil image even if Quick Look never calls completion. Ignore late completion.

- [ ] **Step 4: Add and reuse metadata-only icon resolution**

Create:

```swift
@MainActor
static func icon(for entry: FileEntry, size: NSSize) -> NSImage
```

Resolve from `FileEntry.kind`, `fileExtension`, and `UTType(filenameExtension:)`; never call `NSWorkspace.icon(forFile:)`. Make the table use `16x16` and the preview use `64x64`. Keep existing preview policy and the 120 ms debounce.

- [ ] **Step 5: Run focused tests and the path-lookup scan**

```bash
swift test --filter FilePreviewThumbnailLoaderTests
swift test --filter FileEntryIconResolverTests
rg -n 'icon\(forFile:' Sources/MyMacFinder
```

Expected: focused tests pass and the scan prints no preview or table path-based icon lookup.

- [ ] **Step 6: Commit Task 4**

```bash
git add Sources/MyMacFinder/UI Tests/MyMacFinderTests/FilePreviewThumbnailLoaderTests.swift Tests/MyMacFinderTests/FileEntryIconResolverTests.swift
git commit -m "fix: cancel stale preview thumbnail work"
```

### Task 5: Documentation, Review, Full Verification, And Release

**Files:**
- Modify: `README.md`
- Create: `docs/qa/2026-08-08-archive-preview-lifecycle-verification.md`
- Review: every production and test file changed in Tasks 1-4

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified release app, personal ZIP, QA evidence, and final documentation commit.

- [ ] **Step 1: Run the full automated verification gate**

```bash
xcode-select -p
xcodebuild -version
xcrun --find xctest
swift build -Xswiftc -warnings-as-errors
swift test --enable-code-coverage
git diff --check
```

Expected: full Xcode tools are selected, every command exits 0, and XCTest reports zero failures.

- [ ] **Step 2: Independently review the complete implementation diff**

```bash
rg -n 'try!|as!|fatalError|catch\s*\{\s*\}|try\?' Sources/MyMacFinder/Services/ArchiveTemporaryArtifactStore.swift Sources/MyMacFinder/Services/ArchiveBrowsingService.swift Sources/MyMacFinder/Services/QuickLookPreviewService.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/UI/FilePreviewThumbnailLoader.swift
git diff 89ec7ed..HEAD -- Sources/MyMacFinder Tests/MyMacFinderTests
```

Review canonical containment, symlink rejection, owner identity, partial cleanup, corrupt registry preservation, retain-before-open order, one-shot release, stale context, double continuation resume, and cleanup error reporting. Fix every Critical or Important finding and rerun affected tests.

- [ ] **Step 3: Update README and QA evidence**

Document session-owned ZIP Quick Look files, 24-hour external-open retention, visible default-open failures, and cancellation behavior. Record exact test totals, command results, bundle hashes, manual QA limits, and leftover checks in the verification report. Do not claim a UI interaction passed unless it was actually performed.

- [ ] **Step 4: Build, sign, and package release artifacts**

```bash
./scripts/build_app.sh --configuration release
codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
./scripts/package_personal.sh
/usr/bin/unzip -tq dist/MyMacFinder-personal-mac.zip
shasum -a 256 build/MyMacFinder.app/Contents/MacOS/MyMacFinder
```

Expected: regenerated `build/MyMacFinder.app` and `dist/MyMacFinder-personal-mac.zip`, valid signature, valid ZIP, and a recorded executable SHA-256.

- [ ] **Step 5: Run isolated app smoke and preview QA**

Create one UUID-scoped system-temporary QA directory containing a text file, image, PDF, ZIP of those fixtures, and unrelated sentinel. Launch a QA-bundle-ID copy of the release app with ad-hoc signing. Verify normal and ZIP Quick Look, panel replacement and close, rapid selection, default-open success, tab/pane switch during preparation, no immediate crash, exact temp cleanup, 24-hour retention using injected QA state, and sentinel/original preservation.

If UI automation cannot exercise a flow, record manual verification required rather than passed. Remove the exact QA root and QA app copy and assert both are absent.

- [ ] **Step 6: Safely replace the installed personal app after all gates pass**

Quit only processes whose executable resolves to `MyMacFinder.app`. Copy the new bundle to a UUID staging directory, verify signature and executable SHA-256, move any existing `/Applications/MyMacFinder.app` to a UUID backup, atomically move staging into `/Applications`, compare installed and build hashes, launch, and verify PID plus executable path. On failure restore the backup immediately. After success move the backup to Trash without emptying Trash and remove staging.

- [ ] **Step 7: Commit documentation and final evidence**

```bash
git add README.md docs/qa/2026-08-08-archive-preview-lifecycle-verification.md
git commit -m "docs: record archive preview lifecycle verification"
git status --short --branch
```

Expected: clean `master`, local implementation and verification commits, and no push.
