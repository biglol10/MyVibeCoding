#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacClean.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/MyMacClean-dev.dmg"
ZIP_PATH="$DIST_DIR/MyMacClean-dev.zip"

"$ROOT_DIR/scripts/build-app-bundle.sh"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/MyMacClean.app"
rm -f "$DMG_PATH"
if hdiutil create -volname "MyMacClean" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"; then
  echo "$DMG_PATH"
else
  echo "hdiutil failed; creating zip fallback at $ZIP_PATH" >&2
  rm -f "$ZIP_PATH"
  (cd "$DMG_ROOT" && ditto -c -k --sequesterRsrc --keepParent MyMacClean.app "$ZIP_PATH")
  echo "$ZIP_PATH"
fi
