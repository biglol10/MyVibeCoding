# ZIP Search Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add read-only ZIP browsing, current-pane search, large-folder performance hardening, shortcut polish, and a full manual QA pass.

**Architecture:** Add ZIPFoundation as the ZIP engine and keep archive parsing behind an `ArchiveBrowsing` service. Extend pane state from plain filesystem URLs to `PaneLocation`, while still rendering normal `FileEntry` rows so the table remains simple. Search is a store-level filtered view over loaded entries, and AppKit table changes stay focused on reuse, focus commands, and read-only archive safeguards.

**Tech Stack:** Swift 6.1.2, macOS 15 SDK, SwiftUI, AppKit `NSTableView`, XCTest, ZIPFoundation 0.9.x, `FileManager`, `NSWorkspace`, Quick Look.

---

## File Structure

- Modify: `Package.swift`
  - Add ZIPFoundation dependency and target dependency.
- Create: `Sources/MyMacFinder/Domain/ArchiveModels.swift`
  - Own `ArchiveLocation`, `PaneLocation`, and archive display path helpers.
- Modify: `Sources/MyMacFinder/Domain/FileEntry.swift`
  - Add `FileEntrySource` so rows can carry filesystem or archive provenance.
- Create: `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`
  - Implement read-only ZIP listing and temporary extraction through ZIPFoundation.
- Create: `Sources/MyMacFinder/Services/FileEntrySearchFilter.swift`
  - Implement current-pane filtering by name, extension, and kind.
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
  - Add command availability that accounts for archive read-only locations.
- Modify: `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
  - Add `Cmd+F`, `Cmd+L`, `Cmd+Up`, `Cmd+Shift+.`, and `Esc` command mapping for commands owned by MyMacFinder.
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
  - Load filesystem and archive panes, enforce archive read-only commands, hold search query, expose filtered entries, and route open/preview/copy path correctly.
- Modify: `Sources/MyMacFinder/UI/ToolbarPathView.swift`
  - Add native search field and focus hooks.
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
  - Reuse table cells, disable drag/drop for archive rows, route Return to open, and keep keyboard behavior stable.
- Modify: `Sources/MyMacFinder/App/RootView.swift`
  - Feed filtered entries to the table and wire search/focus actions.
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
  - Add menu commands and shortcuts for search, path focus, hidden toggle, parent navigation, and refresh.
- Tests:
  - `Tests/MyMacFinderTests/ArchiveModelsTests.swift`
  - `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`
  - `Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift`
  - `Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift`
  - `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
  - `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`
  - `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`

## Task 1: ZIPFoundation Dependency And Archive Domain Models

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MyMacFinder/Domain/ArchiveModels.swift`
- Modify: `Sources/MyMacFinder/Domain/FileEntry.swift`
- Test: `Tests/MyMacFinderTests/ArchiveModelsTests.swift`

- [ ] **Step 1: Write the failing model tests**

Create `Tests/MyMacFinderTests/ArchiveModelsTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class ArchiveModelsTests: XCTestCase {
    func testArchiveLocationNormalizesInternalPaths() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "").internalPath,
            ""
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "/docs/readme.txt").internalPath,
            "docs/readme.txt"
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs//nested/").internalPath,
            "docs/nested"
        )
    }

    func testArchiveDisplayPathUsesHostZipPathAndInternalPath() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "").displayPath,
            "/tmp/sample.zip/"
        )
        XCTAssertEqual(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt").displayPath,
            "/tmp/sample.zip/docs/readme.txt"
        )
    }

    func testArchiveParentNavigationStaysInsideArchive() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let nested = ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/guides")
        let root = ArchiveLocation(archiveURL: archiveURL, internalPath: "")

        XCTAssertEqual(nested.parent, ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"))
        XCTAssertEqual(root.parent, root)
    }

    func testPaneLocationDisplayPathAndArchiveFlag() {
        let folderURL = URL(fileURLWithPath: "/Users/biglol")
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")

        XCTAssertEqual(PaneLocation.fileSystem(folderURL).displayPath, "/Users/biglol")
        XCTAssertFalse(PaneLocation.fileSystem(folderURL).isArchive)

        let archive = PaneLocation.archive(ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"))
        XCTAssertEqual(archive.displayPath, "/tmp/sample.zip/docs")
        XCTAssertTrue(archive.isArchive)
    }

    func testFileEntryDefaultsToFileSystemSource() {
        let url = URL(fileURLWithPath: "/tmp/note.txt")
        let entry = FileEntry(
            url: url,
            name: "note.txt",
            kind: .file,
            typeDescription: "Plain Text Document",
            fileExtension: "txt",
            size: 4,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true
        )

        XCTAssertEqual(entry.source, .fileSystem)
        XCTAssertFalse(entry.isArchiveBacked)
    }
}
```

- [ ] **Step 2: Run the model tests and verify RED**

Run:

```bash
swift test --filter ArchiveModelsTests
```

Expected: FAIL with errors containing `cannot find 'ArchiveLocation' in scope`, `cannot find 'PaneLocation' in scope`, and `value of type 'FileEntry' has no member 'source'`.

- [ ] **Step 3: Add ZIPFoundation dependency**

Modify `Package.swift` to:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyMacFinder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MyMacFinder", targets: ["MyMacFinder"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.20"))
    ],
    targets: [
        .executableTarget(
            name: "MyMacFinder",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/MyMacFinder"
        ),
        .testTarget(
            name: "MyMacFinderTests",
            dependencies: [
                "MyMacFinder",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Tests/MyMacFinderTests"
        )
    ]
)
```

- [ ] **Step 4: Create archive models**

Create `Sources/MyMacFinder/Domain/ArchiveModels.swift`:

```swift
import Foundation

public struct ArchiveLocation: Codable, Equatable, Hashable, Sendable {
    public var archiveURL: URL
    public var internalPath: String

    public init(archiveURL: URL, internalPath: String) {
        self.archiveURL = archiveURL.standardizedFileURL
        self.internalPath = Self.normalize(internalPath)
    }

    public var displayPath: String {
        internalPath.isEmpty ? "\(archiveURL.path)/" : "\(archiveURL.path)/\(internalPath)"
    }

    public var parent: ArchiveLocation {
        guard !internalPath.isEmpty else {
            return self
        }
        let parentPath = NSString(string: internalPath).deletingLastPathComponent
        return ArchiveLocation(archiveURL: archiveURL, internalPath: parentPath == "." ? "" : parentPath)
    }

    public func appending(_ component: String) -> ArchiveLocation {
        ArchiveLocation(
            archiveURL: archiveURL,
            internalPath: [internalPath, component].filter { !$0.isEmpty }.joined(separator: "/")
        )
    }

    public static func normalize(_ rawPath: String) -> String {
        rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}

public enum PaneLocation: Codable, Equatable, Hashable, Sendable {
    case fileSystem(URL)
    case archive(ArchiveLocation)

    public var displayPath: String {
        switch self {
        case .fileSystem(let url):
            return url.path
        case .archive(let location):
            return location.displayPath
        }
    }

    public var fileSystemURL: URL? {
        switch self {
        case .fileSystem(let url):
            return url
        case .archive:
            return nil
        }
    }

    public var archiveLocation: ArchiveLocation? {
        switch self {
        case .fileSystem:
            return nil
        case .archive(let location):
            return location
        }
    }

    public var isArchive: Bool {
        archiveLocation != nil
    }
}

public enum FileEntrySource: Codable, Equatable, Hashable, Sendable {
    case fileSystem
    case archive(ArchiveLocation)
}
```

