#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacStats.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/MyMacStats-test-build.zip"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/MyMacStatsApp" "$MACOS_DIR/MyMacStatsApp"
cp "$ROOT_DIR/Sources/MyMacStatsApp/Resources/MyMacStatsInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacStatsApp/Resources/MyMacStatsIcon.icns" "$RESOURCES_DIR/MyMacStatsIcon.icns"
chmod +x "$MACOS_DIR/MyMacStatsApp"

if command -v strip >/dev/null 2>&1; then
    strip -x "$MACOS_DIR/MyMacStatsApp"
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$ZIP_PATH"
