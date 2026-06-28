#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$ROOT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_DIR/release/FlowPilot_native_mac_arm64"
DMG_ROOT="/private/tmp/flowpilot-native-dmg-$$"
DMG_PATH="$REPO_DIR/release/FlowPilot_native_mac_arm64.dmg"

"$ROOT_DIR/scripts/package-personal.sh" >/dev/null

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"

cp -R "$PACKAGE_DIR/FlowPilot.app" "$DMG_ROOT/FlowPilot.app"
cp "$PACKAGE_DIR/README_INSTALL.txt" "$DMG_ROOT/README_INSTALL.txt"
cp "$PACKAGE_DIR/install-flowpilot-native.command" "$DMG_ROOT/install-flowpilot-native.command"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "FlowPilot Native" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

rm -rf "$DMG_ROOT"

echo "$DMG_PATH"
