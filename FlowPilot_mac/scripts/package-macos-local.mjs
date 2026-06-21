import { mkdirSync, rmSync, symlinkSync } from "node:fs";
import { cp } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(new URL("..", import.meta.url).pathname);
const appPath = resolve(root, "src-tauri/target/release/bundle/macos/FlowPilot.app");
const executablePath = resolve(appPath, "Contents/MacOS/flowpilot");
const dmgPath = resolve(root, "src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg");
const dmgRoot = resolve("/private/tmp", `flowpilot-dmg-${Date.now()}`);
const requirement = '=designated => identifier "app.flowpilot.desktop"';

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    env: {
      ...process.env,
      LANG: "en_US.UTF-8",
      LC_ALL: "en_US.UTF-8",
      ...options.env,
    },
    stdio: "inherit",
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function sign(path) {
  run("codesign", [
    "--force",
    "--sign",
    "-",
    "--options",
    "runtime",
    "--timestamp=none",
    "--identifier",
    "app.flowpilot.desktop",
    "--requirements",
    requirement,
    path,
  ]);
}

run("tauri", ["build", "--bundles", "app", "--no-sign"]);
sign(executablePath);
sign(appPath);
run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
run("codesign", ["-dr", "-", appPath]);

rmSync(dmgRoot, { force: true, recursive: true });
mkdirSync(dmgRoot, { recursive: true });
mkdirSync(dirname(dmgPath), { recursive: true });
rmSync(dmgPath, { force: true });

await cp(appPath, resolve(dmgRoot, "FlowPilot.app"), { recursive: true });
symlinkSync("/Applications", resolve(dmgRoot, "Applications"));

run("hdiutil", ["create", "-volname", "FlowPilot", "-srcfolder", dmgRoot, "-ov", "-format", "UDZO", dmgPath]);
run("hdiutil", ["verify", dmgPath]);

rmSync(dmgRoot, { force: true, recursive: true });
