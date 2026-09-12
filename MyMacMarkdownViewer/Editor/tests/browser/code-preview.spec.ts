import { test, expect, type Page } from '@playwright/test';

const code = '# 코드 클릭\n\n```json\n{\n  "name": "한글",\n  "count": 2\n}\n```\n\n마지막 문단\n';
const diagram = '# 그림 클릭\n\n```mermaid\ngraph LR\n A[시작] --> B[완료]\n```\n\n마지막 문단\n';
const errors = new WeakMap<Page, string[]>();
test.beforeEach(async ({ page }) => {
  errors.set(page, []);
  page.on('pageerror', error => errors.get(page)!.push(error.message));
  await page.goto('/');
  await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(() => window.__editorTest!.settings({ theme: 'night' }));
});
test.afterEach(async ({ page }) => { expect(errors.get(page)).toEqual([]); });
const text = (page: Page) => page.evaluate(() => window.__editorTest!.snapshot().text);
async function lock(page: Page, locked: boolean) {
  await page.evaluate(locked => {
    const s = window.__editorTest!.snapshot();
    window.MarkdownHost.receive({ type: 'lock', sessionID: s.sessionID, documentID: s.documentID, locked });
  }, locked);
}

test('clicking code keeps a code surface while editing and undo preserves source', async ({ page }) => {
  await page.evaluate(source => window.__editorTest!.load(source), code);
  await page.locator('pre code').click();
  const line = page.locator('.code-source-line').filter({ hasText: '"name"' });
  await expect(line).toBeVisible();
  await expect(line).toHaveCSS('background-color', 'rgb(65, 70, 77)');
  await expect(line.locator('span')).not.toHaveCount(0);
  await expect(line.locator('.tok-string').filter({ hasText: '한글' })).toHaveCSS('color', 'rgb(178, 199, 152)');
  expect(await text(page)).toBe(code);
  await page.evaluate(source => window.__editorTest!.select(source.indexOf('한글') + 2), code);
  await page.keyboard.insertText(' 코드');
  expect(await text(page)).toBe(code.replace('한글', '한글 코드'));
  await expect(line).toBeVisible();
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await text(page)).toBe(code);
  await page.evaluate(() => window.__editorTest!.select(0));
  await expect(page.locator('pre code')).toContainText('"name": "한글"');
});

test('ordinary diagram click keeps its SVG and the edit control reveals source alongside it', async ({ page }) => {
  await page.evaluate(source => window.__editorTest!.load(source), diagram);
  const svg = page.locator('.diagram-block svg');
  await expect(svg).toBeVisible();
  await svg.click({ position: { x: 20, y: 20 } });
  await expect(svg).toBeVisible();
  expect(await text(page)).toBe(diagram);
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  await expect(page.locator('.code-source-line').filter({ hasText: 'graph LR' })).toBeVisible();
  await expect(svg).toBeVisible();
  await page.screenshot({ path: 'test-results/diagram-source-and-preview-night.png', fullPage: true });
  await page.getByRole('button', { name: '다이어그램 편집 완료', exact: true }).click();
  await expect(svg).toBeVisible();
  await expect(page.locator('.code-source-line')).toHaveCount(0);
  expect(await text(page)).toBe(diagram);
});

test('diagram edits refresh preview and share document undo and redo', async ({ page }) => {
  await page.evaluate(source => window.__editorTest!.load(source), diagram);
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  await page.evaluate(source => window.__editorTest!.select(source.indexOf('완료'), source.indexOf('완료') + 2), diagram);
  await page.keyboard.insertText('수정');
  await expect(page.locator('.diagram-block svg')).toContainText('수정');
  expect(await text(page)).toBe(diagram.replace('완료', '수정'));
  await page.evaluate(() => window.__editorTest!.command('undo'));
  await expect(page.locator('.diagram-block svg')).toContainText('완료');
  expect(await text(page)).toBe(diagram);
  await page.evaluate(() => window.__editorTest!.command('redo'));
  await expect(page.locator('.diagram-block svg')).toContainText('수정');
});

test('keyboard navigation into diagram source retains preview and source mode remains reversible', async ({ page }) => {
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('graph')); }, diagram);
  await expect(page.locator('.diagram-block svg')).toBeVisible();
  await expect(page.locator('.code-source-line').filter({ hasText: 'graph LR' })).toBeVisible();
  await page.evaluate(() => window.__editorTest!.command('source'));
  await expect(page.locator('.cm-content')).toContainText('```mermaid');
  await expect(page.locator('.diagram-block svg')).toHaveCount(0);
  await page.evaluate(() => window.__editorTest!.command('source'));
  await expect(page.locator('.diagram-block svg')).toBeVisible();
  expect(await text(page)).toBe(diagram);
});

