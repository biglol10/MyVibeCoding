#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CAPTURE_STUDIO_APP_NAME:-CaptureStudio}"
BUNDLE_ID="${CAPTURE_STUDIO_BUNDLE_ID:-com.capturestudio.mac}"
VERSION="${CAPTURE_STUDIO_VERSION:-0.1.0}"
BUILD_NUMBER="${CAPTURE_STUDIO_BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${CAPTURE_STUDIO_OUTPUT_DIR:-$ROOT_DIR/dist}"
WORK_DIR="$OUTPUT_DIR/release-work"
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
ENTITLEMENTS="$ROOT_DIR/Resources/CaptureStudio.entitlements"
DEVELOPER_ID="${CAPTURE_STUDIO_DEVELOPER_ID:-}"
NOTARY_PROFILE="${CAPTURE_STUDIO_NOTARY_PROFILE:-}"
PRE_NOTARY_ZIP="$WORK_DIR/$APP_NAME-notary-upload.zip"
FINAL_ZIP="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS.zip"

case "$CONFIGURATION" in
  release) ;;
  *)
    echo "Release packaging must use CONFIGURATION=release." >&2
    exit 2
    ;;
esac

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "App icon not found: $ICON_SOURCE" >&2
  echo "Generate it with: swift scripts/generate_app_icon.swift" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

if [[ -z "$DEVELOPER_ID" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/"Developer ID Application:/{ print $2; exit }')"
fi

if [[ -z "$DEVELOPER_ID" ]]; then
  echo "No Developer ID Application signing identity found." >&2
  echo "Install an Apple Developer ID Application certificate, or set CAPTURE_STUDIO_DEVELOPER_ID." >&2
  echo "Do not upload Apple Development or ad-hoc signed builds; Gatekeeper will reject them on other Macs." >&2
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
  APPLE_ID="${CAPTURE_STUDIO_APPLE_ID:-}"
  TEAM_ID="${CAPTURE_STUDIO_TEAM_ID:-}"
  APP_SPECIFIC_PASSWORD="${CAPTURE_STUDIO_APP_SPECIFIC_PASSWORD:-}"
  if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_SPECIFIC_PASSWORD" ]]; then
    echo "No notarization credentials provided." >&2
    echo "Either set CAPTURE_STUDIO_NOTARY_PROFILE after running:" >&2
    echo "  xcrun notarytool store-credentials capturestudio-notary" >&2
    echo "or set CAPTURE_STUDIO_APPLE_ID, CAPTURE_STUDIO_TEAM_ID, and CAPTURE_STUDIO_APP_SPECIFIC_PASSWORD." >&2
    exit 2
  fi
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
BUILD_ARGS=(--package-path "$ROOT_DIR" -c "$CONFIGURATION")
if [[ -n "${CAPTURE_STUDIO_ARCHS:-}" ]]; then
  read -r -a ARCHS <<< "$CAPTURE_STUDIO_ARCHS"
  for arch in "${ARCHS[@]}"; do
    BUILD_ARGS+=(--arch "$arch")
  done
fi
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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
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
