#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist
if [ ! -d Editor/node_modules ]; then npm --prefix Editor ci; fi
npm --prefix Editor run build > build/editor-build.log 2>&1
node scripts/collect-licenses.mjs
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Sources/App/Resources/AppIcon.icns
python3 scripts/generate-project.py
if ! xcodebuild -project MyMarkdownViewer.xcodeproj -scheme MyMarkdownViewer -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build > build/xcodebuild.log 2>&1; then
    tail -80 build/xcodebuild.log
    exit 1
fi
if [ -d dist/MyMarkdownViewer.app ]; then
    markdown_previous_release="$(mktemp -d "$PWD/build/previous-release.XXXXXX")"
    mv dist/MyMarkdownViewer.app "$markdown_previous_release/MyMarkdownViewer.app"
fi
ditto build/DerivedData/Build/Products/Release/MyMarkdownViewer.app dist/MyMarkdownViewer.app
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --entitlements Resources/MyMarkdownViewer.entitlements --sign "$SIGN_IDENTITY" dist/MyMarkdownViewer.app
else
    codesign --force --options runtime --entitlements Resources/MyMarkdownViewer.entitlements --sign - dist/MyMarkdownViewer.app
fi
codesign --verify --deep --strict dist/MyMarkdownViewer.app
markdown_release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/MyMarkdownViewer.app/Contents/Info.plist)
ditto -c -k --sequesterRsrc --keepParent dist/MyMarkdownViewer.app "dist/MyMarkdownViewer-${markdown_release_version}-macOS.zip"
printf 'Built: %s/dist/MyMarkdownViewer.app\n' "$PWD"
lipo -archs dist/MyMarkdownViewer.app/Contents/MacOS/MyMarkdownViewer
