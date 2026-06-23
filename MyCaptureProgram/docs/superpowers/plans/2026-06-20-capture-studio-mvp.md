# Capture Studio MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native macOS milestone: SwiftUI/AppKit app skeleton, minimal main window, Settings window, persistent settings, customizable shortcuts with reset defaults, file output naming/fallback, and capture coordinator interfaces.

**Architecture:** Use a Swift Package executable target for a native macOS 15 SwiftUI app. Keep business logic in small Foundation-based files with XCTest coverage, and keep SwiftUI views thin by reading `AppState`, `SettingsStore`, and `ShortcutManager`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit interfaces, XCTest, UserDefaults, SF Symbols.

---

## Scope

This plan implements the first working foundation from the approved design spec:

- Project scaffold
- Minimal main window
- Settings window with Output, Capture, Record, Shortcuts, and Advanced sections
- Persistent settings model
- Custom shortcut model with duplicate detection and reset defaults
- Output filename and folder fallback model
- Capture coordinator protocols and a simulated ScreenCaptureKit service

This plan does not implement real region overlay capture, MP4 recording, annotation rendering, OCR, color picker, or recording trim. Those require separate implementation plans because they are independent subsystems with their own permissions and UI risks.

## File Structure

Create these files:

- `Package.swift`: Swift package manifest for the app and test targets.
- `Sources/CaptureStudio/CaptureStudioApp.swift`: SwiftUI app entry point.
- `Sources/CaptureStudio/App/AppState.swift`: Shared app selection state.
- `Sources/CaptureStudio/Models/CaptureMode.swift`: Screenshot/record mode enum.
- `Sources/CaptureStudio/Models/CaptureAreaType.swift`: Rectangle/window/full-screen/freeform enum.
- `Sources/CaptureStudio/Models/EditorDocument.swift`: In-memory editor document model.
- `Sources/CaptureStudio/Settings/AppSettings.swift`: Codable settings value.
- `Sources/CaptureStudio/Settings/SettingsStore.swift`: UserDefaults-backed settings store.
- `Sources/CaptureStudio/Shortcuts/ShortcutDefinition.swift`: Shortcut actions, bindings, defaults.
- `Sources/CaptureStudio/Shortcuts/ShortcutManager.swift`: Shortcut customization and reset model.
- `Sources/CaptureStudio/Services/FileOutputService.swift`: Filename generation and directory fallback.
- `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`: `+ New` orchestration interfaces.
- `Sources/CaptureStudio/Capture/ScreenshotService.swift`: Screenshot service protocol and simulated implementation.
- `Sources/CaptureStudio/Views/MainWindowView.swift`: Minimal main window.
- `Sources/CaptureStudio/Views/EditorToolbarView.swift`: Bottom editor toolbar.
- `Sources/CaptureStudio/Views/SettingsView.swift`: Settings UI.
- `Tests/CaptureStudioTests/AppSettingsTests.swift`: Settings defaults tests.
- `Tests/CaptureStudioTests/SettingsStoreTests.swift`: Persistence tests.
- `Tests/CaptureStudioTests/ShortcutManagerTests.swift`: Shortcut behavior tests.
- `Tests/CaptureStudioTests/FileOutputServiceTests.swift`: Output naming and fallback tests.
- `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`: Coordinator state tests.

## Task 1: Swift Package Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Create: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Create: `Tests/CaptureStudioTests/SmokeTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureStudio",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CaptureStudio", targets: ["CaptureStudio"])
    ],
    targets: [
        .executableTarget(
            name: "CaptureStudio",
            path: "Sources/CaptureStudio"
        ),
        .testTarget(
            name: "CaptureStudioTests",
            dependencies: ["CaptureStudio"],
            path: "Tests/CaptureStudioTests"
        )
    ]
)
```

- [ ] **Step 2: Create the app entry point**

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 620, minHeight: 430)
        }
    }
}
```

- [ ] **Step 3: Create the temporary main window**

```swift
import SwiftUI

struct MainWindowView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Capture Studio")
                .font(.title2.weight(.semibold))

            Text("Ready to capture")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
```

- [ ] **Step 4: Create a smoke test**

```swift
import XCTest
@testable import CaptureStudio

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual("CaptureStudio".count, 13)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test`

Expected: PASS, with one test passing.

- [ ] **Step 6: Run the app**

Run: `swift run CaptureStudio`

