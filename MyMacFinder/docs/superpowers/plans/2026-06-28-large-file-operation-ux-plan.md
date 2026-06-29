# Large File Operation UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add observable, cancellable large-file operation UX for copy, move, duplicate, trash, ZIP extraction, and ZIP compression.

**Architecture:** Introduce a small operation progress domain model plus an actor-backed reporter. File mutation services receive an optional reporter and cancellation checks, while `ExplorerStore` owns the active reporter and publishes progress snapshots to the UI. The first UI surface is a compact operation banner; the later Activity View phase will reuse the same progress model.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, Foundation FileManager, ZIPFoundation, XCTest.

---

## File Structure

- Create `Sources/MyMacFinder/Domain/FileOperationProgress.swift`
  - Operation id, kind, phase, units, byte counts, title, current item, timestamps, error message.
- Create `Sources/MyMacFinder/Services/FileOperationProgressReporter.swift`
  - Actor that stores the current snapshot, emits updates, and supports cancellation.
- Create `Sources/MyMacFinder/Services/FileOperationManifestBuilder.swift`
  - Enumerates selected filesystem items into count/byte manifests where practical.
- Modify `Sources/MyMacFinder/Services/FileOperationService.swift`
  - Accept optional progress reporters and cancellation checks for copy, move, duplicate, trash.
- Modify `Sources/MyMacFinder/Services/ZipExtractionService.swift`
  - Report per-entry extraction progress and support cancellation between archive entries.
- Modify `Sources/MyMacFinder/Services/ZipCompressionService.swift`
  - Report staging progress and indeterminate archive writing phase.
- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Publish active progress, create reporters, expose cancel command, clear completed progress.
- Create `Sources/MyMacFinder/UI/OperationProgressBanner.swift`
  - Compact banner shown above panes while an operation is active or just completed.
- Modify `Sources/MyMacFinder/App/RootView.swift`
  - Place the banner between toolbar/tab area and file panes.
- Add tests:
  - `Tests/MyMacFinderTests/FileOperationProgressTests.swift`
  - `Tests/MyMacFinderTests/FileOperationProgressReporterTests.swift`
  - `Tests/MyMacFinderTests/FileOperationManifestBuilderTests.swift`
  - Extend `FileOperationServiceTests`, `ZipExtractionServiceTests`, `ZipCompressionServiceTests`, and `ExplorerStoreTests`.

## Task 1: Progress Domain Model

**Files:**

- Create `Sources/MyMacFinder/Domain/FileOperationProgress.swift`
- Create `Tests/MyMacFinderTests/FileOperationProgressTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MyMacFinderTests/FileOperationProgressTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileOperationProgressTests: XCTestCase {
    func testFractionCompletedUsesUnitsWhenByteTotalsAreMissing() {
        let snapshot = FileOperationProgressSnapshot(
            id: FileOperationID(),
            kind: .copy,
            phase: .running,
            title: "Copying 4 items",
            currentItemName: "b.txt",
            completedUnitCount: 1,
            totalUnitCount: 4,
            completedBytes: nil,
            totalBytes: nil,
            isCancellable: true
        )

        XCTAssertEqual(snapshot.fractionCompleted, 0.25)
        XCTAssertEqual(snapshot.statusText, "1 of 4")
    }

    func testFractionCompletedPrefersBytesWhenAvailable() {
        let snapshot = FileOperationProgressSnapshot(
            id: FileOperationID(),
            kind: .copy,
            phase: .running,
            title: "Copying 1 item",
            currentItemName: "large.mov",
            completedUnitCount: 0,
            totalUnitCount: 1,
            completedBytes: 512,
            totalBytes: 1024,
            isCancellable: true
        )

        XCTAssertEqual(snapshot.fractionCompleted, 0.5)
        XCTAssertEqual(snapshot.statusText, "512 bytes of 1 KB")
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter FileOperationProgressTests
```

Expected: build fails because `FileOperationProgressSnapshot` does not exist.

- [ ] **Step 3: Add domain model**

Create `Sources/MyMacFinder/Domain/FileOperationProgress.swift`:

