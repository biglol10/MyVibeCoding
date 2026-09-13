import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { _electron as electron } from "../../Editor/node_modules/playwright/index.mjs";
import { closeElectron, editorFrame } from "./electron-fixtures.mjs";

const data = await fs.mkdtemp(path.join(os.tmpdir(), "mymarkdown-reveal-current-"));
const workspace = path.join(data, "문서");
const outside = path.join(data, "바깥 문서.md");
const targetDirectory = path.join(workspace, "z-folder", "section");
const targetFile = path.join(targetDirectory, "zz-current.md");
const source = [
  "# 현재 문서",
  "",
  ...Array.from({ length: 180 }, (_, index) => `읽기 위치 보존 확인 ${index + 1}: 현재 문서의 원문과 편집 위치를 유지합니다.`),
  "",
].join("\n");
await fs.mkdir(targetDirectory, { recursive: true });
await fs.mkdir(path.join(workspace, "aaa-other"), { recursive: true });
await fs.mkdir(path.join(data, "외부"), { recursive: true });
await fs.writeFile(outside, "# 폴더 밖 문서\n");
await fs.writeFile(targetFile, source);
for (let index = 0; index < 100; index += 1)
  await fs.writeFile(path.join(targetDirectory, `a-${String(index).padStart(3, "0")}.md`), `# 주변 파일 ${index}\n`);

const app = await electron.launch({
  executablePath: path.resolve("Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"),
  args: [path.resolve(process.env.PACKAGED_APP || "Windows"), "--qa-data", data],
});
let failure = null;
const checks = [];

