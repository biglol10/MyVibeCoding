#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MyMacCalendar"
BUILD_DIR=""
LOCAL_APP_DIR="$ROOT_DIR/build/MyMacCalendar.app"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacCalendar"
PACKAGE_APP_DIR="$PACKAGE_DIR/MyMacCalendar.app"
ZIP_PATH="$DIST_DIR/MyMacCalendar-test-build.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
INSTALLER_SOURCE="$ROOT_DIR/scripts/install.command"
APP_DIR="$LOCAL_APP_DIR"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/mymaccalendar-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/mymaccalendar-swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"
BUILD_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
swift build -c release --disable-sandbox

EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build product not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$LOCAL_APP_DIR" "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
fi
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.mymaccalendar.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"
/usr/bin/touch "$APP_DIR"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

mkdir -p "$PACKAGE_DIR"
ditto "$APP_DIR" "$PACKAGE_APP_DIR"
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
  xattr -cr "$PACKAGE_DIR" 2>/dev/null || true
fi

codesign --verify --deep --strict "$PACKAGE_APP_DIR"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

echo "$APP_DIR"
echo "$PACKAGE_DIR"
echo "$PACKAGE_APP_DIR"
echo "$ZIP_PATH"
