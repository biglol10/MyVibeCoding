# MyMacFinder App Icon Design

## Goal

Create a native macOS app icon for MyMacFinder that communicates a professional dual-pane file manager without copying Finder's face icon.

## Approved Direction

**A. Dual Pane Utility**

- Rounded macOS-style app icon silhouette.
- Graphite utility base matching the app's dark professional UI.
- Two overlapping file-manager panes to signal dual-pane browsing.
- A narrow orange accent bar to match MyMacFinder's existing command accent.
- A small blue folder cue so the icon remains readable as a file-management app.

## Implementation Requirements

- Produce a deterministic source image so the icon can be regenerated.
- Generate a 1024px app icon preview PNG.
- Generate a complete macOS `.iconset`.
- Generate `AppIcon.icns`.
- Provide a repeatable app-bundle script that copies the icon into the `.app` bundle and sets `CFBundleIconFile`.
- Add verification so missing or incorrectly wired icon assets are caught before release.

## Non-Goals

- Do not imitate Finder's split-face icon.
- Do not add a marketing-style logo treatment.
- Do not change the app's file-management behavior.
