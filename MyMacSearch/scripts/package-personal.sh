#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${MYMACSEARCH_OUTPUT_DIR:-$ROOT_DIR/dist}"
PACKAGE_ROOT="$OUTPUT_DIR/MyMacSearch-personal-mac"
FINAL_ZIP="$OUTPUT_DIR/MyMacSearch-personal-mac.zip"
APP_SOURCE="$ROOT_DIR/build/MyMacSearch.app"

mkdir -p "$OUTPUT_DIR"
rm -rf "$PACKAGE_ROOT" "$FINAL_ZIP"
mkdir -p "$PACKAGE_ROOT"

"$ROOT_DIR/scripts/build-app-bundle.sh"
ditto "$APP_SOURCE" "$PACKAGE_ROOT/MyMacSearch.app"
ditto "$ROOT_DIR/scripts/install-personal.sh" "$PACKAGE_ROOT/Install MyMacSearch.command"
chmod 755 "$PACKAGE_ROOT/Install MyMacSearch.command"

cat > "$PACKAGE_ROOT/README-FIRST.txt" <<'README'
MyMacSearch personal Mac installer

1. Keep MyMacSearch.app and Install MyMacSearch.command in the same folder.
2. Right-click Install MyMacSearch.command and choose Open.
3. Choose indexing locations in the first-run screen before scanning.

This package is ad-hoc signed for personal use. It is not notarized for public distribution.
README

xattr -cr "$PACKAGE_ROOT" 2>/dev/null || true
ditto -c -k --norsrc --keepParent "$PACKAGE_ROOT" "$FINAL_ZIP"
/usr/bin/unzip -tq "$FINAL_ZIP"
"$ROOT_DIR/scripts/check-distribution.sh" "$FINAL_ZIP"

echo "Created: $FINAL_ZIP"