- [ ] **Step 5: Add source to FileEntry**

Modify `Sources/MyMacFinder/Domain/FileEntry.swift` by adding:

```swift
public let source: FileEntrySource
```

to `FileEntry`, adding `source: FileEntrySource = .fileSystem` to the initializer, setting `self.source = source`, and adding:

```swift
public var isArchiveBacked: Bool {
    if case .archive = source {
        return true
    }
    return false
}
```

- [ ] **Step 6: Run model tests and package resolution**

Run:

```bash
swift package resolve
swift test --filter ArchiveModelsTests
```

Expected: PASS with `ArchiveModelsTests` reporting 5 tests and 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Package.resolved Sources/MyMacFinder/Domain/ArchiveModels.swift Sources/MyMacFinder/Domain/FileEntry.swift Tests/MyMacFinderTests/ArchiveModelsTests.swift
git commit -m "feat: add archive location models"
```

## Task 2: Archive Browsing Service

**Files:**
- Create: `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`
- Test: `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`

- [ ] **Step 1: Write failing archive service tests**

Create `Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift`:

```swift
import Foundation
import XCTest
import ZIPFoundation
@testable import MyMacFinder

final class ArchiveBrowsingServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCanOpenOnlyZipFiles() {
        let service = ArchiveBrowsingService()

        XCTAssertTrue(service.canOpen(URL(fileURLWithPath: "/tmp/archive.zip")))
        XCTAssertFalse(service.canOpen(URL(fileURLWithPath: "/tmp/archive.txt")))
    }

    func testListsRootAndNestedFolders() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()

        let rootEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: ""),
            showHiddenFiles: false
        )
        XCTAssertEqual(rootEntries.map(\.name).sorted(), ["docs", "image.png"])
        XCTAssertTrue(rootEntries.first { $0.name == "docs" }?.isDirectory == true)

        let nestedEntries = try await service.list(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs"),
            showHiddenFiles: false
        )
        XCTAssertEqual(nestedEntries.map(\.name).sorted(), ["readme.txt"])
        XCTAssertEqual(nestedEntries.first?.size, 5)
    }

    func testFiltersHiddenEntries() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "hidden")

        let hiddenOff = try await service.list(location, showHiddenFiles: false)
        let hiddenOn = try await service.list(location, showHiddenFiles: true)

        XCTAssertEqual(hiddenOff.map(\.name), [])
        XCTAssertEqual(hiddenOn.map(\.name), [".secret"])
    }

    func testTemporaryExtractReturnsReadableFile() async throws {
        let archiveURL = try makeArchive()
        let service = ArchiveBrowsingService()
        let extracted = try await service.temporaryExtract(
            ArchiveLocation(archiveURL: archiveURL, internalPath: "docs/readme.txt")
        )

        XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "hello")
    }

    func testInvalidZipThrowsReadableExplorerError() async throws {
        let invalid = tempDirectory.appendingPathComponent("broken.zip")
        try "not a zip".write(to: invalid, atomically: true, encoding: .utf8)
        let service = ArchiveBrowsingService()

        do {
            _ = try await service.list(
                ArchiveLocation(archiveURL: invalid, internalPath: ""),
                showHiddenFiles: false
            )
            XCTFail("Expected invalid archive to throw")
        } catch let error as ExplorerError {
            XCTAssertTrue(error.localizedDescription.contains("ZIP"))
        }
    }

    private func makeArchive() throws -> URL {
        let source = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("hidden", isDirectory: true), withIntermediateDirectories: true)
        try "hello".write(to: source.appendingPathComponent("docs/readme.txt"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source.appendingPathComponent("image.png"))
        try "secret".write(to: source.appendingPathComponent("hidden/.secret"), atomically: true, encoding: .utf8)

        let archiveURL = tempDirectory.appendingPathComponent("fixture.zip")
        try FileManager.default.zipItem(at: source, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        return archiveURL
    }
}
```

- [ ] **Step 2: Run archive service tests and verify RED**

Run:

```bash
swift test --filter ArchiveBrowsingServiceTests
```

Expected: FAIL with `cannot find 'ArchiveBrowsingService' in scope`.

- [ ] **Step 3: Implement ArchiveBrowsingService**

Create `Sources/MyMacFinder/Services/ArchiveBrowsingService.swift`:

```swift
import Foundation
import ZIPFoundation

public struct ArchiveEntry: Equatable, Sendable {
    public var location: ArchiveLocation
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modifiedAt: Date?

    public init(
        location: ArchiveLocation,
        name: String,
        isDirectory: Bool,
        size: Int64?,
        modifiedAt: Date?
    ) {
        self.location = location
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public protocol ArchiveBrowsing: Sendable {
    func canOpen(_ url: URL) -> Bool
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry]
    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL
}

public struct ArchiveBrowsingService: ArchiveBrowsing {
    private let fileManager: FileManager
    private let extractionRoot: URL

    public init(
        fileManager: FileManager = .default,
        extractionRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchivePreview", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.extractionRoot = extractionRoot
    }

    public func canOpen(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
    }

    public func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] {
        try await Task.detached(priority: .userInitiated) {
            let archive = try self.openArchive(location.archiveURL)
            let prefix = location.internalPath.isEmpty ? "" : "\(location.internalPath)/"
            var folders: [String: ArchiveEntry] = [:]
            var files: [ArchiveEntry] = []

            for entry in archive {
                guard entry.path.hasPrefix(prefix) else {
                    continue
                }

                let remainder = String(entry.path.dropFirst(prefix.count))
                guard !remainder.isEmpty else {
                    continue
                }

                let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
                guard let first = components.first else {
                    continue
                }

                let name = String(first)
                if !showHiddenFiles && name.hasPrefix(".") {
                    continue
                }

                if components.count > 1 {
                    let folderLocation = location.appending(name)
                    folders[name] = ArchiveEntry(
                        location: folderLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: nil
                    )
                    continue
                }

                let entryLocation = location.appending(name)
                if entry.type == .directory {
                    folders[name] = ArchiveEntry(
                        location: entryLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                    )
                } else {
                    files.append(
                        ArchiveEntry(
                            location: entryLocation,
                            name: name,
                            isDirectory: false,
                            size: Int64(entry.uncompressedSize),
                            modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                        )
                    )
                }
            }

            return Array(folders.values) + files
        }.value
    }

