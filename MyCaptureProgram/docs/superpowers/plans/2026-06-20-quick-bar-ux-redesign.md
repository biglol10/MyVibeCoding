# Quick Bar UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `New + Mode` workflow with a direct `Capture` / `Record` quick bar while preserving settings, editing, OCR, redaction, shortcut customization, save/copy behavior, and E2E fixes already present in the working tree.

**Architecture:** Keep capture and recording behavior in `CaptureCoordinator`, but expose direct screenshot and recording entry points. Move main-window display decisions into small SwiftUI view helpers and pure presentation helpers so the first screen becomes a compact command surface and post-capture controls appear only when a document exists.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, XCTest.

---

## Current Working Tree Baseline

There are already verified but uncommitted fixes in the working tree:

- `Sources/CaptureStudio/Capture/SelectionService.swift`: click guard so opening the overlay does not create a tiny selection.
- `Sources/CaptureStudio/CaptureStudioApp.swift`: `SettingsLink` for the Capture menu Settings item.
- `Sources/CaptureStudio/Views/MainWindowView.swift`: `SettingsLink` for the main settings button.
- `Sources/CaptureStudio/Shortcuts/ShortcutDefinition.swift`: `customizableActions`.
- `Sources/CaptureStudio/Views/SettingsView.swift`: Shortcuts tab exposes every customizable action.
- `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`: test output folders use temp directories.
- `Tests/CaptureStudioTests/ShortcutManagerTests.swift`: shortcut coverage test.

Do not revert these changes. Treat them as the starting point for this plan.

## File Structure

- Modify `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
  - Expose direct `startScreenshotCapture()` and `startScreenRecording()` methods.
  - Keep `startNewCapture()` as compatibility routing through `appState.captureMode`.
  - Add `revealCurrentDocument()` for contextual recent-result actions.

- Create `Sources/CaptureStudio/Views/MainWindowPresentation.swift`
  - Pure presentation helpers for quick-bar output summary and recent-result labels.
  - Keeps string and state logic testable without SwiftUI view introspection.

- Modify `Sources/CaptureStudio/Views/MainWindowView.swift`
  - Replace `New + Mode` with `Capture`, `Record`, quick options, and settings.
  - Hide editor toolbar until a document exists.
  - Show a compact recent-result row when a document/status exists.
  - Keep screenshot editor and OCR panel behavior after capture.

- Modify `Sources/CaptureStudio/Views/EditorToolbarView.swift`
  - Keep screenshot tools for screenshots.
  - Show only recording-safe actions for recordings.
  - Remove disabled toolbar from the no-document first screen.

- Modify `Sources/CaptureStudio/CaptureStudioApp.swift`
  - Route Capture menu actions through direct screenshot/recording coordinator methods.

- Create `Tests/CaptureStudioTests/MainWindowPresentationTests.swift`
  - Verify quick-bar summaries and recent-result labels.

- Modify `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`
  - Add direct-action tests for screenshot and recording methods.
  - Add reveal-current-document test.

- Existing tests that must keep passing:
  - `Tests/CaptureStudioTests/ShortcutManagerTests.swift`
  - `Tests/CaptureStudioTests/CaptureWorkflowIntegrationTests.swift`
  - `Tests/CaptureStudioTests/ScreenCaptureKitIntegrationTests.swift`
  - editor, OCR, redaction, render, file output tests.

---

### Task 1: Direct Capture And Record Coordinator Actions

**Files:**
- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Modify: `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing tests for direct screenshot and direct recording**

Add these tests to `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift` before the existing `isolatedDefaults` helper:

