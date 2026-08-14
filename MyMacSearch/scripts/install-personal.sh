#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/MyMacSearch.app"
INSTALL_DIR="${MYMACSEARCH_INSTALL_DIR:-/Applications}"
APP_DEST="$INSTALL_DIR/MyMacSearch.app"
INSTALL_STAGE="$INSTALL_DIR/.MyMacSearch.installing.$$"
INSTALL_BACKUP="$INSTALL_DIR/.MyMacSearch.backup.$$"
BACKUP_CREATED=0
INSTALLED_NEW_APP=0

run_privileged() {
  if [[ -w "$INSTALL_DIR" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

rollback() {
  local status=$?
  if [[ $status -eq 0 ]]; then
    return
  fi

  echo "Installation failed; restoring the previous app." >&2
  if [[ -e "$INSTALL_STAGE" ]]; then
    run_privileged rm -rf "$INSTALL_STAGE" || true
  fi
  if [[ $INSTALLED_NEW_APP -eq 1 && -e "$APP_DEST" ]]; then
    run_privileged rm -rf "$APP_DEST" || true
  fi
  if [[ $BACKUP_CREATED -eq 1 && -d "$INSTALL_BACKUP" ]]; then
    run_privileged mv "$INSTALL_BACKUP" "$APP_DEST" || true
  fi
  exit "$status"
}
trap rollback EXIT

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "MyMacSearch.app must stay next to Install MyMacSearch.command." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_SOURCE"

osascript \
  -e 'with timeout of 2 seconds' \
  -e 'tell application id "com.biglol.MyMacSearch" to quit' \
  -e 'end timeout' >/dev/null 2>&1 || true
pkill -x MyMacSearchApp >/dev/null 2>&1 || true

if [[ ! -d "$INSTALL_DIR" ]]; then
  mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
fi

run_privileged rm -rf "$INSTALL_STAGE" "$INSTALL_BACKUP"
run_privileged ditto "$APP_SOURCE" "$INSTALL_STAGE"
run_privileged xattr -cr "$INSTALL_STAGE" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$INSTALL_STAGE"

if [[ -e "$APP_DEST" ]]; then
  run_privileged mv "$APP_DEST" "$INSTALL_BACKUP"
  BACKUP_CREATED=1
fi

run_privileged mv "$INSTALL_STAGE" "$APP_DEST"
INSTALLED_NEW_APP=1
codesign --verify --deep --strict --verbose=2 "$APP_DEST"

if [[ $BACKUP_CREATED -eq 1 ]]; then
  run_privileged rm -rf "$INSTALL_BACKUP"
fi
BACKUP_CREATED=0
INSTALLED_NEW_APP=0
trap - EXIT

echo "Installed: $APP_DEST"
if [[ "${MYMACSEARCH_SKIP_OPEN:-0}" != "1" ]]; then
  open "$APP_DEST"
fi