    public func temporaryExtract(_ location: ArchiveLocation) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let archive = try self.openArchive(location.archiveURL)
            guard let entry = archive[location.internalPath], entry.type != .directory else {
                throw ExplorerError.readFailed("ZIP entry cannot be previewed: \(location.displayPath)")
            }

            try self.fileManager.createDirectory(at: self.extractionRoot, withIntermediateDirectories: true)
            let targetFolder = self.extractionRoot
                .appendingPathComponent(location.archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try self.fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            let destination = targetFolder.appendingPathComponent(URL(fileURLWithPath: location.internalPath).lastPathComponent)
            try archive.extract(entry, to: destination)
            return destination
        }.value
    }

    private func openArchive(_ url: URL) throws -> Archive {
        do {
            return try Archive(url: url, accessMode: .read)
        } catch {
            throw ExplorerError.readFailed("ZIP archive could not be read: \(url.path)")
        }
    }
}
```

- [ ] **Step 4: Run archive service tests and full build**

Run:

```bash
swift test --filter ArchiveBrowsingServiceTests
swift build
```

Expected: PASS with `ArchiveBrowsingServiceTests` reporting 5 tests and 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/Services/ArchiveBrowsingService.swift Tests/MyMacFinderTests/ArchiveBrowsingServiceTests.swift
git commit -m "feat: add read-only archive browsing service"
```

## Task 3: PaneLocation Store Migration

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerModels.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift`

- [ ] **Step 1: Write failing store navigation tests**

Create `Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

private final class TestArchiveBrowser: ArchiveBrowsing {
    var entriesByLocation: [ArchiveLocation: [ArchiveEntry]] = [:]

    func canOpen(_ url: URL) -> Bool {
        url.pathExtension == "zip"
    }

    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] {
        entriesByLocation[location] ?? []
    }

    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL {
        URL(fileURLWithPath: "/tmp/extracted-\(location.nameForTemporaryFile)")
    }
}

final class ExplorerArchiveNavigationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchiveStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testOpeningZipEntersArchiveRoot() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        let root = ArchiveLocation(archiveURL: zip, internalPath: "")
        archive.entriesByLocation[root] = [
            ArchiveEntry(location: root.appending("docs"), name: "docs", isDirectory: true, size: nil, modifiedAt: nil)
        ]
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()

        await store.open(zip.standardizedFileURL)

        XCTAssertEqual(store.activePane.location, .archive(root))
        XCTAssertEqual(store.pathInput, zip.path + "/")
        XCTAssertEqual(store.activePane.entries.map(\.name), ["docs"])
    }

    @MainActor
    func testOpeningArchiveFolderNavigatesInsideArchive() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        let root = ArchiveLocation(archiveURL: zip, internalPath: "")
        let docs = root.appending("docs")
        archive.entriesByLocation[root] = [
            ArchiveEntry(location: docs, name: "docs", isDirectory: true, size: nil, modifiedAt: nil)
        ]
        archive.entriesByLocation[docs] = [
            ArchiveEntry(location: docs.appending("readme.txt"), name: "readme.txt", isDirectory: false, size: 5, modifiedAt: nil)
        ]
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.open(zip.standardizedFileURL)

        await store.open(store.activePane.entries[0].url)

        XCTAssertEqual(store.activePane.location, .archive(docs))
        XCTAssertEqual(store.activePane.backStack.last, .archive(root))
        XCTAssertEqual(store.activePane.entries.map(\.name), ["readme.txt"])
    }

    @MainActor
    func testGoUpFromArchiveRootReturnsToHostFolder() async throws {
        let zip = tempDirectory.appendingPathComponent("sample.zip")
        try Data().write(to: zip)
        let archive = TestArchiveBrowser()
        archive.entriesByLocation[ArchiveLocation(archiveURL: zip, internalPath: "")] = []
        let store = ExplorerStore(initialURL: tempDirectory, archiveBrowser: archive, directoryWatcher: nil)
        await store.loadInitialDirectory()
        await store.open(zip.standardizedFileURL)

        await store.goUp()

        XCTAssertEqual(store.activePane.location, .fileSystem(tempDirectory.standardizedFileURL))
    }
}

private extension ArchiveLocation {
    var nameForTemporaryFile: String {
        internalPath.replacingOccurrences(of: "/", with: "-")
    }
}
```

- [ ] **Step 2: Run archive navigation tests and verify RED**

Run:

```bash
swift test --filter ExplorerArchiveNavigationTests
```

Expected: FAIL with errors containing `extra argument 'archiveBrowser' in call` and `value of type 'PaneState' has no member 'location'`.

- [ ] **Step 3: Migrate PaneState to PaneLocation**

Modify `Sources/MyMacFinder/Domain/ExplorerModels.swift`:

```swift
public struct PaneState: Identifiable, Sendable {
    public let id: PaneID
    public var location: PaneLocation
    public var entries: [FileEntry]
    public var selectedURLs: Set<URL>
    public var backStack: [PaneLocation]
    public var forwardStack: [PaneLocation]
    public var sort: EntrySortDescriptor
    public var group: EntryGroupDescriptor?
    public var isLoading: Bool
    public var error: ExplorerError?

    public init(
        location: PaneLocation = .fileSystem(FileManager.default.homeDirectoryForCurrentUser),
        sort: EntrySortDescriptor = EntrySortDescriptor()
    ) {
        self.id = PaneID()
        self.location = location
        self.entries = []
        self.selectedURLs = []
        self.backStack = []
        self.forwardStack = []
        self.sort = sort
        self.group = nil
        self.isLoading = false
        self.error = nil
    }

    public init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        sort: EntrySortDescriptor = EntrySortDescriptor()
    ) {
        self.init(location: .fileSystem(currentURL.standardizedFileURL), sort: sort)
    }

    public var currentURL: URL {
        switch location {
        case .fileSystem(let url):
            return url
        case .archive(let archiveLocation):
            return archiveLocation.archiveURL
        }
    }

    public var selectedEntries: [FileEntry] {
        entries.filter { selectedURLs.contains($0.url) }
    }
}
```

- [ ] **Step 4: Add archiveBrowser to ExplorerStore and load by location**

Modify `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

