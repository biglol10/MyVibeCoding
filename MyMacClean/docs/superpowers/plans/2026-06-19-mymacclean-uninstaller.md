# MyMacClean Uninstaller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build v1 of MyMacClean as a native macOS uninstaller that discovers installed apps, scans related files, shows a review-focused SwiftUI UI, and permanently deletes confirmed selections with safety checks and a local journal.

**Architecture:** The filesystem engine lives in a testable Swift Package library named `MyMacCleanCore`; the macOS UI is a SwiftUI executable target named `MyMacCleanApp`. Core services return structured domain models, while SwiftUI view models coordinate scanning, selection, confirmation, deletion, and result states.

**Tech Stack:** Swift 6.1.2, Swift Package Manager, SwiftUI, Foundation, AppKit, XCTest, shell scripts for app-bundle and DMG packaging.

---

## Scope Check

This plan implements only the approved V1 Professional App Uninstaller. V2 startup item management and V3 general cleanup features remain documented in `docs/superpowers/specs/2026-06-19-mymacclean-uninstaller-design.md` and are not part of this implementation plan.

## File Structure

- Create `Package.swift`: Swift Package manifest with a library target and test target; add the executable SwiftUI target in Task 12.
- Create `Sources/MyMacCleanCore/Models/InstalledApp.swift`: installed app domain model.
- Create `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`: related file domain model, enums, deletion plan, and deletion result models.
- Create `Sources/MyMacCleanCore/Support/FileSizeCalculator.swift`: deterministic recursive size calculation.
- Create `Sources/MyMacCleanCore/Support/PathUtilities.swift`: path normalization and descendant checks.
- Create `Sources/MyMacCleanCore/Discovery/AppMetadataReader.swift`: reads app bundle metadata from `Info.plist`.
- Create `Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift`: finds `.app` bundles in configured roots.
- Create `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`: scores candidate files against app metadata.
- Create `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`: scans known library locations for related files.
- Create `Sources/MyMacCleanCore/Safety/ProtectionPolicy.swift`: blocks user-content and system-critical paths.
- Create `Sources/MyMacCleanCore/Deletion/DeletionPlanner.swift`: turns selected candidates into a safe deletion plan.
- Create `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift`: permanently deletes files in a confirmed plan.
- Create `Sources/MyMacCleanCore/Deletion/ApplicationDeletionWorkflow.swift`: creates default deletion plans from UI selections.
- Create `Sources/MyMacCleanCore/Journal/DeletionJournal.swift`: writes and reads deletion records as JSON Lines.
- Create `Sources/MyMacCleanCore/Permissions/PermissionCoordinator.swift`: classifies permission failures and guidance copy.
- Create `Sources/MyMacCleanApp/MyMacCleanApp.swift`: SwiftUI app entry point.
- Create `Sources/MyMacCleanApp/ViewModels/ApplicationListViewModel.swift`: bridges core app discovery/scanning/deletion into observable state.
- Create `Sources/MyMacCleanApp/Views/ContentView.swift`: app shell with sidebar, table, inspector, and confirmation sheet.
- Create `Sources/MyMacCleanApp/Views/Components.swift`: reusable view pieces for rows, badges, metrics, and file candidate lists.
- Create `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`: app bundle metadata used by packaging scripts.
- Create `Tests/MyMacCleanCoreTests/TestFixtures.swift`: helpers that build fixture app bundles and library files.
- Create `Tests/MyMacCleanCoreTests/AppMetadataReaderTests.swift`: metadata extraction tests.
- Create `Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift`: app discovery tests.
- Create `Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift`: matching tests.
- Create `Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift`: protected path tests.
- Create `Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift`: scanner tests.
- Create `Tests/MyMacCleanCoreTests/DeletionPlannerTests.swift`: planning tests.
- Create `Tests/MyMacCleanCoreTests/DeletionExecutorTests.swift`: permanent deletion tests against temporary directories.
- Create `Tests/MyMacCleanCoreTests/DeletionJournalTests.swift`: journal persistence tests.
- Create `Tests/MyMacCleanCoreTests/PermissionCoordinatorTests.swift`: permission guidance tests.
- Create `Tests/MyMacCleanCoreTests/ApplicationWorkflowTests.swift`: deletion workflow tests.
- Create `scripts/build-app-bundle.sh`: builds `MyMacClean.app` from the SwiftPM release executable.
- Create `scripts/create-dmg.sh`: packages the app bundle into a local unsigned DMG for development.
- Modify `.gitignore`: add `.build/`, `dist/`, and `.swiftpm/`.

## Task 1: Swift Package Scaffold And Domain Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/MyMacCleanCore/Models/InstalledApp.swift`
- Create: `Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift`
- Create: `Tests/MyMacCleanCoreTests/DomainModelTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Create package manifest and empty source directories**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMacClean",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacCleanCore", targets: ["MyMacCleanCore"])
    ],
    targets: [
        .target(name: "MyMacCleanCore"),
        .testTarget(
            name: "MyMacCleanCoreTests",
            dependencies: ["MyMacCleanCore"]
        )
    ]
)
```

```bash
mkdir -p Sources/MyMacCleanCore/Models Sources/MyMacCleanApp/Resources Tests/MyMacCleanCoreTests
printf '\n.build/\ndist/\n.swiftpm/\n' >> .gitignore
```

- [ ] **Step 2: Write the failing domain model test**

```swift
// Tests/MyMacCleanCoreTests/DomainModelTests.swift
import XCTest
@testable import MyMacCleanCore

final class DomainModelTests: XCTestCase {
    func testDeletionPlanTotalsSelectedCandidateSizes() {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: "124.0",
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let support = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Figma"),
            kind: .applicationSupport,
            size: 25,
            matchReason: "name match in Application Support",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let cache = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"),
            kind: .cache,
            size: 17,
            matchReason: "bundle identifier match in Caches",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )

        let plan = DeletionPlan(app: app, candidates: [support, cache], createdAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(plan.totalSize, 42)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter DomainModelTests/testDeletionPlanTotalsSelectedCandidateSizes`

