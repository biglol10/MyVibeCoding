# MyMacFinder Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working MyMacFinder foundation: SwiftUI/AppKit app scaffold, tested path resolution, tested directory reading, tested sorting/grouping, pane navigation state, and a read-only native table view wired to the real filesystem.

**Architecture:** This plan creates a Swift Package based macOS app executable with focused domain, service, store, and UI modules. The UI uses SwiftUI for window composition and an AppKit `NSTableView` bridge for the file table, matching the design spec's native-quality requirement from the start. File mutation, ZIP browsing, FSEvents synchronization, settings UI, context menus, and shortcuts are separate required implementation plans because the approved v0.1 spec spans multiple independent subsystems.

**Tech Stack:** Swift 6.1.2, macOS 15 SDK, SwiftUI, AppKit, XCTest, `FileManager`, `UniformTypeIdentifiers`.

---

## Plan Boundary

This plan produces a launchable read-only file manager foundation:

- App launches.
- Home directory loads.
- Path input resolves `~`, aliases, absolute paths, and relative paths.
- File entries include type, size, dates, extension, hidden state, and display metadata.
- Hidden files can be included or filtered by service option.
- Sorting and grouping are deterministic and tested.
- Back, forward, up, refresh, and direct navigation work in `ExplorerStore`.
- The main window shows sidebar, toolbar/path field, file table, and a basic inspector with path copy.

The approved v0.1 spec also requires file operations, ZIP browsing, filesystem synchronization, settings, context menus, keymaps, inspector previews, search, and dual pane controls. Those are part of the product scope and are split into separate implementation plans so each subsystem can be built and reviewed independently.

## File Structure

Create these files:

- `Package.swift`: Swift Package manifest for app and tests.
- `Sources/MyMacFinder/App/MyMacFinderApp.swift`: App entry point.
- `Sources/MyMacFinder/App/RootView.swift`: Main window composition.
- `Sources/MyMacFinder/Domain/FileEntry.swift`: File entry domain model.
- `Sources/MyMacFinder/Domain/ExplorerModels.swift`: Pane, sorting, grouping, and sidebar models.
- `Sources/MyMacFinder/Services/PathResolver.swift`: Expands user-entered paths and aliases.
- `Sources/MyMacFinder/Services/FileSystemService.swift`: Reads directories and maps URLs to `FileEntry`.
- `Sources/MyMacFinder/Services/SortEngine.swift`: Sorts and groups `FileEntry` values.
- `Sources/MyMacFinder/Stores/ExplorerStore.swift`: Main navigation and loading state.
- `Sources/MyMacFinder/UI/SidebarView.swift`: Sidebar sections.
- `Sources/MyMacFinder/UI/ToolbarPathView.swift`: Navigation buttons and path input.
- `Sources/MyMacFinder/UI/FileTableView.swift`: AppKit `NSTableView` bridge.
- `Sources/MyMacFinder/UI/InspectorView.swift`: Initial inspector shell.
- `Tests/MyMacFinderTests/PathResolverTests.swift`: Path resolver unit tests.
- `Tests/MyMacFinderTests/FileSystemServiceTests.swift`: Directory reader unit tests.
- `Tests/MyMacFinderTests/SortEngineTests.swift`: Sorting/grouping unit tests.
- `Tests/MyMacFinderTests/ExplorerStoreTests.swift`: Navigation state unit tests.

## Task 1: Create Swift Package App Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Create: `Sources/MyMacFinder/App/RootView.swift`

- [ ] **Step 1: Create folders**

Run:

```bash
mkdir -p Sources/MyMacFinder/App Sources/MyMacFinder/Domain Sources/MyMacFinder/Services Sources/MyMacFinder/Stores Sources/MyMacFinder/UI Tests/MyMacFinderTests
```

Expected: command exits with status `0`.

- [ ] **Step 2: Write `Package.swift`**

Create `Package.swift`:

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
    targets: [
        .executableTarget(
            name: "MyMacFinder",
            path: "Sources/MyMacFinder"
        ),
        .testTarget(
            name: "MyMacFinderTests",
            dependencies: ["MyMacFinder"],
            path: "Tests/MyMacFinderTests"
        )
    ]
)
```

- [ ] **Step 3: Write app entry point**

Create `Sources/MyMacFinder/App/MyMacFinderApp.swift`:

```swift
import SwiftUI

@main
struct MyMacFinderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            Text("MyMacFinder Settings")
                .frame(width: 420, height: 180)
        }
    }
}
```

- [ ] **Step 4: Write initial root view**

Create `Sources/MyMacFinder/App/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("MyMacFinder")
            .frame(minWidth: 900, minHeight: 560)
    }
}
```

- [ ] **Step 5: Run build to confirm scaffold compiles**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit scaffold**

Run:

```bash
git add Package.swift Sources/MyMacFinder/App
git commit -m "chore: add Swift app scaffold"
```

Expected: commit succeeds.

## Task 2: Add Domain Models

**Files:**
- Create: `Sources/MyMacFinder/Domain/FileEntry.swift`
- Create: `Sources/MyMacFinder/Domain/ExplorerModels.swift`

- [ ] **Step 1: Write file entry model**

Create `Sources/MyMacFinder/Domain/FileEntry.swift`:

```swift
import Foundation

