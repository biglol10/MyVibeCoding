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

test("native macOS app declares Safari automation usage", () => {
  const script = readFileSync(resolve(root, "macos-native/scripts/build-dev-app.sh"), "utf8");

  assert.match(script, /NSAppleEventsUsageDescription/);
  assert.match(script, /Safari.*현재 탭.*URL/);
});

test("native macOS app includes the FlowPilot icon", () => {
  const script = readFileSync(resolve(root, "macos-native/scripts/build-dev-app.sh"), "utf8");

  assert.match(script, /src-tauri\/icons\/icon\.icns/);
  assert.match(script, /cp "\$ICON_SOURCE" "\$RESOURCES_DIR\/icon\.icns"/);
  assert.match(script, /CFBundleIconFile/);
  assert.match(script, /<string>icon\.icns<\/string>/);
});

test("native macOS app sets the running Dock icon from the bundled icon", () => {
  const app = readFileSync(resolve(root, "macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift"), "utf8");

  assert.match(app, /installDockIcon\(\)/);
  assert.match(app, /Bundle\.main\.url\(forResource: "icon", withExtension: "icns"\)/);
  assert.match(app, /NSApplication\.shared\.applicationIconImage = icon/);
});
