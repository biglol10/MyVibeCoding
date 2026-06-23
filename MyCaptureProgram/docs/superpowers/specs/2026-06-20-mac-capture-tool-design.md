# Mac Capture Tool Design

Date: 2026-06-20

## Goal

Build a native macOS screenshot and screen recording app that feels as convenient as Windows Snipping Tool, while fitting macOS interaction patterns. The app should keep the main screen minimal, move defaults and behavior controls into Settings, and support phased delivery from core capture and recording to advanced editing and OCR.

The target platform is macOS 15 or newer.

## Windows Snipping Tool Research

The current Windows Snipping Tool combines screenshot capture, screen recording, editing, saving, sharing, OCR, and newer AI-assisted utilities.

Sources reviewed:

- Microsoft Support, "Use Snipping Tool to capture screenshots": https://support.microsoft.com/en-us/windows/use-snipping-tool-to-capture-screenshots-00246869-1843-655f-f220-97299b865f6b
- Microsoft Support, "Keyboard shortcuts in Windows": https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec
- Windows Experience Blog, September 26, 2023 Snipping Tool audio and text actions update: https://blogs.windows.com/windowsexperience/2023/09/26/the-most-personal-windows-11-experience-begins-rolling-out-today/
- Windows Insider Blog, December 8, 2022 screen recording update: https://blogs.windows.com/windows-insider/2022/12/08/screen-recording-in-snipping-tool-begins-rolling-out-to-windows-insiders/
- Windows Insider Blog, February 21, 2025 recording trim update: https://blogs.windows.com/windows-insider/2025/02/21/announcing-windows-11-insider-preview-build-26120-3291-dev-and-beta-channels/
- Windows Insider Blog, April 15, 2025 text extractor update: https://blogs.windows.com/windows-insider/2025/04/15/text-extractor-in-snipping-tool-begins-rolling-out-to-windows-insiders/
- Windows Insider Blog, May 22, 2025 perfect screenshot and color picker update: https://blogs.windows.com/windows-insider/2025/05/22/paint-snipping-tool-and-notepad-updates-with-new-features-begin-rolling-out-to-windows-insiders/
- Windows Insider Blog, August 14, 2025 window-mode recording update: https://blogs.windows.com/windows-insider/2025/08/14/announcing-windows-11-insider-preview-build-27924-canary-channel/
- Windows Insider Blog, September 17, 2025 quick markup update: https://blogs.windows.com/windows-insider/2025/09/17/paint-snipping-tool-and-notepad-app-updates-begin-rolling-out-to-windows-insiders/
- Apple Developer, ScreenCaptureKit documentation: https://developer.apple.com/documentation/screencapturekit/
- Apple Developer, WWDC23 "What's new in ScreenCaptureKit": https://developer.apple.com/videos/play/wwdc2023/10136/
- Apple Developer, WWDC24 "Capture HDR content with ScreenCaptureKit": https://developer.apple.com/videos/play/wwdc2024/10088/

### Capture Features

Windows Snipping Tool supports these screenshot capture modes:

- Rectangular region
- Window
- Full screen
- Freeform
- Video snip for rectangular screen recording
- Perfect screenshot on supported Copilot+ PCs, where the selected area is adjusted to better frame visible content
- Text Extractor, which scans a selected region for text without requiring a normal screenshot
- Color picker, which samples screen colors and supports HEX, RGB, and HSL values

Shortcuts include:

- `Win + Shift + S` for screenshot capture overlay
- `Win + Shift + R` for screen recording region selection
- Print Screen behavior for static screenshot workflows

### Editing Features

After capture, Windows Snipping Tool opens the result in an editor. Documented editing capabilities include:

- Pen
- Highlighter
- Eraser
- Shapes
- Emojis
- Image crop
- Undo and redo
- Text actions with OCR
- Copy all text
- Quick redact for email addresses and phone numbers
- Save, Save As, Share, Print
- Edit in Paint or Clipchamp for deeper image/video editing

Recent Insider builds also include Quick markup, where annotation can happen directly in the selection area before finalizing the screenshot.

### Recording Features

Windows Snipping Tool supports region recording, pause while recording, audio and microphone support, automatic recording save, trim, and window-mode recording in newer builds. Window-mode recording sizes the region to a chosen app window at the start, then records the fixed region.

The Windows keyboard shortcuts documentation states screen recordings are saved by default as MP4 files under a Videos > Screen Recordings folder. Snipping Tool settings can disable automatic recording save in newer versions.

### Settings Features

The Windows settings model includes or implies these categories:

- Automatically copy changes to clipboard
- Automatically save original screenshots
- Screenshot save folder, with Change and Open folder actions
- Ask to save edited screenshots
- Multiple windows for separate captures
- Add border to screenshots
- HDR color correction
- Include system audio by default for screen recordings
- Include microphone input by default
- Preferred microphone/input device
- Automatic save for recordings

## Product Direction

The product will follow a "minimal main + settings model" design.

