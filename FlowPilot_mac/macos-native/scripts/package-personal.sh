#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$ROOT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_DIR/release/FlowPilot_native_mac_arm64"
APP_SOURCE="$ROOT_DIR/.build/FlowPilotNative.app"
APP_DEST="$PACKAGE_DIR/FlowPilot.app"
ZIP_PATH="$REPO_DIR/release/FlowPilot_native_mac_arm64.zip"

"$ROOT_DIR/scripts/build-dev-app.sh" >/dev/null

rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR/Chrome_Extension"
cp -R "$APP_SOURCE" "$APP_DEST"

if [ -d "$REPO_DIR/browser-extension" ]; then
  cp -R "$REPO_DIR/browser-extension/manifest.json" "$PACKAGE_DIR/Chrome_Extension/manifest.json"
  if [ -d "$REPO_DIR/browser-extension/dist" ]; then
    cp -R "$REPO_DIR/browser-extension/dist" "$PACKAGE_DIR/Chrome_Extension/dist"
  fi
fi

cat > "$PACKAGE_DIR/README_INSTALL.txt" <<'README'
FlowPilot Swift Native macOS beta

This package contains the SwiftUI native macOS version of FlowPilot.

Current status:
- Reads the existing FlowPilot database.
- Collects macOS foreground app/window activity natively.
- Receives Chrome/Edge browser extension events on 127.0.0.1:17321.
- Enriches browser sessions by tab domain.
- Reads the active Safari tab URL through macOS automation when Safari is frontmost, then stores the canonical domain.
- Shows native SwiftUI Today, Timeline, Weekly Report, Uncategorized Review, and Rules screens.
- Adds a macOS menu bar item with today's quick summary.

Known beta gaps:
- This build is unsigned and intended for personal local testing.
- Developer ID signing and notarization are still separate release steps.

Install:
1. Run install-flowpilot-native.command.
2. If macOS blocks opening the app, run:
   xattr -dr com.apple.quarantine /Applications/FlowPilot.app
3. Open FlowPilot from Applications.

Permissions:
- Allow Accessibility for accurate app/window metadata.
- Allow Screen Recording if macOS requires it for visible window titles.
- Allow Automation if macOS asks whether FlowPilot may control Safari. This is used only to read Safari's active tab URL/title.
- FlowPilot does not save screen images.
README

cat > "$PACKAGE_DIR/install-flowpilot-native.command" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/FlowPilot.app"
INSTALL_DIR="${FLOWPILOT_INSTALL_DIR:-/Applications}"
APP_DEST="$INSTALL_DIR/FlowPilot.app"

osascript -e 'quit app id "app.flowpilot.desktop"' >/dev/null 2>&1 || true
osascript -e 'quit app id "app.flowpilot.native"' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$INSTALL_DIR"
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" >/dev/null 2>&1 || true
codesign --verify --deep --strict "$APP_DEST"
open "$APP_DEST"

echo "Installed FlowPilot Swift Native to $APP_DEST"
INSTALL

chmod +x "$PACKAGE_DIR/install-flowpilot-native.command"

(
  cd "$REPO_DIR/release"
  zip -qry "$(basename "$ZIP_PATH")" "$(basename "$PACKAGE_DIR")"
)

echo "$PACKAGE_DIR"
echo "$ZIP_PATH"
