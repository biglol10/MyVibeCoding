#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="personal"
ZIP_PATH="$ROOT_DIR/dist/MyMacStats-test-build.zip"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            MODE="release"
            ;;
        -h|--help)
            cat <<'EOF'
Usage:
  ./scripts/check-distribution.sh [--release] [zip-path]

Default mode verifies the personal zip by simulating a downloaded package,
running Install MyMacStats.command into a temporary Applications folder, and
checking that quarantine is removed from the installed app.

Use --release only for Developer ID signed and notarized public release zips.
EOF
            exit 0
            ;;
        *)
            ZIP_PATH="$1"
            ;;
    esac
    shift
done

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
    xattr -rw com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;https://github.com/biglol10/MyVibeCoding" "$TMP_DIR" 2>/dev/null || true
fi

codesign --verify --deep --strict "$APP_PATH"

if [[ "$MODE" == "release" ]]; then
    spctl --assess --type execute -vv "$APP_PATH"
    echo "Release Gatekeeper check passed: $APP_PATH"
    exit 0
fi

INSTALLER_PATH="$(find "$TMP_DIR" -maxdepth 4 -type f -name 'Install MyMacStats.command' -print -quit)"
[[ -n "$INSTALLER_PATH" ]] || {
    echo "error: Install MyMacStats.command not found in $ZIP_PATH" >&2
    exit 1
}

INSTALL_DIR="$TMP_DIR/Applications"
MYMACSTATS_INSTALL_DIR="$INSTALL_DIR" MYMACSTATS_SKIP_OPEN=1 "$INSTALLER_PATH"

INSTALLED_APP_PATH="$INSTALL_DIR/MyMacStats.app"
[[ -d "$INSTALLED_APP_PATH" ]] || {
    echo "error: installed app not found: $INSTALLED_APP_PATH" >&2
    exit 1
}

codesign --verify --deep --strict "$INSTALLED_APP_PATH"

if command -v xattr >/dev/null 2>&1; then
    if xattr -p com.apple.quarantine "$INSTALLED_APP_PATH" >/dev/null 2>&1; then
        echo "error: quarantine attribute still present on installed app" >&2
        exit 1
    fi
fi

echo "Personal distribution install check passed: $INSTALLED_APP_PATH"