test('read-only lock prevents diagram editing and keeps previews visible', async ({ page }) => {
  await page.evaluate(source => window.__editorTest!.load(source), diagram);
  await lock(page, true);
  await expect(page.getByRole('button', { name: '다이어그램 편집', exact: true })).toHaveCount(0);
  await page.locator('.diagram-block svg').click({ position: { x: 20, y: 20 } });
  await page.keyboard.insertText('잠금');
  await expect(page.locator('.diagram-block svg')).toBeVisible();
  expect(await text(page)).toBe(diagram);
  await lock(page, false);
  await expect(page.getByRole('button', { name: '다이어그램 편집', exact: true })).toBeVisible();
});

test('selection across blocks and composition do not corrupt code or render stale diagrams', async ({ page }) => {
  const source = code + '\n' + diagram;
  await page.evaluate(source => window.__editorTest!.load(source), source);
  await page.locator('pre code').click();
  await page.evaluate(source => {
    const t = window.__editorTest!; t.select(source.indexOf('한글') + 2); t.compose(true); t.insert(' 조합'); t.compose(false);
  }, source);
  expect(await text(page)).toBe(source.replace('한글', '한글 조합'));
  await expect(page.locator('.code-source-line').filter({ hasText: '한글 조합' })).toBeVisible();
  await page.evaluate(() => window.__editorTest!.load('# 새 문서\n\n빈 본문\n'));
  await expect(page.locator('.diagram-block')).toHaveCount(0);
  await expect(page.locator('.cm-content')).toContainText('빈 본문');
});

test('invalid Mermaid stays recoverable through its edit control', async ({ page }) => {
  const source = '# 오류 복구\n\n```mermaid\ngraph LR\n A[열린 노드\n```\n';
  await page.evaluate(source => window.__editorTest!.load(source), source);
  await expect(page.locator('.render-error')).toBeVisible();
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  await page.evaluate(source => window.__editorTest!.select(source.indexOf('열린 노드') + '열린 노드'.length), source);
  await page.keyboard.insertText(']');
  await expect(page.locator('.diagram-block svg')).toContainText('열린 노드');
  expect(await text(page)).toBe(source.replace('열린 노드', '열린 노드]'));
});

test('long code retains horizontal bounds and theme styling during editing', async ({ page }) => {
  const source = code.replace('한글', '긴 코드'.repeat(50));
  await page.setViewportSize({ width: 600, height: 700 });
  await page.evaluate(source => window.__editorTest!.load(source), source);
  await page.locator('pre code').click();
  for (const theme of ['light', 'dark', 'night'] as const) {
    await page.evaluate(theme => window.__editorTest!.settings({ theme }), theme);
    await expect(page.locator('.code-source-line:not(.code-fence-line)').first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    expect(await text(page)).toBe(source);
  }
  await page.screenshot({ path: 'test-results/code-editing-narrow-night.png', fullPage: true });
});

test('controls still target their own code and diagram after inserting earlier text', async ({ page }) => {
  const source = code + '\n' + diagram;
  await page.evaluate(source => {
    const t = window.__editorTest!; t.load(source); t.select(0); t.insert('앞에 추가한 문단\n\n'); t.select(0);
  }, source);
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  await expect(page.locator('.diagram-source-line').filter({ hasText: 'graph LR' })).toBeVisible();
  const snapshot = await page.evaluate(() => window.__editorTest!.snapshot());
  expect(snapshot.head).toBe(snapshot.text.indexOf('graph LR'));
  await page.getByRole('button', { name: '다이어그램 편집 완료', exact: true }).click();
  await expect(page.getByRole('button', { name: '다이어그램 편집', exact: true })).toBeFocused();
  await page.keyboard.press('x');
  expect(await text(page)).toBe(snapshot.text);
  await page.locator('pre code').click();
  await expect(page.locator('.code-source-line').filter({ hasText: '"name"' })).toBeVisible();
  expect(await text(page)).toBe(snapshot.text);
});

test('locking an actively edited diagram keeps the picture and blocks source edits', async ({ page }) => {
  await page.evaluate(source => window.__editorTest!.load(source), diagram);
  await page.getByRole('button', { name: '다이어그램 편집', exact: true }).click();
  await lock(page, true);
  await expect(page.locator('.diagram-block svg')).toBeVisible();
  await expect(page.locator('.diagram-source-line')).toHaveCount(0);
  await page.keyboard.insertText('잠금');
  expect(await text(page)).toBe(diagram);
});

test('editing nested code decorates only its parent and preserves later blocks', async ({ page }) => {
  const source = '# 중첩 코드\n\n- 항목\n\n  ```json\n  {"nested": true}\n  ```\n\n```json\n{"sibling": false}\n```\n\n마지막\n';
  await page.evaluate(source => window.__editorTest!.load(source), source);
  await page.locator('pre code').filter({ hasText: 'nested' }).click();
  const nested = page.locator('.code-source-line').filter({ hasText: 'nested' });
  await expect(nested).toBeVisible();
  await expect(nested).toHaveCSS('background-color', 'rgb(65, 70, 77)');
  await expect(page.locator('pre code').filter({ hasText: 'sibling' })).toBeVisible();
  await expect(page.locator('.code-source-line').filter({ hasText: 'sibling' })).toHaveCount(0);
  expect(await text(page)).toBe(source);
});