The main window is not a dashboard. It is a compact capture and editor surface. Output, Capture, and Record defaults are not shown as a persistent inspector in the main window. They live in Settings.

The main window includes:

- `+ New`
- Screenshot/Record segmented control
- Area type menu
- Delay menu
- Open recent or open file action
- Settings action
- Empty preview area before capture
- Preview canvas after capture or recording
- Bottom editor toolbar after capture

The Settings window includes:

- Output
- Capture
- Record
- Shortcuts
- Advanced

## Functional Requirements

### New Button Behavior

`+ New` acts according to the selected mode.

If Screenshot is selected:

1. Hide or exclude the app window.
2. Show a screen selection overlay.
3. Let the user select a rectangle in the first implementation.
4. Capture the selected content.
5. Open the capture in the editor.
6. Save automatically or wait for manual save based on settings.

Window, full-screen, and freeform screenshot modes are part of the final feature set, but they are not required for the first working screenshot milestone.

If Record is selected:

1. Hide or exclude the app window.
2. Show a screen selection overlay.
3. Let the user select a rectangle in the first implementation.
4. Show recording controls.
5. Start recording after optional countdown.
6. Stop, save, and open the recording preview.
7. Save automatically or wait for manual save based on settings.

Window-mode recording is part of the final feature set, but it is not required for the first working recording milestone.

### Output

Default output location is `~/Desktop`.

Users can change screenshot and recording output folders in Settings. If the configured folder is missing or inaccessible, the app falls back to Desktop and shows a recoverable warning.

Screenshot filenames:

- `Screenshot YYYY-MM-DD at HH.mm.ss.png`

Recording filenames:

- `Recording YYYY-MM-DD at HH.mm.ss.mp4`

### Save Modes

The app supports both:

- Automatic save: create the file immediately after capture or recording.
- Manual save: keep the capture in the editor until the user presses Save or Save As.

When manual save is active, closing an edited unsaved capture prompts the user if "Ask to save edited screenshots" is enabled.

### Editing

Initial editor tools:

- Pen
- Highlighter
- Eraser
- Crop
- Undo and redo
- Copy to clipboard
- Save
- Save As
- Share

Later editor tools:

- Shapes
- Text labels
- Emojis or stickers
- OCR text extraction
- Quick redact for email and phone number patterns
- Color picker
- Recording trim

### Settings

Output:

- Automatically save screenshots
- Automatically save recordings
- Screenshot folder
- Recording folder
- Open folder
- Save format
- Ask to save edited screenshots
- Show in Finder after save

Capture:

- Hide or exclude this app while selecting
- Automatically copy captured image
- Automatically copy edits
- Multiple editor windows
- Capture border
- Default delay
- Cursor visibility for screenshots where supported

Record:

- Include system audio by default
- Include microphone by default
- Microphone input device
- Show cursor in recordings
- Countdown before recording
- Quality preset
- Window-mode recording
- MP4 output

Shortcuts:

- New screenshot
- New recording
- Text extraction
- Color picker
- Last capture
- Open settings
- User-customizable key combinations for every shortcut
- Conflict detection when a new shortcut duplicates another shortcut inside the app
- Registration failure handling when macOS or another app has already claimed a global shortcut
- Reset all shortcuts to defaults
- Reset one shortcut to its default value

Advanced:

- Screen Recording permission status
- Microphone permission status
- OCR languages
- Quick redact patterns
- Diagnostics log location
- Update settings

## Architecture

### Technologies

- SwiftUI for the main window, settings window, editor surface, and state-driven UI.
- AppKit for overlay windows, global capture interaction, window behavior, and lower-level macOS integration.
- ScreenCaptureKit for screenshots and screen recording.
- AVFoundation for MP4 writing, media inspection, recording trim, and audio device handling.
- Vision for OCR and quick-redact detection.
- SF Symbols for native iconography.
- `KeyboardShortcuts` as a candidate dependency for configurable global shortcuts.
- `Sparkle` as a candidate dependency for app updates.

The UI should remain native. External UI component libraries are not recommended for the main app because SwiftUI, AppKit, and SF Symbols will look more professional on macOS than a web-style component system. External libraries should be used only where they reduce real implementation risk.

### Core Components

`AppState`

- Tracks selected mode, selected area type, current capture session, current editor document, and permission warnings.

`SettingsStore`

- Persists user settings in `UserDefaults`.
- Exposes typed settings to SwiftUI views and capture services.
- Stores customized keyboard shortcuts and can restore default shortcut values.

`ShortcutManager`

- Registers global shortcuts.
- Exposes editable shortcut bindings to the Settings UI.
- Detects duplicate bindings inside the app.
- Provides "Reset to Default" for an individual shortcut and "Reset All Defaults" for the whole shortcut set.
- Falls back to documented defaults if a custom binding is missing, invalid, or unavailable.

`CaptureCoordinator`

