import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { cp } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const sourceApp = resolve(root, "src-tauri/target/release/bundle/macos/FlowPilot.app");
const releaseRoot = resolve(root, "release/FlowPilot_personal_mac_arm64");
const appReleaseDir = resolve(releaseRoot, "App");
const extensionReleaseDir = resolve(releaseRoot, "Chrome_Extension");
const installerPath = resolve(releaseRoot, "install-flowpilot-personal.command");
const readmePath = resolve(releaseRoot, "README_PERSONAL_INSTALL.txt");
const zipPath = resolve(root, "release/FlowPilot_personal_mac_arm64.zip");

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

export function buildPersonalInstallCommand() {
  return `#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")" && pwd)"
source_app="$package_root/App/FlowPilot.app"
target_dir="\${FLOWPILOT_INSTALL_DIR:-/Applications}"
target_app="$target_dir/FlowPilot.app"

if [ ! -d "$source_app" ]; then
  echo "FlowPilot.app을 찾을 수 없습니다: $source_app"
  exit 1
fi

echo "실행 중인 FlowPilot을 종료합니다..."
osascript -e 'tell application "FlowPilot" to quit' >/dev/null 2>&1 || true
sleep 1

echo "기존 FlowPilot을 삭제합니다..."
mkdir -p "$target_dir"
rm -rf "$target_app"

echo "FlowPilot을 $target_dir에 설치합니다..."
ditto "$source_app" "$target_app"

echo "개인 Mac 설치용 quarantine 속성을 제거합니다..."
xattr -dr com.apple.quarantine "$source_app" 2>/dev/null || true
xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true

echo "앱 서명을 검증합니다..."
codesign --verify --deep --strict --verbose=2 "$target_app"

echo "FlowPilot을 실행합니다..."
open "$target_app"

echo "설치 완료: $target_app"
`;
}

export function buildPersonalReadme() {
  return [
    "FlowPilot 개인 Mac 설치 안내",
    "",
    "이 패키지는 본인 소유의 다른 Mac에 설치하기 위한 개인용 패키지입니다.",
    "Apple Developer ID 공증 배포 파일이 아니므로 FlowPilot.app을 바로 더블클릭하지 마세요.",
    "",
    "설치 방법:",
    "",
    "1. ZIP 압축을 풉니다.",
    "2. 터미널을 열고 압축을 푼 폴더로 이동합니다.",
    "3. 아래 명령을 실행합니다.",
    "",
    "   chmod +x install-flowpilot-personal.command",
    "   ./install-flowpilot-personal.command",
    "",
    "설치 스크립트는 기존 /Applications/FlowPilot.app을 삭제하고 새 앱을 복사한 뒤",
    "macOS 다운로드 quarantine 속성을 제거합니다.",
    "",
    "Chrome 도메인 집계를 쓰려면 Chrome_Extension 폴더를 Chrome 확장 프로그램 개발자 모드에서 로드하세요.",
  ].join("\n");
}

async function packagePersonalBuild() {
  run("npm", ["run", "package:macos:local"]);

  rmSync(releaseRoot, { force: true, recursive: true });
  mkdirSync(appReleaseDir, { recursive: true });
  mkdirSync(extensionReleaseDir, { recursive: true });
  mkdirSync(dirname(zipPath), { recursive: true });
  rmSync(zipPath, { force: true });

  await cp(sourceApp, resolve(appReleaseDir, basename(sourceApp)), { recursive: true });
  await cp(resolve(root, "browser-extension/manifest.json"), resolve(extensionReleaseDir, "manifest.json"));
  await cp(resolve(root, "browser-extension/dist"), resolve(extensionReleaseDir, "dist"), { recursive: true });

  writeFileSync(installerPath, buildPersonalInstallCommand());
  chmodSync(installerPath, 0o755);
  writeFileSync(readmePath, buildPersonalReadme());

  run("zip", ["-r", "-X", zipPath, basename(releaseRoot)], { cwd: dirname(releaseRoot) });
  console.log(`Personal install zip ready: ${zipPath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await packagePersonalBuild();
}