Expected: A native macOS window opens with "Capture Studio" and "Ready to capture".

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold native mac capture app"
```

## Task 2: App State and Capture Models

**Files:**
- Create: `Sources/CaptureStudio/App/AppState.swift`
- Create: `Sources/CaptureStudio/Models/CaptureMode.swift`
- Create: `Sources/CaptureStudio/Models/CaptureAreaType.swift`
- Create: `Sources/CaptureStudio/Models/EditorDocument.swift`
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Delete: `Tests/CaptureStudioTests/SmokeTests.swift`
- Create: `Tests/CaptureStudioTests/AppStateTests.swift`

- [ ] **Step 1: Write failing state tests**

```swift
import XCTest
@testable import CaptureStudio

final class AppStateTests: XCTestCase {
    @MainActor
    func testDefaultsUseScreenshotRectangleAndNoDocument() {
        let state = AppState()

        XCTAssertEqual(state.captureMode, .screenshot)
        XCTAssertEqual(state.areaType, .rectangle)
        XCTAssertNil(state.currentDocument)
    }

    @MainActor
    func testSelectingRecordKeepsAreaType() {
        let state = AppState()

        state.captureMode = .record

        XCTAssertEqual(state.captureMode, .record)
        XCTAssertEqual(state.areaType, .rectangle)
    }

    func testEditorDocumentDirtyState() {
        let document = EditorDocument(kind: .screenshot, createdAt: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(document.isDirty)
        XCTAssertNil(document.fileURL)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppStateTests`

Expected: FAIL because `AppState`, `CaptureMode`, `CaptureAreaType`, and `EditorDocument` are not defined.

- [ ] **Step 3: Add capture mode model**

```swift
import Foundation

public enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case screenshot
    case record

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenshot:
            return "Screenshot"
        case .record:
            return "Record"
        }
    }
}
```

- [ ] **Step 4: Add capture area model**

```swift
import Foundation

public enum CaptureAreaType: String, CaseIterable, Codable, Identifiable {
    case rectangle
    case window
    case fullScreen
    case freeform

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle:
            return "Rectangle"
        case .window:
            return "Window"
        case .fullScreen:
            return "Full Screen"
        case .freeform:
            return "Freeform"
        }
    }
}
```

- [ ] **Step 5: Add editor document model**

```swift
import Foundation

public struct EditorDocument: Equatable, Identifiable {
    public enum Kind: Equatable {
        case screenshot
        case recording
    }

    public let id: UUID
    public var kind: Kind
    public var createdAt: Date
    public var fileURL: URL?
    public var isDirty: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        fileURL: URL? = nil,
        isDirty: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.isDirty = isDirty
    }
}
```

- [ ] **Step 6: Add app state**

```swift
import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var captureMode: CaptureMode
    @Published public var areaType: CaptureAreaType
    @Published public var currentDocument: EditorDocument?
    @Published public var statusMessage: String?

    public init(
        captureMode: CaptureMode = .screenshot,
        areaType: CaptureAreaType = .rectangle,
        currentDocument: EditorDocument? = nil,
        statusMessage: String? = nil
    ) {
        self.captureMode = captureMode
        self.areaType = areaType
        self.currentDocument = currentDocument
        self.statusMessage = statusMessage
    }
}
```

- [ ] **Step 7: Inject `AppState` into the app**

Replace `Sources/CaptureStudio/CaptureStudioApp.swift` with:

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 620, minHeight: 430)
        }
    }
}
```

- [ ] **Step 8: Update the main window to use state**

Replace `Sources/CaptureStudio/Views/MainWindowView.swift` with:

```swift
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    appState.statusMessage = "Capture flow is ready for implementation."
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Picker("Mode", selection: $appState.captureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                Picker("Area", selection: $appState.areaType) {
                    ForEach(CaptureAreaType.allCases) { areaType in
                        Text(areaType.title).tag(areaType)
                    }
                }
                .frame(width: 150)

                Spacer()

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
            .padding(12)

            Divider()

            VStack(spacing: 14) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Ready to capture")
                    .font(.title3.weight(.semibold))

                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }

    private var statusText: String {
        if let statusMessage = appState.statusMessage {
            return statusMessage
        }

        return "Choose a mode and press New."
    }
}
```

- [ ] **Step 9: Remove the smoke test**

Run: `rm Tests/CaptureStudioTests/SmokeTests.swift`

Expected: the temporary smoke test file is removed.

- [ ] **Step 10: Run tests**

Run: `swift test --filter AppStateTests`

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add Sources Tests
git commit -m "feat: add capture app state models"
```

## Task 3: Settings Defaults and Persistence

**Files:**
- Create: `Sources/CaptureStudio/Settings/AppSettings.swift`
- Create: `Sources/CaptureStudio/Settings/SettingsStore.swift`
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Create: `Tests/CaptureStudioTests/AppSettingsTests.swift`
- Create: `Tests/CaptureStudioTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing settings tests**