Expected: FAIL at compile time with messages mentioning `cannot find 'InstalledApp' in scope`, `cannot find 'RelatedFileCandidate' in scope`, or `cannot find 'DeletionPlan' in scope`.

- [ ] **Step 4: Add the minimal domain models**

```swift
// Sources/MyMacCleanCore/Models/InstalledApp.swift
import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let executableName: String?
    public let bundleURL: URL
    public let iconIdentifier: String?
    public let bundleSize: Int64
    public let lastOpenedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        executableName: String?,
        bundleURL: URL,
        iconIdentifier: String?,
        bundleSize: Int64,
        lastOpenedAt: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.executableName = executableName
        self.bundleURL = bundleURL
        self.iconIdentifier = iconIdentifier
        self.bundleSize = bundleSize
        self.lastOpenedAt = lastOpenedAt
    }
}
```

```swift
// Sources/MyMacCleanCore/Models/RelatedFileCandidate.swift
import Foundation

public enum RelatedFileKind: String, Codable, Equatable, Sendable {
    case appBundle
    case applicationSupport
    case cache
    case preferences
    case savedState
    case container
    case groupContainer
    case log
    case httpStorage
    case webKit
    case launchAgent
    case launchDaemon
    case script
    case unknown
}

public enum MatchConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

public struct RelatedFileCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: RelatedFileKind
    public let size: Int64
    public let matchReason: String
    public let confidence: MatchConfidence
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
    public let isProtected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: RelatedFileKind,
        size: Int64,
        matchReason: String,
        confidence: MatchConfidence,
        defaultSelected: Bool,
        requiresManualReview: Bool,
        isProtected: Bool
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.size = size
        self.matchReason = matchReason
        self.confidence = confidence
        self.defaultSelected = defaultSelected
        self.requiresManualReview = requiresManualReview
        self.isProtected = isProtected
    }
}

public struct DeletionPlan: Equatable, Sendable {
    public let app: InstalledApp
    public let candidates: [RelatedFileCandidate]
    public let totalSize: Int64
    public let createdAt: Date

    public init(app: InstalledApp, candidates: [RelatedFileCandidate], createdAt: Date = Date()) {
        self.app = app
        self.candidates = candidates
        self.totalSize = candidates.reduce(0) { $0 + $1.size }
        self.createdAt = createdAt
    }
}

public struct DeletionItemResult: Codable, Equatable, Sendable {
    public let path: String
    public let success: Bool
    public let errorMessage: String?

    public init(path: String, success: Bool, errorMessage: String?) {
        self.path = path
        self.success = success
        self.errorMessage = errorMessage
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter DomainModelTests/testDeletionPlanTotalsSelectedCandidateSizes`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources/MyMacCleanCore/Models Tests/MyMacCleanCoreTests/DomainModelTests.swift
git commit -m "feat: add core domain models"
```

## Task 2: Fixture Helpers And Metadata Reader

**Files:**
- Create: `Sources/MyMacCleanCore/Support/FileSizeCalculator.swift`
- Create: `Sources/MyMacCleanCore/Discovery/AppMetadataReader.swift`
- Create: `Tests/MyMacCleanCoreTests/TestFixtures.swift`
- Create: `Tests/MyMacCleanCoreTests/AppMetadataReaderTests.swift`

- [ ] **Step 1: Write fixture helpers used by metadata tests**

```swift
// Tests/MyMacCleanCoreTests/TestFixtures.swift
import Foundation

enum TestFixtures {
    static func temporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeAppBundle(
        root: URL,
        name: String,
        bundleIdentifier: String,
        version: String = "1.0",
        executableName: String? = nil,
        payloadSize: Int = 3
    ) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let executable = executableName ?? name
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": executable
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)

        let executableURL = macOSURL.appendingPathComponent(executable)
        try Data(repeating: 1, count: payloadSize).write(to: executableURL)
        return appURL
    }
}
```

- [ ] **Step 2: Write the failing metadata reader test**

```swift
// Tests/MyMacCleanCoreTests/AppMetadataReaderTests.swift
import XCTest
@testable import MyMacCleanCore

final class AppMetadataReaderTests: XCTestCase {
    func testReadsMetadataFromInfoPlistAndComputesBundleSize() throws {
        let root = try TestFixtures.temporaryDirectory(named: "metadata")
        let appURL = try TestFixtures.makeAppBundle(
            root: root,
            name: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: "124.1",
            executableName: "FigmaDesktop",
            payloadSize: 5
        )

        let app = try AppMetadataReader().readApp(at: appURL)

        XCTAssertEqual(app.displayName, "Figma")
        XCTAssertEqual(app.bundleIdentifier, "com.figma.Desktop")
        XCTAssertEqual(app.version, "124.1")
        XCTAssertEqual(app.executableName, "FigmaDesktop")
        XCTAssertEqual(app.bundleURL, appURL)
        XCTAssertGreaterThanOrEqual(app.bundleSize, 5)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter AppMetadataReaderTests/testReadsMetadataFromInfoPlistAndComputesBundleSize`

Expected: FAIL at compile time with `cannot find 'AppMetadataReader' in scope`.

- [ ] **Step 4: Add size calculator and metadata reader**

```swift
// Sources/MyMacCleanCore/Support/FileSizeCalculator.swift
import Foundation

public struct FileSizeCalculator: Sendable {
    public init() {}

    public func sizeOfItem(at url: URL) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if resourceValues.isDirectory == true {
            return try directorySize(at: url)
        }
        return Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
    }

    private func directorySize(at url: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return total
    }
}
```

```swift
// Sources/MyMacCleanCore/Discovery/AppMetadataReader.swift
import Foundation

public enum AppMetadataReaderError: Error, Equatable {
    case missingInfoPlist(URL)
    case unreadableInfoPlist(URL)
}

public struct AppMetadataReader: Sendable {
    private let sizeCalculator: FileSizeCalculator

    public init(sizeCalculator: FileSizeCalculator = FileSizeCalculator()) {
        self.sizeCalculator = sizeCalculator
    }

    public func readApp(at appURL: URL) throws -> InstalledApp {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            throw AppMetadataReaderError.missingInfoPlist(infoURL)
        }
        let data = try Data(contentsOf: infoURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data) as? [String: Any] else {
            throw AppMetadataReaderError.unreadableInfoPlist(infoURL)
        }

        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? fallbackName

