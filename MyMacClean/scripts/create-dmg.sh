#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacClean"
APP_DIR="$PACKAGE_DIR/MyMacClean.app"
FIRST_RUN_COMMAND="$PACKAGE_DIR/처음 실행하기.command"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/MyMacClean-dev.dmg"

"$ROOT_DIR/scripts/build-app-bundle.sh"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/MyMacClean.app"
cp "$FIRST_RUN_COMMAND" "$DMG_ROOT/처음 실행하기.command"
chmod +x "$DMG_ROOT/처음 실행하기.command"
if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$DMG_ROOT"
fi
rm -f "$DMG_PATH"
hdiutil create -volname "MyMacClean" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
echo "$DMG_PATH"
