import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { editorFrame, closeElectron } from './electron-fixtures.mjs';
const data = await fs.mkdtemp(path.join(os.tmpdir(), 'markdown-cursor-'));
const file = path.join(data, 'code-cursor.md');
const body = 'deny_paths: ["/etc", "/secrets"]';
const source = `BEFORE_MARKER\n\n\n\`\`\`\n${body}\n\`\`\`\n\n\nAFTER_MARKER\n`;
await fs.writeFile(file, source);
const app = await electron.launch({ executablePath: path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'), args: [path.resolve('Windows'), '--qa-data', data] });
const errors = [];
try {
  const page = await app.firstWindow(); page.on('pageerror', e => errors.push(e.message));
  const frame = await editorFrame(page);
  const invoke = (action, payload = {}) => page.evaluate(([action, payload]) => window.desktop.invoke(action, payload), [action, payload]);
  await app.evaluate(async (_app, folder) => globalThis.__qa.grant(folder), data);
  assert.equal((await invoke('open', { path: file })).ok, true);
  await frame.waitForFunction(file => window.MarkdownHost.snapshot().documentID === file, file);
  const jump = position => frame.evaluate(position => { const state = window.MarkdownHost.snapshot(); window.MarkdownHost.receive({ type: 'jump', sessionID: state.sessionID, documentID: state.documentID, from: position }); }, position);
  const measure = () => frame.evaluate(async body => {
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const surface = [...document.querySelectorAll('pre, .cm-line.code-source-line')].find(el => el.textContent.includes(body));
    const header = document.querySelector('.code-language-select');
    const scroller = document.querySelector('.cm-scroller');
    const after = [...document.querySelectorAll('.cm-line')].find(el => el.textContent === 'AFTER_MARKER');
    const box = surface.getBoundingClientRect(), control = header.getBoundingClientRect(), style = getComputedStyle(surface);
    return { top: box.top + scroller.scrollTop, height: box.height, headerGap: box.top - control.bottom,
      after: after.getBoundingClientRect().top + scroller.scrollTop, paddingTop: style.paddingTop, borderTop: style.borderTopWidth };
  }, body);
  const checks = [];
  for (const theme of ['night', 'dark', 'light']) {
    await invoke('settings', { patch: { theme, autosave: false } }); await jump(0);
    const baseline = await measure();
    for (const position of [source.indexOf('```'), source.indexOf(body), source.lastIndexOf('```'), source.lastIndexOf('```') + 4, 0]) {
      await jump(position); const current = await measure();
      for (const key of ['top', 'height', 'headerGap', 'after']) assert.ok(Math.abs(current[key] - baseline[key]) < 1, `${theme} ${position}: ${key}`);
      assert.equal(current.paddingTop, '16px'); assert.equal(current.borderTop, '1px'); assert.ok(current.headerGap > 0);
      checks.push({ theme, position, ...current });
    }
  }
  await invoke('settings', { patch: { theme: 'night' } }); await jump(0);
  await frame.locator('pre code').click();
  for (const key of ['Home', 'ArrowUp', 'ArrowDown', 'End', 'ArrowDown']) {
    await frame.locator('.cm-content').press(key); const current = await measure(); assert.ok(current.headerGap > 0); assert.equal(current.paddingTop, '16px');
  }
  await fs.mkdir('Windows/test-results', { recursive: true });
  await page.screenshot({ path: 'Windows/test-results/code-cursor-night.png' });
  assert.equal((await invoke('save')).ok, true); assert.equal(await fs.readFile(file, 'utf8'), source); assert.deepEqual(errors, []);
  const report = { passed: true, environment: 'Electron 44.3.0 on macOS arm64; actual Windows OS unverified', checks, keyboardBoundaryFlow: true, savedSourceUnchanged: true, errors };
  await fs.writeFile('docs/code-cursor-windows-verification.json', JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ passed: true, states: checks.length, keyboardBoundaryFlow: true, savedSourceUnchanged: true }));
} finally { await closeElectron(app); await fs.rm(data, { recursive: true, force: true }); }
