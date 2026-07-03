# FlowPilot macOS Development and Packaging

## Development Run

From `/Users/biglol/Desktop/practice/FlowPilot_mac`:

SwiftUI native macOS app:

```bash
npm install --prefix browser-extension
npm run build --prefix browser-extension
swift test --package-path macos-native
cd macos-native
swift run FlowPilotNative
```

Tauri/React app:

```bash
npm install
source "$HOME/.cargo/env"
npm run tauri dev
```

Current macOS personal builds should use the SwiftUI native app unless specifically testing the Tauri/React path. The native app reads and writes the existing FlowPilot SQLite database at `~/Library/Application Support/app.flowpilot.desktop/time-manager.sqlite3`. If the database is missing or unreadable, it shows sample data. If the legacy Tauri FlowPilot app is already running, the native collector pauses to avoid double-counting activity.

## macOS Permissions

FlowPilot can run without macOS permissions by reading running app metadata through `NSWorkspace`.
Permission status is still surfaced in the app because richer per-window metadata on macOS requires additional user approval.

Useful for higher quality macOS collection:

- Accessibility: lets FlowPilot read focused app/window metadata such as window titles.
- Screen Recording: lets FlowPilot inspect the visible window list and titles. FlowPilot does not store screenshots or screen pixels.
- Automation for Safari: lets FlowPilot read the active Safari tab URL/title when Safari is frontmost.

Open System Settings > Privacy & Security, grant the permission to FlowPilot, then restart FlowPilot.

For local test builds, grant permissions to the exact `FlowPilot.app` you are launching. The native `/Applications/FlowPilot.app` and the Tauri build output under `src-tauri/target/release/bundle/macos/FlowPilot.app` can appear with the same display name while macOS treats them as different privacy entries.

Local packages are ad-hoc signed with a custom designated requirement:

```text
identifier "app.flowpilot.desktop"
```

The app still has no release signing certificate, but the designated requirement is stable across rebuilds. This avoids
the default ad-hoc behavior where the designated requirement is only the build-specific CDHash, which can make macOS
Privacy & Security rows look enabled while the rebuilt app still sees permissions as missing.

If FlowPilot was previously ad-hoc signed (`signingIdentity = "-"`), macOS may show old enabled privacy rows that are
attached to a stale CDHash. Reset those one time before granting permissions to the locally signed app:

```bash
tccutil reset Accessibility app.flowpilot.desktop
tccutil reset ScreenCapture app.flowpilot.desktop
```

Then install and launch the new `/Applications/FlowPilot.app`, enable FlowPilot in Accessibility and Screen Recording,
and restart FlowPilot. A Developer ID signed and notarized build is still required for distributed releases.

## Browser Domain Tracking

Chrome and Edge use the existing `browser-extension` package. The extension reports active tab domains to `http://127.0.0.1:17321/browser-event`.

After changing extension source, rebuild it before loading or packaging:

```bash
npm run build --prefix browser-extension
```

The SwiftUI native macOS app reads the active Safari tab URL/title through macOS Automation when Safari is frontmost,
then stores the canonical domain. If macOS prompts for Automation permission, allow FlowPilot to control Safari.

A future Safari Web Extension can still use the same payload shape as the Chromium bridge:

```json
{
  "domain": "example.com",
  "title": "Example",
  "url": null
}
```

The app falls back to Safari app/window tracking when Automation permission is denied or the active tab URL is unavailable.

## Local Tauri Packaging

Build an app bundle or DMG:

```bash
source "$HOME/.cargo/env"
npm run package:macos
```

Expected outputs are under `src-tauri/target/release/bundle/`.

`npm run package:macos` is a local development package. Do not upload this DMG or a ZIP containing this DMG to
MyVibeCoding or another external distribution service.

The local `.app` is ad-hoc signed with a stable designated requirement for macOS privacy permission testing. You can
confirm the bundle identity with:

```bash
codesign -dv --verbose=4 src-tauri/target/release/bundle/macos/FlowPilot.app
codesign -dr - src-tauri/target/release/bundle/macos/FlowPilot.app
```

The script pins `LANG` and `LC_ALL` to `en_US.UTF-8`. This avoids a macOS `bundle_dmg.sh` failure where the generated DMG script invokes `perl` while the shell is configured with the Linux-style `C.UTF-8` locale.

For personal installation on another Mac without notarization, build the Tauri personal ZIP instead:

```bash
npm run package:macos:personal
```

Expected output:

```text
release/FlowPilot_personal_mac_arm64.zip
```

Use the included `install-flowpilot-personal.command`; it replaces `/Applications/FlowPilot.app` and removes quarantine.

## SwiftUI Native Packaging

The SwiftUI native macOS app lives under `macos-native/`. Build personal ZIP and DMG packages with:

```bash
npm run package:macos:native
npm run package:macos:native:dmg
```

Expected outputs:

```text
release/FlowPilot_native_mac_arm64.zip
release/FlowPilot_native_mac_arm64.dmg
```

These packages are ad-hoc signed and intended for personal Mac-to-Mac testing. Use `install-flowpilot-native.command`
from the ZIP or DMG to replace `/Applications/FlowPilot.app`, remove quarantine, and launch the installed app bundle. Grant macOS privacy permissions to `/Applications/FlowPilot.app`, not to Terminal or the installer command file.

## Developer ID Signing and Notarization

Direct distribution outside the Mac App Store requires Developer ID signing and notarization.

Release prerequisites:

- Apple Developer Program membership.
- Developer ID Application certificate installed in the macOS keychain.
- Apple Team ID.
- App Store Connect API key or Apple ID notarization credentials.

Use the release packaging script for files that will be downloaded on another Mac:

```bash
APPLE_NOTARY_KEYCHAIN_PROFILE="flowpilot-notary" \
FLOWPILOT_DEVELOPER_ID="Developer ID Application: YOUR_NAME_OR_COMPANY (TEAM_ID)" \
npm run package:macos:release

npm run package:macos:distribution
```

The release script signs and notarizes both `FlowPilot.app` and the DMG, staples the notarization tickets, and runs
Gatekeeper validation with `spctl`. The distribution script refuses to create the upload ZIP unless the DMG has a valid
notarization ticket.

See `docs/macos-distribution.md` for the full setup.

References:

- https://v2.tauri.app/distribute/sign/macos/
- https://v2.tauri.app/distribute/
- https://developer.apple.com/documentation/safariservices/safari-web-extensions