```swift
import XCTest
@testable import CaptureStudio

final class AppSettingsTests: XCTestCase {
    func testDefaultFoldersUseDesktop() {
        let settings = AppSettings.defaults

        XCTAssertTrue(settings.screenshotFolderPath.hasSuffix("/Desktop"))
        XCTAssertTrue(settings.recordingFolderPath.hasSuffix("/Desktop"))
    }

    func testDefaultSaveBehaviorMatchesSpec() {
        let settings = AppSettings.defaults

        XCTAssertTrue(settings.automaticallySaveScreenshots)
        XCTAssertTrue(settings.automaticallySaveRecordings)
        XCTAssertTrue(settings.hideAppDuringCapture)
        XCTAssertTrue(settings.copyCapturedImageToClipboard)
        XCTAssertFalse(settings.askToSaveEditedScreenshots)
    }
}
```

- [ ] **Step 2: Write failing persistence tests**

```swift
import XCTest
@testable import CaptureStudio

final class SettingsStoreTests: XCTestCase {
    func testStoreLoadsDefaultsWhenEmpty() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.empty")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.empty")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .defaults)
    }

    func testStorePersistsUpdatedSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.persist")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.persist")

        let store = SettingsStore(defaults: defaults)
        store.update { settings in
            settings.automaticallySaveScreenshots = false
            settings.screenshotFolderPath = "/tmp/captures"
        }

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertFalse(reloaded.settings.automaticallySaveScreenshots)
        XCTAssertEqual(reloaded.settings.screenshotFolderPath, "/tmp/captures")
    }

    func testResetRestoresDefaults() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.reset")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.reset")

        let store = SettingsStore(defaults: defaults)
        store.update { settings in
            settings.automaticallySaveRecordings = false
        }

        store.reset()

        XCTAssertEqual(store.settings, .defaults)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter AppSettingsTests && swift test --filter SettingsStoreTests`

Expected: FAIL because `AppSettings` and `SettingsStore` are not defined.

- [ ] **Step 4: Add `AppSettings`**

```swift
import Foundation

public struct AppSettings: Codable, Equatable {
    public var automaticallySaveScreenshots: Bool
    public var automaticallySaveRecordings: Bool
    public var screenshotFolderPath: String
    public var recordingFolderPath: String
    public var askToSaveEditedScreenshots: Bool
    public var showInFinderAfterSave: Bool

    public var hideAppDuringCapture: Bool
    public var copyCapturedImageToClipboard: Bool
    public var copyEditsToClipboard: Bool
    public var multipleEditorWindows: Bool
    public var captureBorderEnabled: Bool
    public var defaultDelaySeconds: Int

    public var includeSystemAudio: Bool
    public var includeMicrophone: Bool
    public var microphoneDeviceName: String
    public var showCursorInRecordings: Bool
    public var countdownSeconds: Int
    public var recordingQuality: RecordingQuality

    public enum RecordingQuality: String, Codable, Equatable, CaseIterable, Identifiable {
        case standard
        case high

        public var id: String { rawValue }
    }

    public static var desktopPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    public static var defaults: AppSettings {
        AppSettings(
            automaticallySaveScreenshots: true,
            automaticallySaveRecordings: true,
            screenshotFolderPath: desktopPath,
            recordingFolderPath: desktopPath,
            askToSaveEditedScreenshots: false,
            showInFinderAfterSave: false,
            hideAppDuringCapture: true,
            copyCapturedImageToClipboard: true,
            copyEditsToClipboard: true,
            multipleEditorWindows: true,
            captureBorderEnabled: false,
            defaultDelaySeconds: 0,
            includeSystemAudio: true,
            includeMicrophone: false,
            microphoneDeviceName: "System Default",
            showCursorInRecordings: true,
            countdownSeconds: 3,
            recordingQuality: .standard
        )
    }
}
```

- [ ] **Step 5: Add `SettingsStore`**

```swift
import Foundation
import SwiftUI

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.AppSettings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .defaults
        }
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        persist(next)
    }

    public func reset() {
        settings = .defaults
        persist(.defaults)
    }

    private func persist(_ settings: AppSettings) {
        let data = try? JSONEncoder().encode(settings)
        defaults.set(data, forKey: storageKey)
    }
}
```

- [ ] **Step 6: Inject `SettingsStore`**

Replace `Sources/CaptureStudio/CaptureStudioApp.swift` with:

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .frame(minWidth: 620, minHeight: 430)
        }
    }
}
```

- [ ] **Step 7: Run tests**

Run: `swift test --filter AppSettingsTests && swift test --filter SettingsStoreTests`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat: add persistent app settings"
```

## Task 4: File Output Service

