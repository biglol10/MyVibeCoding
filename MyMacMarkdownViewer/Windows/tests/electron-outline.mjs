import { editorFrame, closeElectron } from './electron-fixtures.mjs';
import { _electron as electron } from "../../Editor/node_modules/playwright/index.mjs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";

const data = await fs.mkdtemp(path.join(os.tmpdir(), "mymarkdown-outline-"));
const workspace = path.join(data, "outline");
const first = path.join(workspace, "outline.md");
const second = path.join(workspace, "second.md");
const noHeadings = path.join(workspace, "plain.md");
const source = [
  "# 소개",
  "", "첫 문단", "", "### 건너뛴 하위 제목", "", "본문", "",
  "## 같은 제목", "", "첫 번째", "", "## 같은 제목", "", "두 번째", "",
  "## Café", "", "NFC 검색", "",
  "# 아주 긴 한글 제목이 이백이십 픽셀 목차 사이드바에서 안전하게 잘려서 표시되는지 확인합니다", "", "끝",
  ...Array.from({ length: 80 }, (_, index) => `스크롤 위치 확인용 본문 ${index + 1}`),
].join("\n");
await fs.mkdir(workspace, { recursive: true });
await fs.writeFile(first, source);
await fs.writeFile(second, "# 두 번째 문서\n\n## 새 제목\n");
await fs.writeFile(noHeadings, "제목 없는 일반 문서\n");

const app = await electron.launch({
  executablePath: path.resolve("Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"),
  args: [path.resolve(process.env.PACKAGED_APP || "Windows"), "--qa-data", data],
});
let failure = null;
const stage = (name) => console.log(`[outline] ${name}`);