        return InstalledApp(
            displayName: displayName,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            version: plist["CFBundleShortVersionString"] as? String,
            executableName: plist["CFBundleExecutable"] as? String,
            bundleURL: appURL,
            iconIdentifier: plist["CFBundleIconFile"] as? String,
            bundleSize: try sizeCalculator.sizeOfItem(at: appURL),
            lastOpenedAt: try appURL.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        )
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter AppMetadataReaderTests/testReadsMetadataFromInfoPlistAndComputesBundleSize`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanCore/Support Sources/MyMacCleanCore/Discovery Tests/MyMacCleanCoreTests/TestFixtures.swift Tests/MyMacCleanCoreTests/AppMetadataReaderTests.swift
git commit -m "feat: read app bundle metadata"
```

## Task 3: App Discovery Service

**Files:**
- Create: `Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift`
- Create: `Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift`

- [ ] **Step 1: Write the failing discovery test**

```swift
// Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift
import XCTest
@testable import MyMacCleanCore

final class AppDiscoveryServiceTests: XCTestCase {
    func testDiscoversOnlyAppBundlesFromConfiguredRoots() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "discovery")
        _ = try TestFixtures.makeAppBundle(root: root, name: "Figma", bundleIdentifier: "com.figma.Desktop")
        _ = try TestFixtures.makeAppBundle(root: root, name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        try "not an app".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let apps = try await AppDiscoveryService(searchRoots: [root]).discoverApps()

        XCTAssertEqual(apps.map(\.displayName).sorted(), ["Figma", "Slack"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AppDiscoveryServiceTests/testDiscoversOnlyAppBundlesFromConfiguredRoots`

Expected: FAIL at compile time with `cannot find 'AppDiscoveryService' in scope`.

- [ ] **Step 3: Add the discovery service**

```swift
// Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift
import Foundation

public struct AppDiscoveryService: Sendable {
    private let searchRoots: [URL]
    private let metadataReader: AppMetadataReader

    public init(
        searchRoots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ],
        metadataReader: AppMetadataReader = AppMetadataReader()
    ) {
        self.searchRoots = searchRoots
        self.metadataReader = metadataReader
    }

    public func discoverApps() async throws -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in searchRoots where FileManager.default.fileExists(atPath: root.path) {
            let contents = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for url in contents where url.pathExtension == "app" {
                if let app = try? metadataReader.readApp(at: url), !isProtectedSystemApp(app) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func isProtectedSystemApp(_ app: InstalledApp) -> Bool {
        app.bundleURL.path.hasPrefix("/System/Applications/")
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AppDiscoveryServiceTests/testDiscoversOnlyAppBundlesFromConfiguredRoots`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Discovery/AppDiscoveryService.swift Tests/MyMacCleanCoreTests/AppDiscoveryServiceTests.swift
git commit -m "feat: discover installed app bundles"
```

## Task 4: Path Utilities And Protection Policy

**Files:**
- Create: `Sources/MyMacCleanCore/Support/PathUtilities.swift`
- Create: `Sources/MyMacCleanCore/Safety/ProtectionPolicy.swift`
- Create: `Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift`

- [ ] **Step 1: Write the failing protection policy tests**

```swift
// Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift
import XCTest
@testable import MyMacCleanCore

final class ProtectionPolicyTests: XCTestCase {
    func testBlocksUserDocumentFoldersAndSystemCriticalPaths() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Documents/Figma Export.fig")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Desktop/Sketch.sketch")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        XCTAssertTrue(policy.isProtected(URL(fileURLWithPath: "/private/var/db/example")))
    }

    func testAllowsKnownUserLibraryAppData() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectionPolicy(homeDirectory: home)