public enum FileEntryKind: String, Codable, CaseIterable {
    case folder
    case file
    case symlink
    case package
    case volume
    case zipVirtualFolder
    case zipVirtualFile
    case other
}

public struct FileEntry: Identifiable, Hashable, Codable {
    public let id: URL
    public let url: URL
    public let name: String
    public let kind: FileEntryKind
    public let typeDescription: String
    public let fileExtension: String
    public let size: Int64?
    public let dateModified: Date?
    public let dateCreated: Date?
    public let dateAccessed: Date?
    public let isHidden: Bool
    public let isDirectoryLike: Bool
    public let isReadable: Bool

    public init(
        url: URL,
        name: String,
        kind: FileEntryKind,
        typeDescription: String,
        fileExtension: String,
        size: Int64?,
        dateModified: Date?,
        dateCreated: Date?,
        dateAccessed: Date?,
        isHidden: Bool,
        isDirectoryLike: Bool,
        isReadable: Bool
    ) {
        self.id = url
        self.url = url
        self.name = name
        self.kind = kind
        self.typeDescription = typeDescription
        self.fileExtension = fileExtension
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.dateAccessed = dateAccessed
        self.isHidden = isHidden
        self.isDirectoryLike = isDirectoryLike
        self.isReadable = isReadable
    }
}
```

- [ ] **Step 2: Write explorer model types**

Create `Sources/MyMacFinder/Domain/ExplorerModels.swift`:

```swift
import Foundation

public struct PaneID: Hashable, Codable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum SortKey: String, Codable, CaseIterable {
    case name
    case size
    case kind
    case fileExtension
    case dateModified
    case dateCreated
    case dateAccessed
    case permissions
    case owner
    case hidden
    case folderFileType
    case path
}

public enum SortDirection: String, Codable, CaseIterable {
    case ascending
    case descending
}

public enum FolderFileOrdering: String, Codable, CaseIterable {
    case foldersFirst
    case filesFirst
    case mixed
}

public struct EntrySortDescriptor: Codable, Equatable {
    public var key: SortKey
    public var direction: SortDirection
    public var folderFileOrdering: FolderFileOrdering

    public init(
        key: SortKey = .name,
        direction: SortDirection = .ascending,
        folderFileOrdering: FolderFileOrdering = .foldersFirst
    ) {
        self.key = key
        self.direction = direction
        self.folderFileOrdering = folderFileOrdering
    }
}

public enum GroupKey: String, Codable, CaseIterable {
    case folderFile
    case kind
    case fileExtension
    case dateBucket
    case sizeBucket
    case hidden
    case source
}

public struct EntryGroupDescriptor: Codable, Equatable {
    public var key: GroupKey

    public init(key: GroupKey) {
        self.key = key
    }
}

public struct PaneState: Identifiable {
    public let id: PaneID
    public var currentURL: URL
    public var entries: [FileEntry]
    public var selectedURLs: Set<URL>
    public var backStack: [URL]
    public var forwardStack: [URL]
    public var sort: EntrySortDescriptor
    public var group: EntryGroupDescriptor?
    public var isLoading: Bool
    public var error: ExplorerError?

    public init(currentURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.id = PaneID()
        self.currentURL = currentURL
        self.entries = []
        self.selectedURLs = []
        self.backStack = []
        self.forwardStack = []
        self.sort = EntrySortDescriptor()
        self.group = nil
        self.isLoading = false
        self.error = nil
    }

    public var selectedEntries: [FileEntry] {
        entries.filter { selectedURLs.contains($0.url) }
    }
}

