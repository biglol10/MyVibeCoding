# FlowPilot

FlowPilot is a local productivity tracker for macOS and Windows. It records app/window usage and browser tab domains,
then builds daily and weekly productivity reports with charts, tables, timelines, classification rules, exclude rules,
display aliases, and persistent local storage.

This repository currently contains:

- Tauri v2 + React + Rust desktop app.
- SwiftUI native macOS app under `macos-native/`.
- Chromium browser extension under `browser-extension/`.

Current macOS direction:

- The SwiftUI native app is the recommended personal macOS build path.
- The native app reads and writes the existing FlowPilot SQLite database at
  `~/Library/Application Support/app.flowpilot.desktop/time-manager.sqlite3`.
- The native app includes its own macOS foreground app/window collector, idle detection, Chrome/Edge bridge, Safari Automation domain capture, rules editing, reports, and menu bar summary.
- The Tauri app remains for the cross-platform React/Rust path and Windows continuity.

## Development

Install dependencies:

```bash
npm install
npm install --prefix browser-extension
npm run build --prefix browser-extension
source "$HOME/.cargo/env"
```

Run the Tauri app:

```bash
npm run tauri dev
```

Run the SwiftUI native macOS app:

```bash
cd macos-native
swift run FlowPilotNative
```

The native app falls back to sample data only when the existing FlowPilot database is missing or unreadable. When the legacy Tauri FlowPilot app is already running, the native collector pauses to avoid double-counting activity.

## macOS Permissions

FlowPilot can collect basic running app metadata without extra permissions, but richer macOS collection needs user
approval:

- Accessibility: app/window metadata and focused window title.
- Screen Recording: visible window list and titles. FlowPilot does not store screen images.
- Automation for Safari: active Safari tab URL/title when Safari is frontmost.

Grant permissions to the exact `/Applications/FlowPilot.app` bundle you launch, then restart FlowPilot.

More detail: [docs/macos-development.md](docs/macos-development.md)

## Browser Domain Tracking

Chrome and Edge use the unpacked extension in `browser-extension/`. The extension sends active tab domains to the local
bridge at `http://127.0.0.1:17321/browser-event`.

For Chrome development:

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Run `npm run build --prefix browser-extension` after changing extension code.
4. Load unpacked extension from `browser-extension/`.

Safari is handled by macOS Automation in the native app when permission is available. It falls back to app/window
tracking if the active tab URL cannot be read.

## Tests

```bash
npm test
npm run build
npm test --prefix browser-extension
npm run e2e
cargo test --manifest-path src-tauri/Cargo.toml
swift test --package-path macos-native
```

## Packaging

Local Tauri package:

```bash
npm run package:macos
```

Personal SwiftUI native packages:

```bash
npm run package:macos:native
npm run package:macos:native:dmg
```

Expected native outputs:

```text
release/FlowPilot_native_mac_arm64.zip
release/FlowPilot_native_mac_arm64.dmg
```

These personal packages are ad-hoc signed and intended for your own Macs only. Use the included
`install-flowpilot-native.command` to replace `/Applications/FlowPilot.app` and remove quarantine.

For the Tauri personal package, use:

```bash
npm run package:macos:personal
```

Expected output:

```text
release/FlowPilot_personal_mac_arm64.zip
```

## Distribution

Public or third-party download distribution requires Developer ID signing and Apple notarization. Do not upload local
ad-hoc builds to external distribution services.

See [docs/macos-distribution.md](docs/macos-distribution.md) for Developer ID, notarization, personal install, and
Gatekeeper validation commands.

## Safety Notes

- Browser bridge listens on loopback only.
- macOS idle time is excluded from active usage where supported.
- Browser/window observation data is pruned to avoid unbounded database growth.
- Rule lists support add, edit, disable, and delete flows.
