# Permission Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit macOS folder access recovery, sandbox-aware security-scoped bookmark persistence, and Settings management for granted folders.

**Architecture:** Keep permission behavior behind focused service boundaries. `PermissionGuidance` decides the recovery action, `SecurityScopedBookmarkStore` persists grant metadata, `UserSelectedFolderAccessService` owns AppKit folder picking and security-scoped access, and `ExplorerStore` coordinates UI state, safe retries, and Settings-facing summaries.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit `NSOpenPanel`, Foundation `URL` bookmarks, UserDefaults, XCTest, existing SwiftPM app bundle scripts.

---

## File Structure

- Modify `Sources/MyMacFinder/Domain/PermissionGuidance.swift`
  - Add `PermissionRecoveryAction`.
  - Preserve `primaryActionTitle` as a convenience for existing alert code.
  - Make sandboxed permission errors prefer `chooseFolder`.
- Create `Sources/MyMacFinder/Domain/FolderAccessGrant.swift`
  - Value models for stored grants and Settings summaries.
- Create `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`
  - UserDefaults-backed grant persistence.
- Create `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`
  - Protocol plus AppKit implementation for folder picking, bookmark creation, bookmark resolution, and access lifecycle.
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Inject sandbox summary, bookmark store, and access service.
  - Publish granted folder summaries.
  - Track permission retry context.
  - Expose choose/remove/reset methods.
- Modify `Sources/MyMacFinder/App/RootView.swift`
  - Dispatch visible error primary action by recovery action enum.
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`
  - Expand Privacy & Access Settings UI.
- Add `Tests/MyMacFinderTests/PermissionGuidanceTests.swift` cases.
- Add `Tests/MyMacFinderTests/SecurityScopedBookmarkStoreTests.swift`.
- Add `Tests/MyMacFinderTests/UserSelectedFolderAccessServiceTests.swift`.
- Add `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`.
- Add `docs/qa/permission-policy-manual-qa.md`.

## Task 1: Permission Recovery Domain And Guidance

**Files:**

- Modify: `Sources/MyMacFinder/Domain/PermissionGuidance.swift`
- Test: `Tests/MyMacFinderTests/PermissionGuidanceTests.swift`

- [ ] **Step 1: Add failing guidance tests**

Append these tests to `Tests/MyMacFinderTests/PermissionGuidanceTests.swift`:

```swift
func testSandboxedPermissionDeniedPrefersChooseFolderRecovery() {
    let guidance = PermissionGuidance(
        error: .permissionDenied("/Users/biglol/Documents"),
        sandbox: SandboxPolicySummary(isSandboxed: true)
    )

    XCTAssertEqual(guidance.recoveryAction, .chooseFolder)
    XCTAssertEqual(guidance.primaryActionTitle, "Choose Folder...")
    XCTAssertTrue(guidance.message.contains("/Users/biglol/Documents"))
}

func testUnrestrictedPermissionDeniedUsesPrivacySettingsRecovery() {
    let guidance = PermissionGuidance(
        error: .permissionDenied("/Users/biglol/Documents"),
        sandbox: SandboxPolicySummary(isSandboxed: false)
    )

    XCTAssertEqual(guidance.recoveryAction, .openPrivacySettings)
    XCTAssertEqual(guidance.primaryActionTitle, "Open Privacy Settings")
}