public enum ExplorerError: LocalizedError, Equatable {
    case invalidPath(String)
    case pathDoesNotExist(String)
    case notDirectory(String)
    case permissionDenied(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notDirectory(let path):
            return "Path is not a folder: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .readFailed(let message):
            return message
        }
    }
}
```

- [ ] **Step 3: Build and confirm domain models compile**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Commit domain models**

Run:

```bash
git add Sources/MyMacFinder/Domain
git commit -m "feat: add explorer domain models"
```

Expected: commit succeeds.

## Task 3: Implement Path Resolver With Tests

**Files:**
- Create: `Sources/MyMacFinder/Services/PathResolver.swift`
- Create: `Tests/MyMacFinderTests/PathResolverTests.swift`

- [ ] **Step 1: Write failing path resolver tests**

Create `Tests/MyMacFinderTests/PathResolverTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class PathResolverTests: XCTestCase {
    func testExpandsTildeToHomeDirectory() throws {
        let resolver = PathResolver(aliases: [:])

        let resolved = try resolver.resolve("~/Downloads", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
    }

    func testResolvesAliasWithRemainingPath() throws {
        let devURL = URL(fileURLWithPath: "/Users/example/personalDev", isDirectory: true)
        let resolver = PathResolver(aliases: ["@dev": devURL])

        let resolved = try resolver.resolve("@dev/app", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, "/Users/example/personalDev/app")
    }

    func testResolvesAbsolutePath() throws {
        let resolver = PathResolver(aliases: [:])

        let resolved = try resolver.resolve("/Applications", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, "/Applications")
    }

    func testResolvesRelativePathAgainstCurrentFolder() throws {
        let resolver = PathResolver(aliases: [:])
        let current = URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true)

        let resolved = try resolver.resolve("project-a", relativeTo: current)

        XCTAssertEqual(resolved.path, "/Users/example/Desktop/project-a")
    }

    func testRejectsEmptyPath() {
        let resolver = PathResolver(aliases: [:])

        XCTAssertThrowsError(try resolver.resolve("   ", relativeTo: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertEqual(error as? ExplorerError, .invalidPath(""))
        }
    }
}
```

- [ ] **Step 2: Run path tests and verify failure**

Run:

```bash
swift test --filter PathResolverTests
```

Expected: FAIL with `cannot find 'PathResolver' in scope`.

- [ ] **Step 3: Implement path resolver**

Create `Sources/MyMacFinder/Services/PathResolver.swift`:

```swift
import Foundation

public struct PathResolver {
    public let aliases: [String: URL]
    private let homeDirectory: URL

    public init(
        aliases: [String: URL],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.aliases = aliases
        self.homeDirectory = homeDirectory
    }

    public func resolve(_ rawInput: String, relativeTo currentURL: URL) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExplorerError.invalidPath("")
        }

        let expanded = expandTilde(expandAlias(trimmed))
        let url: URL

        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = currentURL.appendingPathComponent(expanded)
        }

        return url.standardizedFileURL
    }

    private func expandTilde(_ input: String) -> String {
        if input == "~" {
            return homeDirectory.path
        }

        if input.hasPrefix("~/") {
            let suffix = String(input.dropFirst(2))
            return homeDirectory.appendingPathComponent(suffix).path
        }

        return input
    }

    private func expandAlias(_ input: String) -> String {
        let components = input.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = components.first else {
            return input
        }

        let aliasKey = String(first)
        guard let aliasURL = aliases[aliasKey] else {
            return input
        }

        if components.count == 1 {
            return aliasURL.path
        }

        return aliasURL.appendingPathComponent(String(components[1])).path
    }
}
```

- [ ] **Step 4: Run path tests and verify pass**

Run:

```bash
swift test --filter PathResolverTests
```

Expected: PASS with all `PathResolverTests` passing.

- [ ] **Step 5: Commit path resolver**

Run:

```bash
git add Sources/MyMacFinder/Services/PathResolver.swift Tests/MyMacFinderTests/PathResolverTests.swift
git commit -m "feat: add path resolver"
```

Expected: commit succeeds.

## Task 4: Implement Directory Reading Service

**Files:**
- Create: `Sources/MyMacFinder/Services/FileSystemService.swift`
- Create: `Tests/MyMacFinderTests/FileSystemServiceTests.swift`

- [ ] **Step 1: Write failing filesystem tests**

Create `Tests/MyMacFinderTests/FileSystemServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class FileSystemServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsVisibleFilesAndFolders() async throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try "hello".write(to: tempDirectory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: false))

        XCTAssertEqual(Set(entries.map(\.name)), ["Folder", "note.txt"])
        XCTAssertTrue(entries.first { $0.name == "Folder" }?.isDirectoryLike == true)
        XCTAssertEqual(entries.first { $0.name == "note.txt" }?.fileExtension, "txt")
    }

    func testFiltersDotHiddenFilesWhenHiddenFilesAreDisabled() async throws {
        try "secret".write(to: tempDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "public".write(to: tempDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: false))

        XCTAssertEqual(entries.map(\.name), ["README.md"])
    }

    func testIncludesHiddenFilesWhenEnabled() async throws {
        try "secret".write(to: tempDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let entries = try await service.contentsOfDirectory(at: tempDirectory, options: DirectoryReadOptions(showHiddenFiles: true))

        XCTAssertEqual(entries.map(\.name), [".env"])
        XCTAssertTrue(entries[0].isHidden)
    }

    func testRejectsFileURLWhenDirectoryExpected() async throws {
        let fileURL = tempDirectory.appendingPathComponent("plain.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = FileSystemService()

        do {
            _ = try await service.contentsOfDirectory(at: fileURL, options: DirectoryReadOptions())
            XCTFail("Expected notDirectory error")
        } catch {
            XCTAssertEqual(error as? ExplorerError, .notDirectory(fileURL.path))
        }
    }
}
```

- [ ] **Step 2: Run filesystem tests and verify failure**

Run:

```bash
swift test --filter FileSystemServiceTests
```

Expected: FAIL with missing `FileSystemService` and `DirectoryReadOptions`.

- [ ] **Step 3: Implement filesystem service**

Create `Sources/MyMacFinder/Services/FileSystemService.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

public struct DirectoryReadOptions {
    public var showHiddenFiles: Bool

    public init(showHiddenFiles: Bool = false) {
        self.showHiddenFiles = showHiddenFiles
    }
}

public struct FileSystemService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func contentsOfDirectory(at url: URL, options: DirectoryReadOptions = DirectoryReadOptions()) async throws -> [FileEntry] {
        try validateDirectory(url)

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .isReadableKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentAccessDateKey,
            .typeIdentifierKey,
            .localizedTypeDescriptionKey
        ]

        let childURLs = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants]
        )

        return try childURLs.compactMap { childURL in
            let entry = try makeEntry(for: childURL, resourceKeys: keys)
            if !options.showHiddenFiles && entry.isHidden {
                return nil
            }
            return entry
        }
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExplorerError.pathDoesNotExist(url.path)
        }
        guard isDirectory.boolValue else {
            throw ExplorerError.notDirectory(url.path)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ExplorerError.permissionDenied(url.path)
        }
    }

    private func makeEntry(for url: URL, resourceKeys: Set<URLResourceKey>) throws -> FileEntry {
        let values = try url.resourceValues(forKeys: resourceKeys)
        let name = url.lastPathComponent
        let isDirectory = values.isDirectory == true
        let isPackage = values.isPackage == true
        let isSymlink = values.isSymbolicLink == true
        let hiddenByName = name.hasPrefix(".")
        let hiddenByFlag = values.isHidden == true
        let kind = determineKind(url: url, isDirectory: isDirectory, isPackage: isPackage, isSymlink: isSymlink)

        return FileEntry(
            url: url.standardizedFileURL,
            name: name,
            kind: kind,
            typeDescription: values.localizedTypeDescription ?? fallbackTypeDescription(kind: kind, extension: url.pathExtension),
            fileExtension: url.pathExtension.lowercased(),
            size: values.fileSize.map(Int64.init),
            dateModified: values.contentModificationDate,
            dateCreated: values.creationDate,
            dateAccessed: values.contentAccessDate,
            isHidden: hiddenByName || hiddenByFlag,
            isDirectoryLike: isDirectory && !isPackage,
            isReadable: values.isReadable ?? FileManager.default.isReadableFile(atPath: url.path)
        )
    }

    private func determineKind(url: URL, isDirectory: Bool, isPackage: Bool, isSymlink: Bool) -> FileEntryKind {
        if isSymlink {
            return .symlink
        }
        if isPackage {
            return .package
        }
        if isDirectory {
            return .folder
        }
        if url.pathExtension.lowercased() == "zip" {
            return .zipVirtualFolder
        }
        return .file
    }

    private func fallbackTypeDescription(kind: FileEntryKind, extension fileExtension: String) -> String {
        switch kind {
        case .folder:
            return "Folder"
        case .symlink:
            return "Alias"
        case .package:
            return "Package"
        case .zipVirtualFolder:
            return "ZIP Archive"
        case .file:
            return fileExtension.isEmpty ? "File" : "\(fileExtension.uppercased()) File"
        case .volume:
            return "Volume"
        case .zipVirtualFile:
            return "ZIP Item"
        case .other:
            return "Item"
        }
    }
}
```

- [ ] **Step 4: Run filesystem tests**

Run:

```bash
swift test --filter FileSystemServiceTests
```

Expected: PASS with all `FileSystemServiceTests` passing.

- [ ] **Step 5: Commit filesystem service**

Run:

```bash
git add Sources/MyMacFinder/Services/FileSystemService.swift Tests/MyMacFinderTests/FileSystemServiceTests.swift
git commit -m "feat: add directory reading service"
```

Expected: commit succeeds.

## Task 5: Implement Sort And Group Engine

**Files:**
- Create: `Sources/MyMacFinder/Services/SortEngine.swift`
- Create: `Tests/MyMacFinderTests/SortEngineTests.swift`

- [ ] **Step 1: Write failing sort tests**

Create `Tests/MyMacFinderTests/SortEngineTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

