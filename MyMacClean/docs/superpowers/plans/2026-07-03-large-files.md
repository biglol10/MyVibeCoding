# Large Files Implementation Plan

Status: implemented. This file is kept as execution history; current behavior
is summarized in `../../../README.md` and
`../specs/2026-07-03-mymacclean-personal-cleaner-design.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe Large Files screen that scans user-review roots, lists large files without auto-selecting them, and moves explicitly selected files to Trash through the existing verified deletion pipeline.

**Architecture:** Add a focused Large Files scanner in `MyMacCleanCore`, a `UserFileCleanupPolicy` so selected personal files can be trashed without weakening app-uninstall protections, a `LargeFilesViewModel` in `MyMacCleanAppSupport`, and SwiftUI screens in `ContentView`. Reuse `DeletionExecutor`, `DeletionVerifier`, `DeletionReceiptStore`, `DeleteActionButton`, and existing confirmation UI patterns.

**Tech Stack:** Swift 6 package, SwiftUI, Observation, XCTest, Foundation `FileManager`, existing MyMacClean Core/AppSupport modules.

---

## Scope Note

The approved personal-cleaner spec has four implementation phases. This plan covers Phase 1 only: Large Files. Developer Cache, Startup Items, and existing cleanup polish must get separate plans after this phase is complete.

## File Structure

- Create `Sources/MyMacCleanCore/LargeFiles/LargeFileCandidate.swift`
  - Owns Large Files data types: candidate, kind, scan options, sort mode.
- Create `Sources/MyMacCleanCore/LargeFiles/LargeFileScanner.swift`
  - Walks review roots and returns files above a minimum size.
- Create `Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift`
  - Allows only explicitly selected files under scan roots to be moved to Trash.
- Modify `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift`
  - Support both app-cleanup policy and user-file-cleanup policy.
- Modify `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`
  - Add `largeFileCleanup` receipt action.
- Create `Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift`
  - Owns scan/filter/sort/selection/delete state for Large Files.
- Modify `Sources/MyMacCleanAppSupport/SidebarDestination.swift`
  - Move `largeFiles` into current release and update subtitles/actions.
- Modify `Sources/MyMacCleanApp/Views/ContentView.swift`
  - Add Large Files content/detail screens and confirmation handling.
- Create `Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift`
- Create `Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift`
- Create `Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift`
- Modify `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift`

---

### Task 1: Core Large File Model And Scanner

**Files:**
- Create: `Sources/MyMacCleanCore/LargeFiles/LargeFileCandidate.swift`
- Create: `Sources/MyMacCleanCore/LargeFiles/LargeFileScanner.swift`
- Test: `Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift`

- [ ] **Step 1: Write the failing scanner tests**

Create `Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift`:

```swift
import XCTest
@testable import MyMacCleanCore

final class LargeFileScannerTests: XCTestCase {
    func testScannerReturnsOnlyFilesAtOrAboveMinimumSize() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-threshold")
        let smallFile = root.appendingPathComponent("small.mov")
        let largeFile = root.appendingPathComponent("large.mov")
        try Data(repeating: 1, count: 10).write(to: smallFile)
        try Data(repeating: 1, count: 1_024).write(to: largeFile)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [largeFile])
        XCTAssertEqual(results.first?.size, 1_024)
        XCTAssertEqual(results.first?.kind, .video)
        XCTAssertFalse(results.first?.defaultSelected ?? true)
    }

    func testScannerSkipsAppBundlesAndPackageContents() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-packages")
        let appBundle = root.appendingPathComponent("Heavy.app", isDirectory: true)
        let appPayload = appBundle.appendingPathComponent("Contents/Resources/payload.bin")
        let normalFile = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: appPayload.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2_000).write(to: appPayload)
        try Data(repeating: 1, count: 1_500).write(to: normalFile)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [normalFile])
    }

    func testScannerSkipsSystemRootsEvenWhenProvidedDirectly() async throws {
        let results = try await LargeFileScanner(
            roots: [URL(fileURLWithPath: "/System", isDirectory: true)],
            minimumSize: 1
        ).scan()

        XCTAssertTrue(results.isEmpty)
    }

    func testScannerSortsBySizeDescendingByDefault() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "large-files-sort")
        let medium = root.appendingPathComponent("medium.zip")
        let largest = root.appendingPathComponent("largest.dmg")
        try Data(repeating: 1, count: 1_500).write(to: medium)
        try Data(repeating: 1, count: 3_000).write(to: largest)

        let results = try await LargeFileScanner(
            roots: [root],
            minimumSize: 1_000
        ).scan()

        XCTAssertEqual(results.map(\.url), [largest, medium])
    }
}
```

- [ ] **Step 2: Run the scanner tests and verify RED**

Run:

```bash
swift test --filter LargeFileScannerTests
```

Expected: FAIL because `LargeFileScanner`, `LargeFileCandidate`, and `LargeFileKind` do not exist.

- [ ] **Step 3: Add the large file model**

Create `Sources/MyMacCleanCore/LargeFiles/LargeFileCandidate.swift`:

```swift
import Foundation

