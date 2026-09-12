import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { editorFrame, closeElectron } from './electron-fixtures.mjs';

const data = await fs.mkdtemp(path.join(os.tmpdir(), 'markdown-code-preview-'));
const file = path.join(data, '미리보기 검증.md');
const source = '# 코드와 다이어그램 통합 검증\n\n```json\n{\n  "name": "한글",\n  "count": 2\n}\n```\n\n미리보기 사이 문단.\n\n```mermaid\ngraph LR\n A[시작] --> B[완료]\n```\n';
await fs.writeFile(file, source, 'utf8');
const initialHash = crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
const electronBinary = path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron');
const app = await electron.launch({ executablePath: electronBinary, args: [path.resolve('Windows'), '--qa-data', data] });
const ownedPid = app.process().pid;
const errors = [];
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(20000);
  page.on('pageerror', error => errors.push(error.message));
  const frame = await editorFrame(page);
  const call = (action, payload = {}) => page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  await app.evaluate(async (_electronApp, folder) => globalThis.__qa.grant(folder), data);
  const settings = await call('settings', { patch: { theme: 'night', autosave: false } });
  assert.equal(settings.ok, true, JSON.stringify(settings));
  const opened = await call('open', { path: file });
  assert.equal(opened.ok, true, JSON.stringify(opened));
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().documentID === expected, file);
  await frame.waitForFunction(() => document.documentElement.dataset.theme === 'night');
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().text), source);

  const codePreview = frame.locator('pre code').first();
  await codePreview.click();
  const codeLine = frame.locator('.code-source-line').filter({ hasText: '"count": 2' });
  await codeLine.waitFor({ state: 'visible' });
  const codeSurface = await codeLine.evaluate(node => ({
    background: getComputedStyle(node).backgroundColor,
    highlightedSpans: node.querySelectorAll('span').length,
  }));
  assert.notEqual(codeSurface.background, 'rgba(0, 0, 0, 0)', `Code source background is transparent: ${codeSurface.background}`);
  assert.ok(codeSurface.highlightedSpans > 0, 'Expected syntax-highlighted source spans');
  await codeLine.click();
  await page.keyboard.press('End');
  await page.keyboard.press('Shift+ArrowLeft');
  await page.keyboard.insertText('7');
  const editedCode = source.replace('"count": 2', '"count": 7');
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, editedCode);
  const undoCode = await call('command', { command: 'undo' });
  assert.equal(undoCode.ok, true, JSON.stringify(undoCode));
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, source);
  const savedCode = await call('save');
  assert.equal(savedCode.ok, true, JSON.stringify(savedCode));
  assert.equal(await fs.readFile(file, 'utf8'), source, 'Code edit undo should restore the exact source before save');

  const svg = frame.locator('.diagram-block svg').first();
  await svg.waitFor({ state: 'visible' });
  await svg.click({ position: { x: 20, y: 20 } });
  await svg.waitFor({ state: 'visible' });
  assert.equal(await frame.evaluate(() => window.MarkdownHost.snapshot().text), source);
  await frame.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  const diagramLine = frame.locator('.diagram-source-line').filter({ hasText: 'B[완료]' });
  await diagramLine.waitFor({ state: 'visible' });
  await svg.waitFor({ state: 'visible' });
  const labelStart = source.indexOf('완료');
  await frame.evaluate(({ from, to, text }) => {
    const snapshot = window.MarkdownHost.snapshot();
    window.MarkdownHost.receive({ type: 'jump', ...snapshot, from, to });
    window.MarkdownHost.receive({ type: 'insert', ...window.MarkdownHost.snapshot(), text });
  }, { from: labelStart, to: labelStart + 2, text: '확인' });
  const editedDiagram = source.replace('B[완료]', 'B[확인]');
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, editedDiagram);
  await svg.waitFor({ state: 'visible' });
  await frame.waitForFunction(() => document.querySelector('.diagram-block svg')?.textContent.includes('확인'));
  const undoDiagram = await call('command', { command: 'undo' });
  assert.equal(undoDiagram.ok, true, JSON.stringify(undoDiagram));
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, source);
  await svg.waitFor({ state: 'visible' });
  await frame.waitForFunction(() => document.querySelector('.diagram-block svg')?.textContent.includes('완료'));
  await frame.locator('.diagram-source-line').filter({ hasText: 'graph LR' }).waitFor({ state: 'visible' });
  const savedDiagram = await call('save');
  assert.equal(savedDiagram.ok, true, JSON.stringify(savedDiagram));
  const finalBytes = await fs.readFile(file);
  assert.equal(finalBytes.toString('utf8'), source, 'Diagram edit undo should restore exact source before save');
  const finalHash = crypto.createHash('sha256').update(finalBytes).digest('hex');
  assert.equal(finalHash, initialHash, 'Fixture source hash changed after undo and save');

  await fs.mkdir('Windows/test-results', { recursive: true });
  await page.screenshot({ path: 'Windows/test-results/code-preview-electron-night.png', fullPage: true });
  assert.deepEqual(errors, [], `Renderer exceptions: ${errors.join('; ')}`);
  const host = await app.evaluate(({ app: electronApp }) => ({
    appVersion: electronApp.getVersion(), platform: globalThis.process.platform,
    architecture: globalThis.process.arch, electronVersion: globalThis.process.versions.electron,
  }));
  console.log(JSON.stringify({
    passed: true, host, checks: [
      'Mac-host Electron app opened an isolated synthetic Markdown fixture',
      'Night theme reached the shared editor frame',
      'code preview click retained highlighted nontransparent editable source',
      'keyboard code edit and desktop undo restored exact text',
      'diagram SVG click preserved preview and source',
      'diagram source edit retained editable lines beside SVG and desktop undo restored exact text',
      'save preserved fixture bytes and SHA-256 after undo',
      'no renderer exceptions',
    ], screenshot: 'Windows/test-results/code-preview-electron-night.png',
    sourceSHA256: finalHash,
  }, null, 2));
} finally {
  await closeElectron(app);
  await fs.rm(data, { recursive: true, force: true });
}
try {
  process.kill(ownedPid, 0);
  throw new Error(`Owned Electron process ${ownedPid} remained after close`);
} catch (error) {
  if (error.code !== 'ESRCH') throw error;
}
