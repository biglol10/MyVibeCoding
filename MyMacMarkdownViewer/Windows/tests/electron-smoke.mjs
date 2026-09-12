import { _electron as electron } from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const data = await fs.mkdtemp(path.join(os.tmpdir(),'mymarkdown-windows-qa-'));
const workspace = path.join(data,'문서 폴더'); await fs.mkdir(workspace);
const file = path.join(workspace,'한글 문서.md');
const source = '# 제목\n\n앞 👩🏽‍💻 찾을말 뒤\n\n- [ ] 작업\n';
await fs.writeFile(file, source);
await fs.writeFile(path.join(workspace,'두 번째.md'), '찾을말\n');
const executablePath = path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron');
const app = await electron.launch({ executablePath, args: [path.resolve(process.env.PACKAGED_APP || 'Windows'),'--qa-data',data] });
try {
 const page = await app.firstWindow(); page.setDefaultTimeout(15000); console.log("WINDOW",page.url());
 page.on('console',m=>{if(m.type()==='error')console.log('CONSOLE',m.text())});
 page.on('pageerror',e=>console.log('PAGEERROR',e.message));
 await page.waitForSelector('#editor-frame');
 const frame = page.frame({url:'app://editor/index.html'}) || await page.waitForEvent('framenavigated', {predicate:f=>f.url()==='app://editor/index.html'});
 await frame.waitForFunction(()=>window.MarkdownHost?.snapshot);
 await app.evaluate(async(_,folder)=>globalThis.__qa.grant(folder),workspace);
 const call = (action,payload={})=>page.evaluate(async([a,p])=>window.desktop.invoke(a,p),[action,payload]);
 let r=await call('open',{path:file}); assert.equal(r.ok,true,JSON.stringify(r));
 await frame.waitForFunction(s=>window.MarkdownHost.snapshot().text===s,source);
await frame.evaluate(()=>window.MarkdownHost.receive({type:'insert',...window.MarkdownHost.snapshot(),text:'추가 '}));
 await page.waitForTimeout(300);
 r=await call('save'); assert.equal(r.ok,true,JSON.stringify(r));
 assert.equal(await fs.readFile(file,'utf8'),'추가 '+source);
 await call('command',{command:'undo'}); await page.waitForTimeout(250);
assert.equal(await frame.evaluate(()=>window.MarkdownHost.snapshot().text),source);
await call('save');
// A directory copy must include the active nested document's unsaved snapshot
// without changing the original document.
const nested=path.join(workspace,'중첩'); const nestedFile=path.join(nested,'초안.md'); await fs.mkdir(nested); await fs.writeFile(nestedFile,'디스크 원본\n');
await call('settings',{patch:{autosave:false}}); r=await call('open',{path:nestedFile}); assert.equal(r.ok,true,JSON.stringify(r));
await frame.evaluate(()=>window.MarkdownHost.receive({type:'insert',...window.MarkdownHost.snapshot(),text:'미저장 '})); await page.waitForTimeout(250);
r=await call('duplicate',{path:nested}); assert.equal(r.ok,true,JSON.stringify(r));
assert.equal(await fs.readFile(nestedFile,'utf8'),'디스크 원본\n');
assert.equal(await fs.readFile(path.join(workspace,'중첩 복사본','초안.md'),'utf8'),'미저장 디스크 원본\n');
await call('save');
r=await call('search',{query:'찾을말',caseSensitive:false}); assert.equal(r.ok,true,JSON.stringify(r)); assert.equal(r.value.files.length,2);
 const report=r.value;
 r=await call('reviewReplace',{searchID:report.id,replacement:'바꾼말'}); assert.equal(r.ok,true,JSON.stringify(r));
 r=await call('applyReplace',{reviewID:r.value.id,selected:[file]});assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.value.savedCount,1);
assert.ok((await fs.readFile(file,'utf8')).includes('바꾼말'));
assert.equal(await fs.readFile(path.join(workspace,'두 번째.md'),'utf8'),'찾을말\n');
const scoped=path.join(workspace,'범위'); const scopedFile=path.join(scoped,'범위 문서.md'); await fs.mkdir(scoped); await fs.writeFile(scopedFile,'범위말\n'); await fs.writeFile(path.join(workspace,'범위 밖.md'),'범위말\n');
r=await call('search',{query:'범위말',root:scoped}); assert.equal(r.ok,true,JSON.stringify(r)); assert.equal(r.value.files.length,1);
r=await call('reviewReplace',{searchID:r.value.id,replacement:'범위변경'}); assert.equal(r.ok,true,JSON.stringify(r));
r=await call('applyReplace',{reviewID:r.value.id,selected:[scopedFile]}); assert.equal(r.ok,true,JSON.stringify(r)); assert.equal(r.value.savedCount,1);
assert.equal(await fs.readFile(scopedFile,'utf8'),'범위변경\n'); assert.equal(await fs.readFile(path.join(workspace,'범위 밖.md'),'utf8'),'범위말\n');
 r=await call('open',{path:file}); assert.equal(r.ok,true,JSON.stringify(r));