```swift
    @MainActor
    func testStartScreenshotCaptureDoesNotDependOnSelectedMode() async {
        let appState = AppState(captureMode: .record)
        let settingsStore = makeSettingsStore("directScreenshot")
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = false
            settings.copyCapturedImageToClipboard = false
        }
        let screenshotService = MockScreenshotService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: screenshotService,
            fileOutputService: FileOutputService(),
            selectionService: selectionService
        )

        await coordinator.startScreenshotCapture()

        XCTAssertEqual(appState.captureMode, .record)
        XCTAssertEqual(appState.currentDocument?.kind, .screenshot)
        XCTAssertEqual(selectionService.selectionCallCount, 1)
        XCTAssertEqual(screenshotService.captureCallCount, 1)
        XCTAssertEqual(appState.statusMessage, "Screenshot captured. Press Save to write the file.")
    }

    @MainActor
    func testStartScreenRecordingDoesNotDependOnSelectedMode() async {
        let appState = AppState(captureMode: .screenshot)
        let settingsStore = makeSettingsStore("directRecording")
        settingsStore.update { settings in
            settings.automaticallySaveRecordings = true
            settings.countdownSeconds = 0
        }
        let recordingService = MockRecordingService()
        let selectionService = MockSelectionService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            recordingService: recordingService,
            selectionService: selectionService,
            delaySleeper: MockDelaySleeper()
        )

        await coordinator.startScreenRecording()

        XCTAssertEqual(appState.captureMode, .screenshot)
        XCTAssertEqual(appState.currentDocument?.kind, .recording)
        XCTAssertEqual(selectionService.selectionCallCount, 1)
        XCTAssertEqual(recordingService.recordCallCount, 1)
        XCTAssertEqual(appState.statusMessage, "Recording saved.")
    }
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter CaptureCoordinatorTests/testStartScreenshotCaptureDoesNotDependOnSelectedMode
swift test --filter CaptureCoordinatorTests/testStartScreenRecordingDoesNotDependOnSelectedMode
```

Expected:

- Both fail to compile because `startScreenshotCapture()` and `startScreenRecording()` are private.

- [ ] **Step 3: Expose direct coordinator methods**

In `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`, change:

```swift
    private func startScreenshotCapture() async {
```

to:

```swift
    public func startScreenshotCapture() async {
```

Change:

```swift
    private func startScreenRecording() async {
```

to:

```swift
    public func startScreenRecording() async {
```

Leave `startNewCapture()` unchanged:

```swift
    public func startNewCapture() async {
        switch appState.captureMode {
        case .screenshot:
            await startScreenshotCapture()
        case .record:
            await startScreenRecording()
        }
    }
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
swift test --filter CaptureCoordinatorTests/testStartScreenshotCaptureDoesNotDependOnSelectedMode
swift test --filter CaptureCoordinatorTests/testStartScreenRecordingDoesNotDependOnSelectedMode
```

Expected:

- Both selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CaptureStudio/Capture/CaptureCoordinator.swift Tests/CaptureStudioTests/CaptureCoordinatorTests.swift
git commit -m "feat: expose direct capture actions"
```

---

### Task 2: Recent Result Presentation Model

**Files:**
- Create: `Sources/CaptureStudio/Views/MainWindowPresentation.swift`
- Create: `Tests/CaptureStudioTests/MainWindowPresentationTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Create `Tests/CaptureStudioTests/MainWindowPresentationTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

final class MainWindowPresentationTests: XCTestCase {
    func testOutputSummaryUsesScreenshotFolderDelayAndClipboard() {
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = "/Users/biglol/Desktop"
        settings.defaultDelaySeconds = 3
        settings.copyCapturedImageToClipboard = true

        let summary = MainWindowPresentation.outputSummary(settings: settings)

        XCTAssertEqual(summary, "Desktop · PNG · 3s · Clipboard")
    }

    func testOutputSummaryUsesFolderNameAndNoClipboardWhenDisabled() {
        var settings = AppSettings.defaults
        settings.screenshotFolderPath = "/tmp/Capture Output"
        settings.defaultDelaySeconds = 0
        settings.copyCapturedImageToClipboard = false

        let summary = MainWindowPresentation.outputSummary(settings: settings)

        XCTAssertEqual(summary, "Capture Output · PNG · 0s")
    }

    func testRecentResultForSavedScreenshot() {
        let document = EditorDocument(
            kind: .screenshot,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/Screenshot.png"),
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            isDirty: false
        )

        let result = MainWindowPresentation.recentResult(for: document, statusMessage: "Screenshot captured.")

        XCTAssertEqual(result.title, "Screenshot saved")
        XCTAssertEqual(result.detail, "Screenshot captured.")
        XCTAssertEqual(result.systemImage, "photo")
        XCTAssertTrue(result.canReveal)
        XCTAssertTrue(result.canCopy)
        XCTAssertFalse(result.requiresSave)
    }

    func testRecentResultForUnsavedRecording() {
        let document = EditorDocument(
            kind: .recording,
            createdAt: Date(timeIntervalSince1970: 10),
            fileURL: URL(fileURLWithPath: "/tmp/Recording.mp4"),
            isDirty: true
        )

        let result = MainWindowPresentation.recentResult(for: document, statusMessage: nil)

        XCTAssertEqual(result.title, "Unsaved recording")
        XCTAssertEqual(result.detail, "Press Save to write the file.")
        XCTAssertEqual(result.systemImage, "record.circle")
        XCTAssertFalse(result.canCopy)
        XCTAssertTrue(result.requiresSave)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter MainWindowPresentationTests
```

