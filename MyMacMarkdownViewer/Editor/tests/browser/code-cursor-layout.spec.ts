import { test, expect, type Page } from '@playwright/test';

const body = 'deny_paths: ["/etc", "/secrets"]';
const sample = `BEFORE_MARKER\n\n\n\`\`\`\n${body}\n\`\`\`\n\n\nAFTER_MARKER\n`;

async function geometry(page: Page) {
  return page.evaluate(async body => {
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    const code = [...document.querySelectorAll<HTMLElement>('pre, .cm-line.code-source-line')]
      .find(element => element.textContent?.includes(body))!;
    const header = document.querySelector<HTMLElement>('.code-language-select')!;
    const after = [...document.querySelectorAll<HTMLElement>('.cm-line')].find(element => element.textContent === 'AFTER_MARKER')!;
    const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
    let node: Node | null;
    let textTop = NaN;
    while ((node = walker.nextNode())) {
      if (!node.textContent?.trim()) continue;
      const range = document.createRange(); range.selectNodeContents(node);
      textTop = range.getBoundingClientRect().top; break;
    }
    const rect = code.getBoundingClientRect(), head = header.getBoundingClientRect(), style = getComputedStyle(code);
    return { top: rect.top, height: rect.height, left: rect.left, width: rect.width,
      textTop, headerTop: head.top, headerBottom: head.bottom, headerRight: head.right,
      afterTop: after.getBoundingClientRect().top, scroll: document.querySelector('.cm-scroller')!.scrollTop,
      paddingTop: parseFloat(style.paddingTop), paddingBottom: parseFloat(style.paddingBottom),
      borderTop: parseFloat(style.borderTopWidth), borderBottom: parseFloat(style.borderBottomWidth) };
  }, body);
}

for (const fontSize of [17, 30]) test(`all cursor boundaries preserve the code header and surface at ${fontSize}px`, async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(([source, fontSize]) => {
    window.__editorTest!.settings({ theme: 'night', fontSize });
    window.__editorTest!.load(source); window.__editorTest!.select(0);
  }, [sample, fontSize] as const);
  const baseline = await geometry(page);
  const open = sample.indexOf('```'), close = sample.lastIndexOf('```'), start = sample.indexOf(body);
  for (const [label, anchor, head] of [
    ['before blank', open - 1, open - 1], ['opening start', open, open], ['opening end', open + 3, open + 3],
    ['body start', start, start], ['body middle', start + 10, start + 10], ['body end', start + body.length, start + body.length],
    ['closing start', close, close], ['closing end', close + 3, close + 3],
    ['after blank', close + 4, close + 4], ['following blank', close + 5, close + 5],
    ['body selection', start, start + body.length], ['whole fence selection', open, close + 3], ['exit', 0, 0],
  ] as const) {
    await page.evaluate(([a, h]) => window.__editorTest!.select(a, h), [anchor, head]);
    const actual = await geometry(page);
    for (const key of Object.keys(baseline) as (keyof typeof baseline)[]) {
      expect.soft(Math.abs(actual[key] - baseline[key]), `${label}: ${key} ${actual[key]} vs ${baseline[key]}`).toBeLessThan(1);
    }
    expect.soft(actual.headerBottom, `${label}: picker must sit above the box`).toBeLessThan(actual.top);
    expect.soft(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(sample);
  }
});

test('real clicks and arrow movement keep the header clear of the code box', async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(source => { window.__editorTest!.settings({ theme: 'night' }); window.__editorTest!.load(source); window.__editorTest!.select(0); }, sample);
  const baseline = await geometry(page);
  await page.locator('pre code').click();
  for (const key of ['Home', 'ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowDown', 'ArrowUp']) {
    await page.keyboard.press(key);
    const actual = await geometry(page);
    expect.soft(actual.headerBottom).toBeLessThan(actual.top);
    expect.soft(actual.paddingTop).toBe(16);
    expect.soft(actual.borderTop).toBe(1);
    expect.soft(Math.abs(actual.top - baseline.top), `${key}: code top`).toBeLessThan(1);
    expect.soft(Math.abs(actual.afterTop - baseline.afterTop), `${key}: following prose`).toBeLessThan(1);
  }
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(sample);
  await page.screenshot({ path: 'test-results/code-cursor-layout-night.png', fullPage: true });
});