public enum LargeFileKind: String, CaseIterable, Codable, Equatable, Sendable {
    case archive
    case diskImage
    case video
    case audio
    case document
    case image
    case other

    public static func infer(from url: URL) -> LargeFileKind {
        switch url.pathExtension.lowercased() {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .archive
        case "dmg", "iso":
            return .diskImage
        case "mov", "mp4", "m4v", "avi", "mkv":
            return .video
        case "mp3", "m4a", "wav", "aiff", "flac":
            return .audio
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "key":
            return .document
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp":
            return .image
        default:
            return .other
        }
    }
}

public enum LargeFileSort: String, CaseIterable, Identifiable, Sendable {
    case sizeDescending
    case modifiedDescending
    case pathAscending

    public var id: Self { self }

    public var title: String {
        switch self {
        case .sizeDescending: "Size"
        case .modifiedDescending: "Modified"
        case .pathAscending: "Path"
        }
    }
}

public struct LargeFileCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modifiedAt: Date?
    public let kind: LargeFileKind
    public let rootURL: URL
    public let defaultSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        size: Int64,
        modifiedAt: Date?,
        kind: LargeFileKind,
        rootURL: URL,
        defaultSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.rootURL = rootURL
        self.defaultSelected = defaultSelected
    }
}
```

- [ ] **Step 4: Add the scanner**

Create `Sources/MyMacCleanCore/LargeFiles/LargeFileScanner.swift`:

```swift
import Foundation

public struct LargeFileScanner: Sendable {
    private let roots: [URL]
    private let minimumSize: Int64

    public init(
        roots: [URL],
        minimumSize: Int64 = 500 * 1_024 * 1_024
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
    }