Expected:

- Fails to compile because `MainWindowPresentation` does not exist.

- [ ] **Step 3: Create presentation helper**

Create `Sources/CaptureStudio/Views/MainWindowPresentation.swift`:

```swift
import Foundation

public enum MainWindowPresentation {
    public struct RecentResult: Equatable {
        public let title: String
        public let detail: String
        public let systemImage: String
        public let canCopy: Bool
        public let canReveal: Bool
        public let requiresSave: Bool
    }

    public static func outputSummary(settings: AppSettings) -> String {
        var parts = [
            folderName(from: settings.screenshotFolderPath),
            "PNG",
            "\(settings.defaultDelaySeconds)s"
        ]
        if settings.copyCapturedImageToClipboard {
            parts.append("Clipboard")
        }
        return parts.joined(separator: " · ")
    }

    public static func recordingSummary(settings: AppSettings) -> String {
        [
            folderName(from: settings.recordingFolderPath),
            "MP4",
            "\(settings.countdownSeconds)s",
            settings.recordingQuality.rawValue.capitalized
        ].joined(separator: " · ")
    }

    public static func recentResult(for document: EditorDocument, statusMessage: String?) -> RecentResult {
        switch document.kind {
        case .screenshot:
            return RecentResult(
                title: document.isDirty ? "Unsaved screenshot" : "Screenshot saved",
                detail: statusMessage ?? (document.isDirty ? "Press Save to write the file." : fileLocationText(for: document)),
                systemImage: "photo",
                canCopy: true,
                canReveal: document.fileURL != nil,
                requiresSave: document.isDirty
            )
        case .recording:
            return RecentResult(
                title: document.isDirty ? "Unsaved recording" : "Recording saved",
                detail: statusMessage ?? (document.isDirty ? "Press Save to write the file." : fileLocationText(for: document)),
                systemImage: "record.circle",
                canCopy: false,
                canReveal: document.fileURL != nil,
                requiresSave: document.isDirty
            )
        }
    }

    private static func folderName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func fileLocationText(for document: EditorDocument) -> String {
        guard let fileURL = document.fileURL else {
            return "No file yet."
        }
        return "Saved to \(folderName(from: fileURL.deletingLastPathComponent().path))"
    }
}
```

- [ ] **Step 4: Run presentation tests**

Run:

```bash
swift test --filter MainWindowPresentationTests
```

Expected:

- All `MainWindowPresentationTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CaptureStudio/Views/MainWindowPresentation.swift Tests/CaptureStudioTests/MainWindowPresentationTests.swift
git commit -m "feat: add quick bar presentation model"
```

---

### Task 3: Quick Bar Main Window

**Files:**
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Modify: `Sources/CaptureStudio/Views/EditorToolbarView.swift`

- [ ] **Step 1: Update `MainWindowView` to use direct actions and settings**

Replace `Sources/CaptureStudio/Views/MainWindowView.swift` with:

