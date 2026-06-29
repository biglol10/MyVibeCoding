#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$ROOT_DIR/Sources/MyMacFinder/Resources"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
PREVIEW_PNG="$RESOURCES_DIR/AppIcon.png"
ICNS_FILE="$RESOURCES_DIR/AppIcon.icns"
BUNDLE_SCRIPT="$ROOT_DIR/scripts/create-app-bundle.sh"

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_png_size() {
  local path="$1"
  local expected_width="$2"
  local expected_height="$3"
  local width height

  assert_file "$path"
  width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

  [[ "$width" == "$expected_width" ]] || fail "$path width was $width, expected $expected_width"
  [[ "$height" == "$expected_height" ]] || fail "$path height was $height, expected $expected_height"
}

assert_png_size "$PREVIEW_PNG" 1024 1024

required_icon_sizes=(
  "icon_16x16.png 16 16"
  "icon_16x16@2x.png 32 32"
  "icon_32x32.png 32 32"
  "icon_32x32@2x.png 64 64"
  "icon_128x128.png 128 128"
  "icon_128x128@2x.png 256 256"
  "icon_256x256.png 256 256"
  "icon_256x256@2x.png 512 512"
  "icon_512x512.png 512 512"
  "icon_512x512@2x.png 1024 1024"
)

for icon_size in "${required_icon_sizes[@]}"; do
  read -r filename width height <<< "$icon_size"
  assert_png_size "$ICONSET_DIR/$filename" "$width" "$height"
done

assert_file "$ICNS_FILE"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
iconutil -c iconset "$ICNS_FILE" -o "$tmp_dir/AppIcon.iconset"
assert_file "$tmp_dir/AppIcon.iconset/icon_512x512@2x.png"

[[ -x "$BUNDLE_SCRIPT" ]] || fail "missing executable bundle script: $BUNDLE_SCRIPT"
"$BUNDLE_SCRIPT" --configuration debug

APP_BUNDLE="$ROOT_DIR/.build/app/MyMacFinder.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/MyMacFinder"

assert_file "$INFO_PLIST"
assert_file "$APP_ICON"
assert_file "$APP_EXECUTABLE"

bundle_icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")"
[[ "$bundle_icon_name" == "AppIcon" ]] || fail "CFBundleIconFile was $bundle_icon_name, expected AppIcon"

echo "App icon verification passed"
