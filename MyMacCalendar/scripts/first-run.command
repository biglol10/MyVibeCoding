#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/MyMacCalendar.app"

echo "MyMacCalendar first-run helper"
echo

if [ ! -d "$APP_PATH" ]; then
    echo "Error: MyMacCalendar.app was not found next to this helper."
    echo "After unzipping, keep MyMacCalendar.app and this command in the same MyMacCalendar folder."
    exit 1
fi

if command -v xattr >/dev/null 2>&1; then
    echo "Removing macOS download quarantine from the MyMacCalendar package..."
    xattr -cr "$SCRIPT_DIR" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
else
    echo "xattr was not found; skipping quarantine cleanup."
fi

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "Error: MyMacCalendar.app failed local code signature verification."
    echo "Download the package again from the release page."
    exit 1
fi

echo "Opening MyMacCalendar..."
open "$APP_PATH"
echo
echo "If macOS still blocks the app, open System Settings > Privacy & Security and allow MyMacCalendar."