    public func scan() async throws -> [LargeFileCandidate] {
        var candidates: [LargeFileCandidate] = []
        for root in roots.map({ $0.resolvingSymlinksInPath().standardizedFileURL }) {
            guard !isSystemRoot(root) else { continue }
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            candidates.append(contentsOf: try scan(root: root))
        }
        return candidates.sorted {
            if $0.size == $1.size {
                return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }

    private func scan(root: URL) throws -> [LargeFileCandidate] {
        var results: [LargeFileCandidate] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            if shouldSkipPackage(url) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            let size = Int64(values?.fileSize ?? 0)
            guard size >= minimumSize else { continue }

            results.append(
                LargeFileCandidate(
                    url: url,
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    kind: LargeFileKind.infer(from: url),
                    rootURL: root,
                    defaultSelected: false
                )
            )
        }

        return results
    }

    private func shouldSkipPackage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["app", "framework", "bundle", "photoslibrary"].contains(ext) {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    private func isSystemRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || path.hasPrefix("/usr/")
    }
}
```

- [ ] **Step 5: Run the scanner tests and verify GREEN**

Run:

```bash
swift test --filter LargeFileScannerTests
```

Expected: PASS, 4 tests with 0 failures.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/MyMacCleanCore/LargeFiles/LargeFileCandidate.swift Sources/MyMacCleanCore/LargeFiles/LargeFileScanner.swift Tests/MyMacCleanCoreTests/LargeFileScannerTests.swift
git commit -m "feat: add large file scanner"
```

---

### Task 2: User File Cleanup Policy And Receipt Action

**Files:**
- Create: `Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift`
- Modify: `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift`
- Modify: `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`
- Test: `Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift`
- Test: `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`

- [ ] **Step 1: Write failing policy and receipt tests**

Create `Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift`:

```swift
import XCTest
@testable import MyMacCleanCore

final class UserFileCleanupPolicyTests: XCTestCase {
    func testAllowsFilesInsideExplicitScanRoot() throws {
        let root = try TestFixtures.temporaryDirectory(named: "user-file-policy")
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 8).write(to: file)

        let policy = UserFileCleanupPolicy(allowedRoots: [root])

        XCTAssertFalse(policy.isProtected(file))
    }

    func testBlocksFilesOutsideExplicitScanRoot() throws {
        let allowed = try TestFixtures.temporaryDirectory(named: "user-file-policy-allowed")
        let outside = try TestFixtures.temporaryDirectory(named: "user-file-policy-outside")
        let file = outside.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 8).write(to: file)

        let policy = UserFileCleanupPolicy(allowedRoots: [allowed])

        XCTAssertTrue(policy.isProtected(file))
    }

    func testBlocksSystemRootsEvenWhenPassedAsAllowedRoot() {
        let policy = UserFileCleanupPolicy(allowedRoots: [URL(fileURLWithPath: "/System", isDirectory: true)])

        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    }
}
```

Append this test to `Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift`:

```swift
    func testSupportsLargeFileCleanupReceipts() throws {
        let root = try TestFixtures.temporaryDirectory(named: "receipt-large-files")
        let store = DeletionReceiptStore(fileURL: root.appendingPathComponent("receipts.jsonl"))
        let receipt = DeletionReceipt(
            appName: "Large Files",
            bundleIdentifier: nil,
            bundlePath: root.path,
            action: .largeFileCleanup,
            completedAt: Date(timeIntervalSince1970: 10),
            selectedCandidates: [],
            executionResults: [],
            verificationResults: [],
            confirmationMatched: true
        )

        try store.append(receipt)

        XCTAssertEqual(try store.readReceipts(), [receipt])
    }
```

- [ ] **Step 2: Run policy tests and verify RED**

Run:

```bash
swift test --filter UserFileCleanupPolicyTests
swift test --filter DeletionReceiptStoreTests/testSupportsLargeFileCleanupReceipts
```

Expected: FAIL because `UserFileCleanupPolicy` and `DeletionAction.largeFileCleanup` do not exist.

- [ ] **Step 3: Add `DeletionProtectionPolicy` bridge to executor**

Modify `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift` by adding this type above `DeletionExecutor`:

```swift
public struct DeletionProtectionPolicy: Sendable {
    private let isProtectedHandler: @Sendable (URL) -> Bool

    public init(isProtected: @escaping @Sendable (URL) -> Bool) {
        self.isProtectedHandler = isProtected
    }

    public func isProtected(_ url: URL) -> Bool {
        isProtectedHandler(url)
    }

    public static func appCleanup(_ protectionPolicy: ProtectionPolicy = ProtectionPolicy()) -> DeletionProtectionPolicy {
        DeletionProtectionPolicy { url in
            protectionPolicy.isProtected(url)
        }
    }
}
```

Then replace `DeletionExecutor`'s policy storage and initializer with:

```swift
public struct DeletionExecutor: Sendable {
    private let fileRemover: DeletionFileRemover
    private let deletionProtectionPolicy: DeletionProtectionPolicy

    public init(
        fileRemover: DeletionFileRemover = .live,
        protectionPolicy: ProtectionPolicy = ProtectionPolicy()
    ) {
        self.fileRemover = fileRemover
        self.deletionProtectionPolicy = .appCleanup(protectionPolicy)
    }

    public init(
        fileRemover: DeletionFileRemover = .live,
        deletionProtectionPolicy: DeletionProtectionPolicy
    ) {
        self.fileRemover = fileRemover
        self.deletionProtectionPolicy = deletionProtectionPolicy
    }
```

In `execute(plan:confirmation:force:mode:)`, replace the guard with:

```swift
            guard !candidate.isProtected, !deletionProtectionPolicy.isProtected(candidate.url) else {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.protectedPathSkipped)
            }
```

- [ ] **Step 4: Add user-file cleanup policy**

Create `Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift`:

```swift
import Foundation

public struct UserFileCleanupPolicy: Sendable {
    private let allowedRoots: [URL]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    public func isProtected(_ url: URL) -> Bool {
        let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard !isSystemPath(normalizedURL) else { return true }
        return !allowedRoots.contains { root in
            PathUtilities.isDescendant(normalizedURL, of: root)
                || PathUtilities.isDescendantResolvingSymlinks(normalizedURL, of: root)
        }
    }

    public var deletionProtectionPolicy: DeletionProtectionPolicy {
        DeletionProtectionPolicy { url in
            isProtected(url)
        }
    }

    private func isSystemPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || path.hasPrefix("/usr/")
    }
}
```

- [ ] **Step 5: Add the receipt action**

Modify `Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift`:

```swift
public enum DeletionAction: String, Codable, Equatable, Sendable {
    case uninstall
    case orphanCleanup
    case largeFileCleanup
}
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter UserFileCleanupPolicyTests
swift test --filter DeletionReceiptStoreTests/testSupportsLargeFileCleanupReceipts
swift test --filter DeletionExecutorTests
```

Expected: PASS, with existing deletion executor tests still green.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/MyMacCleanCore/Safety/UserFileCleanupPolicy.swift Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift Sources/MyMacCleanCore/Journal/DeletionReceiptStore.swift Tests/MyMacCleanCoreTests/UserFileCleanupPolicyTests.swift Tests/MyMacCleanCoreTests/DeletionReceiptStoreTests.swift
git commit -m "feat: add user file cleanup policy"
```

---

### Task 3: Large Files View Model

**Files:**
- Create: `Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift`
- Test: `Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift`:

```swift
import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class LargeFilesViewModelTests: XCTestCase {
    func testScanLoadsLargeFilesWithoutDefaultSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesVM-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 1_500).write(to: file)

