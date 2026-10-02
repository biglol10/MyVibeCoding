#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$root_dir/scripts/generate-xcode-project.py"
xcodebuild -project "$root_dir/PaneHarbor.xcodeproj" -scheme PaneHarbor \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$root_dir/build/PaneHarbor-local.xcarchive" \
  -derivedDataPath "$root_dir/build/XcodeDerived" CODE_SIGNING_ALLOWED=NO archive
archive_app="$root_dir/build/PaneHarbor-local.xcarchive/Products/Applications/PaneHarbor.app"
# Local verification signing. App Store export needs the owner's distribution identity/profile.
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" --options runtime \
  --timestamp=none --entitlements "$root_dir/Config/PaneHarbor.entitlements" "$archive_app"
codesign --verify --deep --strict "$archive_app"
app_dir="$root_dir/build/PaneHarbor.app"
if [[ -d "$app_dir" ]]; then
  prior_dir="$root_dir/build/backups/local-bundle-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$prior_dir"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app_dir" || true
  mv "$app_dir" "$prior_dir/PaneHarbor.saved-bundle"
  mv "$prior_dir/PaneHarbor.saved-bundle/Contents/Info.plist" "$prior_dir/PaneHarbor.saved-bundle/Contents/Info.restore-plist"
fi
ditto "$archive_app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
lipo -archs "$app_dir/Contents/MacOS/PaneHarbor"
echo "$app_dir"
