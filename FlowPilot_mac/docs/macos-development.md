# FlowPilot macOS Development and Packaging

## Development Run

From `/Users/biglol/Desktop/practice/FlowPilot_mac`:

```bash
npm install
npm install --prefix browser-extension
source "$HOME/.cargo/env"
npm run tauri dev
```

FlowPilot stores local app data under the Tauri app data directory and uses SQLite for sessions, rules, browser events, and macOS window observations.

## macOS Permissions

FlowPilot can run without macOS permissions by reading running app metadata through `NSWorkspace`.
Permission status is still surfaced in the app because richer per-window metadata on macOS requires additional user approval.

Useful for higher quality macOS collection:

- Accessibility: lets FlowPilot read focused app/window metadata such as window titles.
- Screen Recording: lets FlowPilot inspect the visible window list and titles. FlowPilot does not store screenshots or screen pixels.

Open System Settings > Privacy & Security, grant the permission to FlowPilot, then restart FlowPilot.

For local test builds, grant permissions to the exact `FlowPilot.app` you are launching. A copied app in
`/Applications` and the build output under `src-tauri/target/release/bundle/macos/FlowPilot.app` can appear with the same
display name while macOS treats them as different privacy entries.

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

Safari domain tracking requires a Safari Web Extension packaged through Xcode. The future Safari extension should send the same payload shape as the Chromium bridge:

```json
{
  "domain": "example.com",
  "title": "Example",
  "url": null
}
```

Until that package exists, Safari sessions are classified by app name and window title.

## Unsigned Local Packaging

Build an app bundle or DMG:

```bash
source "$HOME/.cargo/env"
npm run package:macos
```

Expected outputs are under `src-tauri/target/release/bundle/`.

The local `.app` is ad-hoc signed with a stable designated requirement for macOS privacy permission testing. You can
confirm the bundle identity with:

```bash
codesign -dv --verbose=4 src-tauri/target/release/bundle/macos/FlowPilot.app
codesign -dr - src-tauri/target/release/bundle/macos/FlowPilot.app
```

The script pins `LANG` and `LC_ALL` to `en_US.UTF-8`. This avoids a macOS `bundle_dmg.sh` failure where the generated DMG script invokes `perl` while the shell is configured with the Linux-style `C.UTF-8` locale.

## Developer ID Signing and Notarization

Direct distribution outside the Mac App Store requires Developer ID signing and notarization.

Release prerequisites:

- Apple Developer Program membership.
- Developer ID Application certificate installed in the macOS keychain.
- Apple Team ID.
- App Store Connect API key or Apple ID notarization credentials.

Configure Tauri's macOS signing and notarization environment variables according to the official Tauri macOS signing guide, then rebuild the DMG. Notarized releases should be stapled before distribution.

References:

- https://v2.tauri.app/distribute/sign/macos/
- https://v2.tauri.app/distribute/
- https://developer.apple.com/documentation/safariservices/safari-web-extensions