        let viewModel = LargeFilesViewModel(scanRoots: [root], minimumSize: 1_000)

        await viewModel.scan()

        XCTAssertEqual(viewModel.candidates.map(\.url), [file])
        XCTAssertTrue(viewModel.selectedCandidateIDs.isEmpty)
        XCTAssertEqual(viewModel.totalBytes, 1_500)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFilterAndSortVisibleCandidates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesFilter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("archive.zip")
        let video = root.appendingPathComponent("video.mov")
        try Data(repeating: 1, count: 2_000).write(to: archive)
        try Data(repeating: 1, count: 3_000).write(to: video)

        let viewModel = LargeFilesViewModel(scanRoots: [root], minimumSize: 1_000)
        await viewModel.scan()
        viewModel.searchText = "archive"

        XCTAssertEqual(viewModel.visibleCandidates.map(\.url), [archive])
    }

    func testDeleteSelectedFilesRecordsReceiptAndRemovesVerifiedItems() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesDelete-\(UUID().uuidString)", isDirectory: true)
        let receiptRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanLargeFilesReceipt-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: receiptRoot)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 1_500).write(to: file)
        let store = DeletionReceiptStore(fileURL: receiptRoot.appendingPathComponent("receipts.jsonl"))
        let remover = DeletionFileRemover(
            trash: { url in try FileManager.default.removeItem(at: url) },
            remove: { url in try FileManager.default.removeItem(at: url) }
        )

        let viewModel = LargeFilesViewModel(
            scanRoots: [root],
            minimumSize: 1_000,
            executor: DeletionExecutor(
                fileRemover: remover,
                deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: [root]).deletionProtectionPolicy
            ),
            receiptStore: store
        )

        await viewModel.scan()
        viewModel.selectedCandidateIDs = Set(viewModel.candidates.map(\.id))
        await viewModel.moveSelectedToTrash(confirmation: "DELETE")

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(viewModel.candidates.isEmpty)
        let receipts = try store.readReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].action, .largeFileCleanup)
        XCTAssertEqual(receipts[0].verificationResults.map(\.status), [.deleted])
    }
}
```

- [ ] **Step 2: Run view model tests and verify RED**

Run:

```bash
swift test --filter LargeFilesViewModelTests
```

Expected: FAIL because `LargeFilesViewModel` does not exist.

- [ ] **Step 3: Add the view model**

Create `Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift`:

```swift
import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class LargeFilesViewModel {
    private let scanRoots: [URL]
    private let minimumSize: Int64
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var candidates: [LargeFileCandidate] = []
    public var selectedCandidateIDs: Set<LargeFileCandidate.ID> = []
    public var searchText = ""
    public var sort: LargeFileSort = .sizeDescending
    public var isScanning = false
    public var isDeleting = false
    public var hasScanned = false
    public var errorMessage: String?
    public var deletionReport: DeletionReportViewModel?

    public init(
        scanRoots: [URL] = LargeFilesViewModel.defaultScanRoots(),
        minimumSize: Int64 = 500 * 1_024 * 1_024,
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor? = nil,
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = .default()
    ) {
        self.scanRoots = scanRoots
        self.minimumSize = minimumSize
        self.planner = planner
        self.executor = executor ?? DeletionExecutor(
            deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: scanRoots).deletionProtectionPolicy
        )
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public static func defaultScanRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectory.appendingPathComponent("Movies", isDirectory: true),
            homeDirectory.appendingPathComponent("Documents", isDirectory: true)
        ]
    }

    public var visibleCandidates: [LargeFileCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = candidates.filter { candidate in
            query.isEmpty
                || candidate.url.lastPathComponent.lowercased().contains(query)
                || candidate.url.path.lowercased().contains(query)
                || candidate.kind.rawValue.lowercased().contains(query)
        }
        return sorted(filtered)
    }

    public var selectedCandidates: [LargeFileCandidate] {
        candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    public var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    public var totalBytes: Int64 {
        candidates.reduce(0) { $0 + $1.size }
    }

    public func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        candidates = []
        selectedCandidateIDs = []
        deletionReport = nil
        do {
            candidates = try await LargeFileScanner(roots: scanRoots, minimumSize: minimumSize).scan()
            hasScanned = true
            errorMessage = nil
        } catch {
            hasScanned = true
            errorMessage = error.localizedDescription
        }
    }

    public func moveSelectedToTrash(confirmation: String) async {
        guard !isDeleting else { return }
        let relatedCandidates = selectedCandidates.map { candidate in
            RelatedFileCandidate(
                id: candidate.id,
                url: candidate.url,
                kind: .unknown,
                size: candidate.size,
                matchReason: "large file selected by user",
                confidence: .high,
                safety: .review,
                defaultSelected: false,
                requiresManualReview: true,
                isProtected: false
            )
        }
        let app = InstalledApp(
            displayName: "Large Files",
            bundleIdentifier: nil,
            version: nil,
            executableName: nil,
            bundleURL: scanRoots.first ?? FileManager.default.homeDirectoryForCurrentUser,
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        do {
            let selectedIDs = Set(relatedCandidates.map(\.id))
            let plan = try planner.makePlan(app: app, candidates: relatedCandidates, selectedIDs: selectedIDs)
            isDeleting = true
            defer { isDeleting = false }
            let results = await executor.execute(plan: plan, confirmation: confirmation, mode: .moveToTrash)
            let verificationResults = await verifier.verify(plan: plan, executionResults: results)
            let receipt = DeletionReceipt(
                appName: "Large Files",
                bundleIdentifier: nil,
                bundlePath: app.bundleURL.path,
                action: .largeFileCleanup,
                selectedCandidates: plan.candidates.map {
                    DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
                },
                executionResults: results,
                verificationResults: verificationResults,
                confirmationMatched: results.allSatisfy { $0.errorMessage != DeletionExecutionErrorMessage.confirmationMismatch }
            )
            deletionReport = DeletionReportViewModel(receipt: receipt)
            removeVerifiedDeletedCandidates(from: verificationResults)
            errorMessage = nil
            do {
                try receiptStore.append(receipt)
            } catch {
                errorMessage = "Cleanup finished, but deletion history could not be saved: \(error.localizedDescription)"
            }
        } catch {
            deletionReport = nil
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    private func removeVerifiedDeletedCandidates(from verificationResults: [DeletionVerificationResult]) {
        let deletedPaths = Set(verificationResults.filter { $0.status == .deleted }.map(\.path))
        candidates.removeAll { deletedPaths.contains($0.url.path) }
        let remainingIDs = Set(candidates.map(\.id))
        selectedCandidateIDs.formIntersection(remainingIDs)
    }

    private func sorted(_ candidates: [LargeFileCandidate]) -> [LargeFileCandidate] {
        switch sort {
        case .sizeDescending:
            candidates.sorted {
                if $0.size == $1.size {
                    return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                }
                return $0.size > $1.size
            }
        case .modifiedDescending:
            candidates.sorted {
                ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
        case .pathAscending:
            candidates.sorted {
                $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
        }
    }
}
```

- [ ] **Step 4: Run view model tests and verify GREEN**

Run:

```bash
swift test --filter LargeFilesViewModelTests
```

Expected: PASS, 3 tests with 0 failures.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/MyMacCleanAppSupport/LargeFilesViewModel.swift Tests/MyMacCleanAppSupportTests/LargeFilesViewModelTests.swift
git commit -m "feat: add large files view model"
```

---

### Task 4: Sidebar And SwiftUI Large Files Screen

**Files:**
- Modify: `Sources/MyMacCleanAppSupport/SidebarDestination.swift`
- Modify: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Test: `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift`

- [ ] **Step 1: Write failing sidebar test**

Modify `Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift` so `testDestinationsExposeDistinctTitlesAndActions` includes:

```swift
        XCTAssertTrue(SidebarDestination.currentRelease.contains(.largeFiles))
        XCTAssertFalse(SidebarDestination.roadmap.contains(.largeFiles))
        XCTAssertEqual(SidebarDestination.largeFiles.primaryActionTitle, "Scan Large Files")
```

- [ ] **Step 2: Run sidebar test and verify RED**

Run:

```bash
swift test --filter SidebarDestinationTests
```

Expected: FAIL because `.largeFiles` is still in roadmap and its action is `"Find Large Files"`.

- [ ] **Step 3: Update sidebar destination metadata**

Modify `Sources/MyMacCleanAppSupport/SidebarDestination.swift`:

```swift
    public static let currentRelease: [SidebarDestination] = [
        .applications,
        .orphanFiles,
        .deleteHistory,
        .largeFiles
    ]

    public static let roadmap: [SidebarDestination] = [
        .startupItems,
        .systemCleanup,
        .maintenance
    ]
```

In `subtitle`, use:

```swift
        case .largeFiles:
            "Find oversized files for manual review before moving anything to Trash."
```

In `primaryActionTitle`, use:

```swift
        case .largeFiles: "Scan Large Files"
```

- [ ] **Step 4: Add Large Files state to ContentView**

Modify `Sources/MyMacCleanApp/Views/ContentView.swift`.

Add this state property near the other view models:

```swift
    @State private var largeFilesViewModel = LargeFilesViewModel()
```

Update the alert binding to include `largeFilesViewModel.errorMessage`:

```swift
                viewModel.errorMessage != nil
                    || historyViewModel.errorMessage != nil
                    || orphanFilesViewModel.errorMessage != nil
                    || largeFilesViewModel.errorMessage != nil
```

Update alert clearing:

```swift
                    viewModel.errorMessage = nil
                    historyViewModel.errorMessage = nil
                    orphanFilesViewModel.errorMessage = nil
                    largeFilesViewModel.errorMessage = nil
```

Update alert message:

```swift
            Text(viewModel.errorMessage ?? historyViewModel.errorMessage ?? orphanFilesViewModel.errorMessage ?? largeFilesViewModel.errorMessage ?? "")
```

- [ ] **Step 5: Route Large Files content and detail**

In `contentColumn`, add:

```swift
        case .largeFiles:
            largeFilesContent
```

In `detailColumn`, add:

```swift
        case .largeFiles:
            largeFilesDetail
```

Add these views near `orphanFilesContent` and `orphanFilesDetail`:

```swift
    private var largeFilesContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Large Files")
                        .font(.title2.weight(.semibold))
                    Text("Find oversized files for manual review before moving anything to Trash.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(largeFilesViewModel.isScanning ? "Scanning..." : SidebarDestination.largeFiles.primaryActionTitle) {
                    Task { await largeFilesViewModel.scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(largeFilesViewModel.isScanning || largeFilesViewModel.isDeleting)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search large files by name, kind, or path", text: $largeFilesViewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            if largeFilesViewModel.isScanning {
                ProgressView("Scanning Large Files")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !largeFilesViewModel.hasScanned {
                ContentUnavailableView(
                    "Scan Large Files",
                    systemImage: "internaldrive",
                    description: Text("Large files are never selected automatically. Review results before moving anything to Trash.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if largeFilesViewModel.visibleCandidates.isEmpty {
                ContentUnavailableView("No Large Files", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(largeFilesViewModel.visibleCandidates) { candidate in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { largeFilesViewModel.selectedCandidateIDs.contains(candidate.id) },
                            set: { isSelected in
                                if isSelected {
                                    largeFilesViewModel.selectedCandidateIDs.insert(candidate.id)
                                } else {
                                    largeFilesViewModel.selectedCandidateIDs.remove(candidate.id)
                                }
                            }
                        ))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.url.lastPathComponent)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            Text(candidate.url.deletingLastPathComponent().path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(candidate.kind.rawValue)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        SizeText(bytes: candidate.size)
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var largeFilesDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Large Files")
                    .font(.title2.weight(.semibold))
                Text("\(largeFilesViewModel.candidates.count) files, \(largeFilesViewModel.selectedCandidates.count) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let report = largeFilesViewModel.deletionReport {
                DeletionReportPanel(report: report)
            }

            if largeFilesViewModel.candidates.isEmpty {
                ContentUnavailableView(
                    largeFilesViewModel.hasScanned ? "No Large Files" : "No Scan Yet",
                    systemImage: "internaldrive",
                    description: Text("Run a scan and select files manually before cleanup.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HistoryMetric(title: "Found", value: "\(largeFilesViewModel.candidates.count)")
                    HistoryMetric(
                        title: "Total Size",
                        value: ByteCountFormatter.string(fromByteCount: largeFilesViewModel.totalBytes, countStyle: .file)
                    )
                    HistoryMetric(
                        title: "Selected",
                        value: ByteCountFormatter.string(fromByteCount: largeFilesViewModel.selectedBytes, countStyle: .file)
                    )
                }

                Spacer()

                DeleteActionButton(
                    selectedCount: largeFilesViewModel.selectedCandidates.count,
                    selectedBytes: largeFilesViewModel.selectedBytes,
                    disabledSummary: "Select large files first"
                ) {
                    presentConfirmation(.largeFiles)
                }
            }
        }
        .padding(22)
    }
```

- [ ] **Step 6: Add Large Files confirmation routing**

Update `DeletionConfirmationMode`:

```swift
private enum DeletionConfirmationMode: Identifiable {
    case application
    case orphanFiles
    case largeFiles

    var id: String {
        switch self {
        case .application: "application"
        case .orphanFiles: "orphanFiles"
        case .largeFiles: "largeFiles"
        }
    }
}
```

Update the confirmation button switch:

```swift
                        case .largeFiles:
                            await largeFilesViewModel.moveSelectedToTrash(confirmation: confirmationText)
```

Update `confirmationSheet(for:)` so Large Files always uses Trash-only cleanup and does not expose permanent delete or force-unlock controls:

```swift
            let allowsAdvancedDeleteOptions = mode != .largeFiles
            let effectivePermanentDelete = allowsAdvancedDeleteOptions && permanentDelete
            Text(effectivePermanentDelete ? "Permanent Deletion" : "Move to Trash")
                .font(.title2.weight(.semibold))
```

Replace the instruction text with:

```swift
            Text(effectivePermanentDelete ? "Type DELETE to permanently remove selected items. This cannot be undone from Trash." : "Type DELETE to move selected items to Trash.")
                .foregroundStyle(.secondary)
```

Wrap the two advanced toggles and force warning:

```swift
            if allowsAdvancedDeleteOptions {
                Toggle("Permanently delete instead", isOn: $permanentDelete)
                    .toggleStyle(.checkbox)
                    .disabled(isDeleting)
                Toggle("Force unlock locked items", isOn: $forceDelete)
                    .toggleStyle(.checkbox)
                    .help("Clears file locks and restores write permission before retrying. This cannot bypass Full Disk Access or administrator-only paths.")
                    .disabled(isDeleting)
                if forceDelete {
                    Text("Force unlock retries locked files, but Full Disk Access and administrator-only paths can still block deletion.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
```

Update the destructive button setup:

```swift
                Button(isDeleting ? "Deleting..." : (effectivePermanentDelete ? "Permanently Delete" : "Move to Trash"), role: .destructive) {
                    Task {
                        let deletionMode: DeletionMode = effectivePermanentDelete ? .permanent : .moveToTrash
```

Update `confirmationSelectedCandidates(for:)`:

```swift
        case .largeFiles:
            largeFilesViewModel.selectedCandidates.map { candidate in
                RelatedFileCandidate(
                    id: candidate.id,
                    url: candidate.url,
                    kind: .unknown,
                    size: candidate.size,
                    matchReason: "large file selected by user",
                    confidence: .high,
                    safety: .review,
                    defaultSelected: false,
                    requiresManualReview: true,
                    isProtected: false
                )
            }
```

Update `confirmationTargetTitle(for:)`:

```swift
        case .largeFiles:
            "Large Files"
```

Update `confirmationIsDeleting(for:)`:

```swift
        case .largeFiles:
            largeFilesViewModel.isDeleting
```

- [ ] **Step 7: Run focused tests and build**

Run:

```bash
swift test --filter SidebarDestinationTests
swift test --filter LargeFilesViewModelTests
swift build
```

Expected: all commands exit 0.

- [ ] **Step 8: Commit Task 4**

```bash
git add Sources/MyMacCleanAppSupport/SidebarDestination.swift Sources/MyMacCleanApp/Views/ContentView.swift Tests/MyMacCleanAppSupportTests/SidebarDestinationTests.swift
git commit -m "feat: add large files screen"
```

---

### Task 5: Full Verification And Release Build

**Files:**
- No new source files unless a prior task reveals a compile fix.

- [ ] **Step 1: Run full automated tests**

Run:

```bash
swift test
```

Expected: all tests pass with 0 failures. Do not continue if any test fails.

- [ ] **Step 2: Build app bundle and DMG**

Run:

```bash
scripts/create-dmg.sh
```

Expected:

- Release build succeeds.
- `dist/MyMacClean.app` is created.
- `dist/MyMacClean-dev.dmg` is created.

- [ ] **Step 3: Verify codesign**

Run:

```bash
codesign --verify --deep --strict --verbose=2 dist/MyMacClean.app
```

Expected:

```text
dist/MyMacClean.app: valid on disk
dist/MyMacClean.app: satisfies its Designated Requirement
```

- [ ] **Step 4: Launch the app and manually inspect Large Files**

Run:

```bash
open dist/MyMacClean.app
```

Expected manual checks:

- Sidebar shows Large Files under Current Release.
- Large Files opens a real screen, not the roadmap placeholder.
- Scan Large Files button is enabled.
- Initial state says files are never selected automatically.
- After scan, listed files have unchecked toggles.
- Move Selected Items to Trash is disabled until at least one file is selected.

- [ ] **Step 5: Commit verification-only fixes if needed**

If Step 1-4 expose a fix, make the smallest fix, rerun:

```bash
swift test
scripts/create-dmg.sh
codesign --verify --deep --strict --verbose=2 dist/MyMacClean.app
```

Then commit:

```bash
git add Sources Tests
git commit -m "fix: polish large files verification"
```

If no fixes were needed, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage:
  - Large file review: Task 1, Task 3, Task 4.
  - No default selection: Task 1 and Task 3 tests.
  - Trash cleanup through existing deletion pipeline: Task 2 and Task 3.
  - Receipt and verification: Task 2 and Task 3.
  - Real screen instead of roadmap placeholder: Task 4.
  - Full build/codesign/manual launch: Task 5.
- Placeholders: no task contains deferred implementation markers.
- Type consistency:
  - `LargeFileCandidate.ID` is `UUID`, matching selection sets.
  - `LargeFileSort` is defined before `LargeFilesViewModel` uses it.
  - `UserFileCleanupPolicy.deletionProtectionPolicy` feeds `DeletionExecutor`.
  - `DeletionAction.largeFileCleanup` is used by receipts.