try {
  stage("window ready");
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  const frame = await editorFrame(page);
  await frame.waitForFunction(() => window.MarkdownHost?.snapshot);
  await app.evaluate(async (_, folder) => globalThis.__qa.grant(folder), workspace);
  const call = (action, payload = {}) => page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setContentSize(800, 560));
  await page.locator("#resize").press("ArrowLeft");
  await page.locator("#resize").press("ArrowLeft");
  assert.equal((await call("open", { path: first })).ok, true);
  await frame.waitForFunction(value => window.MarkdownHost.snapshot().documentID === value, first);
  await page.getByRole("tab", { name: "목차", exact: true }).click();
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor();
  stage("initial outline");

  assert.equal(await page.locator("#sidebar").evaluate(node => Math.round(node.getBoundingClientRect().width)), 220);
  const long = page.locator(".outline-link").filter({ hasText: "아주 긴 한글 제목" });
  assert.equal(await long.evaluate(node => node.scrollWidth > node.clientWidth), true);
  assert.ok((await long.getAttribute("title")).includes("아주 긴 한글 제목"));
  const introToggle = page.locator(".outline-row").filter({ hasText: "소개" }).locator(".outline-toggle");
  await introToggle.focus();
  await page.keyboard.press("Space");
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor({ state: "hidden" });
  assert.equal(await page.evaluate(() => document.activeElement?.dataset.outlineToggleId), await introToggle.getAttribute("data-outline-toggle-id"));
  await page.keyboard.press("Enter");
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor();
  assert.equal(await page.evaluate(() => document.activeElement?.dataset.outlineToggleId), await introToggle.getAttribute("data-outline-toggle-id"));
  await introToggle.click();
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor({ state: "hidden" });
  await fs.mkdir("Windows/test-results", { recursive: true });
  await page.screenshot({ path: "Windows/test-results/outline-collapsed.png" });
  stage("keyboard collapse");

  const query = page.getByPlaceholder("목차에서 찾기");
  await query.focus();
  await page.evaluate(() => {
    window.__outlineChildMutations = 0;
    new MutationObserver(records => window.__outlineChildMutations += records.filter(record => record.type === "childList").length)
      .observe(document.querySelector("#outline"), { childList: true });
  });
  await frame.locator(".cm-scroller").evaluate(node => {
    node.scrollTop = node.scrollHeight;
    node.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(250);
  assert.equal(await page.evaluate(() => document.activeElement?.id), "outline-query");
  assert.equal(await page.evaluate(() => window.__outlineChildMutations), 0);
  await query.fill("  건너뛴 하위  ");
  await page.locator(".outline-link").filter({ hasText: "소개" }).waitFor();
  assert.equal(await page.locator(".outline-link").count(), 2);
  assert.equal(await page.locator("#collapse-outline").isDisabled(), true);
  assert.equal(await introToggle.isDisabled(), true);
  assert.equal(await introToggle.getAttribute("aria-expanded"), "true");
  await page.screenshot({ path: "Windows/test-results/outline-search.png" });
  stage("search and screenshot");
  await page.locator("#clear-outline-search").click();
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor({ state: "hidden" });

  await page.getByRole("tab", { name: "파일", exact: true }).click();
  await page.getByRole("tab", { name: "목차", exact: true }).click();
  assert.equal(await query.inputValue(), "");
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor({ state: "hidden" });

  await page.locator("#expand-outline").click();
  const duplicates = page.locator(".outline-link").filter({ hasText: "같은 제목" });
  assert.equal(await duplicates.count(), 2);
  await duplicates.nth(1).click();
  await frame.waitForFunction(offset => window.MarkdownHost.snapshot().anchor === offset, source.lastIndexOf("## 같은 제목"));

  await query.fill("  CAFE\u0301  ");
  assert.equal(await page.locator(".outline-link").count(), 2);
  await page.locator("#clear-outline-search").click();
  await query.fill("없는 제목");
  assert.equal(await page.locator(".outline-link").count(), 0);
  assert.equal(await page.locator("#outline").innerText(), "일치하는 제목이 없습니다.");
  await page.locator("#clear-outline-search").click();

  await page.locator("#collapse-outline").click();
  await page.locator(".outline-link").filter({ hasText: "건너뛴 하위 제목" }).waitFor({ state: "hidden" });
  const changedSource = source.replace("### 건너뛴 하위 제목", "### 변경된 하위 제목");
  await frame.evaluate(text => window.MarkdownHost.receive({ type: "insert", ...window.MarkdownHost.snapshot(), text }), changedSource);
  await page.locator(".outline-link").filter({ hasText: "변경된 하위 제목" }).waitFor();
  await query.fill("변경된");
  stage("heading edit reset");
  assert.equal((await call("save")).ok, true);
  await page.waitForFunction(() => document.querySelector("#save-state").textContent === "저장됨");
  stage("edited document saved");

  assert.equal((await call("open", { path: second })).ok, true);
  await frame.waitForFunction(value => window.MarkdownHost.snapshot().documentID === value, second);
  await page.locator(".outline-link").filter({ hasText: "새 제목" }).waitFor();
  assert.equal(await query.inputValue(), "");
  assert.equal(await page.locator("#collapse-outline").isDisabled(), false);
  assert.equal((await call("open", { path: noHeadings })).ok, true);
  await frame.waitForFunction(value => window.MarkdownHost.snapshot().documentID === value, noHeadings);
  await page.waitForFunction(() => document.querySelector("#outline").textContent.includes("문서의 제목"));
  assert.equal(await page.locator("#collapse-outline").isDisabled(), true);
  assert.equal(await page.locator("#expand-outline").isDisabled(), true);
  assert.deepEqual(errors, []);
  stage("session reset");
  console.log(JSON.stringify({ passed: true, checks: ["800x560 resized to 220px sidebar", "long Korean heading title and ellipsis", "skipped levels and duplicate headings", "Space/Enter toggle focus restoration", "collapse/search/restore and tab retention", "NFC case search and empty result", "scroll position retains focus without outline DOM replacement", "actual outline jump", "actual heading edit and session state reset"] }, null, 2));
} catch (error) {
  failure = error;
  console.error("[outline] failure", error.stack || error);
} finally {
  await closeElectron(app);
  if (failure) process.exitCode = 1;
}
