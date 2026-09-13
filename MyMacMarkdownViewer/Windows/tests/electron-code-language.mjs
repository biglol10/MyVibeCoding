import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { editorFrame, closeElectron } from './electron-fixtures.mjs';

const data = await fs.mkdtemp(path.join(os.tmpdir(), 'markdown-language-host-'));
const file = path.join(data, '언어 변경.md');
const source = '# 코드 언어\n\n~~~py  title="Example"\nvalue = "한글 보존"\nprint(value)\n~~~\n\n뒤 문단\n';
const original = Buffer.from('\ufeff' + source.replaceAll('\n', '\r\n'));
await fs.writeFile(file, original);
const app = await electron.launch({
  executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),
  args: [path.resolve('Windows'), '--qa-data', data],
});
const errors = [];
try {
  const page = await app.firstWindow();
  page.setDefaultTimeout(15000);
  page.on('pageerror', error => errors.push(error.message));
  const frame = await editorFrame(page);
  const invoke = (action, payload = {}) => page.evaluate(([name, value]) => window.desktop.invoke(name, value), [action, payload]);
  await app.evaluate(async (_electronApp, folder) => globalThis.__qa.grant(folder), data);
  assert.equal((await invoke('settings', { patch: { theme: 'night', autosave: false } })).ok, true);
  assert.equal((await invoke('open', { path: file })).ok, true);
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().documentID === expected, file);
  const language = frame.getByRole('combobox', { name: '코드 언어', exact: true });
  await language.waitFor();
  await language.selectOption('javascript');
  const changed = source.replace('~~~py  title=', '~~~javascript  title=');
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, changed);
  assert.equal((await invoke('save')).ok, true);
  assert.deepEqual(await fs.readFile(file), Buffer.from('\ufeff' + changed.replaceAll('\n', '\r\n')));
  assert.equal((await invoke('command', { command: 'undo' })).ok, true);
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, source);
  assert.equal((await invoke('save')).ok, true);
  assert.deepEqual(await fs.readFile(file), original);
  assert.equal((await invoke('command', { command: 'redo' })).ok, true);
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, changed);
  await fs.mkdir('Windows/test-results', { recursive: true });
  await page.screenshot({ path: 'Windows/test-results/code-language-night.png' });
  assert.equal((await invoke('command', { command: 'undo' })).ok, true);
  await frame.waitForFunction(expected => window.MarkdownHost.snapshot().text === expected, source);
  assert.equal((await invoke('save')).ok, true);
  const bytes = await fs.readFile(file);
  assert.deepEqual(bytes, original);
  assert.deepEqual(errors, []);
  const report = {
    passed: true, environment: 'Electron on macOS arm64; actual Windows OS not exercised',
    changedOnlyFenceLanguage: true, preservedFenceAndMetadata: true,
    preservedUTF8BOMAndCRLF: true, savedChangedLanguage: true, undoRedoPassed: true,
    restoredFileSHA256: crypto.createHash('sha256').update(bytes).digest('hex'), rendererErrors: errors,
  };
  await fs.writeFile('Windows/test-results/code-language.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} finally {
  await closeElectron(app);
  await fs.rm(data, { recursive: true, force: true });
}