final class SortEngineTests: XCTestCase {
    func testFoldersFirstNameAscending() {
        let entries = [
            entry("z-file.txt", kind: .file),
            entry("b-folder", kind: .folder),
            entry("a-file.txt", kind: .file),
            entry("a-folder", kind: .folder)
        ]

        let result = SortEngine.sorted(
            entries,
            descriptor: EntrySortDescriptor(key: .name, direction: .ascending, folderFileOrdering: .foldersFirst)
        )

        XCTAssertEqual(result.map(\.name), ["a-folder", "b-folder", "a-file.txt", "z-file.txt"])
    }

    func testFilesFirstSizeDescending() {
        let entries = [
            entry("folder", kind: .folder, size: nil),
            entry("small.txt", kind: .file, size: 10),
            entry("large.txt", kind: .file, size: 100)
        ]

        let result = SortEngine.sorted(
            entries,
            descriptor: EntrySortDescriptor(key: .size, direction: .descending, folderFileOrdering: .filesFirst)
        )

        XCTAssertEqual(result.map(\.name), ["large.txt", "small.txt", "folder"])
    }

    func testGroupsByKind() {
        let entries = [
            entry("photo.png", kind: .file, typeDescription: "PNG image"),
            entry("src", kind: .folder, typeDescription: "Folder"),
            entry("notes.md", kind: .file, typeDescription: "Markdown document")
        ]

        let groups = SortEngine.group(entries, descriptor: EntryGroupDescriptor(key: .kind))

        XCTAssertEqual(groups.map(\.title), ["Folder", "Markdown document", "PNG image"])
        XCTAssertEqual(groups.first?.entries.map(\.name), ["src"])
    }