**Files:**
- Create: `Sources/CaptureStudio/Services/FileOutputService.swift`
- Create: `Tests/CaptureStudioTests/FileOutputServiceTests.swift`

- [ ] **Step 1: Write failing file output tests**

```swift
import XCTest
@testable import CaptureStudio

final class FileOutputServiceTests: XCTestCase {
    func testScreenshotFilenameUsesMacStyleTimestamp() {
        let service = FileOutputService()
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        let filename = service.screenshotFilename(for: date)

        XCTAssertTrue(filename.hasPrefix("Screenshot "))
        XCTAssertTrue(filename.hasSuffix(".png"))
        XCTAssertTrue(filename.contains(" at "))
    }

    func testRecordingFilenameUsesMP4Extension() {
        let service = FileOutputService()
        let date = Date(timeIntervalSince1970: 1_782_000_000)

        let filename = service.recordingFilename(for: date)

        XCTAssertTrue(filename.hasPrefix("Recording "))
        XCTAssertTrue(filename.hasSuffix(".mp4"))
    }

    func testExistingDirectoryIsUsed() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let service = FileOutputService()

        let resolved = service.resolvedOutputDirectory(preferredPath: temporaryDirectory.path)

        XCTAssertEqual(resolved.standardizedFileURL, temporaryDirectory.standardizedFileURL)
    }

    func testMissingDirectoryFallsBackToDesktop() {
        let service = FileOutputService()
        let missingPath = "/path/that/does/not/exist"

        let resolved = service.resolvedOutputDirectory(preferredPath: missingPath)

        XCTAssertTrue(resolved.path.hasSuffix("/Desktop"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileOutputServiceTests`

Expected: FAIL because `FileOutputService` is not defined.

- [ ] **Step 3: Add `FileOutputService`**

```swift
import Foundation

public struct FileOutputService {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        self.dateFormatter = formatter
    }

    public func screenshotFilename(for date: Date = Date()) -> String {
        "Screenshot \(dateFormatter.string(from: date)).png"
    }

    public func recordingFilename(for date: Date = Date()) -> String {
        "Recording \(dateFormatter.string(from: date)).mp4"
    }

    public func resolvedOutputDirectory(preferredPath: String) -> URL {
        let preferredURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        if directoryExists(at: preferredURL) {
            return preferredURL
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    public func screenshotURL(settings: AppSettings, date: Date = Date()) -> URL {
        resolvedOutputDirectory(preferredPath: settings.screenshotFolderPath)
            .appendingPathComponent(screenshotFilename(for: date))
    }

    public func recordingURL(settings: AppSettings, date: Date = Date()) -> URL {
        resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(recordingFilename(for: date))
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter FileOutputServiceTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CaptureStudio/Services Tests/CaptureStudioTests/FileOutputServiceTests.swift
git commit -m "feat: add capture output file service"
```

## Task 5: Shortcut Model and Reset Defaults

**Files:**
- Create: `Sources/CaptureStudio/Shortcuts/ShortcutDefinition.swift`
- Create: `Sources/CaptureStudio/Shortcuts/ShortcutManager.swift`
- Create: `Tests/CaptureStudioTests/ShortcutManagerTests.swift`
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`

- [ ] **Step 1: Write failing shortcut tests**

```swift
import XCTest
@testable import CaptureStudio

final class ShortcutManagerTests: XCTestCase {
    @MainActor
    func testDefaultBindingsContainAllActions() {
        let manager = ShortcutManager(defaults: isolatedDefaults("defaults"))

        XCTAssertEqual(Set(manager.bindings.keys), Set(ShortcutAction.allCases))
    }

    @MainActor
    func testCustomBindingPersists() throws {
        let defaults = isolatedDefaults("persist")
        let manager = ShortcutManager(defaults: defaults)
        let binding = ShortcutBinding(key: "5", modifiers: [.command, .shift])

        try manager.setBinding(binding, for: .newScreenshot)

        let reloaded = ShortcutManager(defaults: defaults)
        XCTAssertEqual(reloaded.bindings[.newScreenshot], binding)
    }

