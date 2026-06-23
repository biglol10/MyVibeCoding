import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, symlinkSync } from "node:fs";
import { cp } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { resolveDeveloperId, resolveNotaryArgs } from "./macos-release-config.mjs";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const appPath = resolve(root, "src-tauri/target/release/bundle/macos/FlowPilot.app");
const executablePath = resolve(appPath, "Contents/MacOS/flowpilot");
const appNotaryZipPath = resolve(root, "src-tauri/target/release/bundle/macos/FlowPilot.app.notary.zip");
const dmgPath = resolve(root, "src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg");
const dmgRoot = resolve("/private/tmp", `flowpilot-release-dmg-${Date.now()}`);

function spawn(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: root,
    env: {
      ...process.env,
      LANG: "en_US.UTF-8",
      LC_ALL: "en_US.UTF-8",
      ...options.env,
    },
    encoding: options.encoding ?? "utf8",
    stdio: options.stdio ?? "inherit",
  });
}

function run(command, args, options = {}) {
  const result = spawn(command, args, options);
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
  return result;
}

function capture(command, args) {
  const result = spawn(command, args, { stdio: "pipe" });
  if (result.status !== 0) {
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
    throw new Error(output || `${command} ${args.join(" ")} failed`);
  }
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function signCode(path, identity, extraArgs = []) {
  run("codesign", [
    "--force",
    ...extraArgs,
    "--sign",
    identity,
    "--options",
    "runtime",
    "--timestamp",
    path,
  ]);
}

function signDmg(path, identity) {
  run("codesign", ["--force", "--sign", identity, "--timestamp", path]);
}

function notarize(path, notaryArgs, label) {
  console.log(`\nNotarizing ${label} with ${notaryArgs.description}...`);
  run("xcrun", ["notarytool", "submit", path, "--wait", ...notaryArgs.args]);
}

function staple(path, label) {
  console.log(`\nStapling ${label}...`);
  run("xcrun", ["stapler", "staple", path]);
  run("xcrun", ["stapler", "validate", path]);
}

let developerId;
let notaryArgs;

try {
  const identitiesOutput = capture("security", ["find-identity", "-v", "-p", "codesigning"]);
  developerId = resolveDeveloperId(process.env, identitiesOutput);
  notaryArgs = resolveNotaryArgs(process.env);
} catch (error) {
  console.error("\nmacOS release packaging configuration error:");
  console.error(error instanceof Error ? error.message : String(error));
  console.error("\nSee docs/macos-distribution.md for setup instructions.");
  process.exit(1);
}

console.log(`Using signing identity: ${developerId}`);
console.log(`Using notarization credentials: ${notaryArgs.description}`);

run("tauri", ["build", "--bundles", "app", "--no-sign"]);

signCode(executablePath, developerId);
signCode(appPath, developerId, ["--deep"]);
run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
run("codesign", ["-dv", "--verbose=4", appPath]);

rmSync(appNotaryZipPath, { force: true });
run("ditto", ["-c", "-k", "--keepParent", appPath, appNotaryZipPath]);
notarize(appNotaryZipPath, notaryArgs, "FlowPilot.app");
staple(appPath, "FlowPilot.app");
run("spctl", ["--assess", "--type", "execute", "--verbose=4", appPath]);
rmSync(appNotaryZipPath, { force: true });

rmSync(dmgRoot, { force: true, recursive: true });
mkdirSync(dmgRoot, { recursive: true });
mkdirSync(dirname(dmgPath), { recursive: true });
rmSync(dmgPath, { force: true });

await cp(appPath, resolve(dmgRoot, "FlowPilot.app"), { recursive: true });
symlinkSync("/Applications", resolve(dmgRoot, "Applications"));

run("hdiutil", ["create", "-volname", "FlowPilot", "-srcfolder", dmgRoot, "-ov", "-format", "UDZO", dmgPath]);
run("hdiutil", ["verify", dmgPath]);
signDmg(dmgPath, developerId);
run("codesign", ["--verify", "--verbose=2", dmgPath]);
notarize(dmgPath, notaryArgs, "FlowPilot.dmg");
staple(dmgPath, "FlowPilot.dmg");
run("spctl", ["--assess", "--type", "open", "--verbose=4", dmgPath]);

rmSync(dmgRoot, { force: true, recursive: true });

console.log(`\nRelease DMG ready: ${dmgPath}`);