        XCTAssertFalse(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Library/Caches/com.figma.Desktop")))
        XCTAssertFalse(policy.isProtected(URL(fileURLWithPath: "/Users/tester/Library/Application Support/Figma")))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProtectionPolicyTests`

Expected: FAIL at compile time with `cannot find 'ProtectionPolicy' in scope`.

- [ ] **Step 3: Add path utilities and protection policy**

```swift
// Sources/MyMacCleanCore/Support/PathUtilities.swift
import Foundation

public enum PathUtilities {
    public static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    public static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        let childPath = standardizedPath(child)
        let parentPath = standardizedPath(parent)
        return childPath == parentPath || childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }
}
```

```swift
// Sources/MyMacCleanCore/Safety/ProtectionPolicy.swift
import Foundation

public struct ProtectionPolicy: Sendable {
    private let protectedRoots: [URL]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.protectedRoots = [
            homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectory.appendingPathComponent("Documents", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent("Pictures", isDirectory: true),
            homeDirectory.appendingPathComponent("Movies", isDirectory: true),
            homeDirectory.appendingPathComponent("Music", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Mobile Documents", isDirectory: true),
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            URL(fileURLWithPath: "/var", isDirectory: true)
        ]
    }

    public func isProtected(_ url: URL) -> Bool {
        protectedRoots.contains { PathUtilities.isDescendant(url, of: $0) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProtectionPolicyTests`

Expected: PASS with `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Support/PathUtilities.swift Sources/MyMacCleanCore/Safety Tests/MyMacCleanCoreTests/ProtectionPolicyTests.swift
git commit -m "feat: block protected deletion paths"
```

## Task 5: Candidate Matcher

**Files:**
- Create: `Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift`
- Create: `Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift`

- [ ] **Step 1: Write the failing matcher tests**

```swift
// Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift
import XCTest
@testable import MyMacCleanCore

final class CandidateMatcherTests: XCTestCase {
    func testHighConfidenceForBundleIdentifierPath() {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"),
            app: app,
            kind: .cache
        )

        XCTAssertEqual(match?.confidence, .high)
        XCTAssertEqual(match?.defaultSelected, true)
    }

    func testDoesNotMatchPartialUnrelatedNames() {
        let app = InstalledApp(
            displayName: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            version: nil,
            executableName: "Arc",
            bundleURL: URL(fileURLWithPath: "/Applications/Arc.app"),
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        let match = CandidateMatcher().match(
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Archive Utility"),
            app: app,
            kind: .applicationSupport
        )

        XCTAssertNil(match)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CandidateMatcherTests`

Expected: FAIL at compile time with `cannot find 'CandidateMatcher' in scope`.

- [ ] **Step 3: Add candidate matcher**

```swift
// Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift
import Foundation

public struct CandidateMatch: Equatable, Sendable {
    public let matchReason: String
    public let confidence: MatchConfidence
    public let defaultSelected: Bool
    public let requiresManualReview: Bool
}

public struct CandidateMatcher: Sendable {
    public init() {}

    public func match(url: URL, app: InstalledApp, kind: RelatedFileKind) -> CandidateMatch? {
        let normalizedPath = url.lastPathComponent.lowercased()
        let fullPath = url.path.lowercased()

        if let bundleIdentifier = app.bundleIdentifier?.lowercased(), fullPath.contains(bundleIdentifier) {
            return CandidateMatch(
                matchReason: "bundle identifier match",
                confidence: .high,
                defaultSelected: true,
                requiresManualReview: false
            )
        }

        let appTokens = tokenSet(from: app.displayName)
        let executableTokens = tokenSet(from: app.executableName ?? "")
        let candidateTokens = tokenSet(from: normalizedPath)
        let acceptedTokens = appTokens.union(executableTokens).filter { $0.count >= 3 }

        if !acceptedTokens.isEmpty && !candidateTokens.isDisjoint(with: acceptedTokens) {
            return CandidateMatch(
                matchReason: "app name token match",
                confidence: kind == .unknown ? .low : .medium,
                defaultSelected: kind != .unknown,
                requiresManualReview: kind == .unknown
            )
        }

        return nil
    }

    private func tokenSet(from value: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            value
                .lowercased()
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CandidateMatcherTests`

Expected: PASS with `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Scanning/CandidateMatcher.swift Tests/MyMacCleanCoreTests/CandidateMatcherTests.swift
git commit -m "feat: score related file candidates"
```

## Task 6: Related File Scanner

**Files:**
- Create: `Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift`
- Create: `Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift`

- [ ] **Step 1: Write the failing scanner test**

```swift
// Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift
import XCTest
@testable import MyMacCleanCore

final class RelatedFileScannerTests: XCTestCase {
    func testScansKnownLibraryLocationsAndMarksProtectedMatches() async throws {
        let home = try TestFixtures.temporaryDirectory(named: "scanner-home")
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: home.appendingPathComponent("Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let support = home.appendingPathComponent("Library/Application Support/Figma", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        let document = home.appendingPathComponent("Documents/Figma Export.fig")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4).write(to: support.appendingPathComponent("state.json"))
        try Data(repeating: 1, count: 5).write(to: cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 1, count: 6).write(to: document)

        let scanner = RelatedFileScanner(homeDirectory: home, extraScanRoots: [home.appendingPathComponent("Documents")])
        let candidates = try await scanner.scanRelatedFiles(for: app)

        XCTAssertTrue(candidates.contains { $0.url == support && $0.kind == .applicationSupport && !$0.isProtected })
        XCTAssertTrue(candidates.contains { $0.url == cache && $0.kind == .cache && !$0.isProtected })
        XCTAssertTrue(candidates.contains { $0.url == document && $0.isProtected })
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RelatedFileScannerTests/testScansKnownLibraryLocationsAndMarksProtectedMatches`

Expected: FAIL at compile time with `cannot find 'RelatedFileScanner' in scope`.

- [ ] **Step 3: Add related file scanner**

```swift
// Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift
import Foundation

public struct RelatedFileScanner: Sendable {
    private let homeDirectory: URL
    private let extraScanRoots: [URL]
    private let matcher: CandidateMatcher
    private let protectionPolicy: ProtectionPolicy
    private let sizeCalculator: FileSizeCalculator

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraScanRoots: [URL] = [],
        matcher: CandidateMatcher = CandidateMatcher(),
        protectionPolicy: ProtectionPolicy? = nil,
        sizeCalculator: FileSizeCalculator = FileSizeCalculator()
    ) {
        self.homeDirectory = homeDirectory
        self.extraScanRoots = extraScanRoots
        self.matcher = matcher
        self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
        self.sizeCalculator = sizeCalculator
    }

    public func scanRelatedFiles(for app: InstalledApp) async throws -> [RelatedFileCandidate] {
        var candidates: [RelatedFileCandidate] = [
            RelatedFileCandidate(
                url: app.bundleURL,
                kind: .appBundle,
                size: app.bundleSize,
                matchReason: "selected app bundle",
                confidence: .high,
                defaultSelected: true,
                requiresManualReview: false,
                isProtected: protectionPolicy.isProtected(app.bundleURL)
            )
        ]

        for (root, kind) in scanRoots() {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let urls = try childURLs(in: root)
            for url in urls {
                guard let match = matcher.match(url: url, app: app, kind: kind) else { continue }
                let isProtected = protectionPolicy.isProtected(url)
                candidates.append(
                    RelatedFileCandidate(
                        url: url,
                        kind: kind,
                        size: (try? sizeCalculator.sizeOfItem(at: url)) ?? 0,
                        matchReason: match.matchReason,
                        confidence: match.confidence,
                        defaultSelected: match.defaultSelected && !isProtected,
                        requiresManualReview: match.requiresManualReview || isProtected,
                        isProtected: isProtected
                    )
                )
            }
        }

        return Array(Set(candidates.map(\.url))).compactMap { url in
            candidates.first { $0.url == url }
        }.sorted { $0.url.path < $1.url.path }
    }

    private func scanRoots() -> [(URL, RelatedFileKind)] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let known: [(String, RelatedFileKind)] = [
            ("Application Support", .applicationSupport),
            ("Caches", .cache),
            ("Preferences", .preferences),
            ("Saved Application State", .savedState),
            ("Containers", .container),
            ("Group Containers", .groupContainer),
            ("Logs", .log),
            ("HTTPStorages", .httpStorage),
            ("WebKit", .webKit),
            ("Application Scripts", .script),
            ("LaunchAgents", .launchAgent)
        ]
        return known.map { (library.appendingPathComponent($0.0, isDirectory: true), $0.1) }
            + extraScanRoots.map { ($0, .unknown) }
    }

    private func childURLs(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RelatedFileScannerTests/testScansKnownLibraryLocationsAndMarksProtectedMatches`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Scanning/RelatedFileScanner.swift Tests/MyMacCleanCoreTests/RelatedFileScannerTests.swift
git commit -m "feat: scan app related files"
```

## Task 7: Deletion Planner

**Files:**
- Create: `Sources/MyMacCleanCore/Deletion/DeletionPlanner.swift`
- Create: `Tests/MyMacCleanCoreTests/DeletionPlannerTests.swift`

- [ ] **Step 1: Write the failing planner tests**

```swift
// Tests/MyMacCleanCoreTests/DeletionPlannerTests.swift
import XCTest
@testable import MyMacCleanCore

final class DeletionPlannerTests: XCTestCase {
    func testPlannerExcludesProtectedAndUnselectedCandidates() throws {
        let app = InstalledApp(
            displayName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: nil,
            executableName: "Figma",
            bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
        let selected = candidate(path: "/Users/me/Library/Caches/com.figma.Desktop", selected: true, protected: false, size: 5)
        let unselected = candidate(path: "/Users/me/Library/Logs/Figma", selected: false, protected: false, size: 7)
        let protected = candidate(path: "/Users/me/Documents/Figma Export.fig", selected: true, protected: true, size: 11)

        let plan = try DeletionPlanner().makePlan(app: app, candidates: [selected, unselected, protected], selectedIDs: [selected.id, protected.id])

        XCTAssertEqual(plan.candidates.map(\.url.path), ["/Users/me/Library/Caches/com.figma.Desktop"])
        XCTAssertEqual(plan.totalSize, 5)
    }

    private func candidate(path: String, selected: Bool, protected: Bool, size: Int64) -> RelatedFileCandidate {
        RelatedFileCandidate(
            url: URL(fileURLWithPath: path),
            kind: .cache,
            size: size,
            matchReason: "test",
            confidence: .high,
            defaultSelected: selected,
            requiresManualReview: protected,
            isProtected: protected
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DeletionPlannerTests/testPlannerExcludesProtectedAndUnselectedCandidates`

Expected: FAIL at compile time with `cannot find 'DeletionPlanner' in scope`.

- [ ] **Step 3: Add deletion planner**

```swift
// Sources/MyMacCleanCore/Deletion/DeletionPlanner.swift
import Foundation

public enum DeletionPlannerError: Error, Equatable {
    case emptySelection
}

public struct DeletionPlanner: Sendable {
    public init() {}

    public func makePlan(
        app: InstalledApp,
        candidates: [RelatedFileCandidate],
        selectedIDs: Set<RelatedFileCandidate.ID>,
        createdAt: Date = Date()
    ) throws -> DeletionPlan {
        let selected = candidates
            .filter { selectedIDs.contains($0.id) }
            .filter { !$0.isProtected }

        guard !selected.isEmpty else {
            throw DeletionPlannerError.emptySelection
        }

        return DeletionPlan(app: app, candidates: selected, createdAt: createdAt)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter DeletionPlannerTests/testPlannerExcludesProtectedAndUnselectedCandidates`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Deletion/DeletionPlanner.swift Tests/MyMacCleanCoreTests/DeletionPlannerTests.swift
git commit -m "feat: create safe deletion plans"
```

## Task 8: Permanent Deletion Executor

**Files:**
- Create: `Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift`
- Create: `Tests/MyMacCleanCoreTests/DeletionExecutorTests.swift`

- [ ] **Step 1: Write the failing executor tests**

```swift
// Tests/MyMacCleanCoreTests/DeletionExecutorTests.swift
import XCTest
@testable import MyMacCleanCore

final class DeletionExecutorTests: XCTestCase {
    func testExecutorPermanentlyRemovesPlannedFiles() async throws {
        let root = try TestFixtures.temporaryDirectory(named: "executor")
        let appURL = root.appendingPathComponent("Figma.app", isDirectory: true)
        let cacheURL = root.appendingPathComponent("Library/Caches/com.figma.Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: appURL, iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: cacheURL, kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate], createdAt: Date(timeIntervalSince1970: 0))

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "DELETE Figma")

        XCTAssertEqual(results, [DeletionItemResult(path: cacheURL.path, success: true, errorMessage: nil)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testExecutorRejectsMissingConfirmationPhrase() async throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: nil, version: nil, executableName: nil, bundleURL: URL(fileURLWithPath: "/tmp/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let candidate = RelatedFileCandidate(url: URL(fileURLWithPath: "/tmp/Figma-cache"), kind: .cache, size: 0, matchReason: "test", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let plan = DeletionPlan(app: app, candidates: [candidate])

        let results = await DeletionExecutor().execute(plan: plan, confirmation: "delete figma")

        XCTAssertEqual(results, [DeletionItemResult(path: "/tmp/Figma-cache", success: false, errorMessage: "confirmation phrase mismatch")])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DeletionExecutorTests`

Expected: FAIL at compile time with `cannot find 'DeletionExecutor' in scope`.

- [ ] **Step 3: Add permanent deletion executor**

```swift
// Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift
import Foundation

public struct DeletionExecutor: Sendable {
    public init() {}

    public func requiredConfirmationPhrase(for app: InstalledApp) -> String {
        "DELETE \(app.displayName)"
    }

    public func execute(plan: DeletionPlan, confirmation: String) async -> [DeletionItemResult] {
        guard confirmation == requiredConfirmationPhrase(for: plan.app) else {
            return plan.candidates.map {
                DeletionItemResult(path: $0.url.path, success: false, errorMessage: "confirmation phrase mismatch")
            }
        }

        return plan.candidates.map { candidate in
            do {
                if FileManager.default.fileExists(atPath: candidate.url.path) {
                    try FileManager.default.removeItem(at: candidate.url)
                }
                return DeletionItemResult(path: candidate.url.path, success: true, errorMessage: nil)
            } catch {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DeletionExecutorTests`

Expected: PASS with `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Deletion/DeletionExecutor.swift Tests/MyMacCleanCoreTests/DeletionExecutorTests.swift
git commit -m "feat: permanently delete confirmed plans"
```

## Task 9: Deletion Journal

**Files:**
- Create: `Sources/MyMacCleanCore/Journal/DeletionJournal.swift`
- Create: `Tests/MyMacCleanCoreTests/DeletionJournalTests.swift`

- [ ] **Step 1: Write the failing journal test**

```swift
// Tests/MyMacCleanCoreTests/DeletionJournalTests.swift
import XCTest
@testable import MyMacCleanCore

final class DeletionJournalTests: XCTestCase {
    func testAppendsAndReadsDeletionRecords() throws {
        let root = try TestFixtures.temporaryDirectory(named: "journal")
        let journalURL = root.appendingPathComponent("deletions.jsonl")
        let journal = DeletionJournal(fileURL: journalURL)
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: "124", executableName: "Figma", bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let record = DeletionRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            appName: app.displayName,
            bundleIdentifier: app.bundleIdentifier,
            deletedAt: Date(timeIntervalSince1970: 1),
            results: [DeletionItemResult(path: "/tmp/cache", success: true, errorMessage: nil)]
        )

        try journal.append(record)
        let records = try journal.readRecords()

        XCTAssertEqual(records, [record])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DeletionJournalTests/testAppendsAndReadsDeletionRecords`

Expected: FAIL at compile time with `cannot find 'DeletionJournal' in scope` or `cannot find 'DeletionRecord' in scope`.

- [ ] **Step 3: Add deletion journal**

```swift
// Sources/MyMacCleanCore/Journal/DeletionJournal.swift
import Foundation

public struct DeletionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let bundleIdentifier: String?
    public let deletedAt: Date
    public let results: [DeletionItemResult]

    public init(id: UUID = UUID(), appName: String, bundleIdentifier: String?, deletedAt: Date = Date(), results: [DeletionItemResult]) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deletedAt = deletedAt
        self.results = results
    }
}

public struct DeletionJournal: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ record: DeletionRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try encoder.encode(record)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }

    public func readRecords() throws -> [DeletionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try text
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                return try decoder.decode(DeletionRecord.self, from: data)
            }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter DeletionJournalTests/testAppendsAndReadsDeletionRecords`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Journal Tests/MyMacCleanCoreTests/DeletionJournalTests.swift
git commit -m "feat: persist deletion journal"
```

## Task 10: Permission Coordinator

**Files:**
- Create: `Sources/MyMacCleanCore/Permissions/PermissionCoordinator.swift`
- Create: `Tests/MyMacCleanCoreTests/PermissionCoordinatorTests.swift`

- [ ] **Step 1: Write the failing permission tests**

```swift
// Tests/MyMacCleanCoreTests/PermissionCoordinatorTests.swift
import XCTest
@testable import MyMacCleanCore

final class PermissionCoordinatorTests: XCTestCase {
    func testClassifiesPermissionDeniedErrors() {
        let status = PermissionCoordinator().status(for: CocoaError(.fileReadNoPermission))

        XCTAssertEqual(status, .fullDiskAccessRecommended)
    }

    func testReturnsActionableFullDiskAccessGuidance() {
        let guidance = PermissionCoordinator().fullDiskAccessGuidance(appName: "MyMacClean")

        XCTAssertTrue(guidance.contains("System Settings"))
        XCTAssertTrue(guidance.contains("Full Disk Access"))
        XCTAssertTrue(guidance.contains("MyMacClean"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PermissionCoordinatorTests`

Expected: FAIL at compile time with `cannot find 'PermissionCoordinator' in scope`.

- [ ] **Step 3: Add permission coordinator**

```swift
// Sources/MyMacCleanCore/Permissions/PermissionCoordinator.swift
import Foundation

public enum PermissionStatus: Equatable, Sendable {
    case available
    case fullDiskAccessRecommended
    case administratorPrivilegesRequired
    case unknownFailure(String)
}

public struct PermissionCoordinator: Sendable {
    public init() {}

    public func status(for error: Error) -> PermissionStatus {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code) {
            return .fullDiskAccessRecommended
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return .administratorPrivilegesRequired
        }
        return .unknownFailure(nsError.localizedDescription)
    }

    public func fullDiskAccessGuidance(appName: String) -> String {
        "Open System Settings, go to Privacy & Security, choose Full Disk Access, then enable \(appName). Restart the app after changing this permission."
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PermissionCoordinatorTests`

Expected: PASS with `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MyMacCleanCore/Permissions Tests/MyMacCleanCoreTests/PermissionCoordinatorTests.swift
git commit -m "feat: describe permission failures"
```

## Task 11: Application List View Model

**Files:**
- Create: `Sources/MyMacCleanCore/Deletion/ApplicationDeletionWorkflow.swift`
- Create: `Sources/MyMacCleanApp/ViewModels/ApplicationListViewModel.swift`
- Create: `Tests/MyMacCleanCoreTests/ApplicationWorkflowTests.swift`

- [ ] **Step 1: Write the failing workflow test against a UI-independent coordinator**

```swift
// Tests/MyMacCleanCoreTests/ApplicationWorkflowTests.swift
import XCTest
@testable import MyMacCleanCore

final class ApplicationWorkflowTests: XCTestCase {
    func testWorkflowBuildsDeletionPlanFromDefaultSelectedCandidates() throws {
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: nil, executableName: "Figma", bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"), iconIdentifier: nil, bundleSize: 10, lastOpenedAt: nil)
        let selected = RelatedFileCandidate(url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.figma.Desktop"), kind: .cache, size: 5, matchReason: "bundle identifier match", confidence: .high, defaultSelected: true, requiresManualReview: false, isProtected: false)
        let ignored = RelatedFileCandidate(url: URL(fileURLWithPath: "/Users/me/Documents/Figma Export.fig"), kind: .unknown, size: 8, matchReason: "app name token match", confidence: .low, defaultSelected: false, requiresManualReview: true, isProtected: true)

        let plan = try ApplicationDeletionWorkflow().makeDefaultPlan(app: app, candidates: [selected, ignored])

        XCTAssertEqual(plan.candidates, [selected])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ApplicationWorkflowTests/testWorkflowBuildsDeletionPlanFromDefaultSelectedCandidates`

Expected: FAIL at compile time with `cannot find 'ApplicationDeletionWorkflow' in scope`.

- [ ] **Step 3: Add workflow coordinator in core**

```swift
// Sources/MyMacCleanCore/Deletion/ApplicationDeletionWorkflow.swift
import Foundation

public struct ApplicationDeletionWorkflow: Sendable {
    private let planner: DeletionPlanner

    public init(planner: DeletionPlanner = DeletionPlanner()) {
        self.planner = planner
    }

    public func makeDefaultPlan(app: InstalledApp, candidates: [RelatedFileCandidate]) throws -> DeletionPlan {
        let selectedIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
        return try planner.makePlan(app: app, candidates: candidates, selectedIDs: selectedIDs)
    }
}
```

- [ ] **Step 4: Add SwiftUI view model that uses the workflow**

```swift
// Sources/MyMacCleanApp/ViewModels/ApplicationListViewModel.swift
import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
final class ApplicationListViewModel {
    private let discoveryService: AppDiscoveryService
    private let scanner: RelatedFileScanner
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor

    var apps: [InstalledApp] = []
    var selectedApp: InstalledApp?
    var candidates: [RelatedFileCandidate] = []
    var selectedCandidateIDs: Set<RelatedFileCandidate.ID> = []
    var deletionResults: [DeletionItemResult] = []
    var errorMessage: String?
    var isScanning = false

    init(
        discoveryService: AppDiscoveryService = AppDiscoveryService(),
        scanner: RelatedFileScanner = RelatedFileScanner(),
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor = DeletionExecutor()
    ) {
        self.discoveryService = discoveryService
        self.scanner = scanner
        self.planner = planner
        self.executor = executor
    }

    func loadApps() async {
        do {
            apps = try await discoveryService.discoverApps()
            selectedApp = apps.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scanSelectedApp() async {
        guard let selectedApp else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            candidates = try await scanner.scanRelatedFiles(for: selectedApp)
            selectedCandidateIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makePlan() throws -> DeletionPlan {
        guard let selectedApp else { throw DeletionPlannerError.emptySelection }
        return try planner.makePlan(app: selectedApp, candidates: candidates, selectedIDs: selectedCandidateIDs)
    }

    func deleteConfirmedItems(confirmation: String) async {
        do {
            let plan = try makePlan()
            deletionResults = await executor.execute(plan: plan, confirmation: confirmation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Run workflow and package tests**

Run: `swift test --filter ApplicationWorkflowTests/testWorkflowBuildsDeletionPlanFromDefaultSelectedCandidates`

Expected: PASS with `Executed 1 test, with 0 failures`.

Run: `swift test`

Expected: PASS with all current tests reporting 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/MyMacCleanCore/Deletion/ApplicationDeletionWorkflow.swift Sources/MyMacCleanApp/ViewModels Tests/MyMacCleanCoreTests/ApplicationWorkflowTests.swift
git commit -m "feat: coordinate app deletion workflow"
```

## Task 12: SwiftUI Native Inspector UI

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MyMacCleanApp/MyMacCleanApp.swift`
- Create: `Sources/MyMacCleanApp/Views/ContentView.swift`
- Create: `Sources/MyMacCleanApp/Views/Components.swift`
- Create: `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`

- [ ] **Step 1: Add executable target to the package manifest**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyMacClean",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyMacCleanCore", targets: ["MyMacCleanCore"]),
        .executable(name: "MyMacCleanApp", targets: ["MyMacCleanApp"])
    ],
    targets: [
        .target(name: "MyMacCleanCore"),
        .executableTarget(
            name: "MyMacCleanApp",
            dependencies: ["MyMacCleanCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MyMacCleanCoreTests",
            dependencies: ["MyMacCleanCore"]
        )
    ]
)
```

- [ ] **Step 2: Add the SwiftUI app entry point**

```swift
// Sources/MyMacCleanApp/MyMacCleanApp.swift
import SwiftUI

@main
struct MyMacCleanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 3: Add shared components**

```swift
// Sources/MyMacCleanApp/Views/Components.swift
import SwiftUI
import MyMacCleanCore

struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            .monospacedDigit()
    }
}

struct ConfidenceBadge: View {
    let confidence: MatchConfidence

    var body: some View {
        Text(confidence.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch confidence {
        case .high: Color.blue.opacity(0.12)
        case .medium: Color.orange.opacity(0.16)
        case .low: Color.gray.opacity(0.14)
        }
    }
}

struct RelatedFileRow: View {
    let candidate: RelatedFileCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(candidate.isProtected ? .secondary : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.url.lastPathComponent)
                        .font(.subheadline.weight(.medium))
                    Text(candidate.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                ConfidenceBadge(confidence: candidate.confidence)
                SizeText(bytes: candidate.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(candidate.isProtected)
        .opacity(candidate.isProtected ? 0.55 : 1)
    }
}
```

- [ ] **Step 4: Add main native inspector view**

```swift
// Sources/MyMacCleanApp/Views/ContentView.swift
import SwiftUI
import MyMacCleanCore

struct ContentView: View {
    @State private var viewModel = ApplicationListViewModel()
    @State private var confirmationText = ""
    @State private var showsConfirmation = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            appList
        } detail: {
            inspector
        }
        .task {
            await viewModel.loadApps()
        }
        .alert("MyMacClean", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showsConfirmation) {
            confirmationSheet
        }
    }

    private var sidebar: some View {
        List {
            Section("Current Release") {
                Label("Applications", systemImage: "app.dashed")
                Label("Delete History", systemImage: "clock")
            }
            Section("Roadmap") {
                Label("Startup Items", systemImage: "bolt")
                Label("System Cleanup", systemImage: "sparkles")
                Label("Large Files", systemImage: "internaldrive")
                Label("Maintenance", systemImage: "wrench.adjustable")
            }
        }
        .navigationTitle("MyMacClean")
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Applications")
                        .font(.title2.weight(.semibold))
                    Text("Review installed apps and related files before permanent deletion.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan Selected") {
                    Task { await viewModel.scanSelectedApp() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedApp == nil || viewModel.isScanning)
            }
            .padding()

            Table(viewModel.apps, selection: Binding(
                get: { viewModel.selectedApp?.id },
                set: { newID in viewModel.selectedApp = viewModel.apps.first { $0.id == newID } }
            )) {
                TableColumn("Name") { app in
                    Text(app.displayName)
                }
                TableColumn("Bundle ID") { app in
                    Text(app.bundleIdentifier ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
                TableColumn("Size") { app in
                    SizeText(bytes: app.bundleSize)
                }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let app = viewModel.selectedApp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayName)
                        .font(.title3.weight(.semibold))
                    Text(app.bundleIdentifier ?? app.bundleURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("App Bundle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SizeText(bytes: app.bundleSize)
                            .font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Related Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.candidates.count)")
                            .font(.headline)
                    }
                }
                Divider()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.candidates) { candidate in
                            RelatedFileRow(
                                candidate: candidate,
                                isSelected: viewModel.selectedCandidateIDs.contains(candidate.id),
                                toggle: {
                                    if viewModel.selectedCandidateIDs.contains(candidate.id) {
                                        viewModel.selectedCandidateIDs.remove(candidate.id)
                                    } else {
                                        viewModel.selectedCandidateIDs.insert(candidate.id)
                                    }
                                }
                            )
                        }
                    }
                }
                Button(role: .destructive) {
                    confirmationText = ""
                    showsConfirmation = true
                } label: {
                    Text("Permanently Delete Selected Items")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedCandidateIDs.isEmpty)
            } else {
                ContentUnavailableView("No App Selected", systemImage: "app.dashed")
            }
        }
        .padding()
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            let appName = viewModel.selectedApp?.displayName ?? ""
            Text("Permanent Deletion")
                .font(.title2.weight(.semibold))
            Text("Type DELETE \(appName) to permanently remove selected items. This does not move files to Trash.")
                .foregroundStyle(.secondary)
            TextField("DELETE \(appName)", text: $confirmationText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showsConfirmation = false }
                Spacer()
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteConfirmedItems(confirmation: confirmationText)
                        showsConfirmation = false
                    }
                }
                .disabled(confirmationText != "DELETE \(appName)")
            }
        }
        .padding()
        .frame(width: 460)
    }
}
```

- [ ] **Step 5: Add app resource plist for packaging scripts**

```xml
<!-- Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.mymacclean</string>
    <key>CFBundleName</key>
    <string>MyMacClean</string>
    <key>CFBundleDisplayName</key>
    <string>MyMacClean</string>
    <key>CFBundleExecutable</key>
    <string>MyMacCleanApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 6: Build the SwiftUI executable**

Run: `swift build`

Expected: PASS with `Build complete!`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MyMacCleanApp
git commit -m "feat: add native uninstaller interface"
```

## Task 13: Development App Bundle And DMG Scripts

**Files:**
- Create: `scripts/build-app-bundle.sh`
- Create: `scripts/create-dmg.sh`

- [ ] **Step 1: Add app bundle build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacClean.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/MyMacCleanApp" "$MACOS_DIR/MyMacCleanApp"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/MyMacCleanApp"

echo "$APP_DIR"
```

- [ ] **Step 2: Add local DMG creation script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacClean.app"
DMG_PATH="$DIST_DIR/MyMacClean-dev.dmg"

"$ROOT_DIR/scripts/build-app-bundle.sh"
rm -f "$DMG_PATH"
hdiutil create -volname "MyMacClean" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
echo "$DMG_PATH"
```

- [ ] **Step 3: Make scripts executable**

Run: `chmod +x scripts/build-app-bundle.sh scripts/create-dmg.sh`

Expected: command exits 0.

- [ ] **Step 4: Build app bundle**

Run: `scripts/build-app-bundle.sh`

Expected: PASS and prints `dist/MyMacClean.app`.

- [ ] **Step 5: Create development DMG**

Run: `scripts/create-dmg.sh`

Expected: PASS and prints `dist/MyMacClean-dev.dmg`.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app-bundle.sh scripts/create-dmg.sh
git commit -m "build: package MyMacClean app bundle"
```

## Task 14: Full Verification Pass

**Files:**
- Modify only files needed to fix failures found by the verification commands.

- [ ] **Step 1: Run the full Swift test suite**

Run: `swift test`

Expected: PASS with all tests reporting 0 failures.

- [ ] **Step 2: Run debug build**

Run: `swift build`

Expected: PASS with `Build complete!`.

- [ ] **Step 3: Run release app bundle build**

Run: `scripts/build-app-bundle.sh`

Expected: PASS and `dist/MyMacClean.app/Contents/MacOS/MyMacCleanApp` exists.

- [ ] **Step 4: Run development DMG packaging**

Run: `scripts/create-dmg.sh`

Expected: PASS and `dist/MyMacClean-dev.dmg` exists.

- [ ] **Step 5: Inspect Git status**

Run: `git status --short`

Expected: no uncommitted files except generated artifacts ignored by `.gitignore`.

- [ ] **Step 6: Commit verification fixes if any files changed**

```bash
git add Package.swift Sources Tests scripts .gitignore
git commit -m "chore: stabilize MyMacClean verification"
```

Skip this commit only when `git status --short` is already empty.

## Self-Review Checklist

- Spec coverage: Tasks 1-3 cover app discovery and metadata; Tasks 4-8 cover related file scanning, protected paths, deletion planning, and permanent deletion; Task 9 covers deletion journal; Task 10 covers permission guidance; Tasks 11-12 cover SwiftUI state and approved native inspector UI; Task 13 covers local DMG packaging.
- Incomplete-item scan: This plan contains concrete file paths, commands, expected failures, and code blocks for every code-producing step.
- Type consistency: `InstalledApp`, `RelatedFileCandidate`, `DeletionPlan`, `DeletionItemResult`, `DeletionPlanner`, `DeletionExecutor`, and `ApplicationListViewModel` names are consistent across tasks.