    @MainActor
    func testDuplicateBindingThrows() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("duplicate"))
        let recordingBinding = ShortcutDefinition.defaultBinding(for: .newRecording)

        XCTAssertThrowsError(try manager.setBinding(recordingBinding, for: .newScreenshot)) { error in
            XCTAssertEqual(error as? ShortcutManager.ShortcutError, .duplicateBinding(existingAction: .newRecording))
        }
    }

    @MainActor
    func testResetOneShortcutRestoresDefault() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("resetOne"))

        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)
        manager.resetToDefault(.newScreenshot)

        XCTAssertEqual(manager.bindings[.newScreenshot], ShortcutDefinition.defaultBinding(for: .newScreenshot))
    }

    @MainActor
    func testResetAllShortcutsRestoresDefaults() throws {
        let manager = ShortcutManager(defaults: isolatedDefaults("resetAll"))

        try manager.setBinding(ShortcutBinding(key: "5", modifiers: [.command]), for: .newScreenshot)
        manager.resetAllToDefaults()

        XCTAssertEqual(manager.bindings, ShortcutDefinition.defaultBindings)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "ShortcutManagerTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ShortcutManagerTests`

Expected: FAIL because shortcut types are not defined.

- [ ] **Step 3: Add shortcut definitions**

```swift
import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case newScreenshot
    case newRecording
    case textExtraction
    case colorPicker
    case lastCapture
    case openSettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newScreenshot:
            return "New Screenshot"
        case .newRecording:
            return "New Recording"
        case .textExtraction:
            return "Text Extraction"
        case .colorPicker:
            return "Color Picker"
        case .lastCapture:
            return "Last Capture"
        case .openSettings:
            return "Open Settings"
        }
    }
}

public enum ShortcutModifier: String, CaseIterable, Codable, Comparable {
    case command
    case shift
    case option
    case control

    public static func < (lhs: ShortcutModifier, rhs: ShortcutModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .control:
            return 0
        case .option:
            return 1
        case .shift:
            return 2
        case .command:
            return 3
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Hashable {
    public var key: String
    public var modifiers: [ShortcutModifier]

    public init(key: String, modifiers: [ShortcutModifier]) {
        self.key = key.uppercased()
        self.modifiers = modifiers.sorted()
    }

    public var displayValue: String {
        let modifierText = modifiers.map(\.symbol).joined()
        return "\(modifierText)\(key)"
    }
}

public extension ShortcutModifier {
    var symbol: String {
        switch self {
        case .command:
            return "Command-"
        case .shift:
            return "Shift-"
        case .option:
            return "Option-"
        case .control:
            return "Control-"
        }
    }
}

public enum ShortcutDefinition {
    public static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .newScreenshot: ShortcutBinding(key: "S", modifiers: [.command, .shift]),
        .newRecording: ShortcutBinding(key: "R", modifiers: [.command, .shift]),
        .textExtraction: ShortcutBinding(key: "T", modifiers: [.command, .shift]),
        .colorPicker: ShortcutBinding(key: "C", modifiers: [.command, .shift]),
        .lastCapture: ShortcutBinding(key: "L", modifiers: [.command, .shift]),
        .openSettings: ShortcutBinding(key: ",", modifiers: [.command])
    ]

    public static func defaultBinding(for action: ShortcutAction) -> ShortcutBinding {
        defaultBindings[action]!
    }
}
```

- [ ] **Step 4: Add shortcut manager**

```swift
import Foundation
import SwiftUI

@MainActor
public final class ShortcutManager: ObservableObject {
    public enum ShortcutError: Error, Equatable {
        case duplicateBinding(existingAction: ShortcutAction)
    }

    @Published public private(set) var bindings: [ShortcutAction: ShortcutBinding]
    @Published public private(set) var registrationFailures: [ShortcutAction: String]

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.ShortcutBindings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.registrationFailures = [:]

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutAction: ShortcutBinding].self, from: data) {
            self.bindings = ShortcutDefinition.defaultBindings.merging(decoded) { _, custom in custom }
        } else {
            self.bindings = ShortcutDefinition.defaultBindings
        }
    }

    public func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        if let duplicate = bindings.first(where: { $0.key != action && $0.value == binding })?.key {
            throw ShortcutError.duplicateBinding(existingAction: duplicate)
        }

        bindings[action] = binding
        persist()
    }

    public func resetToDefault(_ action: ShortcutAction) {
        bindings[action] = ShortcutDefinition.defaultBinding(for: action)
        persist()
    }

    public func resetAllToDefaults() {
        bindings = ShortcutDefinition.defaultBindings
        registrationFailures = [:]
        persist()
    }

    public func markRegistrationFailed(for action: ShortcutAction, reason: String) {
        registrationFailures[action] = reason
    }

    private func persist() {
        let data = try? JSONEncoder().encode(bindings)
        defaults.set(data, forKey: storageKey)
    }
}
```

- [ ] **Step 5: Inject `ShortcutManager`**

Replace `Sources/CaptureStudio/CaptureStudioApp.swift` with:

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var shortcutManager = ShortcutManager()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(minWidth: 620, minHeight: 430)
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter ShortcutManagerTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CaptureStudio/Shortcuts Sources/CaptureStudio/CaptureStudioApp.swift Tests/CaptureStudioTests/ShortcutManagerTests.swift
git commit -m "feat: add customizable shortcut model"
```

## Task 6: Settings UI

**Files:**
- Create: `Sources/CaptureStudio/Views/SettingsView.swift`
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`

- [ ] **Step 1: Add the Settings scene**

Replace `Sources/CaptureStudio/CaptureStudioApp.swift` with:

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var shortcutManager = ShortcutManager()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(minWidth: 620, minHeight: 430)
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(width: 640, height: 520)
        }
    }
}
```

- [ ] **Step 2: Add Settings UI**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var shortcutManager: ShortcutManager

    var body: some View {
        TabView {
            outputSettings
                .tabItem { Label("Output", systemImage: "folder") }

            captureSettings
                .tabItem { Label("Capture", systemImage: "viewfinder") }

            recordSettings
                .tabItem { Label("Record", systemImage: "record.circle") }

            shortcutSettings
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            advancedSettings
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .padding(20)
    }

    private var outputSettings: some View {
        Form {
            Toggle("Automatically save screenshots", isOn: binding(\.automaticallySaveScreenshots))
            Toggle("Automatically save recordings", isOn: binding(\.automaticallySaveRecordings))
            Toggle("Ask to save edited screenshots", isOn: binding(\.askToSaveEditedScreenshots))
            Toggle("Show in Finder after save", isOn: binding(\.showInFinderAfterSave))

            LabeledContent("Screenshot folder", value: settingsStore.settings.screenshotFolderPath)
            LabeledContent("Recording folder", value: settingsStore.settings.recordingFolderPath)

            Button("Reset Output Defaults") {
                settingsStore.update { settings in
                    let defaults = AppSettings.defaults
                    settings.automaticallySaveScreenshots = defaults.automaticallySaveScreenshots
                    settings.automaticallySaveRecordings = defaults.automaticallySaveRecordings
                    settings.screenshotFolderPath = defaults.screenshotFolderPath
                    settings.recordingFolderPath = defaults.recordingFolderPath
                    settings.askToSaveEditedScreenshots = defaults.askToSaveEditedScreenshots
                    settings.showInFinderAfterSave = defaults.showInFinderAfterSave
                }
            }
        }
    }

    private var captureSettings: some View {
        Form {
            Toggle("Hide Capture Studio while selecting", isOn: binding(\.hideAppDuringCapture))
            Toggle("Copy captured image to clipboard", isOn: binding(\.copyCapturedImageToClipboard))
            Toggle("Copy edits to clipboard", isOn: binding(\.copyEditsToClipboard))
            Toggle("Multiple editor windows", isOn: binding(\.multipleEditorWindows))
            Toggle("Capture border", isOn: binding(\.captureBorderEnabled))
            Stepper("Default delay: \(settingsStore.settings.defaultDelaySeconds)s", value: intBinding(\.defaultDelaySeconds), in: 0...10)
        }
    }

    private var recordSettings: some View {
        Form {
            Toggle("Include system audio", isOn: binding(\.includeSystemAudio))
            Toggle("Include microphone", isOn: binding(\.includeMicrophone))
            Toggle("Show cursor in recordings", isOn: binding(\.showCursorInRecordings))
            Stepper("Countdown: \(settingsStore.settings.countdownSeconds)s", value: intBinding(\.countdownSeconds), in: 0...10)
            Picker("Quality", selection: recordingQualityBinding) {
                ForEach(AppSettings.RecordingQuality.allCases) { quality in
                    Text(quality.rawValue.capitalized).tag(quality)
                }
            }
        }
    }

    private var shortcutSettings: some View {
        Form {
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Text(displayValue(for: action))
                        .foregroundStyle(.secondary)
                    Button("Reset") {
                        shortcutManager.resetToDefault(action)
                    }
                }
            }

            Button("Reset All Defaults") {
                shortcutManager.resetAllToDefaults()
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            LabeledContent("Screen Recording", value: "Checked when capture starts")
            LabeledContent("Microphone", value: "Checked when recording starts")
            LabeledContent("OCR Languages", value: "System defaults")

            Button("Reset All Settings") {
                settingsStore.reset()
                shortcutManager.resetAllToDefaults()
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var recordingQualityBinding: Binding<AppSettings.RecordingQuality> {
        Binding(
            get: { settingsStore.settings.recordingQuality },
            set: { newValue in
                settingsStore.update { settings in
                    settings.recordingQuality = newValue
                }
            }
        )
    }

    private func displayValue(for action: ShortcutAction) -> String {
        if let binding = shortcutManager.bindings[action] {
            return binding.displayValue
        }

        return "Unassigned"
    }
}
```

