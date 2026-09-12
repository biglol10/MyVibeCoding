import { test, expect, type Page } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

const sample = '# 한글 문서\n\n본문 **강조**와 *기울임* 및 $x^2$입니다.\n\n## 표\n\n| 이름 | 값 |\n| --- | --- |\n| 한글 | 123 |\n\n- [ ] 할 일\n\n```mermaid\ngraph LR\n A[시작] --> B[완료]\n```\n\n```swift\nlet title = "안녕하세요"\n```\n\n마지막 문단\n';

const errors = new WeakMap<Page, string[]>();
test.beforeEach(async ({ page }) => { errors.set(page, []); page.on('pageerror', error => errors.get(page)!.push(error.message)); await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest); });
test.afterEach(async ({ page }) => { expect(errors.get(page)).toEqual([]); });

test('first launch stays dark on a light system and renders specialized blocks', async ({ page }) => {
  await page.evaluate(text => window.__editorTest!.load(text), sample);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.locator('table')).toBeVisible();
  await expect(page.locator('.katex').first()).toBeVisible();
  await expect(page.locator('.diagram-block svg')).toBeAttached();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: 'test-results/editor-dark.png', fullPage: true });
});

test('table cells edit through undoable source transactions and controls change structure', async ({ page }) => {
  const source = '| 이름 | 값 |\n| :--- | ---: |\n| 한글 | 123 |\n';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  await expect(page.getByRole('button', { name: '표 편집' })).toBeVisible();
  await page.getByRole('button', { name: '표 편집' }).click();
  const cells = page.locator('.table-cell-input');
  await cells.nth(2).fill('수정');
  await cells.nth(2).press('Tab');
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('| 수정 | 123 |');
  await page.getByRole('button', { name: '열 추가' }).click();
  await expect.poll(() => page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('| 이름 | 값 |  |');
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('| 수정 | 123 |');
});

test('semantic commands and standalone export use complete safe document source', async ({ page }) => {
  await page.evaluate(() => window.__editorTest!.load('# 제목\n\n본문[^1]\n\n[^1]: 내용\n\n![remote](https://example.com/a.png)\n'));
  await page.evaluate(() => { const t = window.__editorTest!; t.select(0); t.command('toc'); t.command('footnote'); t.command('frontMatter'); });
  const text = await page.evaluate(() => window.__editorTest!.snapshot().text);
  expect(text).toContain('---\ntitle: 문서 제목\n---');
  expect(text).toContain('[^2]');
  const html = await page.evaluate(() => { window.__editorTest!.load('# 제목\n\n본문[^1]\n\n[^1]: 내용\n\n![remote](https://example.com/a.png)\n'); return window.MarkdownHost.exportHTML(); });
  expect(html).toContain('<!doctype html>');
  expect(html).toContain('id="제목"');
  expect(html).toContain('외부 이미지');
  expect(html).not.toContain('https://example.com/a.png');
});

test('live preview resolves document-wide references and renders one rich footnote footer', async ({ page }) => {
  const source = '# 시작\n\n[문서][guide]와 각주[^a]를 봅니다.\n\n[guide]: notes/guide.md "안내"\n\n[^a]: **굵은** 각주\n';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  await expect(page.locator('a[href="notes/guide.md"]')).toHaveText('문서');
  await expect(page.locator('.footnotes')).toHaveCount(1);
  await expect(page.locator('.footnotes')).toContainText('굵은');
});

test('mode switches and formatting preserve source, selection and undo history', async ({ page }) => {
  await page.evaluate(text => window.__editorTest!.load(text), sample);
  await page.evaluate(() => { const t = window.__editorTest!; t.select(2, 4); t.command('bold'); });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('# **한글** 문서');
  await page.evaluate(() => { window.__editorTest!.command('source'); window.__editorTest!.command('source'); window.__editorTest!.command('undo'); });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(sample);
});

test('composition defers replacing the edited block and source remains intact', async ({ page }) => {
  await page.evaluate(() => { const t = window.__editorTest!; t.load('# 제목\n\n문단\n'); t.select(9); t.compose(true); t.insert('한'); t.insert('글'); t.compose(false); });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe('# 제목\n\n문단\n한글');
});

test('checkbox clicks are reversible text edits', async ({ page }) => {
  await page.evaluate(() => window.__editorTest!.load('# Tasks\n\n- [ ] 할 일\n'));
  await page.getByRole('checkbox').click();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('- [x] 할 일');
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('- [ ] 할 일');
});

test('checkbox decoration cannot edit source while composition is frozen', async ({ page }) => {
  const source = '# 조합 중\n\n- [ ] 할 일\n';
  await page.evaluate(text => { const t = window.__editorTest!; t.load(text); t.compose(true); }, source);
  await page.getByRole('checkbox').click();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  await page.evaluate(() => window.__editorTest!.compose(false));
  await page.getByRole('checkbox').click();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('- [x] 할 일');
});

test('document transition lock blocks custom formatting and checkbox edits', async ({ page }) => {
  const source = '# 보호할 문서\n\n- [ ] 할 일\n';
  await page.evaluate(text => {
    const t = window.__editorTest!; t.load(text); t.select(2, 5);
    const snapshot = t.snapshot();
    window.MarkdownHost.receive({ type: 'lock', sessionID: snapshot.sessionID, documentID: snapshot.documentID, locked: true });
    t.command('bold');
  }, source);
  await page.getByRole('checkbox').click();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  await page.evaluate(() => {
    const t = window.__editorTest!, snapshot = t.snapshot();
    window.MarkdownHost.receive({ type: 'lock', sessionID: snapshot.sessionID, documentID: snapshot.documentID, locked: false });
    t.command('bold');
  });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('**보호할**');
});

test('Korean search and replacement can be undone without changing emoji', async ({ page }) => {
  const source = '# 검색\n\n사과 👩🏽‍💻 사과\n';
  await page.evaluate(text => { window.__editorTest!.load(text); window.__editorTest!.command('replace'); }, source);
  await page.getByRole('textbox', { name: '찾기', exact: true }).fill('사과');
  await page.getByRole('textbox', { name: '바꿀 내용', exact: true }).fill('포도');
  await page.getByRole('button', { name: '모두 바꾸기', exact: true }).click();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe('# 검색\n\n포도 👩🏽‍💻 포도\n');
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('untrusted HTML stays text and remote images make no requests', async ({ page }) => {
  const requests: string[] = []; page.on('request', request => { if (request.url().includes('example.com')) requests.push(request.url()); });
  await page.evaluate(() => window.__editorTest!.load('# Safe\n\n<script>window.pwned=true</script>\n\n![remote](https://example.com/track.png)\n'));
  await expect(page.locator('.image-placeholder')).toContainText('외부 이미지');
  expect(requests).toEqual([]);
  expect(await page.evaluate(() => (window as any).pwned)).toBeUndefined();
});

test('theme changes update all surfaces without changing text', async ({ page }) => {
  await page.evaluate(text => window.__editorTest!.load(text), sample);
  await page.evaluate(() => window.__editorTest!.settings({ theme: 'light' }));
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.screenshot({ path: 'test-results/editor-light.png' });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(sample);
});

test('Night colors cover text, code, tables, math and Mermaid while preserving Dark and undo', async ({ page }) => {
  await page.evaluate(text => window.__editorTest!.load(text), sample);
  const node = page.locator('.diagram-block .node rect').first();
  await expect(node).toBeAttached();
  const darkNodeFill = await node.evaluate(element => getComputedStyle(element).fill);
  await page.evaluate(text => { const t = window.__editorTest!; t.select(text.indexOf('본문') + 1); t.insert('Night👩🏽‍💻'); }, sample);
  const edited = await page.evaluate(() => window.__editorTest!.snapshot());
  await page.evaluate(() => window.__editorTest!.settings({ theme: 'night' }));
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  expect(await page.evaluate(() => window.__editorTest!.usesDarkTheme())).toBe(true);
  await expect(page.locator('body')).toHaveCSS('background-color', 'rgb(55, 59, 64)');
  await expect(page.locator('body')).toHaveCSS('color', 'rgb(222, 225, 229)');
  await expect(page.locator('th').first()).toHaveCSS('background-color', 'rgb(65, 70, 77)');
  await expect(page.locator('.preview-widget pre').first()).toHaveCSS('background-color', 'rgb(65, 70, 77)');
  await expect(page.locator('.katex').first()).toHaveCSS('color', 'rgb(222, 225, 229)');
  await expect(node).toHaveCSS('fill', 'rgb(70, 83, 99)');
  const after = await page.evaluate(() => window.__editorTest!.snapshot());
  expect([after.text, after.anchor, after.head, after.revision]).toEqual([edited.text, edited.anchor, edited.head, edited.revision]);
  await page.screenshot({ path: 'test-results/editor-night.png', fullPage: true });
  await page.evaluate(() => window.__editorTest!.settings({ theme: 'dark' }));
  await expect(page.locator('body')).toHaveCSS('background-color', 'rgb(25, 27, 30)');
  await expect(node).toHaveCSS('fill', darkNodeFill);
  await page.evaluate(() => window.__editorTest!.command('undo'));
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(sample);
});

test('a saved Night theme in the initial HTML is not reset to Dark during startup', async ({ page }) => {
  await page.route('**/', async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: (await response.text()).replace('data-theme="dark"', 'data-theme="night"') });
  });
  await page.reload();
  await page.waitForFunction(() => !!window.__editorTest);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'night');
  await expect(page.locator('body')).toHaveCSS('background-color', 'rgb(55, 59, 64)');
  expect(await page.evaluate(() => window.__editorTest!.usesDarkTheme())).toBe(true);
});

