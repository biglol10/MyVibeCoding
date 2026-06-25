#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
LOCAL_APP_DIR="$ROOT_DIR/build/MyMacCalendar.app"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacCalendar"
APP_DIR="$PACKAGE_DIR/MyMacCalendar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
ZIP_PATH="$DIST_DIR/MyMacCalendar-test-build.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
INSTALLER_SOURCE="$ROOT_DIR/scripts/install.command"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$LOCAL_APP_DIR" "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/MyMacCalendar" "$MACOS_DIR/MyMacCalendar"
cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MyMacCalendar</string>
    <key>CFBundleIdentifier</key>
    <string>local.mymaccalendar.app</string>
    <key>CFBundleName</key>
    <string>MyMacCalendar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$FIRST_RUN_SOURCE" "$PACKAGE_DIR/Open MyMacCalendar.command"
cp "$INSTALLER_SOURCE" "$PACKAGE_DIR/Install MyMacCalendar.command"
chmod +x "$PACKAGE_DIR/Open MyMacCalendar.command"
chmod +x "$PACKAGE_DIR/Install MyMacCalendar.command"
cat > "$PACKAGE_DIR/READ ME FIRST.txt" <<'README'
MyMacCalendar test build

If macOS says the app is damaged or should be moved to Trash, do not open
MyMacCalendar.app directly.

Install on your personal Mac:
1. Open this folder after unzipping.
2. Double-click "Install MyMacCalendar.command".
3. The installer removes macOS download quarantine, copies MyMacCalendar.app to
   /Applications, verifies the installed app, and opens it.

Run without installing:
Double-click "Open MyMacCalendar.command".

For a double-clickable public release, build with a Developer ID Application
certificate and Apple notarization credentials.
README

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

mkdir -p "$(dirname "$LOCAL_APP_DIR")"
ditto "$APP_DIR" "$LOCAL_APP_DIR"

echo "$PACKAGE_DIR"
echo "$APP_DIR"
echo "$LOCAL_APP_DIR"
echo "$ZIP_PATH"
