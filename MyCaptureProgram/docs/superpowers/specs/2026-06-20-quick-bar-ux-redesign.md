# Quick Bar UX Redesign

Date: 2026-06-20

## Goal

Redesign Capture Studio so the most common actions, screenshot capture and screen recording, are immediately obvious and usable from the first screen. The app should keep the professional depth already implemented, including settings, annotation, OCR, redaction, shortcuts, and save behavior, but those secondary features should appear only when they are relevant.

The chosen direction is "Quick Bar First": a compact native command surface with two primary actions, `Capture` and `Record`, instead of the current `Mode` picker plus `New` workflow.

## Current UX Problems

The current main window requires users to understand too much before doing the common task:

- Users must notice the Screenshot/Record segmented control before pressing `New`.
- `New` changes behavior depending on mode, which is efficient for the code but less direct for users.
- Output, capture, and recording concepts are scattered between main controls and settings.
- Copy/Save actions exist at the bottom even before a document exists, but are disabled and visually distracting.
- Editing tools are close to the main experience, even though they matter only after a screenshot exists.
- Settings are powerful, but users must know where to look before they can adjust common defaults.

The target redesign should reduce the first-run question from "how do I use this?" to "do I want to capture or record?"

## Product Direction

The main surface becomes a quick action bar and recent-result panel.

Top-level actions:

- `Capture`: starts screenshot area selection immediately.
- `Record`: starts recording area selection immediately.
- Quick options menu: compact access to capture area type, delay/countdown, destination summary, and clipboard behavior.
- Settings button: opens full Settings for durable preferences.

Removed from the main first-run workflow:

- `+ New`
- Persistent Screenshot/Record mode picker
- Always-visible editor toolbar before a capture exists

The app should feel like a focused capture utility first and an editor second.

## Main Window Layout

The default window is compact, not a dashboard.

Structure:

1. Primary command row
   - `Capture` button, blue, first position.
   - `Record` button, red, second position.
   - Quick options button.
   - Settings button.
   - Compact output summary, for example `Desktop · PNG · 0s`.
2. Recent result row
   - Hidden when there is no recent result unless a helpful empty state is needed.
   - Shows thumbnail or recording icon.
   - Shows status: `Saved to Desktop`, `Unsaved screenshot`, or `Recording saved`.
   - Provides contextual actions: `Open Editor`, `Copy`, `Reveal`, `Save`.
3. Preview/editor area
   - Hidden or minimized on first launch.
   - Expands after a screenshot or recording exists.
   - Screenshot documents show the editor canvas and screenshot tools.
   - Recording documents show recording-specific actions only.

The first screen should not explain itself with instructional copy. The controls should make the primary workflow clear.

## Capture Flow

When the user presses `Capture`:

1. The app starts rectangle selection directly.
2. The app excludes its own window from the captured content.
3. If automatic save is enabled, it writes the PNG to the configured screenshot folder and updates the recent result row.
4. If automatic save is disabled, it opens the screenshot as an unsaved document and makes `Save` prominent.
5. The screenshot editor appears only after the screenshot exists.

Future capture modes, such as window, full screen, or freeform, should live behind the quick options menu and later be available as long-press or split-button options. The default left-click behavior remains area capture.

## Recording Flow

When the user presses `Record`:

1. The app starts rectangle selection directly.
2. It applies the configured countdown.
3. It records to MP4 using the configured cursor/audio/quality settings.
4. If automatic save is enabled, it writes the MP4 to the configured recording folder and updates the recent result row.
5. If automatic save is disabled, it keeps the temporary recording as an unsaved document and makes `Save` prominent.

Recording-specific controls should not appear on first launch. They appear in Settings and in the post-recording result area.

## Quick Options

Quick options are for lightweight per-capture changes. They should not become a full settings panel.

Include:

- Capture area type: Area initially, with Window and Full Screen later.
- Screenshot delay: 0s, 3s, 5s, 10s.
- Recording countdown: 0s, 3s, 5s, 10s.
- Destination summary with `Change in Settings`.
- Clipboard toggle for screenshots.