func testNonPermissionErrorHasNoRecoveryAction() {
    let guidance = PermissionGuidance(
        error: .pathDoesNotExist("/missing"),
        sandbox: SandboxPolicySummary(isSandboxed: true)
    )

    XCTAssertEqual(guidance.recoveryAction, .none)
    XCTAssertNil(guidance.primaryActionTitle)
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swift test --filter PermissionGuidanceTests
```

Expected: build fails because `PermissionGuidance.recoveryAction` and `PermissionRecoveryAction` do not exist.

- [ ] **Step 3: Implement recovery action in guidance**

Update `Sources/MyMacFinder/Domain/PermissionGuidance.swift` so it contains this public enum and stores the action:

```swift
public enum PermissionRecoveryAction: String, Equatable, Sendable {
    case chooseFolder
    case openPrivacySettings
    case none
}

public struct PermissionGuidance: Equatable, Sendable {
    public static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    public let message: String
    public let recoveryAction: PermissionRecoveryAction

    public var primaryActionTitle: String? {
        switch recoveryAction {
        case .chooseFolder:
            return "Choose Folder..."
        case .openPrivacySettings:
            return "Open Privacy Settings"
        case .none:
            return nil
        }
    }

    public init(error: ExplorerError, sandbox: SandboxPolicySummary = .current()) {
        switch error {
        case .permissionDenied(let path):
            self.message = Self.permissionDeniedMessage(path: path, sandbox: sandbox)
            self.recoveryAction = sandbox.isSandboxed ? .chooseFolder : .openPrivacySettings
        default:
            self.message = error.localizedDescription
            self.recoveryAction = .none
        }
    }
}
```

Keep the existing `SandboxPolicySummary` and `permissionDeniedMessage(path:sandbox:)` helper. Update the sandboxed message to mention choosing the folder through MyMacFinder:

```swift
return """
Permission denied: \(path)

This app is sandboxed. Choose the folder in MyMacFinder to grant access, or adjust macOS Privacy settings.
"""
```

- [ ] **Step 4: Run guidance tests**

Run:

```bash
swift test --filter PermissionGuidanceTests
```

Expected: all `PermissionGuidanceTests` pass.

- [ ] **Step 5: Commit guidance domain change**

Run:

```bash
git add Sources/MyMacFinder/Domain/PermissionGuidance.swift Tests/MyMacFinderTests/PermissionGuidanceTests.swift
git diff --cached --stat
git commit -m "feat: add permission recovery actions"
```

Expected: commit succeeds with only guidance and guidance tests staged.

## Task 2: Grant Models And Bookmark Persistence

**Files:**

- Create: `Sources/MyMacFinder/Domain/FolderAccessGrant.swift`
- Create: `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`
- Test: `Tests/MyMacFinderTests/SecurityScopedBookmarkStoreTests.swift`

- [ ] **Step 1: Write failing bookmark store tests**

Create `Tests/MyMacFinderTests/SecurityScopedBookmarkStoreTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class SecurityScopedBookmarkStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MyMacFinderTests.SecurityScopedBookmarkStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveLoadAndRemoveGrant() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        let grant = FolderAccessGrant(
            id: FolderAccessGrantID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            url: URL(fileURLWithPath: "/Users/biglol/Documents", isDirectory: true),
            bookmarkData: Data([1, 2, 3]),
            createdAt: Date(timeIntervalSince1970: 10),
            lastResolvedAt: nil
        )

        try store.save(grant)
        XCTAssertEqual(store.load(), [grant])

        store.remove(id: grant.id)
        XCTAssertEqual(store.load(), [])
    }

    func testResetRemovesAllGrants() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        try store.save(FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/a", isDirectory: true), bookmarkData: Data([1])))
        try store.save(FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/b", isDirectory: true), bookmarkData: Data([2])))

        store.reset()

        XCTAssertEqual(store.load(), [])
    }

    func testSavingSameURLReplacesExistingGrant() throws {
        let store = SecurityScopedBookmarkStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        try store.save(FolderAccessGrant(url: url, bookmarkData: Data([1]), createdAt: Date(timeIntervalSince1970: 1)))
        try store.save(FolderAccessGrant(url: url, bookmarkData: Data([9]), createdAt: Date(timeIntervalSince1970: 2)))

        let grants = store.load()
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(grants[0].url, url.standardizedFileURL)
        XCTAssertEqual(grants[0].bookmarkData, Data([9]))
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swift test --filter SecurityScopedBookmarkStoreTests
```

Expected: build fails because `FolderAccessGrant` and `SecurityScopedBookmarkStore` do not exist.

- [ ] **Step 3: Add grant domain models**

Create `Sources/MyMacFinder/Domain/FolderAccessGrant.swift`:

```swift
import Foundation

public struct FolderAccessGrantID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct FolderAccessGrant: Codable, Equatable, Identifiable, Sendable {
    public var id: FolderAccessGrantID
    public var url: URL
    public var bookmarkData: Data
    public var createdAt: Date
    public var lastResolvedAt: Date?

    public init(
        id: FolderAccessGrantID = FolderAccessGrantID(),
        url: URL,
        bookmarkData: Data,
        createdAt: Date = Date(),
        lastResolvedAt: Date? = nil
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.lastResolvedAt = lastResolvedAt
    }

    public var displayPath: String {
        url.path
    }
}

public enum FolderAccessGrantAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct FolderAccessGrantSummary: Equatable, Identifiable, Sendable {
    public var id: FolderAccessGrantID
    public var url: URL
    public var displayPath: String
    public var availability: FolderAccessGrantAvailability
    public var isStale: Bool

    public init(
        grant: FolderAccessGrant,
        availability: FolderAccessGrantAvailability = .unknown,
        isStale: Bool = false
    ) {
        self.id = grant.id
        self.url = grant.url
        self.displayPath = grant.displayPath
        self.availability = availability
        self.isStale = isStale
    }
}
```

- [ ] **Step 4: Add bookmark store**

Create `Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift`:

```swift
import Foundation

public protocol SecurityScopedBookmarkStoring: AnyObject {
    func load() -> [FolderAccessGrant]
    func save(_ grant: FolderAccessGrant) throws
    func remove(id: FolderAccessGrantID)
    func reset()
}

public final class SecurityScopedBookmarkStore: SecurityScopedBookmarkStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.SecurityScopedBookmarks"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [FolderAccessGrant] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([FolderAccessGrant].self, from: data)) ?? []
    }

    public func save(_ grant: FolderAccessGrant) throws {
        var grants = load()
        grants.removeAll { existing in
            existing.id == grant.id || existing.url.standardizedFileURL == grant.url.standardizedFileURL
        }
        grants.append(grant)
        grants.sort { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
        let data = try JSONEncoder().encode(grants)
        defaults.set(data, forKey: key)
    }

    public func remove(id: FolderAccessGrantID) {
        let grants = load().filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(grants) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 5: Run bookmark store tests**

Run:

```bash
swift test --filter SecurityScopedBookmarkStoreTests
```

Expected: all `SecurityScopedBookmarkStoreTests` pass.

- [ ] **Step 6: Commit bookmark store**

Run:

```bash
git add Sources/MyMacFinder/Domain/FolderAccessGrant.swift \
  Sources/MyMacFinder/Services/SecurityScopedBookmarkStore.swift \
  Tests/MyMacFinderTests/SecurityScopedBookmarkStoreTests.swift
git diff --cached --stat
git commit -m "feat: persist folder access grants"
```

Expected: commit succeeds with only grant model, store, and tests staged.

## Task 3: User Selected Folder Access Service

**Files:**

- Create: `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`
- Test: `Tests/MyMacFinderTests/UserSelectedFolderAccessServiceTests.swift`

- [ ] **Step 1: Write failing access service tests**

Create `Tests/MyMacFinderTests/UserSelectedFolderAccessServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class UserSelectedFolderAccessServiceTests: XCTestCase {
    func testPickerCancellationReturnsCancelledResult() async throws {
        let picker = StubFolderPicker(result: nil)
        let service = UserSelectedFolderAccessService(
            picker: picker,
            bookmarkResolver: StubBookmarkResolver()
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: true)

        XCTAssertEqual(result, .cancelled)
    }

    func testSandboxedSelectionCreatesBookmarkGrantAndStartsAccess() async throws {
        let url = URL(fileURLWithPath: "/tmp/granted", isDirectory: true)
        let resolver = StubBookmarkResolver(bookmarkData: Data([4, 5, 6]))
        let service = UserSelectedFolderAccessService(
            picker: StubFolderPicker(result: url),
            bookmarkResolver: resolver
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: true)

        guard case .granted(let grant, let access) = result else {
            return XCTFail("Expected granted result")
        }
        XCTAssertEqual(grant.url, url.standardizedFileURL)
        XCTAssertEqual(grant.bookmarkData, Data([4, 5, 6]))
        XCTAssertEqual(access.url, url.standardizedFileURL)
        XCTAssertEqual(resolver.startedURLs, [url.standardizedFileURL])
    }

    func testUnrestrictedSelectionReturnsGrantWithoutBookmarkData() async throws {
        let url = URL(fileURLWithPath: "/tmp/unrestricted", isDirectory: true)
        let service = UserSelectedFolderAccessService(
            picker: StubFolderPicker(result: url),
            bookmarkResolver: StubBookmarkResolver()
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: false)

        guard case .granted(let grant, _) = result else {
            return XCTFail("Expected granted result")
        }
        XCTAssertEqual(grant.url, url.standardizedFileURL)
        XCTAssertEqual(grant.bookmarkData, Data())
    }
}

private final class StubFolderPicker: FolderPicking {
    var result: URL?

    init(result: URL?) {
        self.result = result
    }

    @MainActor
    func chooseFolder(startingAt url: URL?) async -> URL? {
        result
    }
}

private final class StubBookmarkResolver: BookmarkResolving {
    var bookmarkData: Data
    var startedURLs: [URL] = []

    init(bookmarkData: Data = Data([1])) {
        self.bookmarkData = bookmarkData
    }

    func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data {
        sandboxed ? bookmarkData : Data()
    }

    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        ResolvedFolderAccess(url: grant.url, isStale: false, didStartAccessing: true)
    }

    func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess {
        startedURLs.append(url.standardizedFileURL)
        return ResolvedFolderAccess(url: url.standardizedFileURL, isStale: false, didStartAccessing: sandboxed)
    }

    func stopAccessing(_ access: ResolvedFolderAccess) {}
}
```

- [ ] **Step 2: Run failing access service tests**

Run:

```bash
swift test --filter UserSelectedFolderAccessServiceTests
```

Expected: build fails because access service, picker, resolver, and result types do not exist.

- [ ] **Step 3: Add access service protocols and implementation**

Create `Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift`:

```swift
import AppKit
import Foundation

public enum FolderAccessSelectionResult: Equatable, Sendable {
    case granted(FolderAccessGrant, ResolvedFolderAccess)
    case cancelled
}

public struct ResolvedFolderAccess: Equatable, Sendable {
    public var url: URL
    public var isStale: Bool
    public var didStartAccessing: Bool

    public init(url: URL, isStale: Bool, didStartAccessing: Bool) {
        self.url = url.standardizedFileURL
        self.isStale = isStale
        self.didStartAccessing = didStartAccessing
    }
}

public protocol FolderPicking: AnyObject {
    @MainActor
    func chooseFolder(startingAt url: URL?) async -> URL?
}

public protocol BookmarkResolving: AnyObject {
    func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data
    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess
    func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess
    func stopAccessing(_ access: ResolvedFolderAccess)
}

public protocol UserSelectedFolderAccessing: AnyObject {
    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult
    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess
    func stopAccessing(_ access: ResolvedFolderAccess)
}

public final class UserSelectedFolderAccessService: UserSelectedFolderAccessing {
    private let picker: FolderPicking
    private let bookmarkResolver: BookmarkResolving

    public init(
        picker: FolderPicking = AppKitFolderPicker(),
        bookmarkResolver: BookmarkResolving = SecurityScopedBookmarkResolver()
    ) {
        self.picker = picker
        self.bookmarkResolver = bookmarkResolver
    }

    public func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult {
        guard let selectedURL = await picker.chooseFolder(startingAt: url)?.standardizedFileURL else {
            return .cancelled
        }
        let bookmarkData = try bookmarkResolver.bookmarkData(for: selectedURL, sandboxed: sandboxed)
        let grant = FolderAccessGrant(url: selectedURL, bookmarkData: bookmarkData)
        let access = bookmarkResolver.startAccessing(selectedURL, sandboxed: sandboxed)
        return .granted(grant, access)
    }

    public func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        try bookmarkResolver.resolve(grant)
    }

    public func stopAccessing(_ access: ResolvedFolderAccess) {
        bookmarkResolver.stopAccessing(access)
    }
}

public final class AppKitFolderPicker: FolderPicking {
    public init() {}

    @MainActor
    public func chooseFolder(startingAt url: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = url
        panel.prompt = "Choose"
        panel.message = "Choose a folder to grant MyMacFinder access."
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}

public final class SecurityScopedBookmarkResolver: BookmarkResolving {
    public init() {}

    public func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data {
        guard sandboxed else {
            return Data()
        }
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        guard !grant.bookmarkData.isEmpty else {
            return startAccessing(grant.url, sandboxed: false)
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: grant.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let didStart = url.startAccessingSecurityScopedResource()
        return ResolvedFolderAccess(url: url, isStale: isStale, didStartAccessing: didStart)
    }

    public func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess {
        let didStart = sandboxed ? url.startAccessingSecurityScopedResource() : false
        return ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: didStart)
    }

    public func stopAccessing(_ access: ResolvedFolderAccess) {
        guard access.didStartAccessing else {
            return
        }
        access.url.stopAccessingSecurityScopedResource()
    }
}
```

- [ ] **Step 4: Run access service tests**

Run:

```bash
swift test --filter UserSelectedFolderAccessServiceTests
```

Expected: all `UserSelectedFolderAccessServiceTests` pass.

- [ ] **Step 5: Commit access service**

Run:

```bash
git add Sources/MyMacFinder/Services/UserSelectedFolderAccessService.swift \
  Tests/MyMacFinderTests/UserSelectedFolderAccessServiceTests.swift
git diff --cached --stat
git commit -m "feat: add user selected folder access service"
```

Expected: commit succeeds with only access service and tests staged.

## Task 4: ExplorerStore Permission Recovery State

**Files:**

- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`

- [ ] **Step 1: Write failing store recovery tests**

Create `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerPermissionRecoveryTests: XCTestCase {
    func testNavigationPermissionErrorRecordsChooseFolderRecoveryTarget() async {
        let deniedURL = URL(fileURLWithPath: "/tmp/denied", isDirectory: true)
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            fileSystemService: DenyingFileSystemService(deniedURL: deniedURL),
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.navigate(to: deniedURL)

        XCTAssertEqual(store.visibleErrorGuidance?.recoveryAction, .chooseFolder)
        XCTAssertEqual(store.pendingPermissionRecoveryPath, deniedURL.standardizedFileURL.path)
    }

    func testChooseFolderCancellationLeavesGrantListUnchanged() async {
        let bookmarkStore = InMemoryBookmarkStore()
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: bookmarkStore,
            folderAccessService: StubFolderAccessService(result: .cancelled)
        )

        await store.chooseFolderForAccess()

        XCTAssertEqual(store.grantedFolderSummaries, [])
    }

    func testChooseFolderGrantSavesGrantAndPublishesSummary() async throws {
        let url = URL(fileURLWithPath: "/tmp/granted", isDirectory: true)
        let grant = FolderAccessGrant(url: url, bookmarkData: Data([1]))
        let store = ExplorerStore(
            initialURL: FileManager.default.temporaryDirectory,
            directoryWatcher: nil,
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            bookmarkStore: InMemoryBookmarkStore(),
            folderAccessService: StubFolderAccessService(
                result: .granted(grant, ResolvedFolderAccess(url: url, isStale: false, didStartAccessing: true))
            )
        )

        await store.chooseFolderForAccess()

        XCTAssertEqual(store.grantedFolderSummaries.map(\.displayPath), [url.standardizedFileURL.path])
    }
}

private struct DenyingFileSystemService: FileSystemServicing {
    var deniedURL: URL

    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry] {
        if url.standardizedFileURL == deniedURL.standardizedFileURL {
            throw ExplorerError.permissionDenied(url.path)
        }
        return []
    }
}

private final class InMemoryBookmarkStore: SecurityScopedBookmarkStoring {
    var grants: [FolderAccessGrant] = []

    func load() -> [FolderAccessGrant] {
        grants
    }

    func save(_ grant: FolderAccessGrant) throws {
        grants.removeAll { $0.url == grant.url || $0.id == grant.id }
        grants.append(grant)
    }

    func remove(id: FolderAccessGrantID) {
        grants.removeAll { $0.id == id }
    }

    func reset() {
        grants.removeAll()
    }
}

private final class StubFolderAccessService: UserSelectedFolderAccessing {
    var result: FolderAccessSelectionResult

    init(result: FolderAccessSelectionResult) {
        self.result = result
    }

    func chooseFolder(startingAt url: URL?, sandboxed: Bool) async throws -> FolderAccessSelectionResult {
        result
    }

    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        ResolvedFolderAccess(url: grant.url, isStale: false, didStartAccessing: false)
    }

    func stopAccessing(_ access: ResolvedFolderAccess) {}
}
```

- [ ] **Step 2: Run failing store recovery tests**

Run:

```bash
swift test --filter ExplorerPermissionRecoveryTests
```

Expected: build fails because `ExplorerStore` does not accept the new dependencies and does not publish grant/recovery state.

- [ ] **Step 3: Add store dependencies and published state**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

```swift
@Published public private(set) var grantedFolderSummaries: [FolderAccessGrantSummary]
@Published public private(set) var pendingPermissionRecoveryPath: String?
```

Add private dependencies and active access tracking:

```swift
private let bookmarkStore: any SecurityScopedBookmarkStoring
private let folderAccessService: any UserSelectedFolderAccessing
private var activeFolderAccesses: [FolderAccessGrantID: ResolvedFolderAccess]
```

Extend the initializer signature with default values:

```swift
sandboxPolicy: SandboxPolicySummary = .current(),
bookmarkStore: any SecurityScopedBookmarkStoring = SecurityScopedBookmarkStore(),
folderAccessService: any UserSelectedFolderAccessing = UserSelectedFolderAccessService(),
```

Assign these values in `init`:

```swift
self.grantedFolderSummaries = bookmarkStore.load().map(FolderAccessGrantSummary.init)
self.pendingPermissionRecoveryPath = nil
self.sandboxPolicy = sandboxPolicy
self.bookmarkStore = bookmarkStore
self.folderAccessService = folderAccessService
self.activeFolderAccesses = [:]
```

Replace the current `self.sandboxPolicy = .current()` assignment with `self.sandboxPolicy = sandboxPolicy`.

- [ ] **Step 4: Record permission errors with recovery path**

Add helper methods to `ExplorerStore`:

```swift
private func present(_ error: ExplorerError) {
    visibleError = error
    if case .permissionDenied(let path) = error {
        pendingPermissionRecoveryPath = path
    }
}

