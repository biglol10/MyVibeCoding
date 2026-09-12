import { test, expect } from '@playwright/test';
test.beforeEach(async ({page})=>{await page.goto('/');await page.waitForFunction(()=>window.__editorTest);});

test('footnote navigation reaches offscreen definition and returns to the reference',async({page})=>{
 const source='# 시작\n\n참조[^note]입니다.\n\n'+Array.from({length:100},(_,i)=>`문단 ${i}\n\n`).join('')+'[^note]: 마지막 각주\n';
 await page.evaluate(text=>window.__editorTest!.load(text),source);
 await page.locator('.footnote-ref a').click();
 const at=await page.evaluate(()=>window.__editorTest!.snapshot().anchor);
 expect(at).toBeGreaterThan(source.indexOf('문단 99'));
 // Move the caret outside the definition so its preview/backlink is visible.
 await page.evaluate(()=>{const t=window.__editorTest!; t.select(t.snapshot().text.indexOf('문단 99'));});
 await expect(page.locator('.footnote-backref').first()).toBeVisible();
 await page.locator('.footnote-backref').first().click();
 const back=await page.evaluate(()=>window.__editorTest!.snapshot().anchor);
 expect(back).toBeGreaterThan(0); expect(back).toBeLessThan(source.indexOf('문단 0'));
});

test('editing a reference definition refreshes another paragraph link',async({page})=>{
 const source='# 시작\n\n[Guide][ref]\n\n[ref]: https://example.com/old\n';
 await page.evaluate(text=>window.__editorTest!.load(text),source);
 await expect(page.locator('a[href="https://example.com/old"]')).toHaveCount(1);
 await page.evaluate(()=>{
   const t=window.__editorTest!,text=t.snapshot().text,at=text.indexOf('old');
   t.select(at,at+3);t.insert('new');
 });
 await expect(page.locator('a[href="https://example.com/new"]')).toHaveCount(1);
 await expect(page.locator('a[href="https://example.com/old"]')).toHaveCount(0);
});
test('reversed definitions and code markers keep actual footnote destinations',async({page})=>{
 const source='# Start\n\n`[^b]` and \\[^b] are examples.\n\nActual[^b], then[^a], again[^b].\n\n[^a]: First definition\n\n[^b]: Second definition\n';
 await page.evaluate(text=>window.__editorTest!.load(text),source);
 await expect(page.locator('.footnotes')).toHaveCount(1);
 await expect(page.locator('.footnote-ref')).toHaveCount(3);
 await expect(page.locator('#fnref1')).toHaveAttribute('href','#fn1');
 await page.locator('#fnref1').click();
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().anchor)).toBe(source.indexOf('[^b]:'));
});
test('collapsed reference syntax resolves using document definitions',async({page})=>{
 const source='# Start\n\n[Guide][] and [Guide].\n\n[Guide]: https://example.com/guide\n';
 await page.evaluate(text=>window.__editorTest!.load(text),source);
 await expect(page.locator('a[href="https://example.com/guide"]')).toHaveCount(2);
});
test('rich multi-paragraph footnotes appear once and preserve nearby prose',async({page})=>{
 const source='# Start\n\nActual[^a].\n\n[^a]: First note paragraph\n\n    **Second note paragraph**\n\nOrdinary prose after the note.\n';
 await page.evaluate(text=>window.__editorTest!.load(text),source);
 await expect(page.locator('.footnotes')).toHaveCount(1);
 await expect(page.locator('.footnotes strong')).toHaveText('Second note paragraph');
 await expect(page.locator('pre')).toHaveCount(0);
 await expect(page.locator('.cm-content')).toContainText('Ordinary prose after the note.');
});