Do not include:

- Every output setting.
- All shortcut settings.
- OCR/redaction settings.
- Recording device management.

Those remain in full Settings.

## Settings Model

Settings stays as the durable preferences surface, but it should support the quick-bar mental model.

Tabs remain:

- Output
- Capture
- Record
- Shortcuts
- Advanced

Important adjustments:

- Output settings should clearly separate screenshot and recording destination.
- Capture settings should explain defaults only through labels, not long help text.
- Record settings should make countdown, cursor, audio, and quality easy to scan.
- Shortcuts should expose every default shortcut, including Text Extraction, Color Picker, Last Capture, and Open Settings.
- Full reset and per-shortcut reset remain.

## Post-Capture Editing

The editor should appear only after a screenshot exists.

Screenshot post-capture actions:

- Select
- Pen
- Highlighter
- Arrow
- Rectangle
- Ellipse
- Text
- Redact
- OCR
- Undo
- Redo
- Copy
- Save
- Reveal

The main quick bar remains visible above or near the editor so users can start another capture without closing the editor.

Recording post-capture actions:

- Save
- Reveal
- Play
- Copy path or file reference where supported
- Trim later, when recording trim is implemented

Image-only annotation tools must not appear for recording documents.

## Shortcut Behavior

Shortcuts should match the direct-action model:

- New screenshot shortcut triggers `Capture`.
- New recording shortcut triggers `Record`.
- Open Settings opens Settings.
- Text Extraction, Color Picker, and Last Capture remain configurable even if their full workflows are staged behind later UI.

Shortcut conflicts should always mention a visible action in the Shortcuts settings list. A user should never see an error for a shortcut they cannot inspect or change.

## Error Handling

Selection errors:

- Tiny selections should show a short recoverable message in the recent/status area.
- The click that opened the selection overlay must not be treated as the user's selection.

Permission errors:

- Screen recording permission denial should show a clear message with an action to open macOS Settings later.
- The app should not attempt to silently change macOS security settings.

Save errors:

- If a configured folder is missing or inaccessible, fall back to Desktop and show a recoverable warning.
- The status row should show where the file actually went.

## Implementation Boundaries

Primary code areas:

- `MainWindowView`: replace mode picker plus `New` with quick action buttons and recent-result layout.
- `CaptureCoordinator`: keep capture and recording behavior, but expose direct `startScreenshotCapture` and `startScreenRecording` entry points if needed.
- `EditorToolbarView`: show only when a document exists and tailor actions to screenshot versus recording.
- `SettingsView`: keep tabs but ensure shortcuts expose all default actions.
- `SelectionService`: preserve the click-guard behavior so opening the overlay does not create a tiny selection.

This redesign should not introduce a separate design system or external UI library. SwiftUI and AppKit are sufficient and better aligned with a native macOS capture utility.

## Testing Strategy

Automated tests:

- Main-window view model or state tests for direct `Capture` and `Record` actions.
- Capture coordinator tests for screenshot and recording direct entry points.
- Shortcut tests confirming configurable actions include every default shortcut.
- Selection tests or focused integration checks for preventing open-click tiny selections where practical.
- Existing save, copy, OCR, redaction, render, and ScreenCaptureKit integration tests must keep passing.

Manual E2E checks:

- Launch packaged `.app` test bundle.
- Confirm `Capture` and `Record` are first-screen primary actions.
- Confirm Settings opens from the quick bar and app menu.
- Confirm Output/Capture/Record/Shortcuts/Advanced tabs remain accessible.
- Confirm `Capture` opens area selection without immediately failing as too small.
- Confirm actual capture/recording completes on an app identity with macOS Screen Recording permission.

## Success Criteria

- A new user can identify how to take a screenshot or start recording within one second of seeing the app.
- Capturing no longer requires choosing a mode and then pressing a generic `New` button.
- Settings and editor depth remain available without crowding the first screen.
- Shortcut customization remains complete and conflicts are resolvable from the visible UI.
- Existing capture, recording, save, editing, OCR, and redaction tests continue to pass.