- Add property:

```swift
private let archiveBrowser: any ArchiveBrowsing
```

- Add initializer parameter:

```swift
archiveBrowser: any ArchiveBrowsing = ArchiveBrowsingService(),
```

- Set `self.archiveBrowser = archiveBrowser`.

- Replace URL-only load helpers with location-aware helpers:

```swift
private func loadLocation(_ location: PaneLocation, pushHistory: Bool, paneIndex: Int? = nil) async throws {
    let targetPaneIndex = paneIndex ?? activePaneIndex
    guard panes.indices.contains(targetPaneIndex) else {
        return
    }

    panes[targetPaneIndex].isLoading = true
    defer {
        if panes.indices.contains(targetPaneIndex) {
            panes[targetPaneIndex].isLoading = false
        }
    }

    let entries: [FileEntry]
    switch location {
    case .fileSystem(let url):
        entries = try await fileSystemService.contentsOfDirectory(
            at: url,
            options: DirectoryReadOptions(showHiddenFiles: showHiddenFiles)
        )
    case .archive(let archiveLocation):
        let archiveEntries = try await archiveBrowser.list(archiveLocation, showHiddenFiles: showHiddenFiles)
        entries = archiveEntries.map(makeFileEntry)
    }

    var pane = panes[targetPaneIndex]
    if pushHistory && pane.location != location {
        pane.backStack.append(pane.location)
        pane.forwardStack.removeAll()
    }
    pane.location = location
    pane.entries = SortEngine.sorted(entries, descriptor: pane.sort)
    pane.selectedURLs = pane.selectedURLs.intersection(Set(pane.entries.map(\.url)))
    pane.error = nil
    panes[targetPaneIndex] = pane

    if targetPaneIndex == activePaneIndex {
        pathInput = location.displayPath
        startWatchingActiveDirectory()
    }
}

private func makeFileEntry(from archiveEntry: ArchiveEntry) -> FileEntry {
    let virtualURL = archiveEntry.location.virtualURL
    return FileEntry(
        url: virtualURL,
        name: archiveEntry.name,
        kind: archiveEntry.isDirectory ? .zipVirtualFolder : .zipVirtualFile,
        typeDescription: archiveEntry.isDirectory ? "ZIP Folder" : "ZIP Item",
        fileExtension: archiveEntry.isDirectory ? "" : URL(fileURLWithPath: archiveEntry.name).pathExtension.lowercased(),
        size: archiveEntry.isDirectory ? nil : archiveEntry.size,
        dateModified: archiveEntry.modifiedAt,
        dateCreated: nil,
        dateAccessed: nil,
        isHidden: archiveEntry.name.hasPrefix("."),
        isDirectoryLike: archiveEntry.isDirectory,
        isReadable: true,
        source: .archive(archiveEntry.location)
    )
}
```

- Add `virtualURL` to `ArchiveLocation` in `ArchiveModels.swift`:

```swift
public var virtualURL: URL {
    let archiveKey = archiveURL.path
        .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(abs(archiveURL.path.hashValue))
    let entryKey = internalPath.isEmpty ? "__root__" : internalPath
    return URL(fileURLWithPath: "/__MyMacFinderArchive__")
        .appendingPathComponent(archiveKey, isDirectory: true)
        .appendingPathComponent(entryKey)
}
```

- [ ] **Step 5: Update navigation methods**

Modify `open(_:)`, `navigate(to:)`, `goBack()`, `goForward()`, `goUp()`, `refresh()`, `reloadAllPanes()`, and watcher startup:

```swift
public func navigate(to targetURL: URL) async {
    await navigate(to: .fileSystem(targetURL.standardizedFileURL))
}

private func navigate(to location: PaneLocation) async {
    do {
        try await loadLocation(location, pushHistory: true)
    } catch let error as ExplorerError {
        visibleError = error
    } catch {
        visibleError = .readFailed(error.localizedDescription)
    }
}

public func open(_ url: URL) async {
    guard let entry = activePane.entries.first(where: { $0.url == url }) else {
        return
    }

    switch entry.source {
    case .fileSystem:
        if archiveBrowser.canOpen(entry.url) {
            await navigate(to: .archive(ArchiveLocation(archiveURL: entry.url, internalPath: "")))
        } else if entry.isDirectoryLike {
            await navigate(to: .fileSystem(entry.url))
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    case .archive(let location):
        if entry.isDirectoryLike {
            await navigate(to: .archive(location))
        } else {
            do {
                NSWorkspace.shared.open(try await archiveBrowser.temporaryExtract(location))
            } catch {
                visibleError = .readFailed(error.localizedDescription)
            }
        }
    }
}

public func goUp() async {
    switch activePane.location {
    case .fileSystem(let url):
        await navigate(to: .fileSystem(url.deletingLastPathComponent()))
    case .archive(let location):
        if location.internalPath.isEmpty {
            await navigate(to: .fileSystem(location.archiveURL.deletingLastPathComponent()))
        } else {
            await navigate(to: .archive(location.parent))
        }
    }
}
```

`startWatchingActiveDirectory()` must watch only filesystem pane folders. When the active pane is an archive location, call `directoryWatcher?.stopWatching()` and set `watchedDirectoryURL = nil`; ZIP host-file watching is left out of this pass.

- [ ] **Step 6: Run archive navigation tests**

Run:

```bash
swift test --filter ExplorerArchiveNavigationTests
swift test --filter ExplorerStoreTests
swift test --filter ExplorerLayoutSettingsTests
```

Expected: PASS for archive navigation and existing store/layout tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/MyMacFinder/Domain/ArchiveModels.swift Sources/MyMacFinder/Domain/ExplorerModels.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerArchiveNavigationTests.swift
git commit -m "feat: navigate read-only archive panes"
```

## Task 4: Archive Command Restrictions And Preview Actions

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Test: `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerCommandTests.swift`

- [ ] **Step 1: Write failing archive command tests**

Create `Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

private final class ExtractingArchiveBrowser: ArchiveBrowsing {
    var extractedURL: URL

    init(extractedURL: URL) {
        self.extractedURL = extractedURL
    }

    func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }
    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL { extractedURL }
}

private final class CapturingQuickLookService: QuickLooking {
    var previewedURLs: [URL] = []

    func preview(_ urls: [URL]) throws {
        previewedURLs = urls
    }
}

