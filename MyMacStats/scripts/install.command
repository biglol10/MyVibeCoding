#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP_PATH="$SCRIPT_DIR/MyMacStats.app"
INSTALL_DIR="${MYMACSTATS_INSTALL_DIR:-/Applications}"
INSTALLED_APP_PATH="$INSTALL_DIR/MyMacStats.app"

echo "MyMacStats 개인 맥북 설치 도우미"
echo

if [ ! -d "$SOURCE_APP_PATH" ]; then
    echo "오류: 같은 폴더에서 MyMacStats.app을 찾을 수 없습니다."
    echo "압축을 풀면 MyMacStats 폴더 안에 MyMacStats.app과 이 설치 파일이 함께 있어야 합니다."
    exit 1
fi

echo "설치 위치: $INSTALLED_APP_PATH"
echo

if pgrep -x MyMacStatsApp >/dev/null 2>&1; then
    echo "실행 중인 MyMacStats를 종료합니다..."
    pkill -x MyMacStatsApp >/dev/null 2>&1 || true
    sleep 1
fi

if command -v xattr >/dev/null 2>&1; then
    echo "macOS 다운로드 격리 속성을 제거합니다..."
    xattr -cr "$SCRIPT_DIR" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
else
    echo "xattr 명령을 찾을 수 없어 격리 속성 제거를 건너뜁니다."
fi

echo "앱 서명을 확인합니다..."
codesign --verify --deep --strict "$SOURCE_APP_PATH"

mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALLED_APP_PATH" ]; then
    echo "기존 MyMacStats.app을 교체합니다..."
    rm -rf "$INSTALLED_APP_PATH"
fi

echo "MyMacStats.app을 $INSTALL_DIR에 설치합니다..."
ditto --rsrc --extattr "$SOURCE_APP_PATH" "$INSTALLED_APP_PATH"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$INSTALLED_APP_PATH" 2>/dev/null || true
    xattr -dr com.apple.quarantine "$INSTALLED_APP_PATH" 2>/dev/null || true
fi

echo "설치된 앱 서명을 확인합니다..."
codesign --verify --deep --strict "$INSTALLED_APP_PATH"

if [[ "${MYMACSTATS_SKIP_OPEN:-0}" == "1" ]]; then
    echo "MYMACSTATS_SKIP_OPEN=1 이므로 앱 실행을 건너뜁니다."
else
    echo "MyMacStats를 실행합니다..."
    open "$INSTALLED_APP_PATH"
fi
echo
echo "설치 완료: $INSTALLED_APP_PATH"
echo "다음부터는 Applications에서 MyMacStats를 바로 실행하면 됩니다."
