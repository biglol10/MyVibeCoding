# Privacy & Access Settings Design

Status update, 2026-07-03: implemented in `Sources/MyMacFinder/App/PrivacyAccessSettingsView.swift`. The context below describes the pre-change UI problem that this design fixed.

## Context

Before this change, the Privacy & Access settings tab used a default SwiftUI `Form` inside the app settings `TabView`. In the fixed-size settings window this left the main content visually sparse, put labels and values in an awkward row, and made the empty folder-grant state look unfinished.

## Goals

- Make the Privacy & Access tab look intentional in the existing macOS settings window.
- Keep the app's dark, utility-focused style and avoid decorative marketing UI.
- Keep the current behavior unchanged: choosing a folder, opening macOS privacy settings, listing grants, removing one grant, and resetting all grants.
- Improve layout density, text hierarchy, and empty-state presentation.

## Non-Goals

- Do not redesign the whole settings window.
- Do not change permission, sandbox, or security-scoped bookmark behavior.
- Do not add new privacy workflows or extra system permission checks.

## Design

Create a dedicated `PrivacyAccessSettingsView` SwiftUI view and replace only the second settings tab body with it.

The view uses a constrained top-aligned layout instead of a default `Form`:

- Header: title, concise subtitle, and a lock/shield icon.
- Status panel: shows the sandbox status as a compact badge and the existing sandbox detail text.
- Actions row: primary `Choose Folder...` and secondary `Privacy Settings` buttons with consistent spacing and icons.
- Folder grants panel:
  - Empty state: icon, "No folders selected", and a short explanation.
  - Non-empty state: compact list of selected folder paths with middle truncation and a remove button per row.
  - Reset action appears only when grants exist.

The visual treatment should use subtle backgrounds, small corner radius, system separators, and existing accent color. Text must remain readable in dark mode and fit in the existing settings window.

## Component Boundaries

- `MyMacFinderApp` keeps owning the `Settings` scene, bindings, and `openPrivacySettings`.
- `PrivacyAccessSettingsView` receives:
  - `sandboxPolicy`
  - `grantedFolderSummaries`
  - async closures for choose/remove/reset
  - a closure for opening privacy settings
- No production behavior moves into test-only APIs.

## Testing

Add focused view wiring coverage that verifies the new view can be constructed with empty and non-empty grant states. Existing permission recovery and folder access tests continue to cover behavior.

## Verification

Run:

```sh
swift test --enable-code-coverage
swift build
git diff --check
./scripts/build_app.sh
./scripts/verify-app-icon.sh
codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
./scripts/package_personal.sh
unzip -t dist/MyMacFinder-personal-mac.zip
```

Manual QA should open Settings > Privacy & Access and check empty state, buttons, grant list layout, remove button, and reset button visibility.