```swift
import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject private var appState: AppState
    @ObservedObject var captureCoordinator: CaptureCoordinator
    @StateObject private var editorViewModel: EditorViewModel

    init(captureCoordinator: CaptureCoordinator, appState: AppState) {
        self.captureCoordinator = captureCoordinator
        self.appState = appState
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            quickBar

            if let document = appState.currentDocument {
                Divider()
                recentResultRow(for: document)
            }

            if appState.currentDocument != nil {
                Divider()
                previewArea
            }

            if appState.currentDocument?.kind == .screenshot {
                Divider()
                ToolInspectorView(editorViewModel: editorViewModel)
            }

            if appState.currentDocument != nil {
                Divider()
                EditorToolbarView(
                    documentKind: appState.currentDocument?.kind,
                    activeTool: editorViewModel.activeTool,
                    onToolSelected: { editorViewModel.activeTool = $0 },
                    onUndo: editorViewModel.undo,
                    onRedo: editorViewModel.redo,
                    onCopy: captureCoordinator.copyCurrentDocument,
                    onSave: captureCoordinator.saveCurrentDocument,
                    onOCR: { Task { await captureCoordinator.runOCR() } },
                    onQuickRedact: { Task { await captureCoordinator.quickRedact() } }
                )
            }
        }
        .frame(minWidth: 560, minHeight: appState.currentDocument == nil ? 128 : 430)
    }

    private var quickBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await captureCoordinator.startScreenshotCapture() }
            } label: {
                Label("Capture", systemImage: "viewfinder")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .help("Capture area")

            Button {
                Task { await captureCoordinator.startScreenRecording() }
            } label: {
                Label("Record", systemImage: "record.circle")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .help("Record area")

            quickOptionsMenu

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Settings")

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(MainWindowPresentation.outputSummary(settings: settingsStore.settings))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(MainWindowPresentation.recordingSummary(settings: settingsStore.settings))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(12)
    }

    private var quickOptionsMenu: some View {
        Menu {
            Section("Screenshot Delay") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        settingsStore.update { settings in
                            settings.defaultDelaySeconds = seconds
                        }
                    }
                }
            }

            Section("Recording Countdown") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        settingsStore.update { settings in
                            settings.countdownSeconds = seconds
                        }
                    }
                }
            }

            Toggle("Copy screenshots to clipboard", isOn: Binding(
                get: { settingsStore.settings.copyCapturedImageToClipboard },
                set: { value in
                    settingsStore.update { settings in
                        settings.copyCapturedImageToClipboard = value
                    }
                }
            ))

            Divider()

            SettingsLink {
                Text("Change Output Folders...")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("Quick options")
    }

    private func recentResultRow(for document: EditorDocument) -> some View {
        let result = MainWindowPresentation.recentResult(for: document, statusMessage: appState.statusMessage)
        return HStack(spacing: 12) {
            Image(systemName: result.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(document.kind == .recording ? .red : .blue)
                .frame(width: 42, height: 42)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if result.canCopy {
                Button {
                    captureCoordinator.copyCurrentDocument()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
            }

            if result.requiresSave {
                Button {
                    captureCoordinator.saveCurrentDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .help("Save")
            } else {
                Button {
                    captureCoordinator.saveCurrentDocument()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save copy")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var previewArea: some View {
        HStack(spacing: 0) {
            if let document = appState.currentDocument, document.kind == .screenshot {
                EditorCanvasView(document: document, editorViewModel: editorViewModel)
            } else {
                recordingPreview
            }

            if let result = appState.currentDocument?.ocrResult {
                Divider()
                OCRResultPanelView(result: result, onCopyText: captureCoordinator.copyOCRText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingPreview: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.24))

            VStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.red)

                Text("Recording captured")
                    .font(.title3.weight(.semibold))

                Text(appState.statusMessage ?? "Recording is ready.")
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Update editor toolbar to assume it is only shown with a document**

In `Sources/CaptureStudio/Views/EditorToolbarView.swift`, replace the `.opacity(documentKind == nil ? 0.45 : 1)` line with no opacity modifier. The final modifier block should be:

```swift
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
```

Keep button disabling in place as a defensive fallback:

```swift
        .disabled(documentKind == nil)
```

- [ ] **Step 3: Build**

Run:

```bash
swift build
```

Expected:

- Build succeeds.

- [ ] **Step 4: Run presentation and coordinator tests**

Run:

```bash
swift test --filter MainWindowPresentationTests
swift test --filter CaptureCoordinatorTests
```

Expected:

- Both test groups pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CaptureStudio/Views/MainWindowView.swift Sources/CaptureStudio/Views/EditorToolbarView.swift
git commit -m "feat: redesign main window as quick bar"
```

---

### Task 4: Route App Menu Commands Through Direct Actions

