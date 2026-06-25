#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP_PATH="$SCRIPT_DIR/MyMacCalendar.app"
INSTALL_DIR="${MYMACCALENDAR_INSTALL_DIR:-/Applications}"
INSTALL_APP_PATH="$INSTALL_DIR/MyMacCalendar.app"

echo "MyMacCalendar personal Mac installer"
echo

if [ ! -d "$SOURCE_APP_PATH" ]; then
    echo "Error: MyMacCalendar.app was not found next to this installer."
    echo "After unzipping, keep MyMacCalendar.app and this command in the same MyMacCalendar folder."
    exit 1
fi

if command -v xattr >/dev/null 2>&1; then
    echo "Removing macOS download quarantine from this package..."
    xattr -cr "$SCRIPT_DIR" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
fi

if ! codesign --verify --deep --strict "$SOURCE_APP_PATH" >/dev/null 2>&1; then
    echo "Error: MyMacCalendar.app failed local code signature verification."
    echo "Download the package again from the release page."
    exit 1
fi

mkdir -p "$INSTALL_DIR"
echo "Installing MyMacCalendar to $INSTALL_APP_PATH..."
rm -rf "$INSTALL_APP_PATH"
cp -R "$SOURCE_APP_PATH" "$INSTALL_APP_PATH"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$INSTALL_APP_PATH" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$INSTALL_APP_PATH" 2>/dev/null || true
fi

if ! codesign --verify --deep --strict "$INSTALL_APP_PATH" >/dev/null 2>&1; then
    echo "Error: installed MyMacCalendar.app failed local code signature verification."
    rm -rf "$INSTALL_APP_PATH"
    exit 1
fi

echo "Opening installed MyMacCalendar..."
open "$INSTALL_APP_PATH"
echo
echo "Installed at $INSTALL_APP_PATH"
