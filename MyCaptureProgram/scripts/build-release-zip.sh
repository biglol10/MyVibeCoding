#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/CaptureStudio"
EXECUTABLE_PATH="$PACKAGE_DIR/CaptureStudio"
ZIP_PATH="$DIST_DIR/CaptureStudio-macos-arm64.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
FIRST_RUN_COMMAND="$PACKAGE_DIR/처음 실행하기.command"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR"

cp "$ROOT_DIR/.build/release/CaptureStudio" "$EXECUTABLE_PATH"
cp "$FIRST_RUN_SOURCE" "$FIRST_RUN_COMMAND"
chmod +x "$EXECUTABLE_PATH" "$FIRST_RUN_COMMAND"

if command -v strip >/dev/null 2>&1; then
    strip -x "$EXECUTABLE_PATH"
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

codesign --force --sign "$SIGN_IDENTITY" "$EXECUTABLE_PATH"
codesign --verify --strict "$EXECUTABLE_PATH"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

echo "$PACKAGE_DIR"
echo "$EXECUTABLE_PATH"
echo "$ZIP_PATH"
