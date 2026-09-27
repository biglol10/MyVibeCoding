import { test, expect } from '@playwright/test';
const table = '# Audit\n\n| Name | Value |\n| --- | --- |\n| First | Initial |\n| Second | Initial |\n\nEnd\n';
async function load(page: import('@playwright/test').Page, source=table) { await page.goto('/'); await page.waitForFunction(()=>window.__editorTest); await page.evaluate(source=>window.__editorTest!.load(source),source); }
test('uncommitted table draft survives native document-transition lock',async({page})=>{
 await load(page); const identity=await page.evaluate(()=>window.__editorTest!.snapshot()); await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await page.getByRole('textbox',{name:'2행 2열',exact:true}).fill('UNCOMMITTED');
 await page.evaluate(s=>window.MarkdownHost.receive({type:'lock',documentID:s.documentID,sessionID:s.sessionID,locked:true}),identity);
 expect((await page.evaluate(()=>window.__editorTest!.snapshot())).text).toContain('UNCOMMITTED');
});
test('snapshot from autosave preserves active table-cell focus',async({page})=>{
 await load(page); await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const cell=page.getByRole('textbox',{name:'2행 2열',exact:true}); await cell.fill('ACTIVE_DRAFT');
 await page.evaluate(()=>window.MarkdownHost.snapshot());
 await expect(cell).toBeFocused();
});
test('table reading links reach the host link handler',async({page})=>{
 await load(page,'# Audit\n\n| Name | Link |\n| --- | --- |\n| First | [Target](target.md) |\n\nEnd\n');
 await page.evaluate(()=>{(window as any).auditMessages=[];window.webkit={messageHandlers:{editor:{postMessage:(m: unknown)=>(window as any).auditMessages.push(m)}}};window.addEventListener('click',e=>e.preventDefault());});
 await page.getByRole('link',{name:'Target',exact:true}).click();
 expect(await page.evaluate(()=>(window as any).auditMessages.filter((x: any)=>x.type==='openLink'))).toContainEqual(expect.objectContaining({href:'target.md'}));
});
test('host Undo while find input is focused does not undo document',async({page})=>{
 await load(page,'Original body\n');
 await page.evaluate(()=>{const t=window.__editorTest!;t.select(0);t.insert('DOCUMENT_EDIT ');t.command('find');});
 const search=page.locator('input[name="search"]'); await search.fill('query');
 await page.evaluate(()=>window.__editorTest!.command('undo'));
 expect((await page.evaluate(()=>window.__editorTest!.snapshot())).text).toContain('DOCUMENT_EDIT');
});

test('control: ordinary body edits survive the same native lock',async({page})=>{
 await load(page,'Original body\n'); const identity=await page.evaluate(()=>window.__editorTest!.snapshot());
 await page.evaluate(()=>window.__editorTest!.insert('BODY_DRAFT'));
 await page.evaluate(s=>window.MarkdownHost.receive({type:'lock',documentID:s.documentID,sessionID:s.sessionID,locked:true}),identity);
 expect((await page.evaluate(()=>window.__editorTest!.snapshot())).text).toContain('BODY_DRAFT');
});
test('control: explicit save snapshot retains table text',async({page})=>{
 await load(page); await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await page.getByRole('textbox',{name:'2행 2열',exact:true}).fill('EXPLICIT_SAVE');
 expect((await page.evaluate(()=>window.MarkdownHost.snapshot())).text).toContain('EXPLICIT_SAVE');
});
test('control: paragraph modifier-click reaches host and inserted TOC uses normalized ids',async({page})=>{
 await load(page,'# Audit\n\n[Target](target.md)\n\n## 제목: 설치?\n\nBody\n\n## 반복\n\nFirst\n\n## 반복\n\nSecond\n');
 await page.evaluate(()=>{(window as any).auditMessages=[];window.webkit={messageHandlers:{editor:{postMessage:(m: unknown)=>(window as any).auditMessages.push(m)}}};});
 await page.locator('.md-link').click({modifiers:['Meta']});
 expect(await page.evaluate(()=>(window as any).auditMessages.filter((x: any)=>x.type==='openLink'))).toContainEqual(expect.objectContaining({href:'target.md'}));
 await page.evaluate(()=>{window.__editorTest!.select(0);window.__editorTest!.command('toc');});
 const text=(await page.evaluate(()=>window.__editorTest!.snapshot())).text;
 expect(text).toContain('(#제목-설치)'); expect(text).toContain('(#반복-2)');

});

test('saving a table draft retains its raw value, caret and continued typing', async ({ page }) => {
 await load(page); await page.getByRole('button', { name: '표 편집', exact: true }).click();
 const cell = page.getByRole('textbox', { name: '2행 2열', exact: true });
 await cell.fill('ab|cd'); await cell.evaluate((input: HTMLInputElement) => input.setSelectionRange(2, 2));
 const saved = await page.evaluate(() => window.MarkdownHost.snapshot());
 expect(saved.text).toContain('ab\\|cd');
 await expect(cell).toBeFocused(); await expect(cell).toHaveValue('ab|cd');
 expect(await cell.evaluate((input: HTMLInputElement) => input.selectionStart)).toBe(2);
 await cell.pressSequentially('X');
 const twice = await page.evaluate(() => { window.MarkdownHost.snapshot(); return window.MarkdownHost.snapshot().text; });
 expect(twice).toContain('abX\\|cd'); expect(twice).not.toContain('\\\\|');
 await expect(cell).toBeFocused();
});

