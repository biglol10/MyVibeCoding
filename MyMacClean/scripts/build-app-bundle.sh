#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MyMacClean.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT_DIR/.build/xdg-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH" "$ROOT_DIR/.build/swiftpm-cache"

swift build \
  -c release \
  --package-path "$ROOT_DIR" \
  --disable-sandbox \
  --cache-path "$ROOT_DIR/.build/swiftpm-cache" \
  --manifest-cache local

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/MyMacCleanApp" "$MACOS_DIR/MyMacCleanApp"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns" "$RESOURCES_DIR/MyMacCleanIcon.icns"
chmod +x "$MACOS_DIR/MyMacCleanApp"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
