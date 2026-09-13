import { test, expect } from '@playwright/test';

const longURL = 'https://example.com/a-very-long-address-that-must-stay-readable-while-the-link-is-being-edited-without-expanding-the-editor-width?search=comfortable-link-editing';
const source = `# 읽기 검증\n\n[편집할 긴 링크](${longURL})\n\n인라인 코드: \`value = 42\`\n\n\`\`\`python\ndef greet(name: str, count: int = 2):\n    message = f"Hello, {name}! count={count + 1}"\n    return message  # visible comment\n\`\`\`\n\n\`\`\`json\n{"displayName": "Ada", "count": 2}\n\`\`\`\n`;

function contrast(foreground: string, background: string) {
  const luminance = (color: string) => color.match(/[\d.]+/g)!.slice(0, 3).map(Number)
    .map(n => n / 255).map(n => n <= .04045 ? n / 12.92 : ((n + .055) / 1.055) ** 2.4)
    .reduce((sum, n, i) => sum + n * [.2126, .7152, .0722][i], 0);
  const a = luminance(foreground), b = luminance(background);
  return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
}

const expected = {
  light: { accent: 'rgb(55, 104, 151)', keyword: 'rgb(134, 83, 162)', string: 'rgb(85, 115, 56)', number: 'rgb(138, 92, 33)', function: 'rgb(55, 104, 151)', comment: 'rgb(98, 108, 101)' },
  dark: { accent: 'rgb(155, 188, 225)', keyword: 'rgb(195, 161, 223)', string: 'rgb(178, 199, 152)', number: 'rgb(220, 186, 133)', function: 'rgb(155, 188, 225)', comment: 'rgb(164, 175, 168)' },
  night: { accent: 'rgb(186, 214, 242)', keyword: 'rgb(203, 177, 233)', string: 'rgb(178, 199, 152)', number: 'rgb(220, 186, 133)', function: 'rgb(186, 214, 242)', comment: 'rgb(177, 184, 191)' },
} as const;

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.waitForFunction(() => !!window.__editorTest);
  await page.setViewportSize({ width: 600, height: 760 });
});

