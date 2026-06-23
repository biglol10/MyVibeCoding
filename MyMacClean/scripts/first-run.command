#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/MyMacClean.app"

echo "MyMacClean 처음 실행 도우미"
echo

if [ ! -d "$APP_PATH" ]; then
    echo "오류: 같은 폴더에서 MyMacClean.app을 찾을 수 없습니다."
    echo "압축을 풀면 MyMacClean 폴더 안에 MyMacClean.app과 이 파일이 함께 있어야 합니다."
    exit 1
fi

if command -v xattr >/dev/null 2>&1; then
    echo "macOS 다운로드 격리 속성을 제거합니다..."
    xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
else
    echo "xattr 명령을 찾을 수 없어 격리 속성 제거를 건너뜁니다."
fi

echo "MyMacClean을 실행합니다..."
open "$APP_PATH"
echo
echo "앱이 열리지 않으면 시스템 설정 > 개인정보 보호 및 보안에서 실행 허용을 확인하세요."
