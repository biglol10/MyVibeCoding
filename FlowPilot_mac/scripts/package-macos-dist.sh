#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
DOWNLOAD_DIR="$REPO_ROOT/downloads/FlowPilot_mac"
DIST_DIR="$ROOT_DIR/dist-macos"
PACKAGE_DIR="$DIST_DIR/FlowPilot_mac_arm64"
APP_DIR="$PACKAGE_DIR/FlowPilot.app"
HELPER_SOURCE="$ROOT_DIR/scripts/first-run-macos.command"
HELPER_DEST="$PACKAGE_DIR/처음 실행하기.command"
SOURCE_APP="$ROOT_DIR/src-tauri/target/release/bundle/macos/FlowPilot.app"
SOURCE_DMG="$DOWNLOAD_DIR/FlowPilot_0.1.0_aarch64.dmg"
SOURCE_ZIP="$DOWNLOAD_DIR/FlowPilot_mac_arm64.zip"
ZIP_PATH="$DOWNLOAD_DIR/FlowPilot_mac_arm64.zip"
DMG_PATH="$DOWNLOAD_DIR/FlowPilot_0.1.0_aarch64.dmg"
DMG_ROOT="$DIST_DIR/dmg-root"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
MOUNT_DIR=""

cleanup() {
    if [ -n "$MOUNT_DIR" ] && mount | grep -q "$MOUNT_DIR"; then
        hdiutil detach "$MOUNT_DIR" >/dev/null || true
    fi
}
trap cleanup EXIT

rm -rf "$DIST_DIR"
mkdir -p "$PACKAGE_DIR" "$DOWNLOAD_DIR"

if [ -d "$SOURCE_APP" ]; then
    cp -R "$SOURCE_APP" "$APP_DIR"
else
    if [ ! -f "$SOURCE_DMG" ]; then
        echo "오류: 빌드된 FlowPilot.app 또는 기존 DMG를 찾을 수 없습니다."
        echo "먼저 npm run tauri -- build 를 실행하거나 $SOURCE_DMG 파일을 준비하세요."
        exit 1
    fi

    MOUNT_DIR="$(mktemp -d /tmp/flowpilot-source-dmg.XXXXXX)"
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$SOURCE_DMG" >/dev/null
    cp -R "$MOUNT_DIR/FlowPilot.app" "$APP_DIR"
    cleanup
    MOUNT_DIR=""
fi

cp "$HELPER_SOURCE" "$HELPER_DEST"
chmod +x "$HELPER_DEST"

if [ -d "$ROOT_DIR/browser-extension/dist" ]; then
    mkdir -p "$PACKAGE_DIR/Chrome_Extension"
    cp "$ROOT_DIR/browser-extension/manifest.json" "$PACKAGE_DIR/Chrome_Extension/manifest.json"
    cp -R "$ROOT_DIR/browser-extension/dist" "$PACKAGE_DIR/Chrome_Extension/dist"
elif [ -f "$SOURCE_ZIP" ]; then
    OLD_ZIP_DIR="$DIST_DIR/old-zip"
    mkdir -p "$OLD_ZIP_DIR"
    ditto -x -k "$SOURCE_ZIP" "$OLD_ZIP_DIR"
    if [ -d "$OLD_ZIP_DIR/FlowPilot_mac_arm64/Chrome_Extension" ]; then
        cp -R "$OLD_ZIP_DIR/FlowPilot_mac_arm64/Chrome_Extension" "$PACKAGE_DIR/Chrome_Extension"
    fi
fi

cat > "$PACKAGE_DIR/README_INSTALL.txt" <<'README'
FlowPilot macOS 테스트 빌드

처음 실행 방법:
1. FlowPilot.app과 같은 폴더의 "처음 실행하기.command"를 Finder에서 우클릭합니다.
2. "열기"를 선택합니다.
3. 헬퍼가 다운로드 격리 속성을 제거한 뒤 FlowPilot을 실행합니다.

직접 실행하려면:
xattr -dr com.apple.quarantine FlowPilot.app
open FlowPilot.app

이 빌드는 Apple Developer ID 서명/공증이 없는 개발 테스트용 빌드입니다.
README

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

rm -f "$ZIP_PATH" "$DMG_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/FlowPilot.app"
cp "$HELPER_DEST" "$DMG_ROOT/처음 실행하기.command"
cp "$PACKAGE_DIR/README_INSTALL.txt" "$DMG_ROOT/README_INSTALL.txt"
ln -s /Applications "$DMG_ROOT/Applications"
if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$DMG_ROOT"
fi
hdiutil create -volname "FlowPilot" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

echo "$PACKAGE_DIR"
echo "$ZIP_PATH"
echo "$DMG_PATH"