- Orchestrates `+ New`.
- Reads selected mode and settings.
- Hides or excludes app windows.
- Presents overlay.
- Routes result to screenshot or recording service.

`SelectionOverlayController`

- AppKit-owned overlay over all displays.
- Supports rectangle selection first.
- Adds window and full screen selection later.
- Handles Retina scale and multi-display coordinates.

`ScreenshotService`

- Uses ScreenCaptureKit screenshot APIs.
- Returns an image document for the editor.

`RecordingService`

- Uses ScreenCaptureKit stream APIs.
- Writes MP4 output.
- Handles start, pause where supported, stop, and failure cleanup.
- Verifies system-audio and microphone capture behavior during Phase 3 because macOS support depends on ScreenCaptureKit capabilities, OS version, device configuration, and permissions.

`EditorDocument`

- Holds the captured image or recording metadata.
- Tracks dirty state, save path, and edits.

`FileOutputService`

- Generates filenames.
- Resolves output folders.
- Handles fallback to Desktop.
- Writes image and video files.

`OCRService`

- Uses Vision for text extraction and quick redact candidates.

`PermissionService`

- Checks Screen Recording and Microphone authorization.
- Opens System Settings when required.

## Data Flow

Screenshot flow:

1. User chooses Screenshot mode and presses `+ New`.
2. `CaptureCoordinator` reads `SettingsStore`.
3. App window is hidden or excluded from capture.
4. `SelectionOverlayController` returns selected geometry.
5. `ScreenshotService` captures the region.
6. `EditorDocument` is created.
7. `FileOutputService` saves automatically if enabled.
8. Editor preview opens with save/copy/share controls.

Recording flow:

1. User chooses Record mode and presses `+ New`.
2. `CaptureCoordinator` checks Screen Recording and audio permissions.
3. Overlay returns recording region.
4. Recording controls show countdown and start.
5. `RecordingService` writes MP4.
6. On stop, file is finalized.
7. Preview opens.
8. Auto-save or manual-save behavior follows settings.

Manual save flow:

1. Capture result opens as dirty unsaved document.
2. User edits or previews.
3. Save writes to default folder.
4. Save As opens a file picker.
5. Closing unsaved edited content prompts when enabled.

## Error Handling

The app must handle:

- Missing Screen Recording permission
- Missing Microphone permission
- User cancels overlay selection
- Display disconnects during selection or recording
- Configured output folder missing or inaccessible
- File write failure
- Recording stop/finalization failure
- App loses permission after an OS update or code signing identity change
- User closes the editor with unsaved changes

Errors should be recoverable where possible. Permission errors open Settings guidance. Save failures offer retry, Save As, or fallback to Desktop.

## Implementation Phases

### Phase 1: Project and Core UI

- Create SwiftUI/AppKit macOS 15 project.
- Build minimal main window.
- Build Settings window with Output, Capture, Record, Shortcuts, and Advanced sections.
- Add `SettingsStore`.
- Add shortcut customization UI with per-shortcut reset and reset-all defaults.
- Add filename and output folder model.

### Phase 2: Screenshot Capture

- Implement AppKit selection overlay.
- Implement rectangle screenshot capture.
- Exclude or hide the app during selection.
- Open captured image in editor preview.
- Implement automatic save and manual save.
- Implement clipboard copy.

### Phase 3: Recording

- Implement rectangle region recording.
- Save MP4 to configured folder.
- Add stop controls and recording preview.
- Add microphone and system audio settings where supported.

### Phase 4: Basic Editing

- Add pen, highlighter, eraser, crop, undo, redo.
- Add Save, Save As, Copy, Share.
- Track dirty state and close prompts.

### Phase 5: Advanced Features

- Window capture and full-screen capture.
- Window-mode recording.
- OCR text extraction.
- Quick redact.
- Color picker.
- Recording trim.
- Perfect Screenshot-style automatic region adjustment.

## Testing Strategy

Unit tests:

- Settings load/save defaults
- Shortcut customization, duplicate detection, and reset-to-default behavior
- Filename generation
- Output folder fallback
- Capture state machine
- Manual save dirty-state behavior

Service tests:

- Mock screenshot service result handling
- Mock recording lifecycle
- File output success and failure
- Permission status transitions

Manual macOS validation:

- Screen Recording permission grant and denial
- Microphone permission grant and denial
- Retina displays
- Multi-monitor coordinate handling
- App window exclusion
- Region capture
- Region recording
- Auto-save to Desktop
- Custom output folders
- Manual save
- Clipboard copy

UI validation:

- Main window stays minimal.
- Output, Capture, and Record settings are not duplicated in the main window.
- Editor tools activate only when capture content exists.
- Settings remain understandable on small window sizes.

## Open Decisions

- App name and icon direction are not finalized.
- Whether to include a menu bar extra is deferred until the core window workflow is implemented.
- Whether to ship Sparkle auto-update support depends on distribution target.
- Whether to support Mac App Store distribution is deferred because screen recording and update mechanisms may affect packaging choices.
