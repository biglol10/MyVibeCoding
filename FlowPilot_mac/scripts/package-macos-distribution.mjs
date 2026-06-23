import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { cp } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const dmgPath = resolve(root, "src-tauri/target/release/bundle/dmg/FlowPilot_0.1.0_aarch64.dmg");
const releaseRoot = resolve(root, "release/FlowPilot_mac_arm64");
const appReleaseDir = resolve(releaseRoot, "App");
const extensionReleaseDir = resolve(releaseRoot, "Chrome_Extension");
const zipPath = resolve(root, "release/FlowPilot_mac_arm64.zip");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    env: {
      ...process.env,
      LANG: "en_US.UTF-8",
      LC_ALL: "en_US.UTF-8",
    },
    encoding: "utf8",
    stdio: options.stdio ?? "inherit",
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  return result;
}

run("xcrun", ["stapler", "validate", dmgPath]);
run("spctl", ["--assess", "--type", "open", "--verbose=4", dmgPath]);

rmSync(releaseRoot, { force: true, recursive: true });
mkdirSync(appReleaseDir, { recursive: true });
mkdirSync(extensionReleaseDir, { recursive: true });
mkdirSync(dirname(zipPath), { recursive: true });
rmSync(zipPath, { force: true });

await cp(dmgPath, resolve(appReleaseDir, basename(dmgPath)));
await cp(resolve(root, "browser-extension/manifest.json"), resolve(extensionReleaseDir, "manifest.json"));
await cp(resolve(root, "browser-extension/dist"), resolve(extensionReleaseDir, "dist"), { recursive: true });

writeFileSync(
  resolve(releaseRoot, "README_INSTALL.txt"),
  [
    "FlowPilot macOS 설치 안내",
    "",
    "1. App 폴더의 FlowPilot_0.1.0_aarch64.dmg를 엽니다.",
    "2. FlowPilot.app을 Applications 폴더로 드래그합니다.",
    "3. FlowPilot을 실행한 뒤 macOS 권한 안내가 나오면 시스템 설정에서 허용하고 앱을 다시 실행합니다.",
    "4. Chrome 도메인 집계를 쓰려면 Chrome_Extension 폴더를 Chrome 확장 프로그램 개발자 모드에서 로드합니다.",
    "",
    "이 배포 파일은 Developer ID 서명과 Apple 공증을 통과한 DMG만 포함하도록 생성됩니다.",
  ].join("\n"),
);

run("zip", ["-r", "-X", zipPath, basename(releaseRoot)], { cwd: dirname(releaseRoot) });

console.log(`Distribution zip ready: ${zipPath}`);
