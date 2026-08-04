#!/usr/bin/env bash
set -euo pipefail

configuration="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --configuration=*)
      configuration="${1#*=}"
      shift
      ;;
    *)
      echo "Usage: $0 [--configuration debug|release]" >&2
      exit 2
      ;;
  esac
done

case "$configuration" in
  debug|release) ;;
  *)
    echo "Usage: $0 [--configuration debug|release]" >&2
    exit 2
    ;;
esac

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
icon_file="$root_dir/Sources/MyMacFinder/Resources/AppIcon.icns"

if [[ ! -f "$icon_file" ]]; then
  echo "error: missing app icon: $icon_file" >&2
  exit 1
fi

swift build --configuration "$configuration" --package-path "$root_dir"
bin_dir="$(swift build --configuration "$configuration" --package-path "$root_dir" --show-bin-path)"
executable="$bin_dir/MyMacFinder"

if [[ ! -x "$executable" ]]; then
  echo "error: missing executable: $executable" >&2
  exit 1
fi

app_dir="$root_dir/.build/app/MyMacFinder.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$executable" "$macos_dir/MyMacFinder"
cp "$icon_file" "$resources_dir/AppIcon.icns"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>MyMacFinder</string>
  <key>CFBundleExecutable</key>
  <string>MyMacFinder</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.biglol.MyMacFinder</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MyMacFinder</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$macos_dir/MyMacFinder"

echo "$app_dir"
