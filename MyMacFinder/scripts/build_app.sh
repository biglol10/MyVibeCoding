#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MyMacFinder"
CONFIGURATION="${CONFIGURATION:-release}"
INTERNAL_APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --configuration=*)
      CONFIGURATION="${1#*=}"
      shift
      ;;
    *)
      echo "Usage: $0 [--configuration debug|release]" >&2
      exit 2
      ;;
  esac
done

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Usage: $0 [--configuration debug|release]" >&2
    exit 2
    ;;
esac

echo "Building $APP_NAME ($CONFIGURATION)..."
"$ROOT_DIR/scripts/create-app-bundle.sh" --configuration "$CONFIGURATION"

if [[ ! -d "$INTERNAL_APP_DIR" ]]; then
  echo "Built app bundle not found: $INTERNAL_APP_DIR" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$INTERNAL_APP_DIR" "$APP_DIR"

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"
/usr/bin/touch "$APP_DIR"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
