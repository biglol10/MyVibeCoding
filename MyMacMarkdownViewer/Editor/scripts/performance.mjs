import {webkit,chromium} from 'playwright';
import {spawn} from 'node:child_process';
import fs from 'node:fs/promises';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','preview','--host','127.0.0.1','--port','4181'],{cwd:new URL('..',import.meta.url),stdio:'ignore'});
for(let i=0;i<100;i++){try{if((await fetch('http://127.0.0.1:4181')).ok)break;}catch{}await new Promise(r=>setTimeout(r,100));}
const browser=await webkit.launch();
try{
const page=await browser.newPage({viewport:{width:1100,height:800}});await page.goto('http://127.0.0.1:4181');await page.waitForFunction(()=>window.__editorTest);
const result=await page.evaluate(async()=>{
 const source='# 성능 검증\n\n'+Array.from({length:5000},(_,i)=>`문단 ${i} **강조 문장**과 한글 👩🏽‍💻을 포함한 문서입니다. `+'실제 편집과 같은 내용입니다. '.repeat(8)+'\n\n').join('');
 const api=window.__editorTest;const frame=()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const began=performance.now();api.load(source);await frame();const open=performance.now()-began;
 await new Promise(r=>setTimeout(r,300));
 const select=[],input=[];
 for(let i=0;i<30;i++){let t=performance.now();api.select(40+i);select.push(performance.now()-t);await frame();}
 for(let i=0;i<30;i++){let t=performance.now();api.insert('가');input.push(performance.now()-t);await frame();}
 const stats=a=>({p50:a.slice().sort((a,b)=>a-b)[Math.floor(a.length*.5)],p95:a.slice().sort((a,b)=>a-b)[Math.floor(a.length*.95)],max:Math.max(...a)});
 return {platform:'WebKit',bytes:new TextEncoder().encode(source).length,lines:source.split('\n').length,openMilliseconds:open,selectionMilliseconds:stats(select),inputMilliseconds:stats(input),sourcePreserved:api.snapshot().text.replace('가'.repeat(30),'')===source};
});
console.log(JSON.stringify(result,null,2));
if(process.argv[2])await fs.writeFile(process.argv[2],JSON.stringify(result,null,2)+'\n');
}finally{await browser.close();server.kill();}
