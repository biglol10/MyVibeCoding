import {test,expect} from '@playwright/test';
test('focus mode highlights the current paragraph without changing document width',async({page})=>{
 await page.goto('/'); await page.waitForFunction(()=>window.__editorTest);
 const text='# 집중 모드\n\n첫 문단입니다.\n\n현재 작성할 문단입니다.\n\n다음 문단입니다.\n';
 await page.evaluate(text=>window.__editorTest!.load(text),text);
 const before=await page.locator('.cm-content').evaluate(e=>e.getBoundingClientRect().width);
 await page.evaluate(()=>{const t=window.__editorTest!;t.select(t.snapshot().text.indexOf('현재'));t.settings({focusMode:true});});
 const current=page.locator('.focus-active-line');
 await expect(current).toContainText('현재 작성할');
 expect(await current.evaluate(e=>getComputedStyle(e).opacity)).toBe('1');
 expect(Number(await page.locator('.focus-muted-line').first().evaluate(e=>getComputedStyle(e).opacity))).toBeLessThan(1);
 expect(await page.locator('.cm-content').evaluate(e=>e.getBoundingClientRect().width)).toBe(before);
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toBe(text);
 await page.screenshot({path:'test-results/focus-mode.png'});
});
