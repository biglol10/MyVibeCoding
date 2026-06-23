#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/MyMacClean"
APP_DIR="$PACKAGE_DIR/MyMacClean.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/MyMacClean-test-build.zip"
NOTARY_ZIP_PATH="$DIST_DIR/MyMacClean-notary.zip"
FIRST_RUN_SOURCE="$ROOT_DIR/scripts/first-run.command"
INSTALLER_SOURCE="$ROOT_DIR/scripts/install.command"
FIRST_RUN_COMMAND="$PACKAGE_DIR/Open MyMacClean.command"
INSTALLER_COMMAND="$PACKAGE_DIR/Install MyMacClean.command"
README_PATH="$PACKAGE_DIR/READ ME FIRST.txt"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
MACOS_NOTARY_PROFILE="${MACOS_NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

if [ -z "$SIGN_IDENTITY" ] && command -v security >/dev/null 2>&1; then
    SIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' \
            | head -n 1
    )"
fi

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
fi

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$PACKAGE_DIR" "$ZIP_PATH" "$NOTARY_ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/MyMacCleanApp" "$MACOS_DIR/MyMacCleanApp"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns" "$RESOURCES_DIR/MyMacCleanIcon.icns"
cp "$FIRST_RUN_SOURCE" "$FIRST_RUN_COMMAND"
cp "$INSTALLER_SOURCE" "$INSTALLER_COMMAND"
chmod +x "$MACOS_DIR/MyMacCleanApp"
chmod +x "$FIRST_RUN_COMMAND"
chmod +x "$INSTALLER_COMMAND"
cat > "$README_PATH" <<'README'
MyMacClean test build

If you get a macOS message saying the app is damaged or should be moved to Trash,
do not open MyMacClean.app directly.

Install on your personal Mac:
1. Open this folder after unzipping.
2. Double-click "Install MyMacClean.command".
3. The installer removes macOS download quarantine, copies MyMacClean.app to /Applications,
   verifies the installed app, and opens it.

Run without installing:
Double-click "Open MyMacClean.command".

For a double-clickable public release, build with a Developer ID Application
certificate and Apple notarization credentials.
README

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
        echo "REQUIRE_NOTARIZATION=1 requires a Developer ID Application signing identity." >&2
        exit 1
    fi
    echo "Warning: using non-Developer ID signing identity '$SIGN_IDENTITY'." >&2
    echo "Downloaded apps signed this way must be installed through Install MyMacClean.command or opened through Open MyMacClean.command." >&2
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    notary_args=()
    if [ -n "$MACOS_NOTARY_PROFILE" ]; then
        notary_args=(--keychain-profile "$MACOS_NOTARY_PROFILE")
    elif [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
        notary_args=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
    fi

    if [ "${#notary_args[@]}" -gt 0 ]; then
        COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
        xcrun notarytool submit "$NOTARY_ZIP_PATH" "${notary_args[@]}" --wait
        xcrun stapler staple "$APP_DIR"
        xcrun stapler validate "$APP_DIR"
        spctl --assess --type execute --verbose=4 "$APP_DIR"
    elif [ "$REQUIRE_NOTARIZATION" = "1" ]; then
        echo "REQUIRE_NOTARIZATION=1 requires MACOS_NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD." >&2
        exit 1
    else
        echo "Warning: Developer ID app was signed but not notarized because no notarization credentials were provided." >&2
    fi
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PACKAGE_DIR"
fi

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

echo "$PACKAGE_DIR"
echo "$APP_DIR"
echo "$ZIP_PATH"