final class ExplorerArchiveCommandTests: XCTestCase {
    @MainActor
    func testMutationCommandsAreDisabledInsideArchive() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "readme.txt")
        let entry = FileEntry(
            url: location.virtualURL,
            name: "readme.txt",
            kind: .zipVirtualFile,
            typeDescription: "ZIP Item",
            fileExtension: "txt",
            size: 5,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true,
            source: .archive(location)
        )

        XCTAssertFalse(ExplorerCommand.newFolder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.moveToTrash.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.paste.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.cut.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))

        XCTAssertTrue(ExplorerCommand.open.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.quickLook.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.copyPath.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.revealInFinder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
    }

    @MainActor
    func testQuickLookExtractsArchiveEntryBeforePreviewing() async throws {
        let extracted = URL(fileURLWithPath: "/tmp/extracted-readme.txt")
        let archiveBrowser = ExtractingArchiveBrowser(extractedURL: extracted)
        let quickLook = CapturingQuickLookService()
        let store = ExplorerStore(
            archiveBrowser: archiveBrowser,
            directoryWatcher: nil,
            quickLookService: quickLook
        )
        let archiveLocation = ArchiveLocation(archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"), internalPath: "readme.txt")
        store.replaceActivePaneForTesting(
            location: .archive(archiveLocation.parent),
            entries: [
                FileEntry(
                    url: archiveLocation.virtualURL,
                    name: "readme.txt",
                    kind: .zipVirtualFile,
                    typeDescription: "ZIP Item",
                    fileExtension: "txt",
                    size: 5,
                    dateModified: nil,
                    dateCreated: nil,
                    dateAccessed: nil,
                    isHidden: false,
                    isDirectoryLike: false,
                    isReadable: true,
                    source: .archive(archiveLocation)
                )
            ],
            selectedURLs: [archiveLocation.virtualURL]
        )

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.previewedURLs, [extracted])
    }
}
```

- [ ] **Step 2: Run archive command tests and verify RED**

Run:

```bash
swift test --filter ExplorerArchiveCommandTests
```

Expected: FAIL with missing `isArchiveLocation` overload and missing `replaceActivePaneForTesting`.

- [ ] **Step 3: Add archive-aware command availability**

Modify `ExplorerCommand.isEnabled` to add:

```swift
public func isEnabled(
    selectionCount: Int,
    canPaste: Bool,
    selectedEntries: [FileEntry],
    isArchiveLocation: Bool
) -> Bool {
    if isArchiveLocation {
        switch self {
        case .open, .quickLook, .revealInFinder, .copyPath, .refresh:
            return self == .refresh || selectionCount > 0
        case .calculateFolderSize:
            return selectionCount == 1 && selectedEntries.first?.isDirectoryLike == true
        case .newFolder, .rename, .duplicate, .copy, .cut, .paste, .moveToTrash:
            return false
        }
    }

    return isEnabled(selectionCount: selectionCount, canPaste: canPaste, selectedEntries: selectedEntries)
}
```

Update call sites in `MyMacFinderApp` and `FileTableView` to pass `isArchiveLocation`.

- [ ] **Step 4: Route archive preview/copy/reveal commands**

Modify `ExplorerStore.perform(_:)` helpers:

```swift
private func quickLookSelected() async throws {
    let urls = try await selectedPreviewURLs()
    try quickLookService?.preview(urls)
}

private func selectedPreviewURLs() async throws -> [URL] {
    try await activePane.selectedEntries.asyncMap { entry in
        switch entry.source {
        case .fileSystem:
            return entry.url
        case .archive(let location):
            return try await archiveBrowser.temporaryExtract(location)
        }
    }
}

private func copySelectedPaths() {
    let paths = activePane.selectedEntries.map { entry in
        switch entry.source {
        case .fileSystem:
            return entry.url.path
        case .archive(let location):
            return location.displayPath
        }
    }.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(paths, forType: .string)
}

private func revealSelectedInFinder() {
    guard let first = activePane.selectedEntries.first else { return }
    switch first.source {
    case .fileSystem:
        NSWorkspace.shared.activateFileViewerSelecting([first.url])
    case .archive(let location):
        NSWorkspace.shared.activateFileViewerSelecting([location.archiveURL])
    }
}
```

Add this local async map helper:

```swift
private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
```

- [ ] **Step 5: Disable archive row drag/write**

Modify `FileTableView`:

```swift
func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    guard row >= 0, row < parent.entries.count else {
        return nil
    }
    let entry = parent.entries[row]
    guard !entry.isArchiveBacked else {
        return nil
    }
    return entry.url as NSURL
}
```

Add `currentLocation: PaneLocation` to `FileTableView`, pass it from `RootView`, and make `validateDrop` return `[]` when `parent.currentLocation.isArchive`.

- [ ] **Step 6: Add testing hook**

Add this test-only method to `ExplorerStore`:

```swift
#if DEBUG
public func replaceActivePaneForTesting(location: PaneLocation, entries: [FileEntry], selectedURLs: Set<URL>) {
    panes[activePaneIndex].location = location
    panes[activePaneIndex].entries = entries
    panes[activePaneIndex].selectedURLs = selectedURLs
    pathInput = location.displayPath
}
#endif
```

- [ ] **Step 7: Run archive command tests**

Run:

```bash
swift test --filter ExplorerArchiveCommandTests
swift test --filter ExplorerCommandTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Tests/MyMacFinderTests/ExplorerArchiveCommandTests.swift Tests/MyMacFinderTests/ExplorerCommandTests.swift
git commit -m "feat: restrict archive mutation commands"
```

## Task 5: Current-Pane Search Filter And Store State

**Files:**
- Create: `Sources/MyMacFinder/Services/FileEntrySearchFilter.swift`
- Modify: `Sources/MyMacFinder/Domain/ExplorerModels.swift`
- Modify: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Test: `Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift`
- Test: `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`

- [ ] **Step 1: Write failing search filter tests**

Create `Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FileEntrySearchFilterTests: XCTestCase {
    func testBlankQueryReturnsAllEntries() {
        let entries = [
            makeEntry(name: "Notes.txt", kind: .file, type: "Plain Text Document"),
            makeEntry(name: "Images", kind: .folder, type: "Folder")
        ]

        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "   "), entries)
    }

    func testFiltersByNameExtensionAndKindCaseInsensitively() {
        let entries = [
            makeEntry(name: "Notes.txt", kind: .file, type: "Plain Text Document"),
            makeEntry(name: "photo.PNG", kind: .file, type: "PNG image"),
            makeEntry(name: "Images", kind: .folder, type: "Folder")
        ]

        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "note").map(\.name), ["Notes.txt"])
        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "png").map(\.name), ["photo.PNG"])
        XCTAssertEqual(FileEntrySearchFilter.filtered(entries, query: "folder").map(\.name), ["Images"])
    }

    private func makeEntry(name: String, kind: FileEntryKind, type: String) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: type,
            fileExtension: URL(fileURLWithPath: name).pathExtension.lowercased(),
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: kind == .folder,
            isReadable: true
        )
    }
}
```

- [ ] **Step 2: Run search filter tests and verify RED**

Run:

```bash
swift test --filter FileEntrySearchFilterTests
```

Expected: FAIL with `cannot find 'FileEntrySearchFilter' in scope`.

- [ ] **Step 3: Implement FileEntrySearchFilter**

Create `Sources/MyMacFinder/Services/FileEntrySearchFilter.swift`:

```swift
import Foundation