- [ ] **Step 3: Update the Settings button**

In `Sources/CaptureStudio/Views/MainWindowView.swift`, replace the Settings button action with:

```swift
Button {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
} label: {
    Image(systemName: "gearshape")
}
.help("Settings")
```

- [ ] **Step 4: Build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Run the app and inspect Settings**

Run: `swift run CaptureStudio`

Expected: The app opens. Press `Command-,` or the gear button. Settings opens with Output, Capture, Record, Shortcuts, and Advanced tabs. The Shortcuts tab shows reset buttons and Reset All Defaults.

- [ ] **Step 6: Commit**

```bash
git add Sources/CaptureStudio
git commit -m "feat: add settings interface"
```

## Task 7: Minimal Main Window and Editor Toolbar

**Files:**
- Create: `Sources/CaptureStudio/Views/EditorToolbarView.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`

- [ ] **Step 1: Add editor toolbar view**

```swift
import SwiftUI

struct EditorToolbarView: View {
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton("pencil.tip", "Pen")
            toolbarButton("highlighter", "Highlighter")
            toolbarButton("eraser", "Eraser")
            Divider().frame(height: 22)
            toolbarButton("crop", "Crop")
            toolbarButton("arrow.uturn.backward", "Undo")
            toolbarButton("arrow.uturn.forward", "Redo")
            Divider().frame(height: 22)
            toolbarButton("doc.on.doc", "Copy")
            toolbarButton("square.and.arrow.up", "Share")
            toolbarButton("square.and.arrow.down", "Save")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func toolbarButton(_ systemName: String, _ help: String) -> some View {
        Button {
        } label: {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .disabled(!isEnabled)
        .help(help)
    }
}
```