try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const frame = await editorFrame(page);
  const call = (action, payload = {}) =>
    page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  const button = page.locator("#reveal-current");

  await page.waitForFunction(() => document.querySelector("#reveal-current")?.title.includes("먼저 폴더"));
  assert.equal(await button.isDisabled(), true);
  assert.equal(await button.getAttribute("aria-label"), "현재 문서 찾기");
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setContentSize(800, 560));
  await app.evaluate(async (_, folder) => globalThis.__qa.grant(folder), workspace);
  await page.waitForFunction(() => document.querySelector("#reveal-current")?.title.includes("저장된 문서"));
  assert.equal(await button.isDisabled(), true);
  await page.locator("#resize").press("ArrowLeft");
  await page.locator("#resize").press("ArrowLeft");
  assert.equal((await page.locator("#sidebar").evaluate((node) => Math.round(node.getBoundingClientRect().width))), 220);
  const head = await page.locator(".panel-head").evaluate((node) => {
    const bounds = (selector) => {
      const { left, right, top, bottom } = node.querySelector(selector).getBoundingClientRect();
      return { left, right, top, bottom };
    };
    return { bounds: node.getBoundingClientRect().toJSON(), label: bounds("#root-label"), reveal: bounds("#reveal-current"), menu: bounds(".folder-menu") };
  });
  assert.ok(head.label.right <= head.reveal.left);
  assert.ok(head.reveal.right <= head.menu.left);
  assert.ok(head.reveal.right <= head.bounds.right);
  checks.push("rootless and unsaved disabled reasons; compact 220px header has no overlap");

  assert.equal((await call("openExternal", { path: outside })).ok, true);
  await frame.waitForFunction((file) => window.MarkdownHost.snapshot().documentID === file, outside);
  await page.waitForFunction(() => document.querySelector("#reveal-current")?.title.includes("현재 폴더 안에 없습니다"));
  assert.equal(await button.isDisabled(), true);
  checks.push("document opened outside the root is unavailable with a specific reason");

  assert.equal((await call("open", { path: targetFile })).ok, true);
  await frame.waitForFunction((file) => window.MarkdownHost.snapshot().documentID === file, targetFile);
  assert.equal((await call("settings", { patch: { autosave: false, theme: "night" } })).ok, true);
  await page.locator(".tree-item").filter({ hasText: "zz-current.md" }).waitFor();
  assert.equal(await button.isDisabled(), false);

  const tree = page.locator("#tree");
  await tree.evaluate((node) => { node.scrollTop = 0; });
  const initiallyOffscreen = await page.locator(".tree-item").filter({ hasText: "zz-current.md" }).evaluate((row) => {
    const rowRect = row.getBoundingClientRect();
    const treeRect = document.querySelector("#tree").getBoundingClientRect();
    return rowRect.bottom > treeRect.bottom;
  });
  assert.equal(initiallyOffscreen, true);

  const editorPosition = Math.floor(source.length * 0.7);
  await frame.evaluate((position) => {
    window.MarkdownHost.receive({ type: "jump", ...window.MarkdownHost.snapshot(), from: position, to: position + 5 });
    const snapshot = window.MarkdownHost.snapshot();
    window.MarkdownHost.receive({ type: "insert", sessionID: snapshot.sessionID, documentID: snapshot.documentID, text: "QA edit" });
    window.MarkdownHost.receive({ type: "jump", ...window.MarkdownHost.snapshot(), from: position, to: position + 5 });
    const scroller = document.querySelector(".cm-scroller");
    scroller.scrollTop = Math.min(1200, scroller.scrollHeight);
    scroller.dispatchEvent(new Event("scroll"));
  }, editorPosition);
  await page.waitForTimeout(180);
  const before = await frame.evaluate(() => window.MarkdownHost.snapshot());
  assert.equal(before.text, source.slice(0, editorPosition) + "QA edit" + source.slice(editorPosition + 5));
  assert.equal(before.anchor, editorPosition);
  assert.equal(before.head, editorPosition + 5);
  assert.ok(before.scrollTop > 0);

  const folder = page.locator(".tree-item").filter({ hasText: "z-folder" });
  await folder.click();
  assert.equal(await folder.getAttribute("aria-expanded"), "false");
  await page.locator(".tree-item").filter({ hasText: "zz-current.md" }).waitFor({ state: "hidden" });
  await tree.evaluate((node) => { node.scrollTop = 0; });
  const stateBeforeReveal = await app.evaluate(() => globalThis.__qa.state());
  assert.equal(stateBeforeReveal.doc.path, targetFile);
  assert.equal(stateBeforeReveal.root, workspace);
  assert.equal(stateBeforeReveal.doc.dirty, true);

  await page.evaluate(() => {
    window.__revealLocks = [];
    window.__stopRevealEvents = window.desktop.onEvent(({ type, payload }) => {
      if (type === "editor" && payload.type === "lock") window.__revealLocks.push(payload.locked);
    });
    const reveal = document.querySelector("#reveal-current");
    reveal.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    window.__revealDisabledDuringCheck = reveal.disabled;
    reveal.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });
  assert.equal(await page.evaluate(() => window.__revealDisabledDuringCheck), true);
  await page.waitForFunction(() => document.querySelector("#notice").textContent.includes("파일 목록에서 찾았습니다"));
  assert.equal(await folder.getAttribute("aria-expanded"), "true");
  const section = page.locator(".tree-item").filter({ hasText: "section" });
  assert.equal(await section.getAttribute("aria-expanded"), "true");
  const target = page.locator(".tree-item").filter({ hasText: "zz-current.md" });
  assert.equal(await target.getAttribute("aria-selected"), "true");
  const visibility = await target.evaluate((row) => {
    const tree = document.querySelector("#tree");
    const bounds = row.getBoundingClientRect();
    const viewport = tree.getBoundingClientRect();
    return { visible: bounds.top >= viewport.top && bounds.bottom <= viewport.bottom, scrollTop: tree.scrollTop };
  });
  assert.equal(visibility.visible, true);
  assert.ok(visibility.scrollTop > 0);
  const after = await frame.evaluate(() => window.MarkdownHost.snapshot());
  assert.deepEqual(await page.evaluate(() => {
    window.__stopRevealEvents();
    return window.__revealLocks;
  }), [], "file reveal locked the editor");
  for (const key of ["documentID", "sessionID", "revision", "text", "anchor", "head", "scrollTop"])
    assert.equal(after[key], before[key], `${key} changed during file reveal`);
  assert.equal(await fs.readFile(targetFile, "utf8"), source);
  const stateAfterReveal = await app.evaluate(() => globalThis.__qa.state());
  assert.equal(stateAfterReveal.doc.path, stateBeforeReveal.doc.path);
  assert.equal(stateAfterReveal.doc.sessionID, stateBeforeReveal.doc.sessionID);
  assert.equal(stateAfterReveal.root, stateBeforeReveal.root);
  assert.equal(stateAfterReveal.doc.dirty, true);
  assert.equal(await page.locator(".tree-item").filter({ hasText: "aaa-other" }).getAttribute("aria-expanded"), "false");
  checks.push("offscreen target, collapsed ancestors, selection, repeated click while disabled, unchanged editor snapshot and disk source");
  await fs.mkdir("Windows/test-results", { recursive: true });
  await page.mouse.move(600, 30);
  await page.screenshot({ path: "Windows/test-results/reveal-current-night.png" });

  assert.equal((await call("settings", { patch: { autosave: true } })).ok, true);
  await frame.evaluate(() => {
    const snapshot = window.MarkdownHost.snapshot();
    window.MarkdownHost.receive({ type: "insert", sessionID: snapshot.sessionID, documentID: snapshot.documentID, text: "QA autosave" });
  });
  await page.waitForFunction(() => document.querySelector("#save-state").textContent === "저장 안 됨");
  const beforeAutosave = await frame.evaluate(() => window.MarkdownHost.snapshot());
  await button.click();
  await page.waitForFunction(() => document.querySelector("#save-state").textContent === "저장됨");
  assert.equal(await fs.readFile(targetFile, "utf8"), beforeAutosave.text);
  checks.push("file reveal leaves the editor unlocked and pending autosave still completes");
  const beforeMissing = await frame.evaluate(() => window.MarkdownHost.snapshot());

  await fs.unlink(targetFile);
  await page.evaluate(() => document.querySelector("#reveal-current").dispatchEvent(new MouseEvent("click", { bubbles: true })));
  await page.waitForFunction(() => {
    const notice = document.querySelector("#notice");
    return !notice.hidden && /현재 문서|새로 고침/.test(notice.textContent);
  });
  const afterMissing = await frame.evaluate(() => window.MarkdownHost.snapshot());
  for (const key of ["documentID", "sessionID", "revision", "text", "anchor", "head", "scrollTop"])
    assert.equal(afterMissing[key], beforeMissing[key], `${key} changed after the current file disappeared`);
  const missingState = await app.evaluate(() => globalThis.__qa.state());
  assert.equal(missingState.doc.path, targetFile);
  assert.equal(missingState.root, workspace);
  assert.deepEqual(errors, []);
  checks.push("deleted current file reports visible status without changing the open document or root");

  console.log(JSON.stringify({ passed: true, checks }, null, 2));
} catch (error) {
  failure = error;
  const page = await app.firstWindow();
  console.error("[reveal-current] status", await page.evaluate(() => ({
    notice: document.querySelector("#notice")?.textContent,
    hidden: document.querySelector("#notice")?.hidden,
    buttonDisabled: document.querySelector("#reveal-current")?.disabled,
    buttonReason: document.querySelector("#reveal-current")?.title,
    saveState: document.querySelector("#save-state")?.textContent,
  })));
  console.error("[reveal-current] failure", error.stack || error);
} finally {
  await closeElectron(app);
  await fs.rm(data, { recursive: true, force: true });
  if (failure) process.exitCode = 1;
}