private func present(_ error: Error) {
    if let explorerError = error as? ExplorerError {
        present(explorerError)
    } else {
        visibleError = .readFailed(error.localizedDescription)
    }
}
```

Use this helper for navigation and refresh catches that currently assign `visibleError` directly. The first implementation must at least update `navigate(to:)`, `resolveAndNavigate(_:)`, `refresh()`, and `reloadWatchedPanes()` catch blocks. Leave write-command auto-retry out of scope.

- [ ] **Step 5: Add grant management methods**

Add public methods to `ExplorerStore`:

```swift
public func chooseFolderForAccess() async {
    await chooseFolderForAccess(startingAt: permissionRecoveryStartURL())
}

public func chooseFolderForAccess(startingAt startURL: URL?) async {
    do {
        let result = try await folderAccessService.chooseFolder(
            startingAt: startURL,
            sandboxed: sandboxPolicy.isSandboxed
        )
        guard case .granted(let grant, let access) = result else {
            return
        }
        if sandboxPolicy.isSandboxed {
            try bookmarkStore.save(grant)
            activeFolderAccesses[grant.id] = access
        }
        refreshGrantedFolderSummaries()
        await retryPermissionRecoveryIfSafe()
    } catch let error as ExplorerError {
        present(error)
    } catch {
        visibleError = .readFailed(error.localizedDescription)
    }
}

