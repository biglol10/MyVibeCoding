#!/usr/bin/env bash
set -euo pipefail

# Isolated Markdown Reader QA setup. This script selects only its dedicated AVD.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDK_DIR="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
AVD_NAME="MarkdownReader_QA"
SERIAL="emulator-5580"
PORT="5580"
IMAGE_DIR="$SDK_DIR/system-images/android-35/google_apis/arm64-v8a"
ADB="$SDK_DIR/platform-tools/adb"
EMULATOR="$SDK_DIR/emulator/emulator"
AVDMANAGER="$SDK_DIR/cmdline-tools/latest/bin/avdmanager"
FIXTURES="$ROOT_DIR/Android/tests/fixtures"
HASHES="$FIXTURES/android-fixture-hashes.json"

[[ -x "$ADB" && -x "$EMULATOR" && -x "$AVDMANAGER" ]] || { echo "Android SDK tools not found under $SDK_DIR" >&2; exit 1; }
[[ -d "$IMAGE_DIR" ]] || { echo "Required system image missing: $IMAGE_DIR" >&2; exit 1; }

if ! "$EMULATOR" -list-avds | grep -Fxq "$AVD_NAME"; then
  printf 'no\n' | "$AVDMANAGER" create avd -n "$AVD_NAME" -k 'system-images;android-35;google_apis;arm64-v8a' -d pixel_6
fi

if ! "$ADB" devices | awk 'NR > 1 {print $1}' | grep -Fxq "$SERIAL"; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "TCP port $PORT is occupied; refusing to select another device or port" >&2
    exit 1
  fi
  "$EMULATOR" -avd "$AVD_NAME" -sysdir "$IMAGE_DIR" -port "$PORT" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect >/tmp/MarkdownReader_QA-$PORT.log 2>&1 &
  echo "emulator_pid=$! serial=$SERIAL"
fi

"$ADB" -s "$SERIAL" wait-for-device
for _ in {1..90}; do
  [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
  sleep 1
done
[[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" == "1" ]] || { echo "Emulator boot timeout" >&2; exit 1; }

python3 - "$FIXTURES" "$HASHES" <<'PY'
import hashlib, json, pathlib, sys
root, output = map(pathlib.Path, sys.argv[1:])
entries = []
for path in sorted(root.rglob('*')):
    if path.is_file() and path != output and not path.name.startswith('emulator-'):
        entries.append({'path': path.relative_to(root).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
output.write_text(json.dumps({'fixtureRoot': 'Android/tests/fixtures', 'files': entries}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

"$ADB" -s "$SERIAL" shell mkdir -p /sdcard/Documents/MarkdownReader-QA
"$ADB" -s "$SERIAL" push "$FIXTURES/." /sdcard/Documents/MarkdownReader-QA/ >/dev/null
echo "boot_verified serial=$SERIAL sdk=$("$ADB" -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r') abi=$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')"
echo "fixtures_pushed=/sdcard/Documents/MarkdownReader-QA hashes=$HASHES"
