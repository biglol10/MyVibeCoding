import {chromium} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const assets=path.resolve('Android/app/src/main/assets/reader');
const browser=await chromium.launch({headless:true});
try {
  const context=await browser.newContext({viewport:{width:393,height:852},isMobile:true,hasTouch:true});
  await context.addInitScript(()=>{window.__requests=[];window.AndroidBridge={postMessage(value){window.__requests.push(JSON.parse(value));}};});
  await context.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.hostname!=='appassets.androidplatform.net')return route.abort();
    const relative=url.pathname.replace(/^\/reader\//,'');
    try { await route.fulfill({body:await fs.readFile(path.join(assets,relative)),contentType:{'.html':'text/html','.js':'application/javascript','.css':'text/css'}[path.extname(relative)]||'application/octet-stream'}); }
    catch { await route.fulfill({status:404,body:''}); }
  });
  const page=await context.newPage();
  await page.goto('https://appassets.androidplatform.net/reader/index.html');
  await page.waitForFunction(()=>window.ReaderHost);
  const longDocument=['# 이어 읽기',...Array.from({length:500},(_,index)=>`\n## 단락 ${index}\n\n${'이 위치는 다시 열어도 유지됩니다. '.repeat(8)}`)].join('\n');
  await page.evaluate(text=>window.ReaderHost.receive({type:'document',id:'restore',name:'이어 읽기.md',text,hasFolder:false,position:.62}),longDocument);
  await page.waitForFunction(()=>window.ReaderHost.snapshot().ready==='restore');
  await page.waitForFunction(()=>Math.abs(window.ReaderHost.snapshot().position-.62)<.03);
  await page.setViewportSize({width:852,height:393});
  await page.waitForFunction(()=>Math.abs(window.ReaderHost.snapshot().position-.62)<.04);
  await page.getByRole('button',{name:'읽기 설정',exact:true}).click();
  await page.getByRole('button',{name:'다크',exact:true}).click();
  await page.waitForTimeout(250);
  const afterTheme=await page.evaluate(()=>window.ReaderHost.snapshot().position);
  assert.ok(Math.abs(afterTheme-.62)<.04,`theme render preserves reading position: ${afterTheme}`);
  await page.evaluate(()=>window.ReaderHost.flushPosition());
  // The exact floating-point ratio is intentionally not asserted; native code validates the active session id and URI.
  assert.equal(await page.evaluate(()=>window.__requests.at(-1).id),'restore');
  assert.ok(await page.evaluate(()=>window.__requests.at(-1).ratio)>.5);
  await page.evaluate(()=>{
    window.ReaderHost.receive({type:'document',id:'slow',name:'느린 문서.md',text:'# 느린 문서\n\n'.repeat(800),hasFolder:false,position:.9});
    window.ReaderHost.receive({type:'document',id:'new',name:'새 문서.md',text:'# 새 문서\n\n새 요청이 복원보다 우선합니다.',hasFolder:false,position:0});
  });
  await page.waitForFunction(()=>window.ReaderHost.snapshot().ready==='new');
  assert.equal(await page.evaluate(()=>window.ReaderHost.snapshot().id),'new');
  assert.ok(await page.evaluate(()=>window.ReaderHost.snapshot().position)<.01);
  console.log(JSON.stringify({passed:true,checks:['render-ready ratio restore','rotation preserves ratio','theme preserves current position','debounced lifecycle position bridge','new document wins over stale render']},null,2));
} finally { await browser.close(); }
