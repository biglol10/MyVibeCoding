import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const root = resolve(new URL("..", import.meta.url).pathname);

test("native macOS DMG script creates a verified personal DMG with installer", () => {
  const script = readFileSync(resolve(root, "macos-native/scripts/package-personal-dmg.sh"), "utf8");

  assert.match(script, /FlowPilot_native_mac_arm64\.dmg/);
  assert.match(script, /install-flowpilot-native\.command/);
  assert.match(script, /ln -s \/Applications/);
  assert.match(script, /hdiutil"?,? \["?create|hdiutil create/);
  assert.match(script, /-format.*UDZO/);
  assert.match(script, /hdiutil.*verify/);
});

test("native personal installer supports temporary install dir and verifies signature", () => {
  const script = readFileSync(resolve(root, "macos-native/scripts/package-personal.sh"), "utf8");

  assert.match(script, /INSTALL_DIR="\$\{FLOWPILOT_INSTALL_DIR:-\/Applications\}"/);
  assert.match(script, /APP_DEST="\$INSTALL_DIR\/FlowPilot\.app"/);
  assert.match(script, /mkdir -p "\$INSTALL_DIR"/);
  assert.match(script, /xattr -dr com\.apple\.quarantine "\$APP_DEST"/);
  assert.match(script, /codesign --verify --deep --strict "\$APP_DEST"/);
});

test("native macOS app declares Safari automation usage", () => {
  const script = readFileSync(resolve(root, "macos-native/scripts/build-dev-app.sh"), "utf8");

  assert.match(script, /NSAppleEventsUsageDescription/);
  assert.match(script, /Safari.*현재 탭.*URL/);
});
