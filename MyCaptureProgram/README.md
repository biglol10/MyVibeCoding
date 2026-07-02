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

If `/Applications` is not writable, rerun the command with permission or pass another destination:

```bash
sudo scripts/install_app.sh /Applications
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
and opens it.

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
Apple Developer account first. If it stops with "No notarization credentials provided",
store a notarytool profile or set `CAPTURE_STUDIO_APPLE_ID`, `CAPTURE_STUDIO_TEAM_ID`,
and `CAPTURE_STUDIO_APP_SPECIFIC_PASSWORD`.

## Test

```bash
swift test
```

Run ScreenCaptureKit and screenshot-editor integration tests:

```bash
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
```

## Screenshot Editing

After a screenshot is captured, the editor toolbar can annotate, OCR, and redact the screenshot before saving or copying. Save and Copy flatten annotation layers into a PNG. OCR and Quick Redact run on demand.

## Current Milestone

This milestone includes:

- Minimal main window
- Settings window
- Persistent settings
- Customizable shortcut model with reset defaults
- Output filename and folder fallback model
- Capture coordinator interfaces
- Real screen region selection
- Screenshot capture and screen recording
- Screenshot editing, OCR, and quick redaction

Color picker and recording trim are separate implementation milestones.
