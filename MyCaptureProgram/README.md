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

## Install as a macOS App

Screen recording permission works best with a stable `.app` bundle. Install the app into Applications before granting macOS privacy permissions:

```bash
scripts/install_app.sh
```

Run the script as your normal user. If `/Applications` requires administrator permission,
the script requests it only for the final staged installation. Do not run the whole build
with `sudo`. You can also install to your user Applications folder:

```bash
scripts/install_app.sh "$HOME/Applications"
```

After installing, add `CaptureStudio.app` in System Settings > Privacy & Security > Screen & System Audio Recording. If macOS still asks for permission after a reinstall, remove the old `CaptureStudio` entry from that list and add `/Applications/CaptureStudio.app` again so the TCC entry matches the current code signature.

Regenerate the bundled app icon assets with:

```bash
swift scripts/generate_app_icon.swift
```

## Package for Distribution

For your own Macs only, create a personal installer zip:

```bash
scripts/package_personal.sh
```

This writes:

```text
dist/CaptureStudio-personal-mac.zip
```

Move that zip to your other Mac, unzip it, and run `Install CaptureStudio.command`.
If macOS blocks the installer script, right-click it and choose Open. The installer removes
download quarantine, signs the app locally for that Mac, installs it to `/Applications`,
and opens it. Save any current work and close CaptureStudio first; the installer stops
instead of force-quitting a running app.

Do not upload a zip made from `scripts/install_app.sh` or from `/Applications/CaptureStudio.app`.
That app is for local development/install only and may be signed with an Apple Development
identity, which Gatekeeper rejects after another Mac downloads it.

For MyVibeCoding or any other download site, create a notarized release archive:

```bash
xcrun notarytool store-credentials capturestudio-notary
CAPTURE_STUDIO_NOTARY_PROFILE=capturestudio-notary scripts/package_release.sh
```

The release script requires a `Developer ID Application` certificate in the keychain,
signs with hardened runtime and entitlements, submits the app for Apple notarization,
staples the ticket, runs `spctl`, and writes:

```text
dist/CaptureStudio-0.1.0-macOS.zip
```

Upload only that notarized zip. If the script stops with "No Developer ID Application
signing identity found", install the Developer ID Application certificate from the
Apple Developer account first. If it stops with "No notarization keychain profile provided",
store a `notarytool` profile and set `CAPTURE_STUDIO_NOTARY_PROFILE` to that profile name.

## Test

```bash
swift test
```

Run ScreenCaptureKit and screenshot-editor integration tests:

```bash
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
```

## Documentation

The current user-facing feature list, install steps, packaging flow, and permission notes live in this README.

Files under `docs/superpowers/` are historical planning/specification artifacts from earlier implementation phases. They are useful for design rationale, but they may include task-by-task implementation snippets from that phase. When those files conflict with this README or the current source code, treat this README and the source code as authoritative.

## Screenshot Editing

After a screenshot is captured, the editor toolbar can annotate, OCR, and redact the screenshot before saving or copying. Save and Copy flatten annotation layers into a PNG. OCR and Quick Redact run on demand.

## Features

- Native macOS app bundle with a compact Capture / Record first workflow
- Rectangle, window, and full-screen screenshot capture with ESC cancel support
- Rectangle, window, and full-screen recording with countdown delay, duration control, and stop handling
- Multi-display selection overlay support
- Persistent Settings window for output, capture, recording, shortcuts, and advanced options
- Customizable shortcuts with per-action reset and reset-all defaults; global shortcuts require Command, Option, or Control so ordinary typing is never captured
- Configurable output folders, clipboard behavior, and automatic/manual save mode
- Smart filenames using active app/window context when available
- Screenshot annotation tools: pen, highlighter, arrow, rectangle, ellipse, text, solid redaction, OCR, undo/redo, copy, save, delete
- Quick Redact for detected sensitive text
- Recording preview, trim-copy export, and GIF export; a blank trim end uses the media's actual duration, while invalid or reversed times are rejected with an explanation
- Capture history with thumbnails, search, open, per-item delete, and Clear History that keeps capture files
- Floating pinned screenshot preview
- Presets for quickly switching common workflows
- In-app guide modal for feature explanations

## Notes

- macOS screen recording permission is tied to the installed app bundle and code signature. If permission prompts keep appearing after reinstalling, remove the old `CaptureStudio` entry from System Settings and add `/Applications/CaptureStudio.app` again.
- Starting a new capture or opening a history item while the current screenshot or recording has unsaved changes asks whether to Save, Discard Changes, or Cancel.
- Quitting with unsaved work asks whether to Save, Discard Changes, or Cancel. CaptureStudio also refuses to quit while a capture, recording, export, or file operation is still active.
- If a configured output folder is missing or not writable, CaptureStudio does not silently fall back to Desktop. The new result stays open as unsaved so you can choose another folder and save it.
- Quick Redact adds editable redaction layers. It does not alter an already saved original or the current clipboard; use Save or Copy to create the redacted version.
- Integration tests that touch live screen capture require macOS permissions and are run with `CAPTURE_STUDIO_RUN_INTEGRATION=1`.
- The latest hardening verification is in `docs/qa/2026-08-08-follow-up-hardening.md`. The broader feature matrix is in `docs/qa/2026-08-04-feature-verification-checklist.md`.
