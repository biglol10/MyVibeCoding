#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/MyMacClean.app"

echo "MyMacClean first-run helper"
echo

if [ ! -d "$APP_PATH" ]; then
    echo "Error: MyMacClean.app was not found next to this helper."
    echo "After unzipping, keep MyMacClean.app and this command in the same MyMacClean folder."
    exit 1
fi

if command -v xattr >/dev/null 2>&1; then
    echo "Removing macOS download quarantine from the MyMacClean package..."
    xattr -cr "$SCRIPT_DIR" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
else
    echo "xattr was not found; skipping quarantine cleanup."
fi

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "Error: MyMacClean.app failed local code signature verification."
    echo "Download the package again from the release page."
    exit 1
fi

echo "Opening MyMacClean..."
open "$APP_PATH"
echo
echo "If macOS still blocks the app, open System Settings > Privacy & Security and allow MyMacClean."
