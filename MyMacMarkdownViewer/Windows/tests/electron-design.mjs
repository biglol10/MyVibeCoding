import {_electron as electron} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
const data=await fs.mkdtemp(path.join(os.tmpdir(),'mymarkdown-design-'));
const folder=path.join(data,'나의 문서');await fs.mkdir(folder);await fs.mkdir(path.join(folder,'프로젝트'));
const doc=path.join(folder,'글쓰기의 시작.md');
await fs.writeFile(doc,'# 글쓰기의 시작\n\n생각을 정리하고, 필요한 것에 집중하는 공간.\n\n## 오늘의 기록\n\n좋은 도구는 글을 쓰는 동안 눈에 띄지 않습니다. 문장을 다듬고 생각을 이어 갈 수 있도록, 필요한 기능은 가까이에 두고 문서에는 충분한 여백을 남깁니다.\n\n> 작은 기록들이 모여 하나의 이야기가 됩니다.\n\n## 이어서 할 일\n\n- 자료를 읽고 핵심 내용을 정리하기\n- 목차를 보며 글의 흐름 살펴보기\n- 다음에 이어 쓸 문장 남겨 두기\n');
await fs.writeFile(path.join(folder,'아이디어와 메모.md'),'# 아이디어\n\n다음 글의 시작.\n');
const app=await electron.launch({executablePath:path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),args:[path.resolve(process.env.PACKAGED_APP||'Windows'),'--qa-data',data]});
try{
 const page=await app.firstWindow();page.setDefaultTimeout(15000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const frame=page.frame({url:'app://editor/index.html'})||await page.waitForEvent('framenavigated',{predicate:f=>f.url()==='app://editor/index.html'});await frame.waitForFunction(()=>window.MarkdownHost?.snapshot);
 await app.evaluate(async(_,folder)=>globalThis.__qa.grant(folder),folder);
 await page.locator('.tree-item').filter({hasText:'글쓰기의 시작.md'}).click();
 await frame.waitForFunction(()=>window.MarkdownHost.snapshot().documentID.endsWith('글쓰기의 시작.md'));
 await page.waitForFunction(()=>!document.querySelector('#position').textContent.includes('0줄')) ;
 await fs.mkdir('Windows/test-results',{recursive:true});
 for(const theme of ['dark','light','night']){
  await page.locator('[data-action=settings]').click();await page.locator('#set-theme').selectOption(theme);await page.locator('#save-settings').click();
  await page.waitForFunction(t=>document.documentElement.dataset.theme===t,theme);await frame.waitForFunction(t=>document.documentElement.dataset.theme===t,theme);
  await page.mouse.move(1100,790);await page.screenshot({path:`Windows/test-results/design-${theme}.png`});
 }
 await page.locator('.statusbar [data-action=toggleSidebar]').click();assert.equal(await page.locator('#sidebar').isVisible(),false);
 await page.screenshot({path:'Windows/test-results/design-writing.png'});
 const view=page.locator('.app-menus details').filter({has:page.locator('summary',{hasText:'보기'})});await view.locator('summary').click();await page.locator('[data-action=showOutline]').click();assert.equal(await page.locator('#outline-panel').isVisible(),true);
 await page.getByRole('tab',{name:'파일',exact:true}).click();
 const fileMenu=page.locator('.app-menus details').first();await fileMenu.locator('summary').focus();await page.keyboard.press('ArrowDown');assert.equal(await page.locator('[data-action=new]').evaluate(n=>n===document.activeElement),true);await page.keyboard.press('Escape');assert.equal(await fileMenu.getAttribute('open'),null);
 await page.locator('.tree-item').filter({hasText:'아이디어와 메모.md'}).click({button:'right'});assert.equal(await page.locator('.folder-menu').getAttribute('open'),'');await page.keyboard.press('Escape');
 await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setContentSize(800,560));
 await page.locator('[data-action=settings]').click();await page.locator('#set-theme').selectOption('light');await page.locator('#save-settings').click();
 await page.getByRole('tab',{name:'찾기',exact:true}).click();await page.locator('#search-query').fill('문장');await page.locator('#search-query').press('Enter');await page.locator('[aria-label="바꿀 내용"]').waitFor();
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 const replace=await page.locator('[aria-label="바꿀 내용"]').boundingBox();const sidebar=await page.locator('#sidebar').boundingBox();assert.ok(replace.x+replace.width<=sidebar.x+sidebar.width);
 await page.screenshot({path:'Windows/test-results/design-search-light.png'});
 await page.getByRole('tab',{name:'파일',exact:true}).click();await page.getByLabel('파일 관리',{exact:true}).click();const popup=await page.locator('#file-tools').boundingBox();assert.ok(popup.x>=0&&popup.y+popup.height<=560);await page.screenshot({path:'Windows/test-results/design-menu.png'});await page.keyboard.press('Escape');
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({passed:true,checks:['single-click file open','three matching editor and shell themes','sidebar collapse and outline restore','menu keyboard navigation and Escape','file context menu','narrow search inputs contained','narrow file menu contained','no renderer exceptions']},null,2));
}finally{await app.evaluate(({app})=>app.exit(0)).catch(()=>{});await app.close().catch(()=>{});}
