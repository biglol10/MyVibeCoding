#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${MYMACCALENDAR_APP_NAME:-MyMacCalendar}"
OUTPUT_DIR="${MYMACCALENDAR_OUTPUT_DIR:-$ROOT_DIR/dist}"
PACKAGE_NAME="${APP_NAME}-personal-mac"
PACKAGE_ROOT="$OUTPUT_DIR/$PACKAGE_NAME"
FINAL_ZIP="$OUTPUT_DIR/$PACKAGE_NAME.zip"
INSTALLER="$PACKAGE_ROOT/Install ${APP_NAME}.command"
APP_BUNDLE_SOURCE="$ROOT_DIR/build/$APP_NAME.app"
APP_BUNDLE_TARGET="$PACKAGE_ROOT/$APP_NAME.app"

echo "Creating personal package archive: $PACKAGE_NAME.zip"
rm -rf "$PACKAGE_ROOT" "$FINAL_ZIP"
mkdir -p "$OUTPUT_DIR" "$PACKAGE_ROOT"

echo "Building local app package..."
"$ROOT_DIR/scripts/build_app.sh"

if [[ ! -d "$APP_BUNDLE_SOURCE" ]]; then
  echo "Built app bundle not found: $APP_BUNDLE_SOURCE" >&2
  exit 1
fi

cp -R "$APP_BUNDLE_SOURCE" "$APP_BUNDLE_TARGET"

xattr -cr "$APP_BUNDLE_TARGET" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE_TARGET" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE_TARGET"

cat > "$INSTALLER" <<'INSTALLER_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/MyMacCalendar.app"
DEFAULT_INSTALL_DIR="/Applications"
INSTALL_DIR="${MYMACCALENDAR_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
APP_DEST="$INSTALL_DIR/MyMacCalendar.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pause_if_interactive() {
  if [[ -t 0 ]]; then
    read -r -p "$1"
  fi
}

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "MyMacCalendar.app was not found next to this installer."
  echo "Keep Install MyMacCalendar.command and MyMacCalendar.app in the same folder."
  pause_if_interactive "Press Return to close."
  exit 1
fi

echo "Installing MyMacCalendar for this Mac..."
osascript -e 'tell application "MyMacCalendar" to quit' >/dev/null 2>&1 || true
pkill -x MyMacCalendar >/dev/null 2>&1 || true

echo "Removing quarantine..."
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true
xattr -cr "$APP_SOURCE" 2>/dev/null || true

echo "Signing locally for this Mac..."
codesign --force --deep --sign - "$APP_SOURCE" >/dev/null
codesign --verify --deep --strict "$APP_SOURCE"

echo "Copying to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
if [[ -w "$INSTALL_DIR" ]]; then
  rm -rf "$APP_DEST"
  ditto "$APP_SOURCE" "$APP_DEST"
else
  sudo rm -rf "$APP_DEST"
  sudo ditto "$APP_SOURCE" "$APP_DEST"
fi
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DEST" >/dev/null 2>&1 || true
fi

echo
echo "Installed: $APP_DEST"
echo "Opening MyMacCalendar..."
open "$APP_DEST"
echo
echo "If macOS asks for permissions, enable MyMacCalendar in:"
echo "System Settings > Privacy & Security"
pause_if_interactive "Press Return to close this installer."
INSTALLER_SCRIPT

chmod +x "$INSTALLER"
cat > "$PACKAGE_ROOT/README-FIRST.txt" <<'README'
MyMacCalendar personal Mac installer

Use this package only on your own Macs.

1. Double-click "Install MyMacCalendar.command".
2. If macOS blocks the installer script, right-click it and choose Open.
3. The installer removes the download quarantine, signs the app locally, copies it to /Applications, and opens it.
4. If macOS asks for permissions, allow them in System Settings.

This personal package is not for public distribution. For a public download site, use scripts/package_release.sh with Developer ID notarization.
README

echo "Creating personal installer zip..."
xattr -cr "$PACKAGE_ROOT" 2>/dev/null || true
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT" "$FINAL_ZIP"
/usr/bin/unzip -tq "$FINAL_ZIP"

echo "Created: $FINAL_ZIP"
