#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-$ROOT_DIR/dist/MyMacStats-test-build.zip}"

[[ -f "$ZIP_PATH" ]] || {
    echo "error: distribution zip not found: $ZIP_PATH" >&2
    exit 1
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mymacstats-distribution.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ditto -x -k "$ZIP_PATH" "$TMP_DIR"

APP_PATH="$(find "$TMP_DIR" -maxdepth 4 -type d -name 'MyMacStats.app' -print -quit)"
[[ -n "$APP_PATH" ]] || {
    echo "error: MyMacStats.app not found in $ZIP_PATH" >&2
    exit 1
}

if command -v xattr >/dev/null 2>&1; then
    xattr -wr com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;https://github.com/biglol10/MyVibeCoding" "$APP_PATH" 2>/dev/null || true
fi

codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute -vv "$APP_PATH"

echo "Distribution Gatekeeper check passed: $APP_PATH"
