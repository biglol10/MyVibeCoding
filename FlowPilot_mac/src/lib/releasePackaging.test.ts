import { describe, expect, it } from "vitest";
import { readFileSync, statSync } from "node:fs";
import path from "node:path";

const projectRoot = path.resolve(__dirname, "../..");

describe("macOS release packaging", () => {
  it("packages a first-run helper with Gatekeeper quarantine removal", () => {
    const helperPath = path.join(projectRoot, "scripts/first-run-macos.command");
    const scriptPath = path.join(projectRoot, "scripts/package-macos-dist.sh");
    const packageJsonPath = path.join(projectRoot, "package.json");

    const helperMode = statSync(helperPath).mode;
    expect(helperMode & 0o111).not.toBe(0);

    const helper = readFileSync(helperPath, "utf8");
    expect(helper).toContain("FlowPilot.app");
    expect(helper).toContain("xattr -dr com.apple.quarantine");
    expect(helper).toContain("open");

    const script = readFileSync(scriptPath, "utf8");
    expect(script).toContain("MACOS_SIGN_IDENTITY");
    expect(script).toContain("xattr -cr");
    expect(script).toContain("처음 실행하기.command");
    expect(script).toContain("PACKAGE_DIR=\"$DIST_DIR/FlowPilot_mac_arm64\"");
    expect(script).toContain("ditto -c -k");
    expect(script).toContain("--keepParent");
    expect(script).toContain("hdiutil create");

    const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
    expect(packageJson.scripts["dist:macos"]).toBe("bash scripts/package-macos-dist.sh");
  });
});