public func removeGrantedFolder(id: FolderAccessGrantID) async {
    if let access = activeFolderAccesses.removeValue(forKey: id) {
        folderAccessService.stopAccessing(access)
    }
    bookmarkStore.remove(id: id)
    refreshGrantedFolderSummaries()
    await refreshVisiblePanesAfterAccessChange()
}

public func resetGrantedFolders() async {
    activeFolderAccesses.values.forEach(folderAccessService.stopAccessing)
    activeFolderAccesses.removeAll()
    bookmarkStore.reset()
    refreshGrantedFolderSummaries()
    await refreshVisiblePanesAfterAccessChange()
}

private func refreshGrantedFolderSummaries() {
    grantedFolderSummaries = bookmarkStore.load().map(FolderAccessGrantSummary.init)
}
```

Add safe retry helpers:

```swift
private func permissionRecoveryStartURL() -> URL? {
    guard let path = pendingPermissionRecoveryPath else {
        return activePane.location.fileSystemURL
    }
    var candidate = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
        return candidate
    }
    repeat {
        candidate.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
    } while candidate.path != "/"
    return nil
}

private func retryPermissionRecoveryIfSafe() async {
    guard let path = pendingPermissionRecoveryPath else {
        return
    }
    pendingPermissionRecoveryPath = nil
    clearError()
    await navigate(to: URL(fileURLWithPath: path, isDirectory: true))
}

