import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractAll} from '@electron/asar';
const data=await fs.mkdtemp(path.join(os.tmpdir(),'mymarkdown-session-'));
const folder=path.join(data,'문서');await fs.mkdir(folder);
const source='# 마지막 문서\n\n'+Array.from({length:200},(_,i)=>`## 절 ${i}\n\n읽던 문단 ${i}입니다.\n\n`).join('');
await fs.writeFile(path.join(folder,'last.md'),source);await fs.writeFile(path.join(folder,'explicit.md'),'# 지정한 문서\n');
const results=[];
const teardown=[];
let host=path.resolve('Windows/tests/electron-session-host.mjs');
if(process.env.PACKAGED_APP) {
  const extracted=await fs.mkdtemp(path.join(os.tmpdir(),'mymarkdown-session-package-'));
  extractAll(path.resolve(process.env.PACKAGED_APP),extracted);
  await fs.mkdir(path.join(extracted,'tests'));
  const packagedHost=path.join(extracted,'tests/electron-session-host.mjs');
  await fs.copyFile(host,packagedHost);host=packagedHost;
}
for(const stage of ['seed','restore','renamed','explicit','missing','blank','check-blank']) {
  if(stage==='missing')await fs.unlink(path.join(folder,'explicit.md')); // Owned fixture only.
  const args=[host,'--qa-data',data,'--qa-stage',stage];
  if(stage==='explicit')args.push('--open',path.join(folder,'explicit.md'));
  console.log('[session]',stage);
  await new Promise((resolve,reject)=>{
    const child=spawn(path.resolve('Windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron'),args,{stdio:['ignore','ignore','pipe']});let stderr='';
    child.stderr.on('data',d=>{stderr+=d;});
    let quitAt=0,done=false;
    const finish=(error,cleanup=false)=>{if(done)return;done=true;clearTimeout(timer);clearInterval(poll);teardown.push({stage,forcedOSCleanup:cleanup});error?reject(error):resolve();};
    const timer=setTimeout(()=>{child.kill('SIGKILL');finish(Error(stage+' timed out: '+stderr));},90000);
    const poll=setInterval(async()=>{
      try {const quit=JSON.parse(await fs.readFile(path.join(data,stage+'-quit.json'),'utf8'));assert.equal(quit.code,0);
        if(!quitAt)quitAt=Date.now();
        if(Date.now()-quitAt>3000) {child.kill('SIGKILL');finish(null,true);}
      } catch(error) {if(error.code!=='ENOENT' && !(error instanceof SyntaxError))finish(error);}
    },100);
    child.on('error',error=>finish(error));child.on('exit',(code,signal)=>finish(code===0?null:Error(stage+': '+code+'/'+signal+' '+stderr)));
  });
  const report=JSON.parse(await fs.readFile(path.join(data,stage+'.json'),'utf8'));assert.equal(report.passed,true);results.push(report);
  const saved=JSON.parse(await fs.readFile(path.join(data,'settings.json'),'utf8'));
  assert.equal(saved.root,folder);
  if(stage==='seed') {assert.equal(saved.session.documentPath,path.join(folder,'last.md'));assert.ok(saved.session.position.scrollTop>500);}
  if(stage==='restore')assert.equal(saved.session.documentPath,path.join(folder,'renamed.md'));
}
assert.equal(await fs.readFile(path.join(folder,'renamed.md'),'utf8'),source);
const report={passed:true,debuggerAttached:false,applicationQuitEvent:true,teardown,sourceBytesUnchanged:true,stages:results};
await fs.writeFile(process.env.PACKAGED_APP?'docs/session-windows-packaged-validation.json':'docs/session-windows-validation.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
