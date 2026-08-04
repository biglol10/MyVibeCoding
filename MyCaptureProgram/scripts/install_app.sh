#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CAPTURE_STUDIO_APP_NAME:-CaptureStudio}"
BUNDLE_ID="${CAPTURE_STUDIO_BUNDLE_ID:-com.capturestudio.mac}"
CONFIGURATION="${CONFIGURATION:-release}"
DESTINATION="${1:-/Applications}"
SIGN_IDENTITY="${CAPTURE_STUDIO_CODE_SIGN_IDENTITY:-}"

if [[ "$EUID" -eq 0 ]]; then
  echo "Do not run this entire script with sudo." >&2
  echo "Run it as your normal user; the script requests installation permission only if needed." >&2
  exit 2
fi

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
    echo "Use CONFIGURATION=debug or CONFIGURATION=release." >&2
    exit 2
    ;;
esac

ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "App icon not found: $ICON_SOURCE" >&2
  echo "Generate it with: swift scripts/generate_app_icon.swift" >&2
  exit 1
fi

APP_BUNDLE="$DESTINATION/$APP_NAME.app"
APP_INSTALLING="$DESTINATION/.$APP_NAME.installing.$$.app"
APP_BACKUP="$DESTINATION/.$APP_NAME.previous.$$.app"
USE_SUDO=0

if [[ ! -d "$DESTINATION" ]]; then
  if ! mkdir -p "$DESTINATION" 2>/dev/null; then
    command -v sudo >/dev/null 2>&1 || {
      echo "Destination cannot be created: $DESTINATION" >&2
      exit 1
    }
    sudo mkdir -p "$DESTINATION"
  fi
fi
if [[ ! -w "$DESTINATION" ]]; then
  command -v sudo >/dev/null 2>&1 || {
    echo "Destination is not writable: $DESTINATION" >&2
    exit 1
  }
  sudo -v
  USE_SUDO=1
fi

run_install_command() {
  if [[ "$USE_SUDO" -eq 1 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

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

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/CaptureStudio-install.XXXXXX")"
STAGED_APP="$STAGING_ROOT/$APP_NAME.app"
CONTENTS_DIR="$STAGED_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

cleanup_staging() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup_staging EXIT

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
  codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGED_APP" >/dev/null
else
  echo "Warning: no stable code signing identity found; falling back to ad-hoc signing." >&2
  codesign --force --deep --sign - "$STAGED_APP" >/dev/null
fi
/usr/bin/touch "$STAGED_APP"

restore_previous_install() {
  run_install_command rm -rf "$APP_INSTALLING" 2>/dev/null || true
  if [[ ! -e "$APP_BUNDLE" && -e "$APP_BACKUP" ]]; then
    run_install_command mv "$APP_BACKUP" "$APP_BUNDLE" 2>/dev/null || true
  fi
  cleanup_staging
}
trap restore_previous_install EXIT

run_install_command rm -rf "$APP_INSTALLING" "$APP_BACKUP"
run_install_command ditto "$STAGED_APP" "$APP_INSTALLING"
if [[ -e "$APP_BUNDLE" ]]; then
  run_install_command mv "$APP_BUNDLE" "$APP_BACKUP"
fi
if ! run_install_command mv "$APP_INSTALLING" "$APP_BUNDLE"; then
  echo "Installation failed; restoring the previous app." >&2
  exit 1
fi
run_install_command rm -rf "$APP_BACKUP"
cleanup_staging
trap - EXIT

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Installed $APP_BUNDLE"
echo "Bundle identifier: $BUNDLE_ID"
