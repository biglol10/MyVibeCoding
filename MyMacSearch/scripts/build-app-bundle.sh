#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${MYMACSEARCH_BUILD_DIR:-$ROOT_DIR/build}"
APP_BUNDLE="$BUILD_DIR/MyMacSearch.app"
BUILD_STAGE="$BUILD_DIR/.MyMacSearch.app.building.$$"

cleanup() {
  rm -rf "$BUILD_STAGE"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_STAGE"

swift build --package-path "$ROOT_DIR" --configuration release
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration release --show-bin-path)"
EXECUTABLE="$BIN_DIR/MyMacSearchApp"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Release executable was not produced: $EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$BUILD_STAGE/Contents/MacOS" "$BUILD_STAGE/Contents/Resources"
ditto "$EXECUTABLE" "$BUILD_STAGE/Contents/MacOS/MyMacSearchApp"
ditto "$ROOT_DIR/Sources/MyMacSearchApp/Resources/MyMacSearchInfo.plist" "$BUILD_STAGE/Contents/Info.plist"
ditto "$ROOT_DIR/Sources/MyMacSearchApp/Resources/AppIcon.icns" "$BUILD_STAGE/Contents/Resources/AppIcon.icns"
chmod 755 "$BUILD_STAGE/Contents/MacOS/MyMacSearchApp"

plutil -lint "$BUILD_STAGE/Contents/Info.plist" >/dev/null
xattr -cr "$BUILD_STAGE" 2>/dev/null || true
codesign --force --deep --sign - "$BUILD_STAGE" >/dev/null
codesign --verify --deep --strict --verbose=2 "$BUILD_STAGE"

rm -rf "$APP_BUNDLE"
mv "$BUILD_STAGE" "$APP_BUNDLE"
trap - EXIT

echo "Built: $APP_BUNDLE"
