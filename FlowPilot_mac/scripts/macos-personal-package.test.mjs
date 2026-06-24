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
  assert.match(command, /관리자 권한으로 다시 시도합니다/);
  assert.match(command, /sudo ditto "\$source_app" "\$target_app"/);
  assert.match(command, /xattr -dr com\.apple\.quarantine "\$target_app"/);
  assert.match(command, /codesign --verify --deep --strict --verbose=2 "\$target_app"/);
  assert.match(command, /open "\$target_app"/);
  assert.match(command, /권한 요청이 나오면/);
  assert.match(command, /\$target_app 항목을 허용하세요/);
});

test("personal readme tells the user to run the installer instead of opening the app directly", () => {
  const readme = buildPersonalReadme();

  assert.match(readme, /install-flowpilot-personal\.command/);
  assert.match(readme, /FlowPilot\.app을 바로 더블클릭하지 마세요/);
  assert.match(readme, /quarantine/);
  assert.match(readme, /권한은 install-flowpilot-personal\.command나 Terminal이 아니라/);
  assert.match(readme, /\/Applications\/FlowPilot\.app/);
  assert.match(readme, /직접 Applications로 드래그할 필요는 없습니다/);
});