```swift
import Foundation

public struct FileOperationID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum FileOperationKind: String, Codable, Sendable {
    case createFolder
    case rename
    case duplicate
    case copy
    case move
    case trash
    case extractZip
    case compressZip
}

public enum FileOperationPhase: String, Codable, Sendable {
    case preparing
    case resolvingConflict
    case running
    case writingArchive
    case finishing
    case completed
    case failed
    case cancelled
}

public struct FileOperationProgressSnapshot: Equatable, Sendable {
    public var id: FileOperationID
    public var kind: FileOperationKind
    public var phase: FileOperationPhase
    public var title: String
    public var currentItemName: String?
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var completedBytes: Int64?
    public var totalBytes: Int64?
    public var isCancellable: Bool
    public var errorMessage: String?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: FileOperationID = FileOperationID(),
        kind: FileOperationKind,
        phase: FileOperationPhase = .preparing,
        title: String,
        currentItemName: String? = nil,
        completedUnitCount: Int = 0,
        totalUnitCount: Int? = nil,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        isCancellable: Bool = true,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.phase = phase
        self.title = title
        self.currentItemName = currentItemName
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.isCancellable = isCancellable
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var fractionCompleted: Double? {
        if let completedBytes, let totalBytes, totalBytes > 0 {
            return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
        }
        if let totalUnitCount, totalUnitCount > 0 {
            return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
        }
        return nil
    }

    public var statusText: String {
        if let completedBytes, let totalBytes {
            return "\(Self.sizeText(completedBytes)) of \(Self.sizeText(totalBytes))"
        }
        if let totalUnitCount {
            return "\(completedUnitCount) of \(totalUnitCount)"
        }
        return currentItemName ?? phase.rawValue
    }

    private static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter FileOperationProgressTests
```

Expected: `FileOperationProgressTests` passes.

## Task 2: Progress Reporter And Cancellation

**Files:**

- Create `Sources/MyMacFinder/Services/FileOperationProgressReporter.swift`
- Create `Tests/MyMacFinderTests/FileOperationProgressReporterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MyMacFinderTests/FileOperationProgressReporterTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileOperationProgressReporterTests: XCTestCase {
    func testReporterPublishesSnapshotsInOrder() async {
        let recorder = ProgressRecorder()
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
            onUpdate: { snapshot in
                await recorder.append(snapshot)
            }
        )

        await reporter.update(phase: .running, currentItemName: "a.txt", completedUnitCount: 1, totalUnitCount: 2)
        await reporter.complete()

        let snapshots = await recorder.snapshots
        XCTAssertEqual(snapshots.map(\.phase), [.running, .completed])
        XCTAssertEqual(snapshots.first?.currentItemName, "a.txt")
    }

    func testCheckCancellationThrowsAfterCancel() async {
        let reporter = FileOperationProgressReporter(
            initialSnapshot: FileOperationProgressSnapshot(kind: .move, title: "Moving"),
            onUpdate: { _ in }
        )

        await reporter.cancel()

        do {
            try await reporter.checkCancellation()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor ProgressRecorder {
    private(set) var snapshots: [FileOperationProgressSnapshot] = []

    func append(_ snapshot: FileOperationProgressSnapshot) {
        snapshots.append(snapshot)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter FileOperationProgressReporterTests
```

Expected: build fails because `FileOperationProgressReporter` does not exist.

- [ ] **Step 3: Add reporter**

Create `Sources/MyMacFinder/Services/FileOperationProgressReporter.swift`:

```swift
import Foundation

public actor FileOperationProgressReporter {
    public typealias UpdateHandler = @Sendable (FileOperationProgressSnapshot) async -> Void

    private var snapshot: FileOperationProgressSnapshot
    private let onUpdate: UpdateHandler
    private var isCancelled = false

    public init(
        initialSnapshot: FileOperationProgressSnapshot,
        onUpdate: @escaping UpdateHandler
    ) {
        self.snapshot = initialSnapshot
        self.onUpdate = onUpdate
    }

    public var currentSnapshot: FileOperationProgressSnapshot {
        snapshot
    }

    public func update(
        phase: FileOperationPhase? = nil,
        currentItemName: String? = nil,
        completedUnitCount: Int? = nil,
        totalUnitCount: Int? = nil,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil
    ) async {
        if let phase {
            snapshot.phase = phase
        }
        if let currentItemName {
            snapshot.currentItemName = currentItemName
        }
        if let completedUnitCount {
            snapshot.completedUnitCount = completedUnitCount
        }
        if let totalUnitCount {
            snapshot.totalUnitCount = totalUnitCount
        }
        if let completedBytes {
            snapshot.completedBytes = completedBytes
        }
        if let totalBytes {
            snapshot.totalBytes = totalBytes
        }
        await onUpdate(snapshot)
    }

    public func complete() async {
        snapshot.phase = .completed
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func fail(_ message: String) async {
        snapshot.phase = .failed
        snapshot.errorMessage = message
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func cancel() async {
        isCancelled = true
        snapshot.phase = .cancelled
        snapshot.finishedAt = Date()
        snapshot.isCancellable = false
        await onUpdate(snapshot)
    }

    public func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter FileOperationProgressReporterTests
```

Expected: reporter tests pass.

## Task 3: Manifest Builder

**Files:**

- Create `Sources/MyMacFinder/Services/FileOperationManifestBuilder.swift`
- Create `Tests/MyMacFinderTests/FileOperationManifestBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MyMacFinderTests/FileOperationManifestBuilderTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class FileOperationManifestBuilderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testManifestCountsNestedFilesAndBytes() throws {
        let folder = tempDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: folder.appendingPathComponent("a.bin"))
        try Data(repeating: 1, count: 6).write(to: folder.appendingPathComponent("b.bin"))

        let manifest = try FileOperationManifestBuilder().manifest(for: [folder])

        XCTAssertEqual(manifest.totalFileCount, 2)
        XCTAssertEqual(manifest.totalByteCount, 10)
        XCTAssertEqual(manifest.roots, [folder.standardizedFileURL])
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter FileOperationManifestBuilderTests
```

Expected: build fails because `FileOperationManifestBuilder` does not exist.

- [ ] **Step 3: Add manifest builder**

Create `Sources/MyMacFinder/Services/FileOperationManifestBuilder.swift`:

```swift
import Foundation

public struct FileOperationManifest: Equatable, Sendable {
    public var roots: [URL]
    public var totalFileCount: Int
    public var totalByteCount: Int64
}

public struct FileOperationManifestBuilder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func manifest(for urls: [URL]) throws -> FileOperationManifest {
        var totalFileCount = 0
        var totalByteCount: Int64 = 0

        for url in urls.map(\.standardizedFileURL) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ExplorerError.pathDoesNotExist(url.path)
            }
            if isDirectory.boolValue {
                let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if values.isRegularFile == true {
                        totalFileCount += 1
                        totalByteCount += Int64(values.fileSize ?? 0)
                    }
                }
            } else {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                totalFileCount += 1
                totalByteCount += Int64(values.fileSize ?? 0)
            }
        }

        return FileOperationManifest(
            roots: urls.map(\.standardizedFileURL),
            totalFileCount: totalFileCount,
            totalByteCount: totalByteCount
        )
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter FileOperationManifestBuilderTests
```

Expected: manifest tests pass.

## Task 4: Wire Progress Into FileOperationService

**Files:**

- Modify `Sources/MyMacFinder/Services/FileOperationService.swift`
- Modify `Tests/MyMacFinderTests/FileOperationServiceTests.swift`

- [ ] **Step 1: Add failing copy progress test**

Add to `FileOperationServiceTests`:

```swift
func testCopyItemsReportsProgressPerSource() async throws {
    let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
    let destFolder = tempDirectory.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
    let first = sourceFolder.appendingPathComponent("a.txt")
    let second = sourceFolder.appendingPathComponent("b.txt")
    try "a".write(to: first, atomically: true, encoding: .utf8)
    try "b".write(to: second, atomically: true, encoding: .utf8)
    let recorder = ProgressRecorder()
    let reporter = FileOperationProgressReporter(
        initialSnapshot: FileOperationProgressSnapshot(kind: .copy, title: "Copying"),
        onUpdate: { snapshot in await recorder.append(snapshot) }
    )

    _ = try await FileOperationService().copyItems([first, second], to: destFolder, progress: reporter)

    let snapshots = await recorder.snapshots
    XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 1 && $0.currentItemName == "a.txt" })
    XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 2 && $0.currentItemName == "b.txt" })
}
```

