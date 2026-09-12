import { editorFrame, closeElectron } from './electron-fixtures.mjs';
import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const data = await fs.mkdtemp(path.join(os.tmpdir(), 'mymarkdown-navigation-'));
const workspace = path.join(data, '한글 작업 폴더');
const notes = path.join(workspace, '프로젝트', '회의');
const first = path.join(notes, '가나다 회의.md');
const second = path.join(notes, '라마바 회의.md');
await fs.mkdir(notes, { recursive: true });
await fs.writeFile(first, '# 가나다 회의\n\n원본은 바뀌면 안 됩니다.\n');
await fs.writeFile(second, '# 라마바 회의\n\n두 번째 문서입니다.\n');

const app = await electron.launch({
  executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
  args: [path.resolve(process.env.PACKAGED_APP || 'Windows'), '--qa-data', data],
});
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const frame = await editorFrame(page);
  await frame.waitForFunction(() => window.MarkdownHost?.snapshot);
  await app.evaluate(async (_, folder) => globalThis.__qa.grant(folder), workspace);

  const fileMenu = page.locator('.app-menus details').first();
  await fileMenu.locator('summary').click();
  await fileMenu.locator('[data-action="quickOpen"]').click();
  const dialog = page.locator('#quick-open-dialog');
  const input = dialog.getByLabel('빠른 열기 검색');
  assert.equal(await input.getAttribute('role'), 'combobox');
  assert.equal(await input.getAttribute('aria-controls'), 'quick-open-results');
  assert.equal(await input.getAttribute('aria-expanded'), 'true');
  await input.fill('프로젝트/회의');
  const resultButtons = dialog.locator('.quick-list button');
  await resultButtons.nth(0).waitFor();
  assert.equal(await resultButtons.count(), 2);
  await input.press('Enter');
  await dialog.waitFor({ state: 'hidden' });
  await frame.waitForFunction(value => window.MarkdownHost.snapshot().documentID === value, first);
  assert.equal(await fs.readFile(first, 'utf8'), '# 가나다 회의\n\n원본은 바뀌면 안 됩니다.\n');

  await page.keyboard.press('Control+P');
  await input.fill('프로젝트/회의');
  const results = dialog.locator('.quick-result');
  await results.nth(0).waitFor();
  const openedID = await frame.evaluate(() => window.MarkdownHost.snapshot().documentID);
  await input.dispatchEvent('compositionstart');
  await input.press('Enter');
  assert.equal(await dialog.evaluate(node => node.open), true);
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);
  await input.dispatchEvent('compositionend');
  await input.press('Enter');
  await dialog.waitFor({ state: 'hidden' });
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);

  await page.keyboard.press('Control+P');
  await input.fill('프로젝트/회의');
  await input.dispatchEvent('keydown', { key: 'Enter', keyCode: 229 });
  await dialog.locator('form').evaluate(node => node.requestSubmit());
  assert.equal(await dialog.evaluate(node => node.open), true);
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);
  await input.press('Enter');
  await dialog.waitFor({ state: 'hidden' });

  await page.keyboard.press('Control+P');
  await input.fill('프로젝트/회의');
  assert.equal(await results.nth(0).getAttribute('aria-selected'), 'true');
  assert.equal(await input.getAttribute('aria-activedescendant'), await results.nth(0).getAttribute('id'));
  await input.dispatchEvent('keydown', { key: 'ArrowDown', isComposing: true });
  assert.equal(await results.nth(0).getAttribute('aria-selected'), 'true');
  await input.dispatchEvent('keydown', { key: 'ArrowDown', keyCode: 229 });
  assert.equal(await results.nth(0).getAttribute('aria-selected'), 'true');
  await input.press('ArrowDown');
  assert.equal(await results.nth(1).getAttribute('aria-selected'), 'true');
  await input.press('ArrowUp');
  assert.equal(await results.nth(0).getAttribute('aria-selected'), 'true');
  await input.press('ArrowDown');
  assert.equal(await results.nth(1).getAttribute('aria-selected'), 'true');
  await fs.unlink(second);
  await page.waitForFunction(() => ![...document.querySelectorAll('.tree-item')].some(node => node.textContent.includes('라마바 회의.md')));
  await page.waitForFunction(() => {
    const items = [...document.querySelectorAll('#quick-open-dialog .quick-result')];
    return items.length === 1 && items[0].getAttribute('aria-selected') === 'true';
  });
  await page.keyboard.press('Escape');

  for (let index = 0; index < 32; index += 1)
    await fs.writeFile(path.join(notes, `행 ${String(index).padStart(2, '0')}.md`), '# 긴 목록\n');
  await page.waitForFunction(() => [...document.querySelectorAll('.tree-item')].some(node => node.textContent.includes('행 31.md')));
  await page.keyboard.press('Control+P');
  await input.fill('없는 파일');
  assert.equal(await dialog.locator('.quick-list').innerText(), '일치하는 파일이 없습니다.');
  await input.press('Enter');
  assert.equal(await dialog.evaluate(node => node.open), true);
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);
  await dialog.getByRole('button', { name: '닫기', exact: true }).click();
  assert.equal(await dialog.evaluate(node => node.open), false);
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);

  await page.evaluate(() => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'p', ctrlKey: true, altKey: true, bubbles: true })));
  assert.equal(await dialog.evaluate(node => node.open), false);

  const refreshed = path.join(notes, '새로 생긴 회의.md');
  await fs.writeFile(refreshed, '# 새 문서\n');
  await page.waitForFunction(name => [...document.querySelectorAll('.tree-item')].some(node => node.textContent.includes(name)), '새로 생긴 회의.md');
  await page.keyboard.press('Control+P');
  assert.equal(await input.inputValue(), '');
  await input.fill('새로 생긴');
  assert.equal(await results.count(), 1);
  assert.ok((await results.nth(0).innerText()).includes('프로젝트/회의/새로 생긴 회의.md'));
  await dialog.getByRole('button', { name: '닫기', exact: true }).click();
  assert.equal(await dialog.evaluate(node => node.open), false);
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().documentID), openedID);

  await page.keyboard.press('Control+P');
  await input.fill('행');
  assert.equal(await results.count(), 30);
  for (let index = 0; index < 25; index += 1) await input.press('ArrowDown');
  const list = dialog.locator('.quick-list');
  const scrollBefore = await list.evaluate(node => node.scrollTop);
  assert.ok(scrollBefore > 0);
  assert.equal(await results.nth(25).evaluate((node, container) => {
    const item = node.getBoundingClientRect(), parent = document.querySelector(container).getBoundingClientRect();
    return item.top >= parent.top && item.bottom <= parent.bottom;
  }, '#quick-open-results'), true);
  await input.press('ArrowDown');
  assert.ok((await list.evaluate(node => node.scrollTop)) >= scrollBefore);
  await page.keyboard.press('Escape');

  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setContentSize(800, 560));
  await page.keyboard.press('Control+P');
  await input.fill('프로젝트/회의/새로 생긴 회의.md');
  const box = await dialog.boundingBox();
  assert.ok(box.x >= 0 && box.x + box.width <= 800 && box.y >= 0 && box.y + box.height <= 560);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await fs.mkdir('Windows/test-results', { recursive: true });
  await page.screenshot({ path: 'Windows/test-results/navigation-quick-open.png' });
  await page.keyboard.press('Escape');

  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ passed: true, checks: ['Ctrl+P quick open and Ctrl+Alt+P exclusion', 'Korean relative-path search', 'combobox/listbox active option semantics', 'ArrowUp/ArrowDown and IME composition preservation', 'compositionstart Enter and keyCode 229 requestSubmit keep the document', 'compositionend then normal Enter opens', 'Escape and Close button retain the document with and without results', 'empty-result Enter does not close or open another file', 'open dialog refreshes entries and resets a removed selection', 'reopen clears query and refreshes entries', '30-result keyboard scrolling stays visible', '800x560 dialog has no horizontal overflow and screenshot', 'opened source unchanged'] }, null, 2));
} finally {
  await closeElectron(app);
}