- [ ] **Step 2: Replace the main window**

```swift
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            previewArea
            Divider()
            EditorToolbarView(isEnabled: appState.currentDocument != nil)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                appState.statusMessage = "Capture coordinator is ready."
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Picker("Mode", selection: $appState.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            Picker("Area", selection: $appState.areaType) {
                ForEach(CaptureAreaType.allCases) { areaType in
                    Text(areaType.title).tag(areaType)
                }
            }
            .frame(width: 150)

            Menu("No Delay") {
                Button("No Delay") { }
                Button("3 Seconds") { }
                Button("5 Seconds") { }
                Button("10 Seconds") { }
            }
            .frame(width: 110)

            Spacer()

            Button {
                appState.statusMessage = "Open recent capture is ready for implementation."
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Open recent capture")

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(12)
    }

    private var previewArea: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.28))

            VStack(spacing: 14) {
                Image(systemName: appState.currentDocument == nil ? "viewfinder" : "photo")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(appState.currentDocument == nil ? "Ready to capture" : "Capture preview")
                    .font(.title3.weight(.semibold))

                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if let statusMessage = appState.statusMessage {
            return statusMessage
        }

        return "Choose a mode and press New."
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Run the app**

Run: `swift run CaptureStudio`

Expected: The main window is compact. Output, Capture, and Record options are absent from the main window and available only in Settings.

- [ ] **Step 5: Commit**

```bash
git add Sources/CaptureStudio/Views
git commit -m "feat: refine minimal capture main window"
```

## Task 8: Capture Coordinator Interfaces

**Files:**
- Create: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Create: `Sources/CaptureStudio/Capture/ScreenshotService.swift`
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Create: `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

```swift
import XCTest
@testable import CaptureStudio

final class CaptureCoordinatorTests: XCTestCase {
    @MainActor
    func testNewScreenshotCreatesScreenshotDocumentWithMockService() async {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("screenshot"))
        let service = MockScreenshotService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: service
        )

        await coordinator.startNewCapture()

        XCTAssertEqual(appState.currentDocument?.kind, .screenshot)
        XCTAssertEqual(appState.statusMessage, "Screenshot captured.")
        XCTAssertEqual(service.captureCallCount, 1)
    }

    @MainActor
    func testRecordModeReportsRecordingNotReady() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = SettingsStore(defaults: isolatedDefaults("record"))
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService()
        )

        await coordinator.startNewCapture()

        XCTAssertNil(appState.currentDocument)
        XCTAssertEqual(appState.statusMessage, "Recording will be added in the recording milestone.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MockScreenshotService: ScreenshotServicing {
    var captureCallCount = 0

    func captureSimulatedResult() async throws -> ScreenshotResult {
        captureCallCount += 1
        return ScreenshotResult(createdAt: Date(timeIntervalSince1970: 20))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureCoordinatorTests`

Expected: FAIL because `CaptureCoordinator`, `ScreenshotServicing`, and `ScreenshotResult` are not defined.

- [ ] **Step 3: Add screenshot service protocol**

