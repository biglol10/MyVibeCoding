#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-$ROOT_DIR/dist/MyMacSearch-personal-mac.zip}"
VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mymacsearch-distribution.XXXXXX")"
EXTRACT_ROOT="$VERIFY_ROOT/extracted"
INSTALL_ROOT="$VERIFY_ROOT/Applications"
PACKAGE_ROOT="$EXTRACT_ROOT/MyMacSearch-personal-mac"
PACKAGED_APP="$PACKAGE_ROOT/MyMacSearch.app"
INSTALLER="$PACKAGE_ROOT/Install MyMacSearch.command"
INSTALLED_APP="$INSTALL_ROOT/MyMacSearch.app"

cleanup() {
  rm -rf "$VERIFY_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Distribution archive not found: $ZIP_PATH" >&2
  exit 1
fi

/usr/bin/unzip -tq "$ZIP_PATH"
mkdir -p "$EXTRACT_ROOT" "$INSTALL_ROOT"
ditto -x -k "$ZIP_PATH" "$EXTRACT_ROOT"

if [[ ! -d "$PACKAGED_APP" || ! -x "$INSTALLER" ]]; then
  echo "Archive does not contain the expected app and installer." >&2
  exit 1
fi

plutil -lint "$PACKAGED_APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"

MYMACSEARCH_INSTALL_DIR="$INSTALL_ROOT" MYMACSEARCH_SKIP_OPEN=1 "$INSTALLER"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

PACKAGED_HASH="$(LC_ALL=C LANG=C shasum -a 256 "$PACKAGED_APP/Contents/MacOS/MyMacSearchApp" | awk '{print $1}')"
INSTALLED_HASH="$(LC_ALL=C LANG=C shasum -a 256 "$INSTALLED_APP/Contents/MacOS/MyMacSearchApp" | awk '{print $1}')"

if [[ "$PACKAGED_HASH" != "$INSTALLED_HASH" ]]; then
  echo "Installed executable does not match the packaged executable." >&2
  exit 1
fi

echo "Distribution verified: $ZIP_PATH"
echo "Executable SHA-256: $PACKAGED_HASH"
echo "ZIP SHA-256: $(LC_ALL=C LANG=C shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