public enum FileEntrySearchFilter {
    public static func filtered(_ entries: [FileEntry], query: String) -> [FileEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return entries
        }

        return entries.filter { entry in
            entry.name.lowercased().contains(normalized)
                || entry.fileExtension.lowercased().contains(normalized)
                || entry.typeDescription.lowercased().contains(normalized)
        }
    }
}
```

- [ ] **Step 4: Run search filter tests and verify GREEN**

Run:

```bash
swift test --filter FileEntrySearchFilterTests
```

Expected: PASS.

- [ ] **Step 5: Write failing store search tests**

Create `Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class ExplorerSearchStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try "hello".write(to: tempDirectory.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempDirectory.appendingPathComponent("photo.png"))
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testSearchQueryFiltersActivePaneEntries() async {
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.loadInitialDirectory()

        store.setSearchQuery("note")

        XCTAssertEqual(store.activePaneVisibleEntries.map(\.name), ["Notes.txt"])
    }

    @MainActor
    func testSearchClearsSelectionForFilteredOutRows() async {
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.loadInitialDirectory()
        let photo = tempDirectory.appendingPathComponent("photo.png").standardizedFileURL
        store.updateSelection([photo])

        store.setSearchQuery("note")

        XCTAssertTrue(store.activePane.selectedURLs.isEmpty)
    }

    @MainActor
    func testClearSearchRestoresEntries() async {
        let store = ExplorerStore(initialURL: tempDirectory, directoryWatcher: nil)
        await store.loadInitialDirectory()
        store.setSearchQuery("note")

        store.clearSearch()

        XCTAssertEqual(Set(store.activePaneVisibleEntries.map(\.name)), ["Notes.txt", "photo.png"])
        XCTAssertEqual(store.searchQuery, "")
    }
}
```

- [ ] **Step 6: Run store search tests and verify RED**

Run:

```bash
swift test --filter ExplorerSearchStoreTests
```

Expected: FAIL with missing `setSearchQuery`, `clearSearch`, `activePaneVisibleEntries`, or `searchQuery`.

- [ ] **Step 7: Add search state to ExplorerStore**

Modify `ExplorerStore`:

```swift
@Published public private(set) var searchQuery: String
```

Initialize:

```swift
self.searchQuery = ""
```

Add:

```swift
public var activePaneVisibleEntries: [FileEntry] {
    FileEntrySearchFilter.filtered(activePane.entries, query: searchQuery)
}

public func visibleEntries(forPaneAt index: Int) -> [FileEntry] {
    guard panes.indices.contains(index) else {
        return []
    }
    return FileEntrySearchFilter.filtered(panes[index].entries, query: index == activePaneIndex ? searchQuery : "")
}

public func setSearchQuery(_ query: String) {
    searchQuery = query
    trimSelectionToVisibleEntries()
}

public func clearSearch() {
    setSearchQuery("")
}

private func trimSelectionToVisibleEntries() {
    let visibleURLs = Set(activePaneVisibleEntries.map(\.url))
    panes[activePaneIndex].selectedURLs = activePane.selectedURLs.intersection(visibleURLs)
}
```

Search query is a single toolbar state. `visibleEntries(forPaneAt:)` filters only the active pane; inactive panes display unfiltered entries. `activatePane(at:)` does not clear `searchQuery`, so switching panes applies the existing query to the newly active pane.

- [ ] **Step 8: Run search tests and related store tests**

Run:

```bash
swift test --filter FileEntrySearchFilterTests
swift test --filter ExplorerSearchStoreTests
swift test --filter ExplorerStoreTests
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/MyMacFinder/Services/FileEntrySearchFilter.swift Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/FileEntrySearchFilterTests.swift Tests/MyMacFinderTests/ExplorerSearchStoreTests.swift
git commit -m "feat: add current pane search filtering"
```

## Task 6: Search UI, Focus Commands, And Shortcut Polish

**Files:**
- Modify: `Sources/MyMacFinder/Domain/ExplorerCommand.swift`
- Modify: `Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift`
- Modify: `Sources/MyMacFinder/UI/ToolbarPathView.swift`
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Test: `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift`

- [ ] **Step 1: Add failing shortcut tests**

Modify `Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift` to include:

```swift
func testFocusAndViewShortcutsMapToCommands() {
    XCTAssertEqual(
        ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "f", modifiers: [.command])),
        .focusSearch
    )
    XCTAssertEqual(
        ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "l", modifiers: [.command])),
        .focusPath
    )
    XCTAssertEqual(
        ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: ".", modifiers: [.command, .shift])),
        .toggleHiddenFiles
    )
    XCTAssertEqual(
        ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "up", modifiers: [.command])),
        .goUp
    )
    XCTAssertEqual(
        ExplorerKeyboardShortcut.command(for: ExplorerShortcut(key: "escape", modifiers: [])),
        .clearSearch
    )
}
```

- [ ] **Step 2: Run shortcut tests and verify RED**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
```

Expected: FAIL with missing `ExplorerCommand` cases.

- [ ] **Step 3: Add command cases**

Modify `ExplorerCommand` cases and titles, and add a focus target enum to `ExplorerModels.swift`:

```swift
case focusSearch
case focusPath
case clearSearch
case toggleHiddenFiles
case goUp
```

```swift
public enum ExplorerFocusTarget: Equatable, Sendable {
    case path
    case search
}
```

Titles:

```swift
case .focusSearch: return "Search"
case .focusPath: return "Focus Path"
case .clearSearch: return "Clear Search"
case .toggleHiddenFiles: return "Show Hidden Files"
case .goUp: return "Go Up"
```

Availability:

```swift
case .focusSearch, .focusPath, .clearSearch, .toggleHiddenFiles, .goUp:
    return true
```

- [ ] **Step 4: Update keyboard mapping**

Modify `ExplorerKeyboardShortcut.command(for:)`:

```swift
case [.command]:
    switch shortcut.key {
    case "c": return .copy
    case "x": return .cut
    case "v": return .paste
    case "d": return .duplicate
    case "f": return .focusSearch
    case "l": return .focusPath
    case "o": return .open
    case "r": return .refresh
    case "up": return .goUp
    case "delete": return .moveToTrash
    default: return nil
    }
case [.command, .shift]:
    switch shortcut.key {
    case "n": return .newFolder
    case ".": return .toggleHiddenFiles
    default: return nil
    }
case []:
    switch shortcut.key {
    case "return": return .open
    case "space": return .quickLook
    case "escape": return .clearSearch
    default: return nil
    }
```

- [ ] **Step 5: Run shortcut tests and verify GREEN**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
```

Expected: PASS.

- [ ] **Step 6: Wire command side effects in ExplorerStore**

Add focus request state to `ExplorerStore`:

```swift
@Published public private(set) var requestedFocus: ExplorerFocusTarget?

public func clearFocusRequest() {
    requestedFocus = nil
}

private func requestFocus(_ target: ExplorerFocusTarget) {
    requestedFocus = target
}
```

Initialize `requestedFocus` to `nil`.

Modify `ExplorerStore.perform(_:)`:

```swift
case .focusSearch:
    requestFocus(.search)
case .focusPath:
    requestFocus(.path)
case .clearSearch:
    clearSearch()
case .toggleHiddenFiles:
    await setShowHiddenFiles(!showHiddenFiles)
case .goUp:
    await goUp()
```

Focus commands are requested through the store so both app menu shortcuts and table shortcuts can focus toolbar fields.

- [ ] **Step 7: Add search and focus bindings to ToolbarPathView**

Modify `ToolbarPathView`:

```swift
struct ToolbarPathView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore
    @FocusState.Binding var focusedToolbarField: ToolbarField?

    var body: some View {
        HStack(spacing: 8) {
            ...
            TextField("Path", text: $explorerStore.pathInput)
                .focused($focusedToolbarField, equals: .path)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await explorerStore.resolveAndNavigate(explorerStore.pathInput) }
                }

            TextField("Search", text: searchBinding)
                .focused($focusedToolbarField, equals: .search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { explorerStore.searchQuery },
            set: { explorerStore.setSearchQuery($0) }
        )
    }
}

enum ToolbarField: Hashable {
    case path
    case search
}
```

- [ ] **Step 8: Feed filtered entries and focus commands from RootView**

Modify `RootView`:

```swift
@FocusState private var focusedToolbarField: ToolbarField?
```

Pass:

```swift
ToolbarPathView(focusedToolbarField: $focusedToolbarField)
```

Use:

```swift
entries: explorerStore.visibleEntries(forPaneAt: index)
currentLocation: pane.location
```

Handle focus requests from the store:

```swift
ToolbarPathView(focusedToolbarField: $focusedToolbarField)
    .onChange(of: explorerStore.requestedFocus) { _, target in
        switch target {
        case .path:
            focusedToolbarField = .path
        case .search:
            focusedToolbarField = .search
        case nil:
            break
        }
        explorerStore.clearFocusRequest()
    }
```

Use one command runner for table callbacks:

```swift
private func run(_ command: ExplorerCommand, paneIndex: Int? = nil) {
    if let paneIndex {
        explorerStore.activatePane(at: paneIndex)
    }
    Task { await explorerStore.perform(command) }
}
```

- [ ] **Step 9: Update FileTableView key extraction**

Modify `shortcut(from:)` in `FileTableView`:

```swift
switch event.keyCode {
case 36, 76:
    key = "return"
case 51, 117:
    key = "delete"
case 53:
    key = "escape"
case 126:
    key = "up"
case 49:
    key = "space"
default:
    key = event.charactersIgnoringModifiers?.lowercased() ?? ""
}
```

Change Return behavior from rename to open per spec. Rename remains available through context/menu and can later be assigned to Finder-style `Return` if the user prefers.

- [ ] **Step 10: Update menus**

Modify `MyMacFinderApp` `CommandMenu("Explorer")` to include:

```swift
Button("Focus Path") { perform(.focusPath) }
    .keyboardShortcut("l", modifiers: [.command])

Button("Search") { perform(.focusSearch) }
    .keyboardShortcut("f", modifiers: [.command])

Button("Clear Search") { perform(.clearSearch) }
    .keyboardShortcut(.escape, modifiers: [])

Button("Go Up") { perform(.goUp) }

Button("Show Hidden Files") { perform(.toggleHiddenFiles) }
    .keyboardShortcut(".", modifiers: [.command, .shift])
```

`Cmd+Up` is handled by `FileTableView` AppKit key handling and verified manually because SwiftUI command shortcut support for arrow keys is less reliable across SDK versions.

- [ ] **Step 11: Run UI-adjacent tests**

Run:

```bash
swift test --filter ExplorerKeyboardShortcutTests
swift test --filter ExplorerSearchStoreTests
swift build
```

Expected: PASS.

- [ ] **Step 12: Commit**

```bash
git add Sources/MyMacFinder/Domain/ExplorerCommand.swift Sources/MyMacFinder/Domain/ExplorerKeyboardShortcut.swift Sources/MyMacFinder/UI/ToolbarPathView.swift Sources/MyMacFinder/UI/FileTableView.swift Sources/MyMacFinder/App/RootView.swift Sources/MyMacFinder/App/MyMacFinderApp.swift Tests/MyMacFinderTests/ExplorerKeyboardShortcutTests.swift
git commit -m "feat: add search UI and shortcut polish"
```

## Task 7: Table Reuse And Large-Folder Hardening

**Files:**
- Modify: `Sources/MyMacFinder/UI/FileTableView.swift`
- Test: existing tests plus manual QA script artifacts

- [ ] **Step 1: Improve table cell reuse**

Modify `FileTableView.tableView(_:viewFor:row:)`:

```swift
func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < parent.entries.count else {
        return nil
    }

    let identifier = NSUserInterfaceItemIdentifier("FileTableCell-\(tableColumn?.identifier.rawValue ?? "name")")
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier: identifier)
    let entry = parent.entries[row]
    cell.textField?.stringValue = value(for: entry, column: tableColumn?.identifier.rawValue ?? "name")
    cell.textField?.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
    return cell
}

private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let textField = NSTextField(labelWithString: "")
    textField.lineBreakMode = .byTruncatingMiddle
    textField.translatesAutoresizingMaskIntoConstraints = false
    cell.textField = textField
    cell.addSubview(textField)
    NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])
    return cell
}
```

- [ ] **Step 2: Avoid selection-only reloads**

Keep `renderedEntries` equality gating and add a debug-only counter for manual QA:

```swift
#if DEBUG
private(set) var reloadCount = 0
#endif
```

inside `reloadDataIfNeeded()`:

```swift
#if DEBUG
reloadCount += 1
#endif
```

Do not expose this in production UI.

- [ ] **Step 3: Add a QA fixture script**

Create `scripts/create-large-folder-fixture.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-$HOME/MyMacFinderLargeQA}"
COUNT="${2:-10000}"

