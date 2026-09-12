import { test, expect } from '@playwright/test';

test.beforeEach(async ({page}) => {
  await page.goto('/');
  await page.waitForFunction(() => window.__editorTest);
});

test('offline export resolves references and duplicate-heading TOC without footnotes', async ({page}) => {
  const text = '# Same\n\n[toc]\n\n[Guide][guide]\n\n## Same\n\n[guide]: https://example.com/guide\n';
  const result = await page.evaluate(async text => {
    window.__editorTest!.load(text);
    const doc = new DOMParser().parseFromString(await window.MarkdownHost.exportHTML(), 'text/html');
    return {
      reference: doc.querySelector('a[href="https://example.com/guide"]')?.textContent,
      toc: [...doc.querySelectorAll('a[href^="#"]')].map(a => ({href:a.getAttribute('href'), exists:!!doc.getElementById(decodeURIComponent(a.getAttribute('href')!.slice(1)))})),
      body: doc.body.textContent,
    };
  }, text);
  expect(result.reference).toBe('Guide');
  expect(result.toc).toHaveLength(2);
  expect(result.toc.every(a => a.exists)).toBe(true);
  expect(result.toc[0].href).not.toBe(result.toc[1].href);
  expect(result.body).not.toContain('[toc]');
});

test('mixed export retains multi-paragraph display math, rich footnotes and diagrams', async ({page}) => {
  const source = '# Mixed\n\n$$\na+b\n\n+c\n$$\n\nText[^a] and again[^a].\n\n[^a]: **Rich** note\n\n```mermaid\ngraph LR\n A --> B\n```\n';
  const result = await page.evaluate(async text => {
    window.__editorTest!.load(text);
    const doc = new DOMParser().parseFromString(await window.MarkdownHost.exportHTML(), 'text/html');
    return {
      math:doc.querySelectorAll('.katex-display').length,
      footers:doc.querySelectorAll('.footnotes').length,
      rich:doc.querySelector('.footnotes strong')?.textContent,
      svg:doc.querySelectorAll('svg').length,
      broken:[...doc.querySelectorAll('a[href^="#"]')].filter(a => !doc.getElementById(decodeURIComponent(a.getAttribute('href')!.slice(1)))).map(a=>a.outerHTML),
    };
  }, source);
  expect(result.math).toBe(1);
  expect(result.footers).toBe(1);
  expect(result.rich).toBe('Rich');
  expect(result.svg).toBeGreaterThan(0);
  expect(result.broken).toEqual([]);
});

test('semantic export does not interpret examples inside code fences', async ({page}) => {
  const code='[toc]\n\n$$\nx+y\n$$\n\n[^a]';
  const source='# Example\n\n```text\n'+code+'\n```\n\nActual[^a].\n\n[^a]: Note\n';
  const result=await page.evaluate(async text=>{
    window.__editorTest!.load(text);
    const doc=new DOMParser().parseFromString(await window.MarkdownHost.exportHTML(),'text/html');
    return {code:doc.querySelector('pre code')?.textContent, refs:doc.querySelectorAll('.footnote-ref').length, math:doc.querySelectorAll('.katex-display').length};
  },source);
  expect(result.code).toBe(code+'\n');
  expect(result.refs).toBe(1);
  expect(result.math).toBe(0);
});
test('native host can embed approved local images without browser custom-scheme fetch',async({page})=>{
 const html=await page.evaluate(async()=>{
   window.__editorTest!.load('# Native export\n\n![Local](assets/local.png)\n\n$x^2$\n');
   return window.MarkdownHost.exportHTML(false);
 });
 expect(html).toContain('src="app://assets/');
 expect(html).toContain('data:font/woff2;base64,');
 expect(html).not.toContain('<script');
});
