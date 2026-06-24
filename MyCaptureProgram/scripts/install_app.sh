#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CAPTURE_STUDIO_APP_NAME:-CaptureStudio}"
BUNDLE_ID="${CAPTURE_STUDIO_BUNDLE_ID:-com.capturestudio.mac}"
CONFIGURATION="${CONFIGURATION:-release}"
DESTINATION="${1:-/Applications}"
SIGN_IDENTITY="${CAPTURE_STUDIO_CODE_SIGN_IDENTITY:-}"

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
    echo "Use CONFIGURATION=debug or CONFIGURATION=release." >&2
    exit 2
    ;;
esac

echo "Building $APP_NAME ($CONFIGURATION)..."
echo "Local install only. Do not upload this app bundle or a zip made from it for distribution."
echo "For MyVibeCoding or another download site, use scripts/package_release.sh."
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"
swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"

EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build product not found: $EXECUTABLE" >&2
  exit 1
fi

ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "App icon not found: $ICON_SOURCE" >&2
  echo "Generate it with: swift scripts/generate_app_icon.swift" >&2
  exit 1
fi

if [[ ! -d "$DESTINATION" ]]; then
  mkdir -p "$DESTINATION"
fi

if [[ ! -w "$DESTINATION" ]]; then
  echo "Destination is not writable: $DESTINATION" >&2
  echo "Install to a writable folder or rerun with permission for that destination." >&2
  echo "Example: sudo $0 $DESTINATION" >&2
  exit 1
fi

APP_BUNDLE="$DESTINATION/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
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
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>CaptureStudio can include audio when recording selected screen areas.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>CaptureStudio needs screen access to capture screenshots and record selected screen areas.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/"Apple Development:/{ print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/"/{ print $2; exit }')"
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
else
  echo "Warning: no stable code signing identity found; falling back to ad-hoc signing." >&2
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi
/usr/bin/touch "$APP_BUNDLE"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Installed $APP_BUNDLE"
echo "Bundle identifier: $BUNDLE_ID"