test('rendered HTML whitespace does not add empty reading lines', async ({ page }) => {
  await page.evaluate(() => window.__editorTest!.load('# Title\n\n첫 문단\n\n두 번째 문단\n\n세 번째 문단\n'));
  const gap = await page.evaluate(() => {
    const paragraphs = [...document.querySelectorAll('.cm-line.md-prose:not(.md-heading)')];
    return paragraphs[1].getBoundingClientRect().top - paragraphs[0].getBoundingClientRect().bottom;
  });
  expect(gap).toBeLessThan(50);
});

test('heading and list geometry stay stable when the caret moves between blocks', async ({ page }) => {
  const source = '# 편안한 제목\n\n첫 문단입니다.\n\n## 다음 제목\n\n1. 첫 번째 항목\n2. 두 번째 항목\n3. 세 번째 항목\n\n마지막 문단입니다.\n';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  const measure = () => page.evaluate(() => [...document.querySelectorAll('.cm-line.md-prose')].map(node => {
    const box = node.getBoundingClientRect();
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    let text: Node | null, left = box.left;
    while ((text = walker.nextNode())) {
      if (/[가-힣]/.test(text.textContent ?? '')) {
        const start = text.textContent!.search(/[가-힣]/), range = document.createRange();
        range.setStart(text, start); range.setEnd(text, start + 1); left = range.getBoundingClientRect().left; break;
      }
    }
    return { top: box.top, height: box.height, left };
  }));
  const before = await measure();
  await page.evaluate(text => window.__editorTest!.select(text.indexOf('두 번째') + 2), source);
  const after = await measure();
  expect(after.length).toBe(before.length);
  for (let i = 0; i < before.length; i++) {
    expect(Math.abs(after[i].top - before[i].top)).toBeLessThanOrEqual(1);
    expect(Math.abs(after[i].height - before[i].height)).toBeLessThanOrEqual(1);
    expect(Math.abs(after[i].left - before[i].left)).toBeLessThanOrEqual(1);
  }
  await writeFile('test-results/reading-geometry.json', JSON.stringify({
    maxVerticalShiftPx: Math.max(...after.map((box,i) => Math.abs(box.top - before[i].top))),
    maxTextHorizontalShiftPx: Math.max(...after.map((box,i) => Math.abs(box.left - before[i].left))),
    maxLineHeightChangePx: Math.max(...after.map((box,i) => Math.abs(box.height - before[i].height))),
  }, null, 2));
  await expect(page.locator('.md-editing-item')).toHaveCount(1);
  await expect(page.locator('.md-prefix-source')).toHaveCount(1);
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  await page.screenshot({ path: 'test-results/typora-reading-flow.png' });
});

