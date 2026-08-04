# Capture Studio P0/P1 Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the confirmed data-loss, privacy, concurrency, coordinate, and output-collision defects found in the 2026-08-04 audit without changing unrelated application behavior.

**Architecture:** Keep `CaptureCoordinator` as the main-actor workflow owner, but add explicit operation and document-replacement gates so asynchronous work cannot overwrite newer state. Normalize editor and display coordinates at service boundaries. Make recording teardown idempotent and reserve output paths atomically before producers begin writing.

**Tech Stack:** Swift 6, SwiftUI/AppKit, ScreenCaptureKit, AVFoundation, Vision, XCTest, macOS 15.

## Global Constraints

- Preserve all pre-existing user changes and stage only this plan's delta.
- Do not touch real Desktop, Documents, TCC, clipboard, or user Preferences during automated verification.
- Use unique `/tmp` roots for tests, SwiftPM scratch paths, module caches, and test homes.
- Keep macOS 15 as the deployment floor and add no external dependency.
- Write a failing regression test before each production change.
- Do not commit or push until the approved scope has passed focused tests, the default suite, and Debug/Release builds. Any opt-in integration blocked by TCC identity must remain explicitly documented with equivalent native-app evidence where available.

---

### Task 1: Protect Existing Documents And Serialize Capture Workflows

**Files:**
- Modify: `Sources/CaptureStudio/App/AppState.swift`
- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Create: `Tests/CaptureStudioTests/CaptureCoordinatorDocumentSafetyTests.swift`

**Interfaces:**
- Add an operation state that covers delay, selection, capture, recorder setup, and active recording.
- Add a replacement decision (`save`, `discard`, `cancel`) supplied by a small injectable authorizer.
- `startScreenshotCapture()` and `startScreenRecording()` must return without changing the current document when authorization is cancelled or another operation is active.

- [x] Add tests proving screenshot/recording cancellation and failures preserve an existing dirty document.
- [x] Add tests proving concurrent capture/record entry invokes selection once.
- [x] Add tests for Save/Discard/Cancel replacement decisions, including save failure preserving the document.
- [x] Run the focused tests and confirm they fail for document clearing and duplicate entry.
- [x] Implement the operation gate and document replacement authorization.
- [x] Disable all relevant buttons and commands while the gate is active, while preserving Stop during active recording.
- [x] Re-run the focused tests until green.

### Task 2: Make Editor Rendering And Save State WYSIWYG

**Files:**
- Modify: `Sources/CaptureStudio/Editing/ImageRenderService.swift`
- Modify: `Sources/CaptureStudio/Models/EditorDocument.swift`
- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Modify: `Tests/CaptureStudioTests/ImageRenderServiceTests.swift`
- Modify: `Tests/CaptureStudioTests/CaptureCoordinatorEditingTests.swift`

**Interfaces:**
- Editor layer coordinates remain top-left based.
- `AppKitImageRenderService` performs one explicit top-left-to-AppKit transform before rendering every layer.
- Saving updates file metadata and the saved snapshot but never replaces the immutable editor base image with flattened output while retaining layers.
- Async completions may update only a document with the same identity and expected revision.

- [x] Add asymmetric pixel tests for pen, arrowhead, rectangle, ellipse, text, solid redaction, and blur placement.
- [x] Add save-then-undo/delete tests proving preview returns to the original base image.
- [x] Add delayed save/OCR/redaction tests proving concurrent edits or replacement documents are not overwritten.
- [x] Run focused tests and confirm the vertical placement and saved-base tests fail.
- [x] Apply the renderer coordinate transform and complete arrow rendering.
- [x] Preserve `baseImageData`/layers across save and add identity/revision guarded writeback.
- [x] Abort a delayed screenshot save before file/history creation when its document was deleted or changed.
- [x] Re-run all editor, OCR, and redaction tests.

### Task 3: Harden Recording Lifecycle And Persisted Durations

**Files:**
- Modify: `Sources/CaptureStudio/Capture/RecordingService.swift`
- Modify: `Sources/CaptureStudio/Settings/AppSettings.swift`
- Modify: `Tests/CaptureStudioTests/AppSettingsTests.swift`
- Create: `Tests/CaptureStudioTests/RecordingServiceLifecycleTests.swift`

**Interfaces:**
- Only one recording session may be active or starting.
- Stop requests made during setup are remembered and complete the eventual continuation exactly once.
- Every failure path cancels duration work, stops `SCStream`, cancels microphone capture, closes writer inputs, and removes only files owned by that session.
- Decoded delay/countdown/duration values are clamped to the same supported ranges as the UI before use.

- [x] Add corrupted-settings decoding tests for negative and extreme integers.
- [x] Add injectable lifecycle tests for immediate stop, duplicate start, writer-start failure, and idempotent teardown.
- [x] Confirm the new tests fail against the current lifecycle.
- [x] Add session state and one idempotent teardown path.
- [x] Clamp decoded numeric settings and use overflow-safe duration calculations.
- [x] Re-run lifecycle, coordinator, and live recording workflows.

