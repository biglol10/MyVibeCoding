#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacClean"
APP_DIR="$PACKAGE_DIR/MyMacClean.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/MyMacClean-test-build.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
FIRST_RUN_COMMAND="$PACKAGE_DIR/처음 실행하기.command"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/MyMacCleanApp" "$MACOS_DIR/MyMacCleanApp"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns" "$RESOURCES_DIR/MyMacCleanIcon.icns"
cp "$FIRST_RUN_SOURCE" "$FIRST_RUN_COMMAND"
chmod +x "$MACOS_DIR/MyMacCleanApp"
chmod +x "$FIRST_RUN_COMMAND"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

echo "$PACKAGE_DIR"
echo "$APP_DIR"
echo "$ZIP_PATH"
