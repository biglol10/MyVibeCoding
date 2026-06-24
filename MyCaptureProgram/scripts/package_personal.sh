#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CAPTURE_STUDIO_APP_NAME:-CaptureStudio}"
OUTPUT_DIR="${CAPTURE_STUDIO_OUTPUT_DIR:-$ROOT_DIR/dist}"
PACKAGE_NAME="CaptureStudio-personal-mac"
PACKAGE_ROOT="$OUTPUT_DIR/$PACKAGE_NAME"
FINAL_ZIP="$OUTPUT_DIR/$PACKAGE_NAME.zip"
INSTALLER="$PACKAGE_ROOT/Install CaptureStudio.command"
APP_BUNDLE="$PACKAGE_ROOT/$APP_NAME.app"

echo "Personal package archive: CaptureStudio-personal-mac.zip"
rm -rf "$PACKAGE_ROOT" "$FINAL_ZIP"
mkdir -p "$PACKAGE_ROOT"

echo "Building personal-use app package..."
CAPTURE_STUDIO_CODE_SIGN_IDENTITY="-" "$ROOT_DIR/scripts/install_app.sh" "$PACKAGE_ROOT"

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

cat > "$INSTALLER" <<'INSTALLER_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/CaptureStudio.app"
DEFAULT_INSTALL_DIR="/Applications"
INSTALL_DIR="${CAPTURE_STUDIO_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
APP_DEST="$INSTALL_DIR/CaptureStudio.app"
# Default destination: /Applications/CaptureStudio.app
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pause_if_interactive() {
  if [[ -t 0 ]]; then
    read -r -p "$1"
  fi
}

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "CaptureStudio.app was not found next to this installer."
  echo "Keep Install CaptureStudio.command and CaptureStudio.app in the same folder."
  pause_if_interactive "Press Return to close."
  exit 1
fi

echo "Installing CaptureStudio for this Mac..."
osascript -e 'tell application "CaptureStudio" to quit' >/dev/null 2>&1 || true
pkill -x CaptureStudio >/dev/null 2>&1 || true

echo "Removing download quarantine from the package..."
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
  xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
else
  sudo rm -rf "$APP_DEST"
  sudo ditto "$APP_SOURCE" "$APP_DEST"
  sudo xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DEST" >/dev/null 2>&1 || true
fi

echo
echo "Installed: $APP_DEST"
echo "Opening CaptureStudio..."
open "$APP_DEST"
echo
echo "If macOS asks for permissions, enable CaptureStudio in:"
echo "System Settings > Privacy & Security > Screen & System Audio Recording"
echo
pause_if_interactive "Press Return to close this installer."
INSTALLER_SCRIPT

chmod +x "$INSTALLER"

cat > "$PACKAGE_ROOT/README-FIRST.txt" <<'README'
CaptureStudio personal Mac installer

Use this package only on your own Macs.

1. Double-click "Install CaptureStudio.command".
2. If macOS blocks the installer script, right-click it and choose Open.
3. The installer removes the download quarantine, signs the app locally, copies it to /Applications, and opens it.
4. Enable CaptureStudio in System Settings > Privacy & Security > Screen & System Audio Recording.

This personal package is not for public distribution. For a public download site, use scripts/package_release.sh with Developer ID notarization.
README

echo "Creating personal installer zip..."
xattr -cr "$PACKAGE_ROOT" 2>/dev/null || true
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT" "$FINAL_ZIP"
/usr/bin/unzip -tq "$FINAL_ZIP"

echo "Created: $FINAL_ZIP"