```swift
import Foundation

public struct ScreenshotResult: Equatable {
    public let createdAt: Date

    public init(createdAt: Date = Date()) {
        self.createdAt = createdAt
    }
}

public protocol ScreenshotServicing {
    func captureSimulatedResult() async throws -> ScreenshotResult
}

public struct ScreenCaptureKitScreenshotService: ScreenshotServicing {
    public init() {}

    public func captureSimulatedResult() async throws -> ScreenshotResult {
        ScreenshotResult()
    }
}
```

- [ ] **Step 4: Add capture coordinator**

```swift
import Foundation

@MainActor
public final class CaptureCoordinator: ObservableObject {
    private let appState: AppState
    private let settingsStore: SettingsStore
    private let screenshotService: ScreenshotServicing

    public init(
        appState: AppState,
        settingsStore: SettingsStore,
        screenshotService: ScreenshotServicing = ScreenCaptureKitScreenshotService()
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        self.screenshotService = screenshotService
    }

    public func startNewCapture() async {
        switch appState.captureMode {
        case .screenshot:
            await startScreenshotCapture()
        case .record:
            appState.currentDocument = nil
            appState.statusMessage = "Recording will be added in the recording milestone."
        }
    }

    private func startScreenshotCapture() async {
        do {
            _ = settingsStore.settings
            let result = try await screenshotService.captureSimulatedResult()
            appState.currentDocument = EditorDocument(kind: .screenshot, createdAt: result.createdAt)
            appState.statusMessage = "Screenshot captured."
        } catch {
            appState.currentDocument = nil
            appState.statusMessage = "Screenshot failed: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 5: Inject the coordinator**

Replace `Sources/CaptureStudio/CaptureStudioApp.swift` with:

```swift
import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var shortcutManager = ShortcutManager()

    var body: some Scene {
        WindowGroup {
            MainWindowContainer()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(minWidth: 620, minHeight: 430)
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(width: 640, height: 520)
        }
    }
}

private struct MainWindowContainer: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        MainWindowView(
            captureCoordinator: CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            )
        )
    }
}
```

- [ ] **Step 6: Update main window to call coordinator**

Change the first lines of `MainWindowView` to:

```swift
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var captureCoordinator: CaptureCoordinator
```

Replace the `New` button action with:

```swift
Button {
    Task {
        await captureCoordinator.startNewCapture()
    }
} label: {
    Label("New", systemImage: "plus")
}
.buttonStyle(.borderedProminent)
```

- [ ] **Step 7: Run tests**

Run: `swift test --filter CaptureCoordinatorTests`

Expected: PASS.

- [ ] **Step 8: Build and run**

Run: `swift build && swift run CaptureStudio`

Expected: PASS build. In the app, pressing New in Screenshot mode changes the preview state to "Capture preview" and status to "Screenshot captured." Pressing New in Record mode shows "Recording will be added in the recording milestone."

- [ ] **Step 9: Commit**

```bash
git add Sources/CaptureStudio/Capture Sources/CaptureStudio/CaptureStudioApp.swift Sources/CaptureStudio/Views/MainWindowView.swift Tests/CaptureStudioTests/CaptureCoordinatorTests.swift
git commit -m "feat: add capture coordinator skeleton"
```

## Task 9: Verification and Documentation Update

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README**

```markdown
# Capture Studio

Native macOS screenshot and screen recording app inspired by Windows Snipping Tool.

## Requirements

- macOS 15 or newer
- Xcode command line tools
- Swift 6

## Run

```bash
swift run CaptureStudio
```

## Test

```bash
swift test
```

## Current Milestone

This milestone includes:

- Minimal main window
- Settings window
- Persistent settings
- Customizable shortcut model with reset defaults
- Output filename and folder fallback model
- Capture coordinator interfaces

Real screen region selection, screenshot capture, recording, editing, OCR, and color picker are separate implementation milestones.
```

- [ ] **Step 2: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Inspect git status**

Run: `git status --short`

Expected: only `README.md` is modified before commit.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add capture studio run instructions"
```

## Self-Review Checklist

- Spec coverage: This plan covers the approved first milestone: native app scaffold, minimal main UI, Settings separation, persistent settings, shortcut customization with reset defaults, output path model, and capture coordinator interfaces.
- Intentional gaps: Real overlay selection, ScreenCaptureKit screenshot capture, MP4 recording, editor drawing tools, OCR, quick redact, color picker, and trim are excluded from this plan and require follow-up plans.
- Red-flag scan: The plan contains no incomplete-work markers or vague implementation instructions.
- Type consistency: `AppState`, `SettingsStore`, `ShortcutManager`, `FileOutputService`, `CaptureCoordinator`, `ScreenshotServicing`, and `EditorDocument` names are used consistently across tasks.
