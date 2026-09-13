import { chromium } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const assets = path.resolve('Android/app/src/main/assets/reader');
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
await context.addInitScript(() => {
  window.__requests = [];
  window.AndroidBridge = { postMessage(value) { window.__requests.push(JSON.parse(value)); } };
});
await context.route('**/*', async route => {
  const url = new URL(route.request().url());
  if (url.hostname !== 'appassets.androidplatform.net') return route.abort();
  const relative = url.pathname.replace(/^\/reader\//, '');
  try {
    const body = await fs.readFile(path.join(assets, relative));
    const contentType = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' }[path.extname(relative)] || 'application/octet-stream';
    await route.fulfill({ body, contentType });
  } catch { await route.fulfill({ status: 404, body: '' }); }
});

const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
try {
  await page.goto('https://appassets.androidplatform.net/reader/index.html');
  await page.waitForFunction(() => window.ReaderHost);
  await fs.mkdir('Android/test-results', { recursive: true });
  const longLink = `https://example.invalid/${'long-path-segment-'.repeat(14)}end`;
  const longCode = `const remoteAddress = "${'https://example.invalid/'.repeat(11)}end";`;
  const markdown = [
    '# Readability check',
    '',
    `A long [${longLink}](${longLink}) should wrap within the reading column, and \`inline_identifier_${'segment_'.repeat(4)}end\` should remain easy to read.`,
    '',
    '```js',
    'const answer = 42;',
    'function greet(name) { // clear comment',
    '  return "hello" + name;',
    '}',
    longCode,
    '```',
    '',
    '```json',
    '{"state": "ready"}',
    '```',
    '',
    '| Column one | Column two | Column three |',
    '| --- | --- | --- |',
    `| ${'wide-value-'.repeat(8)} | middle | ${'another-wide-value-'.repeat(7)} |`,
    '',
    'Readable search term: supercalifragilistic.',
  ].join('\n');
  await page.evaluate(text => window.ReaderHost.receive({ type: 'document', id: 'readability', name: 'readability.md', text, hasFolder: false }), markdown);
  await page.waitForFunction(() => window.ReaderHost.snapshot().ready === 'readability');
  await page.waitForFunction(() => document.querySelector('.hljs-number'));

  function luminance(color) {
    const rgb = color.match(/[\d.]+/g).slice(0, 3).map(Number).map(value => value / 255).map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
  }
  function contrast(foreground, background) {
    const a = luminance(foreground), b = luminance(background);
    return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
  }
  async function inspectTheme(theme, buttonName, minimumCodeSize = 15) {
    if (theme !== 'night') {
      await page.locator('#preferences').click();
      await page.getByRole('button', { name: buttonName, exact: true }).click();
      await page.waitForFunction(expected => window.ReaderHost.snapshot().theme === expected, theme);
      await page.locator('#settings .primary').click();
      await page.waitForFunction(() => document.querySelector('#loading').hidden);
    }
    const values = await page.evaluate(() => {
      const article = document.querySelector('#document');
      const computed = selector => getComputedStyle(article.querySelector(selector));
      const preStyle = computed('pre');
      const inlineStyle = computed('p code');
      const tableStyle = computed('table');
      const foregrounds = ['.hljs-keyword', '.hljs-number', '.hljs-string', '.hljs-attr', '.hljs-title.function_', '.hljs-comment']
        .map(selector => getComputedStyle(article.querySelector(`pre ${selector}`)).color);
      const linkStyle = getComputedStyle(article.querySelector('a'));
      const pre = article.querySelector('pre'), tableScroller = article.querySelector('.table-scroll'), link = article.querySelector('a');
      return {
        theme: document.documentElement.dataset.theme,
        codeSize: parseFloat(preStyle.fontSize), inlineSize: parseFloat(inlineStyle.fontSize), tableSize: parseFloat(tableStyle.fontSize),
        codeBackground: preStyle.backgroundColor, codeForegrounds: foregrounds,
        linkColor: linkStyle.color, articleBackground: getComputedStyle(document.body).backgroundColor,
        codeScrollable: pre.scrollWidth > pre.clientWidth,
        tableScrollable: tableScroller.scrollWidth > tableScroller.clientWidth && tableScroller.tabIndex === 0,
        linkWraps: link.getBoundingClientRect().right <= document.querySelector('#reading').getBoundingClientRect().right + 1,
        pageFits: document.documentElement.scrollWidth <= innerWidth,
        writable: article.querySelector('input,textarea,[contenteditable=true]') !== null,
      };
    });
    assert.equal(values.theme, theme);
    assert.ok(values.codeSize >= minimumCodeSize, `${theme} code size ${values.codeSize}px is below ${minimumCodeSize}px`);
    assert.ok(values.inlineSize >= minimumCodeSize, `${theme} inline code size ${values.inlineSize}px is below ${minimumCodeSize}px`);
    assert.ok(values.tableSize >= 15, `${theme} table size ${values.tableSize}px is below 15px`);
    assert.ok(contrast(values.linkColor, values.articleBackground) >= 4.5, `${theme} link contrast is too low`);
    for (const [index, color] of values.codeForegrounds.entries()) {
      assert.ok(contrast(color, values.codeBackground) >= 4.5, `${theme} syntax token ${index} contrast is too low (${color} on ${values.codeBackground})`);
    }
    assert.equal(values.codeScrollable, true, `${theme} long code line should scroll inside its block`);
    assert.equal(values.tableScrollable, true, `${theme} wide table should scroll in its keyboard-focusable container`);
    assert.equal(values.linkWraps, true, `${theme} long link should stay inside the reading column`);
    assert.equal(values.pageFits, true, `${theme} should not create document-level horizontal scrolling`);
    assert.equal(values.writable, false, 'the Android document remains read-only');
    await page.screenshot({ path: `Android/test-results/readability-${theme}.png` });
    await page.locator('#document pre').first().scrollIntoViewIfNeeded();
    await page.screenshot({ path: `Android/test-results/readability-${theme}-code.png` });
    return values;
  }

  const themes = [];
  themes.push(await inspectTheme('night', '나이트'));
  themes.push(await inspectTheme('dark', '다크'));
  themes.push(await inspectTheme('light', '라이트'));

  await page.locator('#preferences').click();
  await page.locator('#font-size').fill('14');
  await page.locator('#settings .primary').click();
  await page.waitForFunction(() => document.querySelector('#loading').hidden);
  const minimumSizes = await page.evaluate(() => ({
    body: parseFloat(getComputedStyle(document.querySelector('#document')).fontSize),
    code: parseFloat(getComputedStyle(document.querySelector('#document pre')).fontSize),
    inline: parseFloat(getComputedStyle(document.querySelector('#document p code')).fontSize),
  }));
  assert.deepEqual(minimumSizes, { body: 14, code: 15, inline: 15 });

  await page.getByRole('button', { name: '본문 검색', exact: true }).click();
  await page.locator('#query').fill('hello');
  await page.waitForFunction(() => document.querySelectorAll('mark.reader-match').length > 0);
  const codeMatch = await page.locator('mark.reader-match.current-match').evaluate(node => ({
    parentClass: node.parentElement.className,
    foreground: getComputedStyle(node).color,
    background: getComputedStyle(node).backgroundColor,
  }));
  assert.match(codeMatch.parentClass, /hljs-string/, 'search identifies a match nested inside a syntax-colored string');
  assert.ok(contrast(codeMatch.foreground, codeMatch.background) >= 4.5, 'a search match inside syntax coloring remains readable');
  await page.locator('#query').fill('supercalifragilistic');
  await page.waitForFunction(() => document.querySelectorAll('mark.reader-match').length > 0);
  assert.equal(await page.locator('mark.reader-match').count(), 1);
  const matchColors = await page.locator('mark.reader-match.current-match').evaluate(node => ({
    foreground: getComputedStyle(node).color,
    background: getComputedStyle(node).backgroundColor,
  }));
  assert.ok(contrast(matchColors.foreground, matchColors.background) >= 4.5, 'the active search result remains readable');
  await page.getByRole('button', { name: '검색 닫기', exact: true }).click();
  assert.equal(await page.locator('#document pre code .hljs-number').count(), 1, 'search leaves syntax markup intact');
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ passed: true, themes, minimumSizes, checks: ['Night, Dark and Light links and syntax meet 4.5:1 contrast','code and inline code scale with reading settings with a 15px floor','small type remains available for prose','long links wrap inside the phone column','long fenced lines and wide tables scroll locally','table scrolling stays keyboard reachable','search preserves syntax markup','document remains read-only','no renderer errors'] }, null, 2));
} finally {
  await browser.close();
}
