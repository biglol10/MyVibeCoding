#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacClean.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/MyMacCleanApp" "$MACOS_DIR/MyMacCleanApp"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns" "$RESOURCES_DIR/MyMacCleanIcon.icns"
chmod +x "$MACOS_DIR/MyMacCleanApp"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
