import assert from "node:assert/strict";
import test from "node:test";

import { buildPersonalInstallCommand, buildPersonalReadme } from "./package-macos-personal.mjs";

test("personal installer copies FlowPilot to Applications and removes quarantine", () => {
  const command = buildPersonalInstallCommand();

  assert.match(command, /target_dir="\$\{FLOWPILOT_INSTALL_DIR:-\/Applications\}"/);
  assert.match(command, /target_app="\$target_dir\/FlowPilot\.app"/);
  assert.match(command, /mkdir -p "\$target_dir"/);
  assert.match(command, /rm -rf "\$target_app"/);
  assert.match(command, /ditto "\$source_app" "\$target_app"/);
  assert.match(command, /xattr -dr com\.apple\.quarantine "\$target_app"/);
  assert.match(command, /codesign --verify --deep --strict --verbose=2 "\$target_app"/);
  assert.match(command, /open "\$target_app"/);
});

test("personal readme tells the user to run the installer instead of opening the app directly", () => {
  const readme = buildPersonalReadme();

  assert.match(readme, /install-flowpilot-personal\.command/);
  assert.match(readme, /FlowPilot\.app을 바로 더블클릭하지 마세요/);
  assert.match(readme, /quarantine/);
});
