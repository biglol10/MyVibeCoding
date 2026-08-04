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
APP_DEST="/Applications/CaptureStudio.app"
APP_INSTALLING="/Applications/.CaptureStudio.installing.$$.app"
APP_BACKUP="/Applications/.CaptureStudio.previous.$$.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "CaptureStudio.app was not found next to this installer."
  echo "Keep Install CaptureStudio.command and CaptureStudio.app in the same folder."
  read -r -p "Press Return to close."
  exit 1
fi

echo "Installing CaptureStudio for this Mac..."
if pgrep -x CaptureStudio >/dev/null 2>&1; then
  echo "CaptureStudio is currently running."
  echo "Save any open capture or recording, close CaptureStudio, then run this installer again."
  read -r -p "Press Return to close this installer."
  exit 1
fi

echo "Removing download quarantine from the package..."
xattr -dr com.apple.quarantine "$APP_SOURCE" 2>/dev/null || true

echo "Signing locally for this Mac..."
codesign --force --deep --sign - "$APP_SOURCE" >/dev/null
codesign --verify --deep --strict "$APP_SOURCE"

echo "Copying to /Applications..."
USE_SUDO=0
if [[ -w "/Applications" ]]; then
  :
else
  sudo -v
  USE_SUDO=1
fi

run_install_command() {
  if [[ "$USE_SUDO" -eq 1 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

restore_previous_install() {
  run_install_command rm -rf "$APP_INSTALLING" 2>/dev/null || true
  if [[ ! -e "$APP_DEST" && -e "$APP_BACKUP" ]]; then
    run_install_command mv "$APP_BACKUP" "$APP_DEST" 2>/dev/null || true
  fi
}
trap restore_previous_install EXIT

run_install_command rm -rf "$APP_INSTALLING" "$APP_BACKUP"
run_install_command ditto "$APP_SOURCE" "$APP_INSTALLING"
if [[ -e "$APP_DEST" ]]; then
  run_install_command mv "$APP_DEST" "$APP_BACKUP"
fi
if ! run_install_command mv "$APP_INSTALLING" "$APP_DEST"; then
  echo "Installation failed; restoring the previous app."
  exit 1
fi
run_install_command xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
run_install_command rm -rf "$APP_BACKUP"
trap - EXIT

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
read -r -p "Press Return to close this installer."
INSTALLER_SCRIPT

chmod +x "$INSTALLER"

cat > "$PACKAGE_ROOT/README-FIRST.txt" <<'README'
CaptureStudio personal Mac installer

Use this package only on your own Macs.

1. Double-click "Install CaptureStudio.command".
2. If macOS blocks the installer script, right-click it and choose Open.
3. The installer removes quarantine only from CaptureStudio.app, signs it locally, replaces the app in /Applications with rollback protection, and opens it.
4. Enable CaptureStudio in System Settings > Privacy & Security > Screen & System Audio Recording.

This personal package is not for public distribution. For a public download site, use scripts/package_release.sh with Developer ID notarization.
README

echo "Creating personal installer zip..."
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT" "$FINAL_ZIP"
/usr/bin/unzip -tq "$FINAL_ZIP"

echo "Created: $FINAL_ZIP"