    private func entry(
        _ name: String,
        kind: FileEntryKind,
        typeDescription: String = "File",
        size: Int64? = nil
    ) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: typeDescription,
            fileExtension: URL(fileURLWithPath: name).pathExtension.lowercased(),
            size: size,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: name.hasPrefix("."),
            isDirectoryLike: kind == .folder,
            isReadable: true
        )
    }
}
```

- [ ] **Step 2: Run sort tests and verify failure**

Run:

```bash
swift test --filter SortEngineTests
```

Expected: FAIL with missing `SortEngine`.

- [ ] **Step 3: Implement sort engine**

Create `Sources/MyMacFinder/Services/SortEngine.swift`:

```swift
import Foundation

public struct EntryGroup: Equatable {
    public let title: String
    public let entries: [FileEntry]
}

public enum SortEngine {
    public static func sorted(_ entries: [FileEntry], descriptor: EntrySortDescriptor) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if let folderComparison = compareFolderFile(lhs, rhs, ordering: descriptor.folderFileOrdering) {
                return folderComparison
            }

            let comparison = compare(lhs, rhs, key: descriptor.key)
            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            switch descriptor.direction {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }

    public static func group(_ entries: [FileEntry], descriptor: EntryGroupDescriptor) -> [EntryGroup] {
        let dictionary = Dictionary(grouping: entries) { entry in
            groupTitle(for: entry, key: descriptor.key)
        }

        return dictionary.keys.sorted().map { key in
            EntryGroup(title: key, entries: dictionary[key] ?? [])
        }
    }

    private static func compareFolderFile(_ lhs: FileEntry, _ rhs: FileEntry, ordering: FolderFileOrdering) -> Bool? {
        guard lhs.isDirectoryLike != rhs.isDirectoryLike else {
            return nil
        }

        switch ordering {
        case .foldersFirst:
            return lhs.isDirectoryLike
        case .filesFirst:
            return !lhs.isDirectoryLike
        case .mixed:
            return nil
        }
    }

    private static func compare(_ lhs: FileEntry, _ rhs: FileEntry, key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return compareOptional(lhs.size, rhs.size)
        case .kind:
            return lhs.typeDescription.localizedStandardCompare(rhs.typeDescription)
        case .fileExtension:
            return lhs.fileExtension.localizedStandardCompare(rhs.fileExtension)
        case .dateModified:
            return compareOptional(lhs.dateModified, rhs.dateModified)
        case .dateCreated:
            return compareOptional(lhs.dateCreated, rhs.dateCreated)
        case .dateAccessed:
            return compareOptional(lhs.dateAccessed, rhs.dateAccessed)
        case .permissions, .owner:
            return .orderedSame
        case .hidden:
            return String(lhs.isHidden).compare(String(rhs.isHidden))
        case .folderFileType:
            return lhs.kind.rawValue.compare(rhs.kind.rawValue)
        case .path:
            return lhs.url.path.localizedStandardCompare(rhs.url.path)
        }
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        }
    }

    private static func groupTitle(for entry: FileEntry, key: GroupKey) -> String {
        switch key {
        case .folderFile:
            return entry.isDirectoryLike ? "Folders" : "Files"
        case .kind:
            return entry.typeDescription
        case .fileExtension:
            return entry.fileExtension.isEmpty ? "No Extension" : ".\(entry.fileExtension)"
        case .dateBucket:
            return dateBucket(for: entry.dateModified)
        case .sizeBucket:
            return sizeBucket(for: entry.size)
        case .hidden:
            return entry.isHidden ? "Hidden" : "Visible"
        case .source:
            return entry.kind == .zipVirtualFile || entry.kind == .zipVirtualFolder ? "ZIP" : "Filesystem"
        }
    }

    private static func dateBucket(for date: Date?) -> String {
        guard let date else { return "No Date" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()), date >= sevenDaysAgo {
            return "Previous 7 Days"
        }
        return "Older"
    }

    private static func sizeBucket(for size: Int64?) -> String {
        guard let size else { return "No Size" }
        if size < 1_000_000 { return "Small" }
        if size < 100_000_000 { return "Medium" }
        return "Large"
    }
}
```

- [ ] **Step 4: Run sort tests**

Run:

```bash
swift test --filter SortEngineTests
```

Expected: PASS with all `SortEngineTests` passing.

- [ ] **Step 5: Commit sort engine**

Run:

```bash
git add Sources/MyMacFinder/Services/SortEngine.swift Tests/MyMacFinderTests/SortEngineTests.swift
git commit -m "feat: add sorting and grouping engine"
```

Expected: commit succeeds.

## Task 6: Implement Explorer Store Navigation

**Files:**
- Create: `Sources/MyMacFinder/Stores/ExplorerStore.swift`
- Create: `Tests/MyMacFinderTests/ExplorerStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/MyMacFinderTests/ExplorerStoreTests.swift`:

```swift
import Foundation
import XCTest
@testable import MyMacFinder