await call('create',{parent:workspace,name:'새 폴더',directory:true});
 r=await call('move',{source:file,parent:path.join(workspace,'새 폴더'),name:'이름 변경.md'});assert.equal(r.ok,true,JSON.stringify(r));
 assert.equal((await app.evaluate(()=>globalThis.__qa.state())).doc.path,path.join(workspace,'새 폴더','이름 변경.md'));
 // Save As is a real main-process action; only the native destination picker is stubbed.
 const savedAs=path.join(workspace,'다른 이름.md');
 await app.evaluate(({dialog},dest)=>{dialog.showSaveDialog=async()=>({canceled:false,filePath:dest});},savedAs);
 r=await call('saveAs'); assert.equal(r.ok,true,JSON.stringify(r));
 await frame.waitForFunction(p=>window.MarkdownHost.snapshot().documentID===p,savedAs);
 await call('settings',{patch:{autosave:false}});
 await frame.evaluate(()=>window.MarkdownHost.receive({type:'insert',...window.MarkdownHost.snapshot(),text:'저장 후 편집 '}));
 await page.waitForTimeout(250); r=await call('save'); assert.equal(r.ok,true,JSON.stringify(r));
 assert.ok((await fs.readFile(savedAs,'utf8')).includes('저장 후 편집 '));
 // Clean external edits reload; dirty external edits preserve editor data and refuse overwrite.
 await fs.writeFile(savedAs,'# 외부 수정\n');
 await frame.waitForFunction(()=>window.MarkdownHost.snapshot().text==='# 외부 수정\n');
 await frame.evaluate(()=>window.MarkdownHost.receive({type:'insert',...window.MarkdownHost.snapshot(),text:'미저장 복구 '}));
 await page.waitForTimeout(300);
 await fs.writeFile(savedAs,'# 디스크 유지\n');
 await page.waitForFunction(()=>document.querySelector('#save-state').textContent==='충돌 감지');
 r=await call('save'); assert.equal(r.ok,false);
 assert.equal(await fs.readFile(savedAs,'utf8'),'# 디스크 유지\n');
 const recoveries=await call('recoveries'); assert.ok(recoveries.value.some(x=>x.text.includes('미저장 복구')));
 // Preserve the dirty draft and restore it into an untitled document, never over the disk file.
 await app.evaluate(({dialog})=>{dialog.showMessageBox=async()=>({response:2});});
 const recoveryID=recoveries.value.find(x=>x.text.includes('미저장 복구')).id;
 r=await call('restoreRecovery',{id:recoveryID});assert.equal(r.ok,true,JSON.stringify(r));
 await frame.waitForFunction(()=>window.MarkdownHost.snapshot().documentID==='untitled');
 assert.equal((await app.evaluate(()=>globalThis.__qa.state())).doc.path,null);
 assert.ok((await frame.evaluate(()=>window.MarkdownHost.snapshot().text)).includes('미저장 복구'));
 // Switching workspaces invalidates an old scoped replace review in the main process.
 r=await call('search',{query:'범위변경',root:scoped}); const stale=await call('reviewReplace',{searchID:r.value.id,replacement:'다시'}); assert.equal(stale.ok,true,JSON.stringify(stale));
 const otherWorkspace=path.join(data,'다른 폴더'); await fs.mkdir(otherWorkspace); await app.evaluate(async(_,folder)=>globalThis.__qa.grant(folder),otherWorkspace);
 r=await call('applyReplace',{reviewID:stale.value.id,selected:[scopedFile]}); assert.equal(r.ok,false);
 // The renderer has no Node or unrestricted native API; stale asset grants are rejected.
 assert.equal(await page.evaluate(()=>typeof window.require),'undefined');
 assert.equal(await frame.evaluate(()=>typeof window.desktop),'undefined');
 assert.equal(await page.evaluate(async()=> (await fetch('app://assets/stale/example.png')).status),404);
 await call('command',{command:'source'}); await page.waitForFunction(()=>document.querySelector('#mode').textContent==='원문 모드');
 await call('settings',{patch:{theme:'night'}}); await page.waitForTimeout(100);
 await fs.mkdir('Windows/test-results',{recursive:true}); await page.screenshot({path:'Windows/test-results/electron-desktop.png'});
 console.log(JSON.stringify({passed:true,data,checks:['open','edit','save','undo','dirty nested directory duplicate','folder search','scoped search and replace','root switch invalidates review','create folder','rename rebind','save as + subsequent save','clean external reload','dirty external conflict refuses overwrite','recovery as untitled','renderer isolation','stale assets','source mode','night theme']},null,2));
} finally { await app.evaluate(({app})=>app.exit(0)).catch(()=>{}); await app.close().catch(()=>{}); }
