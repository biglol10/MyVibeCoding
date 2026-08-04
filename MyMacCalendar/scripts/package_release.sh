#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${MYMACCALENDAR_APP_NAME:-MyMacCalendar}"
BUNDLE_ID="${MYMACCALENDAR_BUNDLE_ID:-com.mymaccalendar.app}"
VERSION="${MYMACCALENDAR_VERSION:-0.1.0}"
BUILD_NUMBER="${MYMACCALENDAR_BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${MYMACCALENDAR_OUTPUT_DIR:-$ROOT_DIR/dist}"
WORK_DIR="$OUTPUT_DIR/release-work"
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
ENTITLEMENTS="$ROOT_DIR/Resources/MyMacCalendar.entitlements"
DEVELOPER_ID="${MYMACCALENDAR_DEVELOPER_ID:-}"
NOTARY_PROFILE="${MYMACCALENDAR_NOTARY_PROFILE:-}"
PRE_NOTARY_ZIP="$WORK_DIR/$APP_NAME-notary-upload.zip"
FINAL_ZIP="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip"

case "$CONFIGURATION" in
  release) ;;
  *)
    echo "Release packaging must use CONFIGURATION=release." >&2
    exit 2
    ;;
esac

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

if [[ -z "$DEVELOPER_ID" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/\"Developer ID Application:/{ print $2; exit }')"
fi

if [[ -z "$DEVELOPER_ID" ]]; then
  echo "No Developer ID Application signing identity found." >&2
  echo "Install an Apple Developer ID Application certificate, or set MYMACCALENDAR_DEVELOPER_ID." >&2
  echo "Do not upload ad-hoc signed builds; Gatekeeper will reject them on other Macs." >&2
  exit 2
fi

IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$DEVELOPER_ID" || true)"
if [[ "$IDENTITY_LINE" != *"Developer ID Application:"* && "$DEVELOPER_ID" != Developer\ ID\ Application:* ]]; then
  echo "Signing identity is not a Developer ID Application identity: $DEVELOPER_ID" >&2
  echo "Use a Developer ID Application certificate for downloadable macOS distribution." >&2
  exit 2
fi

NOTARY_ARGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
else
  APPLE_ID="${MYMACCALENDAR_APPLE_ID:-}"
  TEAM_ID="${MYMACCALENDAR_TEAM_ID:-}"
  APP_SPECIFIC_PASSWORD="${MYMACCALENDAR_APP_SPECIFIC_PASSWORD:-}"
  if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_SPECIFIC_PASSWORD" ]]; then
    echo "No notarization credentials provided." >&2
    echo "Either set MYMACCALENDAR_NOTARY_PROFILE after running:" >&2
    echo "  xcrun notarytool store-credentials mymaccalendar-notary" >&2
    echo "or set MYMACCALENDAR_APPLE_ID, MYMACCALENDAR_TEAM_ID, and MYMACCALENDAR_APP_SPECIFIC_PASSWORD." >&2
    exit 2
  fi
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
BUILD_ARGS=(--package-path "$ROOT_DIR" -c "$CONFIGURATION")
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
swift build "${BUILD_ARGS[@]}"

EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build product not found: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
fi

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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
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

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

echo "Signing with Developer ID Application identity: $DEVELOPER_ID"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$PRE_NOTARY_ZIP" "$FINAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PRE_NOTARY_ZIP"

echo "Submitting to Apple notarization..."
xcrun notarytool submit "$PRE_NOTARY_ZIP" "${NOTARY_ARGS[@]}" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "Assessing with Gatekeeper..."
spctl -a -vvv -t execute "$APP_BUNDLE"

echo "Creating final distributable zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
/usr/bin/unzip -tq "$FINAL_ZIP"

echo "Created notarized release archive: $FINAL_ZIP"