### Task 4: Normalize Window And Multi-Display Coordinates

**Files:**
- Modify: `Sources/CaptureStudio/Capture/CaptureSelection.swift`
- Modify: `Sources/CaptureStudio/Capture/SelectionService.swift`
- Modify: `Sources/CaptureStudio/Services/CaptureMetadataService.swift`
- Modify: `Tests/CaptureStudioTests/CaptureSelectionTests.swift`
- Modify: `Tests/CaptureStudioTests/SelectionOverlayCursorTests.swift`

**Interfaces:**
- Quartz window bounds are converted to AppKit global coordinates once before hit testing.
- `CaptureSelection` receives an explicit display-local source rectangle and does not perform a second implicit Y flip.
- Fixtures cover displays above, below, and left of the primary display and mixed origins.

- [x] Add asymmetric multi-display/window fixtures that fail under raw coordinate comparison.
- [x] Add round-trip source-rectangle tests for negative and vertically offset displays.
- [x] Implement explicit conversion helpers shared by selection and metadata lookup.
- [x] Re-run selection and capture-selection tests; document the single-display live-QA boundary.

### Task 5: Make Output Allocation Safe And Explicit

**Files:**
- Modify: `Sources/CaptureStudio/Services/FileOutputService.swift`
- Modify: `Sources/CaptureStudio/Capture/RecordingService.swift`
- Modify: `Tests/CaptureStudioTests/FileOutputServiceTests.swift`

**Interfaces:**
- Missing configured output directories throw a user-visible output error instead of silently selecting Desktop.
- Recording destinations are atomically reserved with exclusive creation and carry ownership into cleanup.
- Screenshot writes use exclusive destination creation plus atomic replacement of the reservation.
- Smart filenames enforce a UTF-8 byte budget for a single filesystem component.

- [x] Replace fallback tests with explicit missing-directory failure tests.
- [x] Add concurrent allocation tests proving distinct reserved URLs.
- [x] Add external-file ownership tests proving cleanup cannot remove a path it does not own.
- [x] Add long emoji and combining-character filename tests.
- [x] Implement reservation, ownership, and UTF-8-safe truncation.
- [x] Validate recording/export source device/inode identity before publication and remove only the verified source across same-volume and cross-volume paths.
- [x] Publish copy-fallback output only after a complete sibling-temp write and `fsync`; quarantine cleanup targets before identity-checked removal.
- [x] Keep completed output valid when source cleanup fails after quarantine, and restore the source instead of rolling back both paths.
- [x] Move verified deletions through a private sibling quarantine so a path replacement cannot be sent to Trash; recover visibly when Trash fails and the original path is occupied.
- [x] Protect dirty documents before opening history and prevent the personal installer from force-quitting a running app.
- [x] Move recording/trim/GIF publication off the main actor and block conflicting UI actions until completion.
- [x] Re-run file output and recording tests.

### Task 6: Use Exact OCR Range Geometry For Quick Redact

**Files:**
- Modify: `Sources/CaptureStudio/OCR/OCRModels.swift`
- Modify: `Sources/CaptureStudio/OCR/OCRService.swift`
- Modify: `Sources/CaptureStudio/Redaction/RedactionDetector.swift`
- Modify: `Tests/CaptureStudioTests/RedactionDetectorTests.swift`
- Modify: `Tests/CaptureStudioTests/QuickRedactIntegrationTests.swift`

**Interfaces:**
- OCR results carry exact normalized boxes for matched text ranges when Vision can provide them.
- Redaction uses exact range geometry and falls back to the whole observation box, never a character-count approximation.
- Failed exact geometry must over-cover sensitive text rather than under-cover it.

- [x] Add a proportional-text fixture with a wide prefix and narrow suffix.
- [x] Confirm the existing ratio-based candidate under-covers the expected sensitive range.
- [x] Capture Vision range boxes during recognition and use them in redaction detection.
- [x] Add conservative whole-observation fallback tests.
- [x] Re-run OCR, Quick Redact, and asymmetric redaction output tests.

### Task 7: Full Verification And Commit

**Files:**
- Modify: `README.md` only where behavior changed or prior claims were inaccurate.

- [x] Run all focused regression tests in isolated scratch paths.
- [x] Run default `swift test`: 289 executed, 11 opt-in tests skipped, 0 failures.
- [ ] Run opt-in ScreenCaptureKit tests and 30-second recording under the XCTest process. Not run because that process has a different TCC identity; equivalent short native-app capture/record flows were exercised without changing TCC.
- [x] Run isolated Debug and Release builds, all shell syntax checks, and `git diff --check`.
- [x] Exercise safe current-source UI flows for cancellation preservation, screenshot annotation/save, rectangle/window/full-screen capture, rectangle/window recording, stop/playback, settings, history, presets, pin, OCR, trim, and GIF export.
- [x] Review the final delta against the baseline snapshot so no unrelated generated artifact is staged.
- [x] Prepare the approved project stabilization work as one verified commit; do not push.