test('reading column stays centered within its configured maximum width', async ({ page }) => {
  await page.evaluate(() => window.__editorTest!.load('# 가운데 문서\n\n읽기 폭 확인\n'));
  const layout = await page.evaluate(() => {
    const content = document.querySelector('.cm-content')!.getBoundingClientRect();
    const scroller = document.querySelector('.cm-scroller')!.getBoundingClientRect();
    return { width: content.width, left: content.left - scroller.left, right: scroller.right - content.right };
  });
  expect(layout.width).toBeLessThanOrEqual(881);
  expect(Math.abs(layout.left - layout.right)).toBeLessThanOrEqual(16);
});

test('nested list editing exposes the selected item without expanding its parent or siblings', async ({ page }) => {
  const source = '# 목록\n\n- 부모 항목\n  - 중첩 **강조** 항목\n  - 다음 자식\n- 다른 부모\n\n끝\n';
  await page.evaluate(text => { const t = window.__editorTest!; t.load(text); t.select(text.indexOf('중첩') + 1); }, source);
  await expect(page.locator('.md-editing-item')).toHaveCount(1);
  await expect(page.locator('.md-prefix-source')).toHaveCount(1);
  await expect(page.locator('.md-strong')).toHaveText('강조');
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  await page.evaluate(() => { const t = window.__editorTest!; t.insert('한글👩🏽‍💻'); t.command('source'); t.command('source'); t.command('undo'); });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('clicking prose places the caret at the clicked word', async ({ page }) => {
  const source = '# 제목\n\n앞쪽 문장 뒤에 정확한 위치를 클릭합니다.\n\n다음 문단\n';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  const point = await page.evaluate(() => {
    const line = [...document.querySelectorAll('.cm-line.md-prose')].find(node => node.textContent?.includes('정확한'))!;
    const text = line.firstChild!, from = text.textContent!.indexOf('정확한');
    const range = document.createRange(); range.setStart(text, from); range.setEnd(text, from + 3);
    const box = range.getBoundingClientRect(); return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  });
  await page.mouse.click(point.x, point.y);
  const snapshot = await page.evaluate(() => window.__editorTest!.snapshot());
  expect(snapshot.head).toBeGreaterThanOrEqual(source.indexOf('정확한'));
  expect(snapshot.head).toBeLessThanOrEqual(source.indexOf('정확한') + 3);
  expect(snapshot.text).toBe(source);
});

test('headings inside quotes render without markers while another quote line is edited', async ({ page }) => {
  const source = '# 바깥 제목\n\n> #### 쉽게 말하면\n> 설명 **강조** 문장입니다.\n\n마지막 문단\n';
  await page.evaluate(text => { const t = window.__editorTest!; t.load(text); t.select(text.indexOf('설명') + 1); }, source);
  const heading = page.getByRole('heading', { level: 4, name: '쉽게 말하면', exact: true });
  await expect(heading).toBeVisible();
  await expect(heading).not.toContainText('#');
  await page.evaluate(text => window.__editorTest!.select(text.indexOf('쉽게') + 1), source);
  await expect(page.getByRole('heading', { level: 4 })).toContainText('####');
  await page.evaluate(() => { const t = window.__editorTest!; t.insert('한글👩🏽‍💻'); t.command('source'); t.command('source'); t.command('undo'); });
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  await page.evaluate(text => window.__editorTest!.select(text.indexOf('마지막')), source);
  await expect(heading).toBeVisible();
});

test('nested heading levels and closing markers render without changing literal hashes', async ({ page }) => {
  const source = '# 밖\n\n' + Array.from({ length: 6 }, (_, i) => `> ${'#'.repeat(i + 1)} 인용 제목 ${i + 1} ${'#'.repeat(i + 1)}\n> 본문\n\n`).join('')
    + '- #### 목록 제목\n\n> ####붙어있는 일반 문장\n\n끝\n';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  for (let level = 1; level <= 6; level++) {
    await expect(page.getByRole('heading', { level, name: `인용 제목 ${level}`, exact: true })).toBeAttached();
  }
  await expect(page.getByRole('heading', { level: 4, name: '목록 제목', exact: true })).toBeAttached();
  await expect(page.locator('.cm-line').filter({ hasText: '####붙어있는 일반 문장' })).toBeAttached();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('outline location follows the visible heading after a jump', async ({ page }) => {
  await page.evaluate(() => {
    const t = window.__editorTest!;
    const text = '# 시작\n\n' + '읽기 문단입니다.\n\n'.repeat(80) + '## 목표 제목\n\n뒤의 문단\n\n## 다음 제목\n\n끝\n';
    t.load(text);
    const session = t.snapshot();
    window.MarkdownHost.receive({ type: 'jump', sessionID: session.sessionID, documentID: session.documentID, from: text.indexOf('## 목표 제목') });
  });
  await expect.poll(async () => page.evaluate(() => {
    const snapshot = window.__editorTest!.snapshot();
    return snapshot.text.slice(snapshot.visibleFrom, snapshot.visibleFrom + 8);
  })).toBe('## 목표 제목');
});

test('large document opens and accepts edits within the performance budget', async ({ page }) => {
  const result = await page.evaluate(async () => {
    const t = window.__editorTest!;
    const source = '# 긴 문서\n\n' + ('한글과 English를 함께 읽는 문서입니다. 설명과 예제를 이어서 살펴봅니다. '.repeat(3) + '\n\n').repeat(10000);
    const start = performance.now(); t.load(source);
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const openMs = performance.now() - start;
    const samples: number[] = [];
    for (let i = 0; i < 20; i++) { const before = performance.now(); t.insert('가'); samples.push(performance.now() - before); }
    samples.sort((a,b) => a-b);
    return { openMs, inputP95Ms: samples[18], bytes: new TextEncoder().encode(source).length, lines: source.split('\n').length };
  });
  await test.info().attach('performance.json', { body: JSON.stringify(result, null, 2), contentType: 'application/json' });
  await writeFile('test-results/performance.json', JSON.stringify(result, null, 2));
  expect(result.openMs).toBeLessThan(2000); expect(result.inputP95Ms).toBeLessThan(100);
});

test('file relocation retains undo and ignores messages from the former session', async ({ page }) => {
  const result = await page.evaluate(() => {
    const t = window.__editorTest!; t.load('원문 👩🏽‍💻'); t.select(0); t.insert('입력 ');
    const before = t.snapshot();
    window.MarkdownHost.receive({ type: 'relocate', ...before, nextDocumentID: 'renamed.md', nextSessionID: 'renamed-session', baseURL: 'file:///renamed/' });
    window.MarkdownHost.receive({ type: 'insert', ...before, text: '옛 세션' });
    t.command('undo');
    return t.snapshot();
  });
  expect(result.text).toBe('원문 👩🏽‍💻');
  expect(result.documentID).toBe('renamed.md');
  expect(result.sessionID).toBe('renamed-session');
});

test('folder search jump selects the UTF-16 match including emoji safely', async ({ page }) => {
  const result = await page.evaluate(() => {
    const t = window.__editorTest!; t.load('앞 👩🏽‍💻 한글 뒤');
    const snapshot = t.snapshot(), from = snapshot.text.indexOf('한글');
    window.MarkdownHost.receive({ type: 'jump', ...snapshot, from, to: from + 2 });
    const current = t.snapshot();
    return current.text.slice(current.anchor, current.head);
  });
  expect(result).toBe('한글');
});

test('checkboxes support keyboard activation, retain focus and preserve surrounding spaces', async ({ page }) => {
  const source = '# 체크리스트\n\n- [ ] 앞  두 칸 **강조** 뒤\n\n끝';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  const checkbox = page.getByRole('checkbox');
  await checkbox.focus(); await checkbox.press('Space');
  await expect(checkbox).toHaveAttribute('aria-checked', 'true');
  await expect(checkbox).toBeFocused();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source.replace('[ ]', '[x]'));
  await checkbox.press('Enter');
  await expect(checkbox).toHaveAttribute('aria-checked', 'false');
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('visible spacing survives inline formatting in prose', async ({ page }) => {
  const source = '# 확인\n\n앞  두 칸 **강조** 뒤 문장\n\n끝';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  const spacing = await page.evaluate(() => {
    const line = [...document.querySelectorAll('.cm-line')].find(node => node.textContent?.includes('앞  두 칸'))!;
    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const at = node.textContent?.indexOf('  ') ?? -1;
      if (at >= 0) {
        const range = document.createRange(); range.setStart(node, at); range.setEnd(node, at + 2);
        return range.getBoundingClientRect().width;
      }
    }
    return 0;
  });
  expect(spacing).toBeGreaterThan(6);
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('rendered complex list checkbox supports keyboard activation', async ({ page }) => {
  const source = '# 확인\n\n- \\[ ] 문자로 쓴 표기\n\n- [ ] 작업\n\n  ```txt\n  - [ ] 코드 안의 표기\n  ```\n\n- [ ] 두 번째 작업\n\n끝';
  await page.evaluate(text => window.__editorTest!.load(text), source);
  const checkboxes = page.locator('.preview-widget').getByRole('checkbox');
  await expect(checkboxes).toHaveCount(2);
  const checkbox = checkboxes.nth(1);
  await checkbox.focus(); await checkbox.press('Space');
  await expect(checkbox).toHaveAttribute('aria-checked', 'true');
  await expect(checkbox).toBeFocused();
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source.replace('[ ] 두 번째', '[x] 두 번째'));
  await checkbox.press('Enter');
  await expect(checkbox).toHaveAttribute('aria-checked', 'false');
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});


test('localized selection decoration agrees with a full refresh across block boundaries', async ({ page }) => {
  await page.goto('/');
  await page.waitForFunction(() => window.__editorTest);
  const equal = await page.evaluate(() => {
    const api = window.__editorTest!;
    const source = '# 제목 **강조**\n\n일반 **본문**과 [링크](https://example.com)\n\n- [ ] 첫 항목\n- 둘째 항목\n\n```js\nconst value = 1;\n```\n\n마지막 문단\n';
    api.load(source);
    const shape = () => [...document.querySelectorAll('.cm-content .md-prefix-source,.cm-content .md-syntax,.cm-content .preview-widget')].map(node => [node.className.split(/\s+/).sort().join(' '), node.textContent]);
    for (const [from, to] of [[5, 5], [25, 28], [60, 60], [98, 98], [0, source.length], [source.length, source.length], [14, 14]]) {
      api.select(from, to);
      const incremental = JSON.stringify(shape());
      api.settings({});
      if (JSON.stringify(shape()) !== incremental || api.snapshot().text !== source) return false;
    }
    return true;
  });
  expect(equal).toBe(true);
});


test('incremental edits match complete rendering through fences, blank lines and undo', async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => window.__editorTest);
  const equal = await page.evaluate(() => {
    const api = window.__editorTest!;
    api.load('# 제목\n\n문장 **강조**\n\n- [ ] 항목\n- 둘째 항목\n\n```js\nlet x = 1;\n```\n\n마지막\n');
    const shape = () => [...document.querySelectorAll('.cm-content .cm-line,.cm-content .preview-widget')].map(node => [node.className.split(/\s+/).sort().join(' '), node.textContent]);
    for (const [position, insert] of [[3, '새 '], [0, '\n'], [16, '\n\n'], [0, '```\n'], [0, '\n'], [30, '\n# 제목 추가\n']] as [number, string][]) {
      api.select(position); api.insert(insert);
      const incremental = JSON.stringify(shape());
      const source = api.snapshot().text;
      api.settings({});
      if (JSON.stringify(shape()) !== incremental || api.snapshot().text !== source) return false;
      api.command('undo');
      const undone = JSON.stringify(shape()); api.settings({});
      if (JSON.stringify(shape()) !== undone) return false;
    }
    return true;
  });
  expect(equal).toBe(true);
});
