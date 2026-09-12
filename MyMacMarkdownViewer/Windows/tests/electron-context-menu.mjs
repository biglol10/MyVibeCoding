import { editorFrame, closeElectron } from './electron-fixtures.mjs';
import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const data = await fs.mkdtemp(path.join(os.tmpdir(), 'mymarkdown-context-'));
const folder = path.join(data, 'qa-data');
const appPath = path.resolve(process.env.PACKAGED_APP || 'Windows');
await fs.mkdir(folder);
const first = path.join(folder, '원본 문서.md');
const second = path.join(folder, '이름을 바꿀 문서.md');
await fs.writeFile(first, '# 원본\n원본 내용\n');
await fs.writeFile(second, '# 변경 전\n');
await fs.mkdir(path.join(folder, '끝 폴더'));
for (let index = 0; index < 28; index += 1)
  await fs.writeFile(path.join(folder, `행 ${String(index).padStart(2, '0')}.md`), '# 행\n');

const app = await electron.launch({
  executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
  args: [appPath, '--qa-data', data],
});
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const frame = await editorFrame(page);
  await frame.waitForFunction(() => window.MarkdownHost?.snapshot);
  await app.evaluate(async (_, value) => globalThis.__qa.grant(value), folder);

  const original = page.locator('.tree-item').filter({ hasText: '원본 문서.md' });
  const originalBox = await original.boundingBox();
  await original.click({ button: 'right', position: { x: 18, y: 12 } });
  const menu = page.locator('#item-context-menu');
  await menu.waitFor();
  await page.screenshot({ path: path.resolve("build/context-windows-file-menu.png") });
  const initialMenuBox = await menu.boundingBox();
  assert.ok(Math.abs(initialMenuBox.x - (originalBox.x + 18)) <= 1);
  assert.ok(Math.abs(initialMenuBox.y - (originalBox.y + 12)) <= 1);
  assert.equal(await page.locator('.folder-menu').getAttribute('open'), null);
  assert.equal(await menu.getByRole('menuitem', { name: '열기' }).count(), 1);
  assert.equal(await menu.getByRole('menuitem', { name: '여기에 새 문서…' }).count(), 1);
  assert.equal(await menu.getByRole('menuitem', { name: '여기에 새 폴더…' }).count(), 1);
  assert.equal(await original.getAttribute('aria-selected'), 'true');
  await page.keyboard.press('Escape');
  assert.equal(await menu.isHidden(), true);
  assert.equal(await original.evaluate(node => node === document.activeElement), true);

  await original.click({ button: 'right' });
  await page.locator('#tree').evaluate(node => node.dispatchEvent(new Event('scroll')));
  assert.equal(await menu.isHidden(), true);
  await original.click({ button: 'right' });
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setContentSize(1000, 700));
  await page.waitForTimeout(100);
  assert.equal(await menu.isHidden(), true);
  await original.click({ button: 'right' });
  await frame.locator('body').click({ position: { x: 20, y: 20 } });
  assert.equal(await menu.isHidden(), true);

  const directory = page.locator('.tree-item').filter({ hasText: '끝 폴더' });
  await directory.scrollIntoViewIfNeeded();
  await directory.click({ button: 'right' });
  await page.screenshot({ path: path.resolve("build/context-windows-folder-menu.png") });
  const bounds = await menu.boundingBox();
  assert.ok(bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= await page.evaluate(() => innerWidth) && bounds.y + bounds.height <= await page.evaluate(() => innerHeight));
  assert.equal(await menu.getByRole('menuitem', { name: '여기에 새 문서…' }).count(), 1);
  await page.keyboard.press('Escape');

  const renamed = page.locator('.tree-item').filter({ hasText: '이름을 바꿀 문서.md' });
  await renamed.focus();
  await page.keyboard.press('Shift+F10');
  assert.equal(await menu.isVisible(), true);
  assert.equal(await menu.getByRole('menuitem', { name: '열기' }).evaluate(node => node === document.activeElement), true);
  await page.keyboard.press('ArrowDown');
  assert.equal(await menu.getByRole('menuitem', { name: '여기에 새 문서…' }).evaluate(node => node === document.activeElement), true);
  await page.keyboard.press('ArrowDown');
  assert.equal(await menu.getByRole('menuitem', { name: '여기에 새 폴더…' }).evaluate(node => node === document.activeElement), true);
  await page.keyboard.press('ArrowDown');
  assert.equal(await menu.getByRole('menuitem', { name: '복제' }).evaluate(node => node === document.activeElement), true);
  await page.keyboard.press('ArrowDown');
  assert.equal(await menu.getByRole('menuitem', { name: '이름 변경…' }).evaluate(node => node === document.activeElement), true);
  await page.keyboard.press('Enter');
  await page.locator('#item-input').fill('변경된 문서');
  await page.locator('#item-input').press('Enter');
  await page.locator('#item-dialog').waitFor({ state: 'hidden' });
  assert.equal(await fs.readFile(first, 'utf8'), '# 원본\n원본 내용\n');
  assert.equal(await fs.readFile(path.join(folder, '변경된 문서.md'), 'utf8'), '# 변경 전\n');

  await original.click({ button: 'right' });
  await menu.getByRole('menuitem', { name: '복제' }).click();
  await page.waitForFunction(() => [...document.querySelectorAll('.tree-item')].some(node => node.textContent.includes('원본 문서 복사본.md')));
  assert.equal(await fs.readFile(path.join(folder, '원본 문서 복사본.md'), 'utf8'), '# 원본\n원본 내용\n');

  await original.click({ button: 'right' });
  await menu.getByRole('menuitem', { name: '정보' }).click();
  await page.locator('#item-info-dialog').waitFor();
  assert.ok((await page.locator('#item-info').innerText()).includes('원본 문서.md'));
  await page.locator('#item-info-dialog button').click();

  await original.click({ button: 'right' });
  await menu.getByRole('menuitem', { name: '이 폴더에서 검색' }).click();
  await page.locator('[data-tab="search"]').waitFor();
  await page.locator('#search-query').fill('원본 내용');
  await page.locator('#search-query').press('Enter');
  await page.waitForFunction(() => document.querySelector('#search-results').textContent.includes('원본 문서.md'));
  assert.ok((await page.locator('#search-results').innerText()).includes('원본 문서.md'));
  // Editing a query invalidates both displayed matches and a response that was
  // already in flight, so an old replacement plan cannot become actionable.
  await page.locator('#search-query').fill('원본 내용');
  const pendingSearch = page.locator('#search-query').press('Enter');
  await page.locator('#search-query').fill('다른 검색어');
  await pendingSearch;
  await page.waitForTimeout(150);
  assert.equal(await page.locator('#search-results').innerText(), '');
  assert.equal(await page.locator('#reset-search-scope').isVisible(), true);
  await page.locator('#reset-search-scope').click();
  assert.equal(await page.locator('#reset-search-scope').isHidden(), true);
  assert.ok((await page.locator('#search-scope').innerText()).includes('전체 작업 폴더'));
  assert.equal(await page.locator('#search-results').innerText(), '');

  const view = page.locator('.app-menus details').filter({ has: page.locator('summary', { hasText: '보기' }) });
  for (const theme of ['dark', 'night', 'light']) {
    await view.locator('summary').click();
    await view.locator(`[data-theme="${theme}"]`).click();
    await page.waitForFunction(value => document.documentElement.dataset.theme === value, theme);
    await frame.waitForFunction(value => document.documentElement.dataset.theme === value, theme);
    assert.equal(await view.locator(`button[data-theme="${theme}"]`).getAttribute('aria-checked'), 'true');
  }
  const saved = JSON.parse(await fs.readFile(path.join(data, 'settings.json'), 'utf8'));
  assert.equal(saved.settings.theme, 'light');
  await app.evaluate(({ app: electronApp }) => electronApp.exit(0));
  await app.close();
  const restarted = await electron.launch({
    executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
    args: [appPath, '--qa-data', data],
  });
  try {
    const restartedPage = await restarted.firstWindow();
    restartedPage.setDefaultTimeout(15000);
    const restartedFrame = await editorFrame(restartedPage);
    await restartedFrame.waitForFunction(() => window.MarkdownHost?.snapshot);
    assert.equal(await restartedPage.evaluate(() => document.documentElement.dataset.theme), 'light');
    assert.equal(await restartedFrame.evaluate(() => document.documentElement.dataset.theme), 'light');
  } finally {
    await closeElectron(restarted);
  }
  await fs.writeFile(path.join(data, 'settings.json'), JSON.stringify({ ...saved, settings: { ...saved.settings, theme: 'unsupported' } }));
  const normalized = await electron.launch({
    executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
    args: [appPath, '--qa-data', data],
  });
  try {
    const normalizedPage = await normalized.firstWindow();
    normalizedPage.setDefaultTimeout(15000);
    await normalizedPage.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
  } finally {
    await closeElectron(normalized);
  }
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ passed: true, checks: ['file and folder contextual menus remain separate from root menu', 'pointer-positioned target selection and rename preserve another document', 'non-overwriting duplicate, metadata dialog, and selected-parent search', 'edge-clamped menu', 'scroll resize and iframe focus close the menu', 'Shift+F10 Arrow navigation Escape focus return', 'dark night light shell/editor persistence after relaunch', 'invalid saved theme normalizes to dark'] }, null, 2));
} finally {
  await closeElectron(app);
}