test('keyboard navigation does not leave the caret inside invisible delimiters', async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(source.indexOf('deny_paths')); }, sample);
  await page.locator('.cm-content').focus();
  const opening = sample.indexOf('```'), closing = sample.lastIndexOf('```');
  await page.keyboard.press('ArrowUp');
  expect((await page.evaluate(() => window.__editorTest!.snapshot())).head, 'Up must leave the first code line').toBeLessThan(opening);
  await page.evaluate(source => window.__editorTest!.select(source.indexOf('deny_paths') + 'deny_paths: ["/etc", "/secrets"]'.length), sample);
  await page.keyboard.press('ArrowDown');
  expect((await page.evaluate(() => window.__editorTest!.snapshot())).head, 'Down must leave the last code line').toBeGreaterThan(closing + 3);
  for (const key of ['ArrowUp', 'ArrowDown', 'End', 'ArrowDown', 'ArrowUp']) {
    await page.keyboard.press(key);
    const state = await page.evaluate(() => window.__editorTest!.snapshot());
    expect.soft(state.head >= opening && state.head <= opening + 3, `${key}: hidden opening fence`).toBe(false);
    expect.soft(state.head >= closing && state.head <= closing + 3, `${key}: hidden closing fence`).toBe(false);
    expect(state.text).toBe(sample);
  }
});

test('an empty fenced block keeps its label above its frame when selected', async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  for (const source of ['BEFORE_MARKER\n\n```python\n```\n\nAFTER_MARKER\n', 'BEFORE_MARKER\n\n```python\n\n```\n\nAFTER_MARKER\n']) {
    await page.evaluate(source => { window.__editorTest!.load(source); window.__editorTest!.select(0); }, source);
    for (const position of [source.indexOf('```'), source.lastIndexOf('```'), 0]) {
      await page.evaluate(position => window.__editorTest!.select(position), position);
      const measured = await page.evaluate(async () => {
        await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
        const header = document.querySelector('.code-language-select')!;
        const surface = document.querySelector('pre, .code-empty-source, .code-source-first')!;
        return { headerBottom: header.getBoundingClientRect().bottom, top: surface.getBoundingClientRect().top };
      });
      expect.soft(measured.headerBottom).toBeLessThan(measured.top);
      expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
    }
  }
});

test('source-mode arrows and Shift selection retain normal text editing behavior', async ({ page }) => {
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  await page.evaluate(source => {
    window.__editorTest!.load(source); window.__editorTest!.command('source');
    window.__editorTest!.select(source.indexOf('deny_paths'));
  }, sample);
  await page.locator('.cm-content').focus();
  await page.keyboard.press('ArrowUp');
  const opening = sample.indexOf('```');
  const state = await page.evaluate(() => window.__editorTest!.snapshot());
  expect(state.head).toBeGreaterThanOrEqual(opening);
  expect(state.head).toBeLessThanOrEqual(opening + 3);
  await page.keyboard.press('Shift+ArrowDown');
  const selection = await page.evaluate(() => window.__editorTest!.snapshot());
  expect(selection.anchor).toBe(state.head);
  expect(selection.head).toBeGreaterThan(selection.anchor);
  expect(selection.text).toBe(sample);
});

for (const width of [720, 1100]) test(`long code lines wrap identically before and during editing at ${width}px`, async ({ page }) => {
  await page.setViewportSize({ width, height: 1000 });
  await page.goto('/'); await page.waitForFunction(() => !!window.__editorTest);
  const source = `BEFORE_MARKER\n\n\`\`\`python\n    result = client.messages.create(model=MODEL, max_tokens=MAX_TOKENS, messages=build_messages(question, previous_response, extra_context))\n\n    path = "${'long_segment_'.repeat(16)}"\n\treturn result\n\`\`\`\n\nAFTER_MARKER\n`;
  await page.evaluate(source => { window.__editorTest!.settings({ theme: 'night', fontSize: 17 }); window.__editorTest!.load(source); window.__editorTest!.select(0); }, source);
  const measure = () => page.evaluate(async () => {
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    const preview = document.querySelector<HTMLElement>('pre');
    const first = preview ?? document.querySelector<HTMLElement>('.code-source-first')!;
    const last = preview ?? document.querySelector<HTMLElement>('.code-source-last')!;
    const after = [...document.querySelectorAll<HTMLElement>('.cm-line')].find(line => line.textContent === 'AFTER_MARKER')!;
    return { top: first.getBoundingClientRect().top, bottom: last.getBoundingClientRect().bottom,
      after: after.getBoundingClientRect().top, header: document.querySelector('.code-language-select')!.getBoundingClientRect().top };
  });
  const baseline = await measure();
  await page.locator('pre code').click({ position: { x: 90, y: 10 } });
  for (const position of [source.indexOf('result'), source.indexOf('return'), 0]) {
    await page.evaluate(position => window.__editorTest!.select(position), position);
    const actual = await measure();
    for (const key of Object.keys(baseline) as (keyof typeof baseline)[]) {
      expect.soft(Math.abs(actual[key] - baseline[key]), `${position}: ${key}`).toBeLessThan(1);
    }
  }
  expect(await page.evaluate(() => window.__editorTest!.snapshot().text)).toBe(source);
});