Add the same `ProgressRecorder` actor used by reporter tests if the test file does not already have it.

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
swift test --filter FileOperationServiceTests/testCopyItemsReportsProgressPerSource
```

Expected: build fails because `copyItems` has no `progress:` parameter.

- [ ] **Step 3: Add optional progress parameters and checks**

Modify service signatures:

```swift
public func duplicate(_ url: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
public func copyItems(_ urls: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
public func moveItems(_ urls: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
public func moveToTrash(_ urls: [URL], progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
```

Inside loops, before each filesystem mutation:

```swift
try await progress?.checkCancellation()
await progress?.update(
    phase: .running,
    currentItemName: source.lastPathComponent,
    completedUnitCount: index,
    totalUnitCount: urls.count
)
```

After each successful item:

```swift
await progress?.update(
    phase: .running,
    currentItemName: source.lastPathComponent,
    completedUnitCount: index + 1,
    totalUnitCount: urls.count
)
```

Do not call `complete()` in the service. `ExplorerStore` owns operation lifecycle completion so undo/refresh failures can still mark the operation failed.

- [ ] **Step 4: Run file operation tests**

Run:

```bash
swift test --filter FileOperationServiceTests
```

Expected: file operation tests pass.

## Task 5: Wire Progress Into ZIP Services

**Files:**

- Modify `Sources/MyMacFinder/Services/ZipExtractionService.swift`
- Modify `Sources/MyMacFinder/Services/ZipCompressionService.swift`
- Modify `Tests/MyMacFinderTests/ZipExtractionServiceTests.swift`
- Modify `Tests/MyMacFinderTests/ZipCompressionServiceTests.swift`

- [ ] **Step 1: Add failing ZIP extraction progress test**

Add to `ZipExtractionServiceTests`:

```swift
func testExtractionReportsProgressForArchiveEntries() async throws {
    let zipURL = try makeZip(named: "sample.zip", entries: ["a.txt": "a", "b.txt": "b"])
    let recorder = ProgressRecorder()
    let reporter = FileOperationProgressReporter(
        initialSnapshot: FileOperationProgressSnapshot(kind: .extractZip, title: "Extracting"),
        onUpdate: { snapshot in await recorder.append(snapshot) }
    )

    _ = try await ZipExtractionService().extract([zipURL], to: tempDirectory, progress: reporter)

    let snapshots = await recorder.snapshots
    XCTAssertTrue(snapshots.contains { $0.totalUnitCount == 2 })
    XCTAssertTrue(snapshots.contains { $0.completedUnitCount == 2 })
}
```

- [ ] **Step 2: Add failing ZIP compression progress test**

Add to `ZipCompressionServiceTests`:

```swift
func testCompressionReportsArchiveWritingPhase() async throws {
    let source = tempDirectory.appendingPathComponent("source.txt")
    try "source".write(to: source, atomically: true, encoding: .utf8)
    let recorder = ProgressRecorder()
    let reporter = FileOperationProgressReporter(
        initialSnapshot: FileOperationProgressSnapshot(kind: .compressZip, title: "Compressing"),
        onUpdate: { snapshot in await recorder.append(snapshot) }
    )

    _ = try await ZipCompressionService().compress([source], to: tempDirectory, progress: reporter)

    let snapshots = await recorder.snapshots
    XCTAssertTrue(snapshots.contains { $0.phase == .writingArchive })
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter ZipExtractionServiceTests/testExtractionReportsProgressForArchiveEntries --filter ZipCompressionServiceTests/testCompressionReportsArchiveWritingPhase
```

Expected: build fails because ZIP services do not accept `progress:`.

- [ ] **Step 4: Add progress parameters**

Modify protocols and implementations:

```swift
public protocol ZipExtracting: Sendable {
    func extract(_ zipURLs: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter?) async throws -> FileOperationResult
}

public extension ZipExtracting {
    func extract(_ zipURLs: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        try await extract(zipURLs, to: destinationFolder, progress: nil)
    }
}

public protocol ZipCompressing: Sendable {
    func compress(_ urls: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter?) async throws -> FileOperationResult
}

public extension ZipCompressing {
    func compress(_ urls: [URL], to destinationFolder: URL) async throws -> FileOperationResult {
        try await compress(urls, to: destinationFolder, progress: nil)
    }
}
```

Keep overload compatibility by giving default values in concrete implementation calls:

```swift
public func extract(_ zipURLs: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
public func compress(_ urls: [URL], to destinationFolder: URL, progress: FileOperationProgressReporter? = nil) async throws -> FileOperationResult
```

In extraction, compute `let entries = Array(archive)` and report `totalUnitCount: entries.count`. Call `try await progress?.checkCancellation()` between entries.

In compression, report `.running` for staging copies and `.writingArchive` immediately before `fileManager.zipItem`.

- [ ] **Step 5: Run ZIP tests**

Run:

```bash
swift test --filter ZipExtractionServiceTests --filter ZipCompressionServiceTests
```

Expected: ZIP tests pass.

## Task 6: ExplorerStore Operation Lifecycle

**Files:**

- Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify `Tests/MyMacFinderTests/ExplorerStoreTests.swift`

- [ ] **Step 1: Add failing store lifecycle test**

Add to `ExplorerStoreTests`:

```swift
@MainActor
func testCopyCommandPublishesOperationProgress() async throws {
    let file = tempDirectory.appendingPathComponent("a.txt")
    try "a".write(to: file, atomically: true, encoding: .utf8)
    let destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let store = ExplorerStore(initialURL: tempDirectory)
    await store.refresh()
    store.updateSelection([file.standardizedFileURL])
    await store.perform(.copy)
    await store.navigate(to: destination)

    await store.perform(.paste)

    XCTAssertEqual(store.activeOperationProgress?.phase, .completed)
    XCTAssertEqual(store.activeOperationProgress?.kind, .copy)
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
swift test --filter ExplorerStoreTests/testCopyCommandPublishesOperationProgress
```

Expected: build fails because `activeOperationProgress` does not exist.

- [ ] **Step 3: Add store progress state**

Add published state:

```swift
@Published public private(set) var activeOperationProgress: FileOperationProgressSnapshot?
private var activeOperationReporter: FileOperationProgressReporter?
```

Add helper:

```swift
private func makeOperationReporter(kind: FileOperationKind, title: String) -> FileOperationProgressReporter {
    let snapshot = FileOperationProgressSnapshot(kind: kind, title: title)
    activeOperationProgress = snapshot
    let reporter = FileOperationProgressReporter(initialSnapshot: snapshot) { [weak self] snapshot in
        await MainActor.run {
            self?.activeOperationProgress = snapshot
        }
    }
    activeOperationReporter = reporter
    return reporter
}
```

Add methods:

```swift
public func cancelActiveOperation() {
    guard let activeOperationReporter else { return }
    Task {
        await activeOperationReporter.cancel()
    }
}

public func clearCompletedOperationProgress() {
    guard let phase = activeOperationProgress?.phase,
          [.completed, .failed, .cancelled].contains(phase) else {
        return
    }
    activeOperationProgress = nil
    activeOperationReporter = nil
}
```

Wrap paste/copy/move/trash/extract/compress calls with reporters, call `await reporter.complete()` after undo and refresh succeed, and call `await reporter.fail(error.localizedDescription)` in catch blocks before setting `visibleError`.

- [ ] **Step 4: Run store tests**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: store tests pass.

## Task 7: Operation Progress Banner UI

**Files:**

- Create `Sources/MyMacFinder/UI/OperationProgressBanner.swift`
- Modify `Sources/MyMacFinder/App/RootView.swift`
- Add `Tests/MyMacFinderTests/OperationProgressBannerTests.swift` if the project already supports lightweight SwiftUI view wiring tests; otherwise test the formatter/model only.

- [ ] **Step 1: Add banner model formatting test**

Create `Tests/MyMacFinderTests/OperationProgressBannerTests.swift`:

```swift
import XCTest
@testable import MyMacFinder

final class OperationProgressBannerTests: XCTestCase {
    func testCompletedSnapshotIsDismissible() {
        let snapshot = FileOperationProgressSnapshot(
            kind: .copy,
            phase: .completed,
            title: "Copied 2 items",
            completedUnitCount: 2,
            totalUnitCount: 2,
            isCancellable: false
        )

        XCTAssertTrue(snapshot.isTerminal)
    }
}
```

Add `isTerminal` to `FileOperationProgressSnapshot`:

```swift
public var isTerminal: Bool {
    phase == .completed || phase == .failed || phase == .cancelled
}
```

- [ ] **Step 2: Create banner view**

Create `Sources/MyMacFinder/UI/OperationProgressBanner.swift`:

```swift
import SwiftUI

struct OperationProgressBanner: View {
    let snapshot: FileOperationProgressSnapshot
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: snapshot.fractionCompleted)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.currentItemName ?? snapshot.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(snapshot.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if snapshot.isCancellable {
                Button("Cancel", action: onCancel)
            } else if snapshot.isTerminal {
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
```

- [ ] **Step 3: Wire banner into RootView**

In `RootView.body`, between `TabBarView()` and `Divider()`, add:

```swift
if let progress = explorerStore.activeOperationProgress {
    OperationProgressBanner(
        snapshot: progress,
        onCancel: { explorerStore.cancelActiveOperation() },
        onDismiss: { explorerStore.clearCompletedOperationProgress() }
    )
}
```

- [ ] **Step 4: Run UI-related tests**

Run:

```bash
swift test --filter OperationProgressBannerTests --filter ExplorerStoreTests/testCopyCommandPublishesOperationProgress
```

Expected: tests pass.

## Task 8: Focused Manual QA And Verification

**Files:**

- Modify `docs/qa/file-operations-stabilization-manual-qa.md` or create `docs/qa/large-file-operation-ux-manual-qa.md`

- [ ] **Step 1: Add manual QA fixture instructions**

Create `docs/qa/large-file-operation-ux-manual-qa.md`:

````markdown
# Large File Operation UX Manual QA

## Setup

Run:

```bash
QA_DIR="$HOME/MyMacFinderLargeOperationQA"
rm -rf "$QA_DIR"
mkdir -p "$QA_DIR/source" "$QA_DIR/dest"
for i in $(seq -w 1 200); do
  printf "file-$i\n" > "$QA_DIR/source/file-$i.txt"
done
./scripts/build_app.sh
open build/MyMacFinder.app
```

## Copy Progress

1. Navigate to `$QA_DIR/source`.
2. Select all generated files.
3. Copy.
4. Navigate to `$QA_DIR/dest`.
5. Paste.
6. Expected: operation banner appears, count advances, banner reaches completed state, and files exist in dest.

## Cancel Progress

1. Repeat copy with a larger fixture if the operation completes too quickly.
2. Press Cancel while the banner is visible.
3. Expected: banner changes to canceled or operation stops before all queued top-level items complete. Already copied files remain.

## Cleanup

Run:

```bash
rm -rf "$QA_DIR"
```
````

- [ ] **Step 2: Run full automated verification**

Run:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

Expected: tests pass, diff check prints no errors, and app bundle builds.

- [ ] **Step 3: Run release app manual QA**

Run:

```bash
open build/MyMacFinder.app
```

Use the manual QA document above. Expected: banner appears for multi-file copy, completion and cancel states are visible, and the app remains responsive.

- [ ] **Step 4: Commit Phase 1**

Run:

```bash
git add Sources/MyMacFinder Tests/MyMacFinderTests docs/qa/large-file-operation-ux-manual-qa.md
git commit -m "feat: add large file operation progress UX"
```

Expected: commit succeeds with only Phase 1 files.

## Self-Review

- Spec coverage: progress model, cancellation, service wiring, store state, UI banner, ZIP operations, manual QA, and final verification are each covered by tasks.
- Red-flag scan: no unresolved filler steps remain; each implementation step names files, methods, test commands, and expected results.
- Type consistency: planned names use `FileOperationProgressSnapshot`, `FileOperationProgressReporter`, and `activeOperationProgress` consistently.
- Scope check: this phase intentionally adds one active-operation banner, not the full queue/history UI. Full queue/history belongs to Phase 7 and will reuse the same model.