test('links and rich Python/JSON code stay readable through every theme, live edit, source, and undo', async ({ page }) => {
  for (const theme of ['light', 'dark', 'night'] as const) {
    await page.evaluate(([text, nextTheme]) => {
      const editor = window.__editorTest!;
      editor.settings({ theme: nextTheme, fontSize: 20 });
      editor.load(text);
    }, [source, theme]);

    const palette = expected[theme];
    const inlineCode = page.locator('.md-code').filter({ hasText: 'value = 42' });
    const previewCode = page.locator('pre code').filter({ hasText: 'def greet' });
    await expect(inlineCode).toHaveCSS('font-size', '19px');
    await expect(previewCode).toHaveCSS('font-size', '19px');
    await expect(previewCode.locator('.hljs-keyword').first()).toHaveCSS('color', palette.keyword);
    await expect(previewCode.locator('.hljs-string').first()).toHaveCSS('color', palette.string);
    await expect(previewCode.locator('.hljs-number').first()).toHaveCSS('color', palette.number);
    await expect(previewCode.locator('.hljs-title').first()).toHaveCSS('color', palette.function);
    await expect(previewCode.locator('.hljs-comment')).toHaveCSS('color', palette.comment);
    await expect(previewCode.locator('.hljs-subst').first()).toHaveCSS('color', theme === 'light' ? 'rgb(40, 43, 48)' : theme === 'dark' ? 'rgb(217, 220, 225)' : 'rgb(222, 225, 229)');
    await expect(page.locator('pre code').filter({ hasText: 'displayName' }).locator('.hljs-attr').first()).toHaveCSS('color', palette.function);
    await expect(previewCode).toHaveCSS('line-height', '30.4px');

    await page.locator('.md-link').filter({ hasText: '편집할 긴 링크' }).click();
    const activeURL = page.locator('.cm-editor .tok-url').filter({ hasText: 'example.com' });
    await expect(activeURL).toBeVisible();
    await expect(activeURL).toHaveCSS('color', palette.accent);
    const linkColors = await activeURL.evaluate(n => [getComputedStyle(n).color, getComputedStyle(document.body).backgroundColor]);
    expect(contrast(linkColors[0], linkColors[1])).toBeGreaterThanOrEqual(4.5);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);

    await page.evaluate(() => window.__editorTest!.command('source'));
    await expect(activeURL).toBeVisible();
    await expect(activeURL).toHaveCSS('color', palette.accent);
    await page.evaluate(() => window.__editorTest!.command('source'));

    await previewCode.click();
    const codeLine = page.locator('.code-source-line').filter({ hasText: 'message = f"Hello' });
    await expect(codeLine).toBeVisible();
    await expect(codeLine).toHaveCSS('font-size', '19px');
    await expect(codeLine).toHaveCSS('line-height', '30.4px');
    // Code language parsers load asynchronously. Check the actual edit tokens
    // after they appear, rather than sampling an unhighlighted interim frame.
    const definition = page.locator('.code-source-line').filter({ hasText: 'def greet' });
    await definition.scrollIntoViewIfNeeded();
    await expect(definition.locator('span').filter({ hasText: /^greet$/ })).toHaveCSS('color', palette.function);
    await expect(definition.locator('span').filter({ hasText: /^2$/ })).toHaveCSS('color', palette.number);
    await expect(page.locator('.code-source-line span').filter({ hasText: /^# visible comment$/ })).toHaveCSS('color', palette.comment);
    await expect(codeLine.locator('span').filter({ hasText: /^name$/ })).toHaveCSS('color', theme === 'light' ? 'rgb(40, 43, 48)' : theme === 'dark' ? 'rgb(217, 220, 225)' : 'rgb(222, 225, 229)');
    const tokens = await page.locator('.code-source-line span').evaluateAll(nodes => nodes.map(n => ({ foreground: getComputedStyle(n).color, background: getComputedStyle(n.closest('.code-source-line')!).backgroundColor })));
    for (const token of tokens) expect(contrast(token.foreground, token.background)).toBeGreaterThanOrEqual(4.5);
    await page.evaluate(textAt => window.__editorTest!.select(textAt + 'message'.length), source.indexOf('message ='));
    await page.keyboard.insertText('_edited');
    expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toContain('message_edited =');
    await page.evaluate(() => window.__editorTest!.command('undo'));
    expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
  }
});

test('code scales without a click jump, and modifier-click opens a link without changing its source', async ({ page }) => {
  await page.evaluate(text => {
    window.__editorTest!.load(text);
    (window as any).__linkRequests = [];
    window.webkit = { messageHandlers: { editor: { postMessage(message: any) { if (message.type === 'openLink') (window as any).__linkRequests.push(message); } } } };
  }, source);
  await page.locator('.md-link').filter({ hasText: '편집할 긴 링크' }).click({ modifiers: ['Control'] });
  expect(await page.evaluate(() => (window as any).__linkRequests.map((m: any) => m.href))).toEqual([longURL]);
  for (const size of [12, 17, 30]) {
    await page.evaluate(size => { window.__editorTest!.settings({ fontSize: size }); window.__editorTest!.select(0); }, size);
    const code = page.locator('pre code').filter({ hasText: 'def greet' });
    const reading = await code.evaluate(n => ({ size: parseFloat(getComputedStyle(n).fontSize), height: getComputedStyle(n).lineHeight }));
    expect(reading.size).toBeCloseTo(Math.max(15, size * .95), 1);
    await code.click();
    const editing = await page.locator('.code-source-line').filter({ hasText: 'def greet' }).evaluate(n => ({ size: parseFloat(getComputedStyle(n).fontSize), height: getComputedStyle(n).lineHeight }));
    expect(editing).toEqual(reading);
  }
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});

test('render errors and exported code retain readable colors', async ({ page }) => {
  for (const theme of ['light', 'dark', 'night']) {
    await page.evaluate(theme => { window.__editorTest!.settings({ theme }); window.__editorTest!.load('# 오류 안내\n\n$$\n\\notARealCommand{\n$$\n'); }, theme);
    const error = page.locator('.render-error');
    await expect(error).toBeVisible();
    const colors = await error.evaluate(n => ({ text: getComputedStyle(n).color, background: getComputedStyle(document.body).backgroundColor, size: parseFloat(getComputedStyle(n).fontSize) }));
    expect(contrast(colors.text, colors.background)).toBeGreaterThanOrEqual(4.5);
    expect(colors.size).toBeGreaterThanOrEqual(14);
  }
  const html = await page.evaluate(async text => { window.__editorTest!.load(text); return window.MarkdownHost.exportHTML(); }, source);
  await page.setContent(html);
  const tokens = await page.locator('pre code span').evaluateAll(nodes => nodes.map(n => ({ foreground: getComputedStyle(n).color, background: getComputedStyle(n.closest('pre')!).backgroundColor })));
  expect(new Set(tokens.map(n => n.foreground)).size).toBeGreaterThanOrEqual(5);
  for (const token of tokens) expect(contrast(token.foreground, token.background)).toBeGreaterThanOrEqual(4.5);
  expect(await page.locator('pre code').first().evaluate(n => parseFloat(getComputedStyle(n).fontSize))).toBeGreaterThanOrEqual(15);
});

test('search results remain legible inside syntax-colored text', async ({ page }) => {
  for (const theme of ['light', 'dark', 'night']) {
    await page.evaluate(theme => {
      window.__editorTest!.settings({ theme });
      window.__editorTest!.load('# 검색\n\n```python\nreturn "searchable"\n```\n');
      window.__editorTest!.command('source');
      window.__editorTest!.command('find');
    }, theme);
    const query = page.getByRole('textbox', { name: '찾기', exact: true });
    await query.fill('searchable');
    await query.press('Enter');
    const match = page.locator('.cm-searchMatch').first();
    await expect(match).toBeVisible();
    const colors = await match.evaluate(n => ({ text: getComputedStyle(n).color, background: getComputedStyle(n).backgroundColor }));
    expect(contrast(colors.text, colors.background)).toBeGreaterThanOrEqual(4.5);
    await page.getByRole('button', { name: '닫기', exact: true }).click();
    await page.evaluate(() => window.__editorTest!.command('source'));
  }
});

test('blank code lines preserve their height when a preview becomes editable', async ({ page }) => {
  const code = '# 코드 간격\n\n```python\ndef review(task):\n\n    prompt = f"""\n    Task: {task}\n\n    Return JSON.\n    """\n\n    return prompt\n```\n';
  await page.evaluate(text => { window.__editorTest!.settings({ theme: 'night', fontSize: 17 }); window.__editorTest!.load(text); }, code);
  const preview = page.locator('pre').first();
  const before = await preview.boundingBox();
  await preview.click();
  // The language header has its own fixed-height row; measure editable body
  // lines, including all three genuine blank lines in this code sample.
  const bodyLines = page.locator('.code-source-line:not(.code-fence-line):not(.code-language-line)');
  const lines = await bodyLines.evaluateAll(nodes => nodes.map(n => ({ text: n.textContent, height: parseFloat(getComputedStyle(n).lineHeight), rect: n.getBoundingClientRect().toJSON() })));
  expect(lines.filter(line => !line.text?.trim()).length).toBe(3);
  for (const line of lines) expect(line.height).toBeCloseTo(25.84, 1);
  const afterHeight = lines.at(-1)!.rect.bottom - lines[0].rect.top;
  expect(Math.abs(afterHeight - before!.height)).toBeLessThan(2);
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(code);
});