private func refreshVisiblePanesAfterAccessChange() async {
    await reloadAllPanes()
}
```

- [ ] **Step 6: Run store recovery tests**

Run:

```bash
swift test --filter ExplorerPermissionRecoveryTests
```

Expected: all `ExplorerPermissionRecoveryTests` pass.

- [ ] **Step 7: Run existing store tests**

Run:

```bash
swift test --filter ExplorerStoreTests --filter PermissionGuidanceTests
```

Expected: existing store and guidance tests pass.

- [ ] **Step 8: Commit store recovery integration**

Run:

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift \
  Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift
git diff --cached --stat
git commit -m "feat: track folder access recovery in explorer store"
```

Expected: commit succeeds with only store integration and tests staged.

## Task 5: Alert Recovery And Settings UI

**Files:**

- Modify: `Sources/MyMacFinder/App/RootView.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Test: extend `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`

- [ ] **Step 1: Add a store test for removing and resetting grants**

Append to `Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift`:

```swift
func testRemoveAndResetGrantedFoldersUpdateSummaries() async throws {
    let bookmarkStore = InMemoryBookmarkStore()
    let first = FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/first", isDirectory: true), bookmarkData: Data([1]))
    let second = FolderAccessGrant(url: URL(fileURLWithPath: "/tmp/second", isDirectory: true), bookmarkData: Data([2]))
    try bookmarkStore.save(first)
    try bookmarkStore.save(second)

    let store = ExplorerStore(
        initialURL: FileManager.default.temporaryDirectory,
        directoryWatcher: nil,
        sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
        bookmarkStore: bookmarkStore,
        folderAccessService: StubFolderAccessService(result: .cancelled)
    )

    XCTAssertEqual(store.grantedFolderSummaries.count, 2)

    await store.removeGrantedFolder(id: first.id)
    XCTAssertEqual(store.grantedFolderSummaries.map(\.id), [second.id])

    await store.resetGrantedFolders()
    XCTAssertEqual(store.grantedFolderSummaries, [])
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
swift test --filter ExplorerPermissionRecoveryTests/testRemoveAndResetGrantedFoldersUpdateSummaries
```

Expected: pass if Task 4 already added the methods; otherwise fail and complete Task 4 before continuing.

- [ ] **Step 3: Wire alert primary action**

Update the alert block in `Sources/MyMacFinder/App/RootView.swift`:

```swift
.alert("MyMacFinder", isPresented: explorerStore.hasVisibleError) {
    if let guidance = explorerStore.visibleErrorGuidance,
       let actionTitle = guidance.primaryActionTitle {
        Button(actionTitle) {
            switch guidance.recoveryAction {
            case .chooseFolder:
                Task { await explorerStore.chooseFolderForAccess() }
            case .openPrivacySettings:
                NSWorkspace.shared.open(PermissionGuidance.privacySettingsURL)
                explorerStore.clearError()
            case .none:
                explorerStore.clearError()
            }
        }
    }
    Button("OK", role: .cancel) {
        explorerStore.clearError()
    }
} message: {
    Text(explorerStore.visibleErrorMessage)
}
```

- [ ] **Step 4: Expand Settings Privacy & Access UI**

In `Sources/MyMacFinder/App/MyMacFinderApp.swift`, replace the current Privacy & Access section with:

```swift
Section("Privacy & Access") {
    LabeledContent("Sandbox") {
        Text(explorerStore.sandboxPolicy.statusTitle)
    }

    Text(explorerStore.sandboxPolicy.detail)
        .font(.caption)
        .foregroundStyle(.secondary)

    Button("Choose Folder...") {
        Task { await explorerStore.chooseFolderForAccess(startingAt: nil) }
    }

    if explorerStore.grantedFolderSummaries.isEmpty {
        Text(explorerStore.sandboxPolicy.isSandboxed
            ? "No granted folders yet. Choose folders here to allow access outside the app container."
            : "No folder grants stored. This unrestricted build usually does not require folder grants."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
        ForEach(explorerStore.grantedFolderSummaries) { grant in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(grant.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(grant.availability.rawValue.capitalized + (grant.isStale ? " - Stale" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove") {
                    Task { await explorerStore.removeGrantedFolder(id: grant.id) }
                }
            }
        }

        Button("Reset Granted Folders", role: .destructive) {
            Task { await explorerStore.resetGrantedFolders() }
        }
    }

    Button("Open Privacy Settings") {
        openPrivacySettings()
    }
}
```

If this makes `MyMacFinderApp.swift` hard to scan, create `Sources/MyMacFinder/UI/PrivacyAccessSettingsView.swift` and move only this section into that view. Keep the same bindings and store methods.

- [ ] **Step 5: Run UI compile and focused tests**

Run:

```bash
swift test --filter ExplorerPermissionRecoveryTests --filter PermissionGuidanceTests
```

Expected: tests pass and SwiftUI code compiles.

- [ ] **Step 6: Commit alert and settings UI**

Run:

```bash
git add Sources/MyMacFinder/App/RootView.swift \
  Sources/MyMacFinder/App/MyMacFinderApp.swift \
  Tests/MyMacFinderTests/ExplorerPermissionRecoveryTests.swift
git diff --cached --stat
git commit -m "feat: expose folder access controls in settings"
```

Expected: commit succeeds with only UI wiring and related tests staged.

## Task 6: QA Document, Full Verification, And Manual QA

**Files:**

- Create: `docs/qa/permission-policy-manual-qa.md`
- Modify only when verification exposes a defect: the specific source or test file that owns that defect, committed separately before the QA document commit.

- [ ] **Step 1: Add manual QA document**

Create `docs/qa/permission-policy-manual-qa.md`:

````markdown
# Permission Policy Manual QA

## Setup

Run:

```bash
QA_DIR="$HOME/MyMacFinderPermissionQA"
rm -rf "$QA_DIR"
mkdir -p "$QA_DIR/granted" "$QA_DIR/normal"
printf "permission qa\n" > "$QA_DIR/granted/readme.txt"
./scripts/build_app.sh
open build/MyMacFinder.app
```

## Non-Sandbox Personal Build

1. Open MyMacFinder Settings.
2. Go to Privacy & Access.
3. Expected: Sandbox status is `Unrestricted`.
4. Expected: empty grant text says grants usually are not required for this build.
5. Click `Choose Folder...`.
6. Choose `$HOME/MyMacFinderPermissionQA/granted`.
7. Expected: the folder appears in Granted Folders.
8. Click Remove for that folder.
9. Expected: the folder disappears from Granted Folders.
10. Click `Choose Folder...` again and choose the same folder.
11. Click `Reset Granted Folders`.
12. Expected: Granted Folders is empty.

## Navigation Smoke

1. Navigate to `$HOME/MyMacFinderPermissionQA/granted`.
2. Expected: `readme.txt` is visible.
3. Navigate to `$HOME/MyMacFinderPermissionQA/normal`.
4. Expected: empty folder opens without requiring a grant in the personal build.

## Permission Error Guidance

1. Try a path that the current build cannot read, if one is available on the test machine.
2. Expected for personal non-sandbox build: permission alert offers `Open Privacy Settings`.
3. Expected for sandboxed build: permission alert offers `Choose Folder...`.

## Cleanup

Run:

```bash
rm -rf "$HOME/MyMacFinderPermissionQA"
```
````

- [ ] **Step 2: Run full automated verification**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

Expected: all tests pass, diff check prints no errors, and `build/MyMacFinder.app` is rebuilt.

- [ ] **Step 3: Launch release app**

Run:

```bash
open build/MyMacFinder.app
```

Expected: app opens from the built bundle.

- [ ] **Step 4: Run manual QA**

Follow `docs/qa/permission-policy-manual-qa.md`.

Expected:

- Settings shows Unrestricted for the current personal build.
- Choose Folder adds a grant row.
- Remove deletes one grant row.
- Reset clears all grants.
- Normal folder navigation still works without requiring grants.

- [ ] **Step 5: Clean manual QA fixture**

Run:

```bash
rm -rf "$HOME/MyMacFinderPermissionQA"
```

Expected: fixture directory is removed.

- [ ] **Step 6: Final status and commit**

Run:

```bash
git status --short
git add docs/qa/permission-policy-manual-qa.md
git diff --cached --stat
git commit -m "docs: add permission policy manual QA"
```

Expected: QA doc commit succeeds. If source fixes were required during verification, include them in a separate narrow commit before the QA doc commit.

## Final Phase 2 Gate

Before declaring Phase 2 complete, run:

```bash
swift test
git diff --check
./scripts/build_app.sh
git status --short
```

Expected:

- `swift test` passes with zero failures.
- `git diff --check` prints no errors.
- `./scripts/build_app.sh` exits 0 and prints `build/MyMacFinder.app`.
- `git status --short` is empty.
- Manual QA has been run against `build/MyMacFinder.app` and recorded in `docs/qa/permission-policy-manual-qa.md` or the final response.

## Self-Review

- Spec coverage: Tasks cover `NSOpenPanel`, sandbox bookmarks, permission recovery action, Settings granted locations, non-sandbox behavior, tests, and manual QA.
- Placeholder scan: The plan contains no undefined tasks, deferred implementation markers, or unspecified test steps.
- Type consistency: `PermissionRecoveryAction`, `FolderAccessGrant`, `FolderAccessGrantSummary`, `SecurityScopedBookmarkStore`, `UserSelectedFolderAccessService`, and `ExplorerStore` methods are named consistently across tasks.
- Scope check: Signing, notarization, privileged helpers, and network-volume-specific policy are intentionally excluded from Phase 2.
