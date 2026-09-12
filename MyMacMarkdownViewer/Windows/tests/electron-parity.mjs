import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const data = await fs.mkdtemp(path.join(os.tmpdir(), 'mymarkdown-parity-'));
const workspace = path.join(data, 'workspace');
const documentPath = path.join(workspace, 'guide.markdown');
const imagePath = path.join(data, 'image.png');
const invalidImagePath = path.join(data, 'invalid.png');
const oversizedImagePath = path.join(data, 'oversized.png');
const source = '한글 제목은 본문 문장입니다.\n\n```md\n# 한글 제목\n```\n\n한글 제목\n========\n\n본문\n';
await fs.mkdir(workspace);
await fs.writeFile(documentPath, source);
await fs.writeFile(imagePath, Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mNk+M/wHwAFAAH/e+m+7wAAAABJRU5ErkJggg==', 'base64'));
await fs.writeFile(invalidImagePath, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
await fs.writeFile(oversizedImagePath, Buffer.alloc(20 * 1024 * 1024 + 1));
const app = await electron.launch({
  executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
  args: [path.resolve(process.env.PACKAGED_APP || 'Windows'), '--qa-data', data],
});
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  const frame = page.frame({ url: 'app://editor/index.html' }) || await page.waitForEvent('framenavigated', { predicate: current => current.url() === 'app://editor/index.html' });
  await frame.waitForFunction(() => window.MarkdownHost?.snapshot);
  const call = (action, payload = {}) => page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  await app.evaluate(async (_, folder) => globalThis.__qa.grant(folder), workspace);
  await page.getByRole('treeitem', { name: 'guide.markdown' }).waitFor();
  let result = await call('open', { path: documentPath });
  assert.equal(result.ok, true, JSON.stringify(result));
  await frame.waitForFunction(value => window.MarkdownHost.snapshot().documentID === value, documentPath);
  result = await call('search', { query: '본문' });
  assert.equal(result.value.files.length, 1);
  result = await call('openLink', { href: '#%ED%95%9C%EA%B8%80-%EC%A0%9C%EB%AA%A9' });
  assert.equal(result.ok, true, JSON.stringify(result));
  await frame.waitForFunction(offset => window.MarkdownHost.snapshot().anchor === offset, source.indexOf('한글 제목\n========'));
  await frame.locator('.cm-content').click();
  await page.keyboard.press('Control+End');

  await app.evaluate(({ dialog }, file) => { dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [file] }); }, imagePath);
  result = await call('insertImage');
  assert.equal(result.ok, true, JSON.stringify(result));
  await frame.waitForFunction(() => window.MarkdownHost.snapshot().text.includes('![이미지](assets/image-'));
  const assets = await fs.readdir(path.join(workspace, 'assets'));
  assert.equal(assets.length, 1);
  assert.deepEqual(await fs.readFile(path.join(workspace, 'assets', assets[0])), await fs.readFile(imagePath));
  await call('command', { command: 'source' });
  await call('command', { command: 'source' });
  await call('openLink', { href: '#%ED%95%9C%EA%B8%80-%EC%A0%9C%EB%AA%A9' });
  const insertedImage = frame.locator('img');
  await insertedImage.waitFor({ state: 'attached' });
  await insertedImage.scrollIntoViewIfNeeded();
  await frame.waitForFunction(() => [...document.images].some(image => image.complete && image.naturalWidth === 1));
  await app.evaluate(({ dialog }) => { dialog.showOpenDialog = async () => ({ canceled: true, filePaths: [] }); });
  result = await call('insertImage');
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal((await fs.readdir(path.join(workspace, 'assets'))).length, 1);
  await app.evaluate(({ dialog }, file) => { dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [file] }); }, invalidImagePath);
  result = await call('insertImage');
  assert.equal(result.ok, false);
  assert.equal((await fs.readdir(path.join(workspace, 'assets'))).length, 1);
  await app.evaluate(({ dialog }, file) => { dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [file] }); }, oversizedImagePath);
  result = await call('insertImage');
  assert.equal(result.ok, false);
  assert.equal((await fs.readdir(path.join(workspace, 'assets'))).length, 1);

  await app.evaluate(({ shell }) => { globalThis.__revealTarget = null; shell.showItemInFolder = value => { globalThis.__revealTarget = value; }; });
  result = await call('reveal', { path: documentPath });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(await app.evaluate(() => globalThis.__revealTarget), documentPath);
  await app.evaluate(({ shell }) => { shell.openPath = async () => 'Explorer failed'; });
  result = await call('reveal', { path: workspace });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'Explorer failed');

  const viewMenu = page.locator('.app-menus details').filter({ has: page.locator('summary', { hasText: '보기' }) });
  await viewMenu.locator('summary').click();
  await viewMenu.locator('[data-theme="system"]').click();
  await page.waitForFunction(() => ['dark', 'light'].includes(document.documentElement.dataset.theme));
  await frame.waitForFunction(() => ['dark', 'light'].includes(document.documentElement.dataset.theme));
  await page.locator('.statusbar [data-action=settings]').click();
  await page.locator('#set-theme').selectOption('system');
  await page.locator('#save-settings').click();
  const saved = JSON.parse(await fs.readFile(path.join(data, 'settings.json'), 'utf8'));
  assert.equal(saved.settings.theme, 'system');
  assert.ok(['dark', 'light'].includes(await page.evaluate(() => document.documentElement.dataset.theme)));
  assert.equal(await page.locator('[data-theme="system"]').count(), 1);
  const editMenu = page.locator('.app-menus details').filter({ has: page.locator('summary', { hasText: '편집' }) });
  await editMenu.locator('summary').click();
  await editMenu.locator('[data-action="command:replace"]').click();
  await frame.locator('input[name="replace"]').waitFor();
  await frame.locator('input[name="search"]').fill('본문');
  await frame.locator('input[name="search"]').press('Enter');
  await frame.locator('.cm-searchMatch').first().waitFor();
  await frame.locator('input[name="replace"]').fill('교체됨');
  await frame.getByRole('button', { name: '다음', exact: true }).click();
  await frame.getByRole('button', { name: '바꾸기', exact: true }).click();
  await frame.waitForFunction(() => window.MarkdownHost.snapshot().text.includes('교체됨'));
  const formatMenu = page.locator('.app-menus details').filter({ has: page.locator('summary', { hasText: '서식' }) });
  const beforeCode = await frame.evaluate(() => window.MarkdownHost.snapshot().text);
  await formatMenu.locator('summary').click();
  await formatMenu.locator('[data-action="command:code"]').click();
  await frame.waitForFunction(before => window.MarkdownHost.snapshot().text !== before && window.MarkdownHost.snapshot().text.includes('``'), beforeCode);
  await fs.mkdir('Windows/test-results', { recursive: true });
  await page.screenshot({ path: 'Windows/test-results/parity-source.png' });
  await app.evaluate(({ nativeTheme }) => { nativeTheme.themeSource = 'light'; nativeTheme.emit('updated'); });
  await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
  await frame.waitForFunction(() => document.documentElement.dataset.theme === 'light');
  await app.evaluate(({ nativeTheme }) => { nativeTheme.themeSource = 'dark'; nativeTheme.emit('updated'); });
  await page.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
  await frame.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
  await app.evaluate(({ app: electronApp }) => electronApp.exit(0));
  await app.close();
  const restarted = await electron.launch({
    executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
    args: [path.resolve(process.env.PACKAGED_APP || 'Windows'), '--qa-data', data],
  });
  try {
    const restartedPage = await restarted.firstWindow();
    restartedPage.setDefaultTimeout(15000);
    const restartedFrame = restartedPage.frame({ url: 'app://editor/index.html' }) || await restartedPage.waitForEvent('framenavigated', { predicate: current => current.url() === 'app://editor/index.html' });
    await restartedFrame.waitForFunction(() => window.MarkdownHost?.snapshot);
    assert.equal(await restartedPage.locator('[data-theme="system"]').getAttribute('aria-checked'), 'true');
    assert.ok(['dark', 'light'].includes(await restartedPage.evaluate(() => document.documentElement.dataset.theme)));
    assert.ok(['dark', 'light'].includes(await restartedFrame.evaluate(() => document.documentElement.dataset.theme)));
  } finally {
    await restarted.evaluate(({ app: electronApp }) => electronApp.exit(0)).catch(() => {});
    await restarted.close().catch(() => {});
  }
  console.log(JSON.stringify({ passed: true, checks: ['markdown tree open and search', 'encoded Korean heading anchor ignores preceding prose', 'file picker image inserts while action lock is held', 'Explorer reveal uses selected approved file', 'system theme preference persists with resolved shell theme', 'replace and inline-code menus present'] }, null, 2));
} finally {
  await app.evaluate(({ app: electronApp }) => electronApp.exit(0)).catch(() => {});
  await app.close().catch(() => {});
}