**Files:**
- Modify: `Sources/CaptureStudio/CaptureStudioApp.swift`
- Modify: `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Confirm compatibility tests still cover `startNewCapture()`**

Run:

```bash
swift test --filter CaptureCoordinatorTests/testNewScreenshotAutoSavesWhenEnabled
swift test --filter CaptureCoordinatorTests/testRecordModeReportsRecordingNotReady
```

Expected:

- Both pass before changes.

- [ ] **Step 2: Update menu command routing**

In `Sources/CaptureStudio/CaptureStudioApp.swift`, replace:

```swift
                Button("New Screenshot") {
                    startCapture(mode: .screenshot)
                }
```

with:

```swift
                Button("Capture") {
                    startScreenshotCapture()
                }
```

Replace:

```swift
                Button("New Recording") {
                    startCapture(mode: .record)
                }
```

with:

```swift
                Button("Record") {
                    startScreenRecording()
                }
```

Replace the private `startCapture(mode:)` helper:

```swift
    private func startCapture(mode: CaptureMode) {
        Task { @MainActor in
            appState.captureMode = mode
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startNewCapture()
        }
    }
```

with:

```swift
    private func startScreenshotCapture() {
        Task { @MainActor in
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startScreenshotCapture()
        }
    }

    private func startScreenRecording() {
        Task { @MainActor in
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startScreenRecording()
        }
    }
```

Do not remove `CaptureMode`; tests and compatibility behavior still use it.

- [ ] **Step 3: Build and run focused tests**

Run:

```bash
swift build
swift test --filter CaptureCoordinatorTests/testStartScreenshotCaptureDoesNotDependOnSelectedMode
swift test --filter CaptureCoordinatorTests/testStartScreenRecordingDoesNotDependOnSelectedMode
```

Expected:

- Build succeeds.
- Focused direct-action tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/CaptureStudio/CaptureStudioApp.swift
git commit -m "feat: route menu commands to direct capture actions"
```

---

### Task 5: Add Reveal Action For Recent Result

**Files:**
- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Modify: `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing reveal-current-document test**

Add this test to `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift` before the helper methods:

```swift
    @MainActor
    func testRevealCurrentDocumentUsesCurrentFileURL() {
        let fileURL = URL(fileURLWithPath: "/tmp/CaptureStudioTests/reveal.png")
        let appState = AppState(
            currentDocument: EditorDocument(
                kind: .screenshot,
                createdAt: Date(timeIntervalSince1970: 10),
                fileURL: fileURL,
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                isDirty: false
            )
        )
        let settingsStore = makeSettingsStore("revealCurrent")
        let fileRevealService = MockFileRevealService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            selectionService: MockSelectionService(),
            fileRevealService: fileRevealService
        )

        coordinator.revealCurrentDocument()

        XCTAssertEqual(fileRevealService.revealedURLs, [fileURL])
        XCTAssertEqual(appState.statusMessage, "Revealed in Finder.")
    }
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
swift test --filter CaptureCoordinatorTests/testRevealCurrentDocumentUsesCurrentFileURL
```

Expected:

- Fails to compile because `revealCurrentDocument()` does not exist.

- [ ] **Step 3: Implement coordinator reveal method**

Add this public method to `Sources/CaptureStudio/Capture/CaptureCoordinator.swift` after `copyCurrentDocument()`:

```swift
    public func revealCurrentDocument() {
        guard let fileURL = appState.currentDocument?.fileURL else {
            appState.statusMessage = "No saved file to reveal."
            return
        }

        fileRevealService.reveal(fileURL)
        appState.statusMessage = "Revealed in Finder."
    }