test('composition survives an attempted transition lock and commits when finished', async ({ page }) => {
 await load(page); const identity = await page.evaluate(() => window.MarkdownHost.snapshot());
 await page.getByRole('button', { name: '표 편집', exact: true }).click();
 const cell = page.getByRole('textbox', { name: '2행 2열', exact: true });
 await cell.focus();
 await cell.evaluate((input: HTMLInputElement) => {
   input.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
   input.value = '한글 조합'; input.dispatchEvent(new InputEvent('input', { bubbles: true, isComposing: true }));
 });
 await page.evaluate(s => window.MarkdownHost.receive({ type: 'lock', documentID: s.documentID, sessionID: s.sessionID, locked: true }), identity);
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).composing).toBe(true);
 await expect(cell).toHaveValue('한글 조합'); await expect(cell).toBeFocused(); await expect(cell).toBeEnabled();
 await cell.dispatchEvent('compositionend', { data: '한글' });
 const result = await page.evaluate(() => window.MarkdownHost.snapshot());
 expect(result.composing).toBe(false); expect(result.text).toContain('한글 조합');
});

test('table drafts notify the host before a snapshot or blur', async ({ page }) => {
 await load(page);
 await page.evaluate(() => { (window as any).auditMessages = []; window.webkit = { messageHandlers: { editor: { postMessage: (m: unknown) => (window as any).auditMessages.push(m) } } }; });
 await page.getByRole('button', { name: '표 편집', exact: true }).click();
 await page.getByRole('textbox', { name: '2행 2열', exact: true }).fill('draft');
 expect(await page.evaluate(() => (window as any).auditMessages.filter((m: any) => m.type === 'tableDraft').at(-1)?.dirty)).toBe(true);
 await page.evaluate(() => window.MarkdownHost.snapshot());
 expect(await page.evaluate(() => (window as any).auditMessages.filter((m: any) => m.type === 'tableDraft').at(-1)?.dirty)).toBe(false);
});

test('find text has its own undo and redo without modifying the document', async ({ page }) => {
 await load(page, 'Original body\n');
 await page.evaluate(() => { window.__editorTest!.insert('KEEP '); window.__editorTest!.command('find'); });
 const search = page.locator('input[name="search"]'); await search.pressSequentially('query');
 await page.evaluate(() => window.__editorTest!.command('undo'));
 await expect(search).not.toHaveValue('query');
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).text).toContain('KEEP');
 await page.evaluate(() => window.__editorTest!.command('redo'));
 await expect(search).toHaveValue('query');
});

test('real typing in the document and search never shares an undo group', async ({ page }) => {
 await load(page, 'Original body\n');
 const body = page.getByRole('textbox', { name: 'Markdown 편집기', exact: true });
 await body.click(); await page.keyboard.press('Meta+Home');
 await page.keyboard.type('KEEP_TYPED ');
 const before = (await page.evaluate(() => window.MarkdownHost.snapshot())).text;
 await page.evaluate(() => window.__editorTest!.command('find'));
 const search = page.locator('input[name="search"]'); await search.pressSequentially('query');
 await page.evaluate(() => window.__editorTest!.command('undo'));
 await expect(search).not.toHaveValue('query');
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).text).toBe(before);
 await page.evaluate(() => window.__editorTest!.command('redo'));
 await expect(search).toHaveValue('query');
 await search.press('Meta+z');
 await expect(search).not.toHaveValue('query');
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).text).toBe(before);
});

test('find and replace fields keep separate local undo histories', async ({ page }) => {
 await load(page, 'Original body\n');
 await page.evaluate(() => window.__editorTest!.command('find'));
 const search = page.locator('input[name="search"]');
 const replace = page.locator('input[name="replace"]');
 await search.pressSequentially('query'); await replace.pressSequentially('replacement');
 await page.evaluate(() => window.__editorTest!.command('undo'));
 await expect(replace).not.toHaveValue('replacement'); await expect(search).toHaveValue('query');
 await page.evaluate(() => window.__editorTest!.command('redo'));
 await expect(replace).toHaveValue('replacement');
 await search.focus(); await page.evaluate(() => window.__editorTest!.command('undo'));
 await expect(search).not.toHaveValue('query'); await expect(replace).toHaveValue('replacement');
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).text).toBe('Original body\n');
});

test('inline, table and host fragment navigation agree on punctuation and duplicates', async ({ page }) => {
 const source = '# Audit\n\n[설치](#제목-설치)\n\n| 링크 |\n| --- |\n| [반복](#반복-2) |\n\n## 제목: 설치?\n\n설치 본문\n\n## 반복\n\n첫째\n\n## 반복\n\n둘째\n';
 await load(page, source);
 await page.locator('.md-link').click({ modifiers: ['Meta'] });
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).head).toBe(source.indexOf('## 제목: 설치?'));
 const link = page.getByRole('link', { name: '반복', exact: true });
 await link.focus(); await link.press('Enter');
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).head).toBe(source.lastIndexOf('## 반복'));
 await page.evaluate(() => { const s = window.MarkdownHost.snapshot(); window.MarkdownHost.receive({ type: 'navigateFragment', documentID: s.documentID, sessionID: s.sessionID, href: '#%EC%A0%9C%EB%AA%A9-%EC%84%A4%EC%B9%98' }); });
 expect((await page.evaluate(() => window.MarkdownHost.snapshot())).head).toBe(source.indexOf('## 제목: 설치?'));
});
