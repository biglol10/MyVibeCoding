import { test, expect } from '@playwright/test';
const source = '# 문서\n\n| 이름 | 값 |\n| --- | --- |\n|  | 123 |\n\n끝\n';
test.beforeEach(async ({page}) => { await page.goto('/'); await page.waitForFunction(()=>window.__editorTest); await page.evaluate(text=>window.__editorTest!.load(text),source); });
test('table cell keeps typing focus, commits pipes as one cell and undoes',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const cell=page.locator('.table-cell-input').nth(2);
 await cell.click(); await cell.pressSequentially('abc|def');
 await expect(cell).toBeFocused(); await expect(cell).toHaveValue('abc|def');
 await page.screenshot({path:'test-results/table-editing.png'});
 const text=await page.evaluate(()=>window.__editorTest!.snapshot().text);
 expect(text).toContain('abc\\|def');
 expect(text).toContain('123');
 await page.evaluate(()=>window.__editorTest!.command('undo'));
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toBe(source);
});
test('table editing is disabled while a host transition is locked',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await page.evaluate(()=>{const s=window.__editorTest!.snapshot();window.MarkdownHost.receive({type:'lock',...s,locked:true});});
 await expect(page.locator('.table-cell-input').first()).toBeDisabled();
 await page.evaluate(()=>{const s=window.__editorTest!.snapshot();window.MarkdownHost.receive({type:'lock',...s,locked:false});});
 await expect(page.locator('.table-cell-input').first()).toBeEnabled();
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toBe(source);
});
test('adding a row while a cell has a draft preserves that draft',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const cell=page.locator('.table-cell-input').nth(2);
 await cell.fill('새 내용');
 await page.getByRole('button',{name:'행 추가',exact:true}).click();
 const text=await page.evaluate(()=>window.__editorTest!.snapshot().text);
 expect(text).toContain('새 내용');
 await expect(page.locator('.table-cell-input')).toHaveCount(6);
});
test('Tab at the final cell adds a row without reverting the committed value',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const cell=page.locator('.table-cell-input').last();
 await cell.fill('마지막 수정'); await cell.press('Tab');
 await expect(page.locator('.table-cell-input')).toHaveCount(6);
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toContain('마지막 수정');
});
test('table controls remain keyboard accessible after text before the table changes',async({page})=>{
 await page.evaluate(()=>{const t=window.__editorTest!;t.select(0);t.insert('앞에 추가\n\n');});
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const add=page.getByRole('button',{name:'열 추가',exact:true});
 await add.focus(); await add.press('Enter');
 await expect(page.locator('.table-cell-input')).toHaveCount(6);
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toMatch(/^앞에 추가\n\n# 문서/);
});
test('table header cannot delete an unrelated body row and visible rows are numbered consecutively',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await page.locator('.table-cell-input').first().focus();
 await expect(page.getByRole('button',{name:'행 삭제',exact:true})).toBeDisabled();
 await expect(page.locator('.table-cell-input').nth(2)).toHaveAttribute('aria-label','2행 1열');
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toBe(source);
});
test('table Tab adds a row and keeps keyboard focus, Shift Tab can leave the first cell',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await page.locator('.table-cell-input').last().press('Tab');
 await expect(page.locator('.table-cell-input')).toHaveCount(6);
 await expect(page.locator('.table-cell-input').nth(4)).toBeFocused();
 await page.locator('.table-cell-input').first().press('Shift+Tab');
 await expect(page.getByRole('combobox',{name:'열 정렬'})).toBeFocused();
});
test('valid short Markdown rows expose their implicit empty cells for editing',async({page})=>{
 await page.evaluate(()=>window.__editorTest!.load('| A | B | C |\n| --- | --- | --- |\n| one |\n\n끝\n'));
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 await expect(page.locator('.table-cell-input')).toHaveCount(6);
 await page.getByRole('textbox',{name:'2행 3열',exact:true}).fill('채운 값');
 const text=await page.evaluate(()=>window.__editorTest!.snapshot().text);
 expect(text).toContain('| one |  | 채운 값 |');
 expect(text).toContain('끝');
});
test('host formatting and undo apply to the active table cell draft',async({page})=>{
 await page.getByRole('button',{name:'표 편집',exact:true}).click();
 const cell=page.locator('.table-cell-input').nth(2);
 await cell.fill('draft'); await cell.evaluate((element: HTMLInputElement)=>element.setSelectionRange(0,5));
 await page.evaluate(()=>window.__editorTest!.command('bold'));
 await expect(cell).toHaveValue('**draft**');
 await page.evaluate(()=>window.__editorTest!.command('undo'));
 expect(await page.evaluate(()=>window.__editorTest!.snapshot().text)).toBe(source);
});
