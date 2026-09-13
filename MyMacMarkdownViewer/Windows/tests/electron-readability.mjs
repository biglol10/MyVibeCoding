import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { editorFrame, closeElectron } from './electron-fixtures.mjs';

const source = '# 읽기 편안함\n\n[참고 문서](https://example.invalid/long/markdown/reference?section=readability)와 `inline_code`를 확인합니다.\n\n```python\ndef grade_by_model(task, solution):\n    prompt = f"Task: {task}"\n    # 결과를 읽습니다\n    return chat(prompt, score=3)\n```\n\n| 항목 | 설명 |\n| --- | --- |\n| 링크 | [안내](https://example.invalid/guide) |\n\n마지막 문단\n';
const data = await fs.mkdtemp(path.join(os.tmpdir(), 'markdown-readability-'));
const file = path.join(data, '링크와 코드 가독성.md');
await fs.writeFile(file, source);
const app = await electron.launch({
  executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
  args: [path.resolve('Windows'), '--qa-data', data],
});
const errors = [], observations = [];
function contrast(a, b) {
  const luminance = value => value.match(/[\d.]+/g).slice(0, 3).map(Number).map(n => n / 255)
    .map(n => n <= .04045 ? n / 12.92 : ((n + .055) / 1.055) ** 2.4)
    .reduce((sum, n, i) => sum + n * [.2126, .7152, .0722][i], 0);
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
}
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  page.on('pageerror', error => errors.push(error.message));
  const frame = await editorFrame(page);
  const call = (action, payload = {}) => page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  await app.evaluate(async (_electronApp, folder) => globalThis.__qa.grant(folder), data);
  assert.equal((await call('open', { path: file })).ok, true);
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().documentID === expected, file);
  await fs.mkdir('Windows/test-results', { recursive: true });
  for (const theme of ['night', 'light', 'dark']) {
    // Exercise the visible settings form, including the host-to-editor bridge.
    await page.getByRole('button', { name: '설정', exact: true }).click();
    await page.locator('#set-theme').selectOption(theme);
    await page.locator('#save-settings').click();
    await frame.waitForFunction(expected => document.documentElement.dataset.theme === expected, theme);
    await frame.evaluate(() => { const s = window.MarkdownHost.snapshot(); window.MarkdownHost.receive({ type: 'jump', ...s, from: 0, to: 0 }); });
    const preview = frame.locator('pre code').first();
    await preview.waitFor();
    const reading = await preview.evaluate(n => ({ size: parseFloat(getComputedStyle(n).fontSize), height: getComputedStyle(n).lineHeight }));
    assert.ok(reading.size >= 15, `Small code in ${theme}: ${reading.size}`);
    await frame.locator('.md-link').first().click();
    const link = await frame.locator('.tok-url').first().evaluate(n => ({ color: getComputedStyle(n).color, background: getComputedStyle(document.body).backgroundColor }));
    assert.ok(contrast(link.color, link.background) >= 4.5, `URL contrast in ${theme}: ${JSON.stringify(link)}`);
    await preview.click();
    const code = frame.locator('.code-source-line').filter({ hasText: 'def grade_by_model' });
    await code.waitFor();
    const editing = await code.evaluate(n => ({ size: parseFloat(getComputedStyle(n).fontSize), height: getComputedStyle(n).lineHeight }));
    assert.ok(Math.abs(reading.size - editing.size) < .1, `Code changes size on click in ${theme}`);
    assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().text), source);
    await page.screenshot({ path: `Windows/test-results/readability-${theme}.png` });
    observations.push({ theme, reading, editing, link, linkContrast: contrast(link.color, link.background) });
  }
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(900, 640));
  await page.getByRole('button', { name: '설정', exact: true }).click();
  const saveBox = await page.locator('#save-settings').boundingBox();
  assert.ok(saveBox && saveBox.y + saveBox.height <= await page.evaluate(() => innerHeight), 'Settings save button is clipped');
  await page.locator('#save-settings').click();
  const overflow = await frame.evaluate(() => {
    const n = document.querySelector('.cm-scroller');
    return n.scrollWidth - n.clientWidth;
  });
  assert.ok(overflow <= 2, `Narrow editor overflows horizontally by ${overflow}px`);
  await page.screenshot({ path: 'Windows/test-results/readability-compact.png' });
  assert.equal(await fs.readFile(file, 'utf8'), source);
  assert.deepEqual(errors, []);
  const report = { passed: true, environment: 'Electron on macOS; Windows OS not exercised', observations, compactWindow: { width: 900, height: 640 }, originalFileUnchanged: true, rendererErrors: errors };
  await fs.writeFile('Windows/test-results/readability.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} finally {
  await closeElectron(app);
  await fs.rm(data, { recursive: true, force: true });
}
