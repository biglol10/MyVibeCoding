import {_electron as electron} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
const data=await fs.mkdtemp(path.join(os.tmpdir(),'mymarkdown-performance-')),workspace=path.join(data,'notes');await fs.mkdir(workspace);
for(let start=0;start<1200;start+=100)await Promise.all(Array.from({length:100},(_,offset)=>fs.writeFile(path.join(workspace,`note-${String(start+offset).padStart(4,'0')}.md`),'# 문서\n\n본문입니다.\n')));
const app=await electron.launch({executablePath:path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),args:[path.resolve(process.env.PACKAGED_APP||'Windows'),'--qa-data',data]});
try{
const page=await app.firstWindow();page.setDefaultTimeout(20000);const frame=page.frame({url:'app://editor/index.html'})||await page.waitForEvent('framenavigated',{predicate:f=>f.url()==='app://editor/index.html'});await frame.waitForFunction(()=>window.MarkdownHost?.snapshot);
await app.evaluate(async(_,folder)=>globalThis.__qa.grant(folder),workspace);
await page.evaluate(p=>window.desktop.invoke('open',{path:p}),path.join(workspace,'note-0000.md'));
await frame.waitForFunction(()=>window.MarkdownHost.snapshot().documentID.endsWith('note-0000.md'));
await page.waitForTimeout(1200);
await app.evaluate((_,folder)=>{
 const fs=process.getBuiltinModule('fs/promises'),read=fs.readFile.bind(fs),list=fs.readdir.bind(fs);globalThis.__perf={reads:0,lists:0};
 fs.readFile=async(...args)=>{if(String(args[0]).startsWith(folder)&&String(args[0]).endsWith('.md'))globalThis.__perf.reads++;return read(...args)};
 fs.readdir=async(...args)=>{if(String(args[0]).startsWith(folder))globalThis.__perf.lists++;return list(...args)};
},workspace);
await page.evaluate(()=>{
 window.__perf={treeMutations:0,treePayloads:0};new MutationObserver(records=>window.__perf.treeMutations+=records.filter(r=>r.type==='childList').length).observe(document.querySelector('#tree'),{childList:true});
 window.desktop.onEvent(event=>{if(event.type==='state'&&event.payload.entries)window.__perf.treePayloads++});
});
await page.waitForTimeout(5200);const idle=await app.evaluate(()=>({...globalThis.__perf}));
for(let i=0;i<20;i++){await frame.evaluate(()=>window.MarkdownHost.receive({type:'insert',...window.MarkdownHost.snapshot(),text:'가'}));await page.waitForTimeout(45);}
await page.waitForTimeout(1500);
const ui=await page.evaluate(()=>window.__perf),io=await app.evaluate(()=>globalThis.__perf);
assert.ok((await fs.readFile(path.join(workspace,'note-0000.md'),'utf8')).includes('가'.repeat(20)));
const result={host:'macOS arm64 Electron44.3',entries:1200,idleMilliseconds:5200,idle,afterTwentyEdits:io,ui,sourceSaved:true};
if(!process.env.PACKAGED_APP){assert.equal(idle.reads,0);assert.equal(idle.lists,0);assert.equal(ui.treeMutations,0);assert.equal(ui.treePayloads,0);}
if(process.argv[2])await fs.writeFile(process.argv[2],JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
}finally{await app.evaluate(({app})=>app.exit(0)).catch(()=>{});await app.close().catch(()=>{});}