@MainActor
final class ExplorerStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testNavigateToUpdatesCurrentURLAndBackStack() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.navigate(to: child)

        XCTAssertEqual(store.activePane.currentURL.path, child.path)
        XCTAssertEqual(store.activePane.backStack.map(\.path), [tempDirectory.path])
    }

    func testBackAndForwardNavigation() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.navigate(to: child)
        await store.goBack()
        XCTAssertEqual(store.activePane.currentURL.path, tempDirectory.path)
        XCTAssertEqual(store.activePane.forwardStack.map(\.path), [child.path])

        await store.goForward()
        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    func testResolveAndNavigateUsesPathResolver() async throws {
        let child = tempDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.resolveAndNavigate("Child")

        XCTAssertEqual(store.activePane.currentURL.path, child.path)
    }

    func testInvalidPathSetsVisibleErrorAndKeepsCurrentURL() async {
        let store = ExplorerStore(initialURL: tempDirectory)

        await store.resolveAndNavigate("/definitely/not/here")

        XCTAssertEqual(store.activePane.currentURL.path, tempDirectory.path)
        XCTAssertTrue(store.visibleErrorMessage.contains("Path does not exist"))
    }
}
```

- [ ] **Step 2: Run store tests and verify failure**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: FAIL with missing `ExplorerStore`.

- [ ] **Step 3: Implement explorer store**

Create `Sources/MyMacFinder/Stores/ExplorerStore.swift`:

```swift
import AppKit
import Foundation
import SwiftUI

@MainActor
public final class ExplorerStore: ObservableObject {
    @Published public private(set) var panes: [PaneState]
    @Published public var pathInput: String
    @Published public private(set) var visibleError: ExplorerError?
    @Published public var showHiddenFiles: Bool

    private let fileSystemService: FileSystemService
    private let pathResolver: PathResolver
    private var activePaneIndex: Int