```

- [ ] **Step 4: Wire reveal button into recent result row**

In `Sources/CaptureStudio/Views/MainWindowView.swift`, inside `recentResultRow(for:)`, after the Copy button block and before the Save button block, add:

```swift
            if result.canReveal {
                Button {
                    captureCoordinator.revealCurrentDocument()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Reveal in Finder")
            }
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter CaptureCoordinatorTests/testRevealCurrentDocumentUsesCurrentFileURL
swift test --filter MainWindowPresentationTests
```

Expected:

- Both pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/CaptureStudio/Capture/CaptureCoordinator.swift Sources/CaptureStudio/Views/MainWindowView.swift Tests/CaptureStudioTests/CaptureCoordinatorTests.swift
git commit -m "feat: add recent result reveal action"
```

---

### Task 6: Final Verification And Manual E2E

**Files:**
- No source files unless verification exposes a bug.

- [ ] **Step 1: Run full unit suite**

Run:

```bash
swift test
```

Expected:

- All non-integration tests pass.
- Integration tests are skipped unless `CAPTURE_STUDIO_RUN_INTEGRATION=1` is set.

- [ ] **Step 2: Run ScreenCaptureKit integration suite**

Run:

```bash
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
```

Expected:

- All tests pass.
- Real screenshot and MP4 integration tests pass.
- No Desktop pollution from unit tests after the temp-folder fix.

- [ ] **Step 3: Build app**

Run:

```bash
swift build
```

Expected:

- Build succeeds.

- [ ] **Step 4: Create temporary `.app` bundle for UI E2E**

Run:

```bash
rm -rf /tmp/CaptureStudioE2E.app
mkdir -p /tmp/CaptureStudioE2E.app/Contents/MacOS
cp /Users/biglol/Desktop/practice/MyCaptureProgram/.build/arm64-apple-macosx/debug/CaptureStudio /tmp/CaptureStudioE2E.app/Contents/MacOS/CaptureStudio
/usr/libexec/PlistBuddy \
  -c 'Add :CFBundleExecutable string CaptureStudio' \
  -c 'Add :CFBundleIdentifier string local.capturestudio.e2e' \
  -c 'Add :CFBundleName string CaptureStudioE2E' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :LSMinimumSystemVersion string 15.0' \
  /tmp/CaptureStudioE2E.app/Contents/Info.plist
open -n /tmp/CaptureStudioE2E.app
```

Expected:

- App opens as `CaptureStudioE2E`.
- Main window first screen shows `Capture` and `Record` primary actions.
- There is no `New` button and no persistent Screenshot/Record mode picker.
- Settings opens from quick bar.
- Quick options menu opens.
- Editor toolbar is not visible before a document exists.

- [ ] **Step 5: Manual UI checks**

Use Computer Use or direct visual inspection:

- Click `Capture`.
- Verify area selection starts and does not immediately fail as "selected region is too small".
- If macOS Screen Recording permission for `local.capturestudio.e2e` is missing, record that UI selection starts but actual capture is blocked by TCC.
- Click `Record`.
- Verify area selection/countdown path starts. If TCC blocks recording, record that accurately.
- Open Settings and confirm Output, Capture, Record, Shortcuts, Advanced are still present.
- Open Shortcuts and confirm all six actions are visible:
  - New Screenshot
  - New Recording
  - Text Extraction
  - Color Picker
  - Last Capture
  - Open Settings

- [ ] **Step 6: Clean up temporary app**

Run:

```bash
osascript -e 'tell application id "local.capturestudio.e2e" to quit' || true
rm -rf /tmp/CaptureStudioE2E.app
```

Expected:

- No `CaptureStudioE2E` process remains.
- `/tmp/CaptureStudioE2E.app` is removed.

- [ ] **Step 7: Check git state**

Run:

```bash
git status --short --branch
```

Expected:

- Only intended files are modified or the branch is clean after commits.

- [ ] **Step 8: Final commit if verification required small fixes**

If verification required a small bug fix, commit it:

```bash
git add <changed-files>
git commit -m "fix: polish quick bar ux"
```

If no changes were needed after Task 5, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Direct `Capture` / `Record` first-screen actions: Task 1, Task 3, Task 4.
- Removal of `New + Mode`: Task 3.
- Quick options: Task 3.
- Settings remains accessible: Task 3, Task 6.
- Screenshot editor appears only after screenshot exists: Task 3.
- Recording-safe actions only for recordings: Task 3.
- Shortcut visibility for every default shortcut: already in baseline and verified in Task 6.
- Overlay click guard: already in baseline and verified in Task 6.
- Save/copy/OCR/redaction behavior preserved: Task 6.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified implementation steps.

Type consistency:

- `CaptureCoordinator.startScreenshotCapture()`, `startScreenRecording()`, and `revealCurrentDocument()` are defined before UI usage.
- `MainWindowPresentation` tests and implementation use matching names.
- `EditorDocument.Kind` handling stays screenshot/recording only.
