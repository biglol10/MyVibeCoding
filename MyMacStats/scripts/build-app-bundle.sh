#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/build-app-bundle.sh [--release] [--deploy-downloads] [--deploy-personal]

Modes:
  default             Build a local development/test zip with first-run helper.
  --deploy-personal   Copy the personal installer zip to ../downloads/MyMacStats.
  --release           Build a Developer ID signed, notarized, stapled public zip.
  --deploy-downloads  Copy the public release zip to ../downloads/MyMacStats.

Release requirements:
  MACOS_SIGN_IDENTITY     Developer ID Application signing identity.
  MACOS_NOTARY_PROFILE    notarytool keychain profile name.

Alternative notary credentials:
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_SPECIFIC_PASSWORD

Create a notary profile once with:
  xcrun notarytool store-credentials MyMacStatsNotary \
    --apple-id you@example.com \
    --team-id TEAMID1234 \
    --password app-specific-password

Then publish with:
  MACOS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
  MACOS_NOTARY_PROFILE="MyMacStatsNotary" \
  ./scripts/build-app-bundle.sh --release --deploy-downloads
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacStats"
APP_DIR="$PACKAGE_DIR/MyMacStats.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/MyMacStats-test-build.zip"
NOTARY_ZIP_PATH="$DIST_DIR/MyMacStats-notary-upload.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
INSTALLER_SOURCE="$ROOT_DIR/scripts/install.command"
FIRST_RUN_COMMAND="$PACKAGE_DIR/처음 실행하기.command"
INSTALL_COMMAND="$PACKAGE_DIR/Install MyMacStats.command"
DOWNLOADS_DIR="$ROOT_DIR/../downloads/MyMacStats"

MODE="development"
DEPLOY_DOWNLOADS=0
DEPLOY_PERSONAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            MODE="release"
            ;;
        --deploy-downloads)
            DEPLOY_DOWNLOADS=1
            ;;
        --deploy-personal)
            DEPLOY_PERSONAL=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
    shift
done

if [[ "$DEPLOY_DOWNLOADS" -eq 1 && "$MODE" != "release" ]]; then
    die "--deploy-downloads requires --release so a broken unnotarized zip is not published"
fi

if [[ "$DEPLOY_PERSONAL" -eq 1 && "$MODE" == "release" ]]; then
    die "--deploy-personal is for the personal installer zip; use --deploy-downloads with --release"
fi

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$PACKAGE_DIR" "$ZIP_PATH" "$NOTARY_ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/MyMacStatsApp" "$MACOS_DIR/MyMacStatsApp"
cp "$ROOT_DIR/Sources/MyMacStatsApp/Resources/MyMacStatsInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacStatsApp/Resources/MyMacStatsIcon.icns" "$RESOURCES_DIR/MyMacStatsIcon.icns"
chmod +x "$MACOS_DIR/MyMacStatsApp"

if [[ "$MODE" != "release" ]]; then
    cp "$FIRST_RUN_SOURCE" "$FIRST_RUN_COMMAND"
    cp "$INSTALLER_SOURCE" "$INSTALL_COMMAND"
    chmod +x "$FIRST_RUN_COMMAND"
    chmod +x "$INSTALL_COMMAND"
fi

if command -v strip >/dev/null 2>&1; then
    strip -x "$MACOS_DIR/MyMacStatsApp"
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

sign_development() {
    local identity="${MACOS_SIGN_IDENTITY:--}"
    codesign --force --deep --sign "$identity" "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
}

find_developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Developer ID Application/ { print $2; exit }'
}

require_developer_id_identity() {
    local identity="${MACOS_SIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        identity="$(find_developer_id_identity || true)"
    fi

    [[ -n "$identity" ]] || die "Developer ID Application certificate is required for --release"

    local identity_details
    identity_details="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$identity" || true)"
    if [[ "$identity $identity_details" != *"Developer ID Application"* ]]; then
        die "--release requires a Developer ID Application identity, got: $identity"
    fi

    printf '%s\n' "$identity"
}

notarytool_submit() {
    if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$NOTARY_ZIP_PATH" \
            --keychain-profile "$MACOS_NOTARY_PROFILE" \
            --wait
        return
    fi

    [[ -n "${APPLE_ID:-}" ]] || die "MACOS_NOTARY_PROFILE or APPLE_ID is required for --release notarization"
    [[ -n "${APPLE_TEAM_ID:-}" ]] || die "APPLE_TEAM_ID is required when MACOS_NOTARY_PROFILE is not set"
    [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] || die "APPLE_APP_SPECIFIC_PASSWORD is required when MACOS_NOTARY_PROFILE is not set"

    xcrun notarytool submit "$NOTARY_ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
}

sign_notarize_and_validate_release() {
    local identity
    identity="$(require_developer_id_identity)"

    codesign --force --deep --options runtime --timestamp --sign "$identity" "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"

    COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
    notarytool_submit

    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    spctl --assess --type execute -vv "$APP_DIR"
}

if [[ "$MODE" == "release" ]]; then
    sign_notarize_and_validate_release
else
    sign_development
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

if [[ "$MODE" == "release" ]]; then
    COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$ZIP_PATH"
else
    COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
fi

if [[ "$DEPLOY_DOWNLOADS" -eq 1 ]]; then
    mkdir -p "$DOWNLOADS_DIR"
    cp "$ZIP_PATH" "$DOWNLOADS_DIR/MyMacStats-test-build.zip"
fi

if [[ "$DEPLOY_PERSONAL" -eq 1 ]]; then
    mkdir -p "$DOWNLOADS_DIR"
    cp "$ZIP_PATH" "$DOWNLOADS_DIR/MyMacStats-test-build.zip"
fi

echo "$PACKAGE_DIR"
echo "$APP_DIR"
echo "$ZIP_PATH"