    public init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystemService: FileSystemService = FileSystemService(),
        pathResolver: PathResolver = PathResolver(
            aliases: [
                "@home": FileManager.default.homeDirectoryForCurrentUser,
                "@desktop": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
                "@downloads": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            ]
        )
    ) {
        self.panes = [PaneState(currentURL: initialURL)]
        self.pathInput = initialURL.path
        self.visibleError = nil
        self.showHiddenFiles = false
        self.fileSystemService = fileSystemService
        self.pathResolver = pathResolver
        self.activePaneIndex = 0
    }

    public var activePane: PaneState {
        panes[activePaneIndex]
    }

    public var hasVisibleError: Binding<Bool> {
        Binding(
            get: { self.visibleError != nil },
            set: { newValue in
                if !newValue {
                    self.visibleError = nil
                }
            }
        )
    }

    public var visibleErrorMessage: String {
        visibleError?.localizedDescription ?? ""
    }

    public func loadInitialDirectory() async {
        await loadCurrentDirectory()
    }

    public func resolveAndNavigate(_ rawPath: String) async {
        do {
            let targetURL = try pathResolver.resolve(rawPath, relativeTo: activePane.currentURL)
            await navigate(to: targetURL)
        } catch let error as ExplorerError {
            visibleError = error
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    public func navigate(to targetURL: URL) async {
        do {
            try await loadDirectory(targetURL, pushHistory: true)
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

        if entry.isDirectoryLike || entry.kind == .zipVirtualFolder {
            await navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    public func goBack() async {
        guard let target = activePane.backStack.last else {
            return
        }
        var pane = activePane
        pane.backStack.removeLast()
        pane.forwardStack.append(pane.currentURL)
        panes[activePaneIndex] = pane
        try? await loadDirectory(target, pushHistory: false)
    }

    public func goForward() async {
        guard let target = activePane.forwardStack.last else {
            return
        }
        var pane = activePane
        pane.forwardStack.removeLast()
        pane.backStack.append(pane.currentURL)
        panes[activePaneIndex] = pane
        try? await loadDirectory(target, pushHistory: false)
    }

    public func goUp() async {
        let parent = activePane.currentURL.deletingLastPathComponent()
        await navigate(to: parent)
    }

    public func refresh() async {
        await loadCurrentDirectory()
    }

    public func updateSelection(_ urls: Set<URL>) {
        panes[activePaneIndex].selectedURLs = urls
    }

    public func clearError() {
        visibleError = nil
    }

    private func loadCurrentDirectory() async {
        do {
            try await loadDirectory(activePane.currentURL, pushHistory: false)
        } catch let error as ExplorerError {
            visibleError = error
        } catch {
            visibleError = .readFailed(error.localizedDescription)
        }
    }

    private func loadDirectory(_ url: URL, pushHistory: Bool) async throws {
        panes[activePaneIndex].isLoading = true
        defer {
            panes[activePaneIndex].isLoading = false
        }

        let entries = try await fileSystemService.contentsOfDirectory(
            at: url,
            options: DirectoryReadOptions(showHiddenFiles: showHiddenFiles)
        )

        var pane = activePane
        if pushHistory && pane.currentURL != url {
            pane.backStack.append(pane.currentURL)
            pane.forwardStack.removeAll()
        }
        pane.currentURL = url
        pane.entries = SortEngine.sorted(entries, descriptor: pane.sort)
        pane.selectedURLs = pane.selectedURLs.intersection(Set(pane.entries.map(\.url)))
        pane.error = nil
        panes[activePaneIndex] = pane
        pathInput = url.path
    }
}
```

- [ ] **Step 4: Run store tests**

Run:

```bash
swift test --filter ExplorerStoreTests
```

Expected: PASS with all `ExplorerStoreTests` passing.

- [ ] **Step 5: Commit explorer store**

Run:

```bash
git add Sources/MyMacFinder/Stores/ExplorerStore.swift Tests/MyMacFinderTests/ExplorerStoreTests.swift
git commit -m "feat: add explorer navigation store"
```

Expected: commit succeeds.

## Task 7: Add Native File Table And Shell Views

**Files:**
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`
- Modify: `Sources/MyMacFinder/App/RootView.swift`
- Create: `Sources/MyMacFinder/UI/SidebarView.swift`
- Create: `Sources/MyMacFinder/UI/ToolbarPathView.swift`
- Create: `Sources/MyMacFinder/UI/FileTableView.swift`
- Create: `Sources/MyMacFinder/UI/InspectorView.swift`

- [ ] **Step 1: Connect app entry point to explorer store**

Replace `Sources/MyMacFinder/App/MyMacFinderApp.swift`:

```swift
import SwiftUI

@main
struct MyMacFinderApp: App {
    @StateObject private var explorerStore = ExplorerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(explorerStore)
                .task {
                    await explorerStore.loadInitialDirectory()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            Form {
                Toggle("Show Hidden Files", isOn: $explorerStore.showHiddenFiles)
                Picker("Default Sort", selection: .constant(SortKey.name)) {
                    Text("Name").tag(SortKey.name)
                    Text("Size").tag(SortKey.size)
                    Text("Kind").tag(SortKey.kind)
                    Text("Date Modified").tag(SortKey.dateModified)
                }
            }
            .padding(20)
            .frame(width: 420, height: 180)
        }
    }
}
```

- [ ] **Step 2: Connect root view to explorer layout**

Replace `Sources/MyMacFinder/App/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                ToolbarPathView()
                Divider()
                HSplitView {
                    FileTableView(
                        entries: explorerStore.activePane.entries,
                        selectedURLs: explorerStore.activePane.selectedURLs,
                        onSelectionChange: { urls in
                            explorerStore.updateSelection(urls)
                        },
                        onOpen: { url in
                            Task { await explorerStore.open(url) }
                        }
                    )
                    .frame(minWidth: 520)

                    InspectorView(selection: explorerStore.activePane.selectedEntries)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                }
            }
        }
        .alert("MyMacFinder", isPresented: explorerStore.hasVisibleError) {
            Button("OK", role: .cancel) {
                explorerStore.clearError()
            }
        } message: {
            Text(explorerStore.visibleErrorMessage)
        }
    }
}
```

- [ ] **Step 3: Write sidebar view**

Create `Sources/MyMacFinder/UI/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore

    var body: some View {
        List {
            Section("Favorites") {
                sidebarButton("Home", systemImage: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                sidebarButton("Desktop", systemImage: "desktopcomputer", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
                sidebarButton("Documents", systemImage: "doc", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
                sidebarButton("Downloads", systemImage: "arrow.down.circle", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                sidebarButton("Applications", systemImage: "a.square", url: URL(fileURLWithPath: "/Applications", isDirectory: true))
            }

            Section("Developer") {
                sidebarButton("@home", systemImage: "at", url: FileManager.default.homeDirectoryForCurrentUser)
                sidebarButton("@downloads", systemImage: "at", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarButton(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            Task { await explorerStore.navigate(to: url) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Write toolbar path view**

Create `Sources/MyMacFinder/UI/ToolbarPathView.swift`:

```swift
import SwiftUI

struct ToolbarPathView: View {
    @EnvironmentObject private var explorerStore: ExplorerStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await explorerStore.goBack() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(explorerStore.activePane.backStack.isEmpty)

            Button {
                Task { await explorerStore.goForward() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(explorerStore.activePane.forwardStack.isEmpty)

            Button {
                Task { await explorerStore.goUp() }
            } label: {
                Image(systemName: "arrow.up")
            }

            TextField("Path", text: $explorerStore.pathInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await explorerStore.resolveAndNavigate(explorerStore.pathInput) }
                }

            Button {
                Task { await explorerStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 5: Write AppKit file table bridge**

Create `Sources/MyMacFinder/UI/FileTableView.swift`:

```swift
import AppKit
import SwiftUI

struct FileTableView: NSViewRepresentable {
    var entries: [FileEntry]
    var selectedURLs: Set<URL>
    var onSelectionChange: (Set<URL>) -> Void
    var onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.target = context.coordinator

        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 260),
            ("size", "Size", 90),
            ("modified", "Date Modified", 170),
            ("kind", "Kind", 120)
        ]

        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.0))
            tableColumn.title = column.1
            tableColumn.width = column.2
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.tableView?.reloadData()
        context.coordinator.applySelection(selectedURLs)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?

        init(parent: FileTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.entries.count else {
                return nil
            }

            let entry = parent.entries[row]
            let identifier = tableColumn?.identifier.rawValue ?? "name"
            let cell = NSTableCellView()
            let textField = NSTextField(labelWithString: value(for: entry, column: identifier))
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else {
                return
            }
            let urls = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < parent.entries.count else { return nil }
                return parent.entries[index].url
            }
            parent.onSelectionChange(Set(urls))
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.entries.count else {
                return
            }
            parent.onOpen(parent.entries[row].url)
        }

        func applySelection(_ urls: Set<URL>) {
            guard let tableView else {
                return
            }

            let indexes = IndexSet(parent.entries.enumerated().compactMap { index, entry in
                urls.contains(entry.url) ? index : nil
            })

            if tableView.selectedRowIndexes != indexes {
                tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        private func value(for entry: FileEntry, column: String) -> String {
            switch column {
            case "name":
                return entry.name
            case "size":
                guard let size = entry.size else { return "--" }
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            case "modified":
                guard let date = entry.dateModified else { return "--" }
                return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            case "kind":
                return entry.typeDescription
            default:
                return ""
            }
        }
    }
}
```

- [ ] **Step 6: Write inspector view**

Create `Sources/MyMacFinder/UI/InspectorView.swift`:

```swift
import SwiftUI

struct InspectorView: View {
    let selection: [FileEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selection.isEmpty {
                Text("No Selection")
                    .font(.headline)
                Text("Select a file or folder to view details.")
                    .foregroundStyle(.secondary)
            } else if selection.count == 1, let entry = selection.first {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 140)
                    .overlay {
                        Image(systemName: entry.isDirectoryLike ? "folder" : "doc")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                    }

                Text(entry.name)
                    .font(.headline)
                    .lineLimit(2)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Kind").foregroundStyle(.secondary)
                        Text(entry.typeDescription)
                    }
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text(sizeText(entry.size))
                    }
                    GridRow {
                        Text("Path").foregroundStyle(.secondary)
                        Text(entry.url.path).lineLimit(3)
                    }
                }
                .font(.caption)

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.path, forType: .string)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("\(selection.count) Items Selected")
                    .font(.headline)
                Text(selection.map(\.name).prefix(6).joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.bar)
    }

    private func sizeText(_ size: Int64?) -> String {
        guard let size else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
```

- [ ] **Step 7: Run all tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 8: Run app build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 9: Commit UI foundation**

Run:

```bash
git add Sources/MyMacFinder/UI Sources/MyMacFinder/App
git commit -m "feat: add native explorer shell"
```

Expected: commit succeeds.

## Task 8: Final Verification For Foundation Plan

**Files:**
- Modify: none

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run release build**

Run:

```bash
swift build -c release
```

Expected: PASS.

- [ ] **Step 3: Launch app manually**

Run:

```bash
swift run MyMacFinder
```

Expected: app launches, shows the home directory, allows entering `~/Downloads`, and updates the table after pressing Return.

- [ ] **Step 4: Check Git status**

Run:

```bash
git status --short
```

Expected: no uncommitted tracked changes.

- [ ] **Step 5: Record foundation completion commit if needed**

If verification required changes, commit them:

```bash
git add Package.swift Sources Tests
git commit -m "test: verify explorer foundation"
```

Expected: commit succeeds only when Step 4 showed tracked changes from verification fixes.