rm -rf "$TARGET"
mkdir -p "$TARGET"

i=1
while [ "$i" -le "$COUNT" ]; do
  printf 'file %05d\n' "$i" > "$TARGET/file-$(printf '%05d' "$i").txt"
  i=$((i + 1))
done

mkdir -p "$TARGET/folder-a" "$TARGET/folder-b"
printf 'png placeholder\n' > "$TARGET/image-sample.png"

echo "$TARGET"
```

Make executable:

```bash
chmod +x scripts/create-large-folder-fixture.sh
```

- [ ] **Step 4: Run tests and build**

Run:

```bash
swift test
swift build -c release
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacFinder/UI/FileTableView.swift scripts/create-large-folder-fixture.sh
git commit -m "perf: reuse file table cells"
```

## Task 8: Full Automated Verification And Manual QA

**Files:**
- No production file changes expected unless QA exposes a bug.
- QA artifacts under `/tmp` or clearly named home folders.

- [ ] **Step 1: Build a release `.app` bundle**

Run:

```bash
swift build -c release
rm -rf .build/qa/MyMacFinder.app
mkdir -p .build/qa/MyMacFinder.app/Contents/MacOS
cp .build/release/MyMacFinder .build/qa/MyMacFinder.app/Contents/MacOS/MyMacFinder
cat > .build/qa/MyMacFinder.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MyMacFinder</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.mymacfinder.qa</string>
  <key>CFBundleName</key>
  <string>MyMacFinder</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST
```

Expected: release app bundle exists at `.build/qa/MyMacFinder.app`.

- [ ] **Step 2: Create QA fixtures**

Run:

```bash
QA_ROOT="$HOME/MyMacFinderZipSearchQA"
rm -rf "$QA_ROOT"
mkdir -p "$QA_ROOT/zip-source/docs/nested" "$QA_ROOT/zip-source/hidden"
printf 'hello\n' > "$QA_ROOT/zip-source/docs/readme.txt"
printf 'nested\n' > "$QA_ROOT/zip-source/docs/nested/file.md"
printf 'secret\n' > "$QA_ROOT/zip-source/hidden/.secret"
printf 'plain\n' > "$QA_ROOT/plain-note.txt"
printf 'png\n' > "$QA_ROOT/photo.png"
cd "$QA_ROOT/zip-source" && zip -qr "$QA_ROOT/sample.zip" .
printf 'not a zip\n' > "$QA_ROOT/broken.zip"
scripts/create-large-folder-fixture.sh "$HOME/MyMacFinderLargeQA" 10000
```

Expected: QA root, valid ZIP, broken ZIP, normal files, and large folder exist.

- [ ] **Step 3: Run automated verification**

Run:

```bash
swift test && swift build -c release && git diff --check
```

Expected: all tests pass, release build succeeds, diff check clean.

- [ ] **Step 4: Manual QA with Computer Use**

Launch:

```bash
open .build/qa/MyMacFinder.app
```

Manual checklist:

- Navigate path field to `$HOME/MyMacFinderZipSearchQA`.
- Double-click `sample.zip`; verify archive root rows show `docs` and `hidden`.
- Open `docs`, then `nested`; verify path displays archive path.
- Use Up, Back, Forward, Refresh inside ZIP.
- Select `readme.txt`; verify Inspector preview/actions do not crash.
- Click Copy Path; verify `pbpaste` contains archive display path.
- Click Quick Look; verify a Quick Look window appears for extracted temp file.
- Try New Folder/Rename/Delete/Paste inside ZIP; verify commands are disabled or rejected.
- Open `broken.zip`; verify readable error and previous valid pane remains.
- Search normal folder for `plain`, `png`, and `folder`; verify filtering.
- Search inside ZIP for `readme`; verify filtering.
- Press `Esc`; verify search clears.
- Press `Cmd+F`; verify search field focuses.
- Press `Cmd+L`; verify path field focuses.
- Press `Cmd+Shift+.`; verify hidden entries toggle.
- Navigate to `$HOME/MyMacFinderLargeQA`; verify 10,000-file folder loads.
- Scroll large folder from top to bottom; verify the app remains usable.
- Sort large folder by Name, Size, Date Modified, and Kind.
- Search large folder for `9999`; verify filtering.
- Select rows in large folder; verify Inspector updates only for selection.
- Switch Settings to Dual Pane and confirm search/selection/Inspector still work.
- Create, rename, copy, move, delete, and drag/drop a normal filesystem file to verify existing operations still work.
- Create or delete a file externally in Terminal and verify filesystem pane refreshes.

- [ ] **Step 5: Clean QA artifacts**

Run:

```bash
pkill -f '/MyMacFinder.app/Contents/MacOS/MyMacFinder' || true
rm -rf "$HOME/MyMacFinderZipSearchQA" "$HOME/MyMacFinderLargeQA"
defaults delete com.local.mymacfinder.qa MyMacFinder.ExplorerSettings >/dev/null 2>&1 || true
```

- [ ] **Step 6: Fix bugs found by QA**

If manual QA exposes a bug, use `superpowers:systematic-debugging` before patching. Add or update an automated test when the bug is reproducible outside pure AppKit focus behavior. Commit fixes with focused messages.

- [ ] **Step 7: Final verification**

Run:

```bash
swift test && swift build -c release && git diff --check && git status --short
```

Expected: 0 failures, release build success, no diff check errors, clean git status.

- [ ] **Step 8: Final commit if QA docs/scripts changed**

If Task 8 produced committed changes:

```bash
git add .
git commit -m "test: complete zip search manual qa"
```

If no files changed, do not create an empty commit.

## Completion Criteria

- ZIPFoundation is resolved through SwiftPM.
- ZIP files open as read-only virtual panes.
- Archive folder navigation, Back, Forward, Up, Refresh, Quick Look, Copy Path, and Reveal host ZIP work.
- Mutation commands are disabled or rejected inside archive panes.
- Search filters active pane entries and clears via `Esc`.
- `Cmd+F`, `Cmd+L`, `Cmd+Shift+.`, `Cmd+R`, `Cmd+Up`, `Space`, and `Return` are verified.
- Large folder QA with 10,000 files is completed manually.
- All automated tests pass.
- Release build succeeds.
- Git status is clean.
