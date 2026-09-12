// Runs the real host without Playwright's Node inspector so normal quit can exit.
import { app, BrowserWindow } from 'electron';
import fs from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import '../main.mjs';
const arg = name => process.argv[process.argv.indexOf(name)+1];
const data=arg('--qa-data'), stage=arg('--qa-stage'), folder=path.join(data,'문서');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
app.once('quit', (_event, code) => writeFileSync(path.join(data,stage+'-quit.json'),JSON.stringify({code})));
// Do not await the suite at module scope: Electron waits for ESM startup before ready.
void (async () => { try {
  let win,frame,snapshot;
  for(let i=0;i<320;i++) {
    win=BrowserWindow.getAllWindows()[0];
    frame=win?.webContents.mainFrame.frames.find(f=>f.url==='app://editor/index.html');
    if(globalThis.__qa && frame && await frame.executeJavaScript('Boolean(window.MarkdownHost?.snapshot)').catch(()=>false)) {
      snapshot=await globalThis.__qa.askEditor('snapshot').catch(()=>null);
      if(snapshot)break;
    }
    await delay(250);
  }
  assert.ok(frame && snapshot,'editor and native bridge ready');
  const qa=globalThis.__qa;
  if(stage==='seed') {
    await qa.grant(folder);await qa.run('open',{path:path.join(folder,'last.md')});
    await frame.executeJavaScript(`(async()=>{window.MarkdownHost.receive({type:'jump',...window.MarkdownHost.snapshot(),from:1500,to:1500});await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));const s=document.querySelector('.cm-scroller');s.scrollTop=1200;s.dispatchEvent(new Event('scroll'));})()`);
  }
  if(stage==='blank')await qa.run('new');
  await delay(900);
  snapshot=await qa.askEditor('snapshot');
  const state=qa.state();
  if(['seed','restore','renamed'].includes(stage)) {
    assert.equal(state.doc.path,path.join(folder,stage==='renamed'?'renamed.md':'last.md'));
    assert.equal(state.root,folder);assert.equal(snapshot.anchor,1500);assert.ok(snapshot.scrollTop>500);
  } else if(stage==='explicit')assert.equal(state.doc.path,path.join(folder,'explicit.md'));
  else if(stage==='missing') {assert.equal(state.doc.path,null);assert.equal(state.root,folder);assert.match(state.status,/문서.*열 수 없습니다/);}
  else {assert.equal(state.doc.path,null);assert.equal(snapshot.text,'');}
  await fs.mkdir(path.resolve('Windows/test-results'),{recursive:true});
  if(stage==='restore'||stage==='missing')await fs.writeFile(path.resolve(`Windows/test-results/session-${stage}.png`),(await win.webContents.capturePage()).toPNG());
  if(stage==='restore')await qa.run('move',{source:path.join(folder,'last.md'),parent:folder,name:'renamed.md'});
  await fs.writeFile(path.join(data,stage+'.json'),JSON.stringify({passed:true,stage,path:state.doc.path,root:state.root,anchor:snapshot.anchor,scrollTop:snapshot.scrollTop,notice:state.status}));
  // Use the product's close event, including final snapshot and settings write.
  win.close();
} catch(error) {
  console.error(error);app.exit(1);
} })();
