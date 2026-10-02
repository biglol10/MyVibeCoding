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
icon_file="$root_dir/Sources/PaneHarbor/Resources/AppIcon.icns"

if [[ ! -f "$icon_file" ]]; then
  echo "error: missing app icon: $icon_file" >&2
  exit 1
fi

swift build --configuration "$configuration" --package-path "$root_dir"
bin_dir="$(swift build --configuration "$configuration" --package-path "$root_dir" --show-bin-path)"
executable="$bin_dir/PaneHarbor"

if [[ ! -x "$executable" ]]; then
  echo "error: missing executable: $executable" >&2
  exit 1
fi

app_dir="$root_dir/.build/app/PaneHarbor.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$executable" "$macos_dir/PaneHarbor"
cp "$icon_file" "$resources_dir/AppIcon.icns"
cp -R "$root_dir/Sources/PaneHarbor/Resources/en.lproj" "$resources_dir/"
cp -R "$root_dir/Sources/PaneHarbor/Resources/ko.lproj" "$resources_dir/"
cp "$root_dir/Sources/PaneHarbor/Resources/PrivacyInfo.xcprivacy" "$resources_dir/PrivacyInfo.xcprivacy"
cp "$root_dir/Sources/PaneHarbor/Resources/ThirdPartyNotices.txt" "$resources_dir/ThirdPartyNotices.txt"

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>PaneHarbor</string>
  <key>CFBundleExecutable</key>
  <string>PaneHarbor</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.biglol.paneharbor.mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PaneHarbor</string>
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
  <key>PaneHarborSupportsExternalFolderOpen</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.biglol.paneharbor.mac.open</string>
      <key>CFBundleURLSchemes</key><array><string>paneharbor</string></array>
      <key>CFBundleTypeRole</key><string>Viewer</string>
    </dict>
  </array>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Open in PaneHarbor</string></dict>
      <key>NSMessage</key><string>openInPaneHarbor</string>
      <key>NSPortName</key><string>PaneHarbor</string>
      <key>NSSendTypes</key>
      <array>
        <string>public.file-url</string>
        <string>NSFilenamesPboardType</string>
        <string>NSStringPboardType</string>
      </array>
      <key>NSRequiredContext</key><dict/>
    </dict>
  </array>
</dict>
</plist>
PLIST

chmod +x "$macos_dir/PaneHarbor"

echo "$app_dir"
