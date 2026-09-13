import {chromium} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const assets=path.resolve('Android/app/src/main/assets/reader');
const browser=await chromium.launch({headless:true});
const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:1,isMobile:true,hasTouch:true});
await context.addInitScript(()=>{window.__requests=[];window.AndroidBridge={postMessage(value){window.__requests.push(JSON.parse(value));}};});
await context.route('**/*',async route=>{
 const url=new URL(route.request().url());
 if(url.hostname!=='appassets.androidplatform.net')return route.abort();
 const rel=url.pathname.replace(/^\/reader\//,'');
 try{const data=await fs.readFile(path.join(assets,rel));const ext=path.extname(rel);await route.fulfill({body:data,contentType:({'.html':'text/html','.js':'application/javascript','.css':'text/css','.woff2':'font/woff2','.woff':'font/woff','.ttf':'font/ttf'})[ext]||'application/octet-stream'});}catch{await route.fulfill({status:404,body:''});}
});
const page=await context.newPage();
const errors=[];page.on('pageerror',error=>errors.push(error.message));
await page.goto('https://appassets.androidplatform.net/reader/index.html');
await page.waitForFunction(()=>window.ReaderHost);

const source=['---','title: Language labels','---','','```python','print("hello")','```','','```javascript','const thisIsAnIntentionallyVeryLongJavaScriptIdentifierForLocalHorizontalScrolling = "reader only";','```','','```odd-language','const unknownLanguageIsKept = true;','```','','```','plain text sample','```','','```  mermaid','graph LR',' A[Source] --> B[Reader]','```','','> ```js','> const nestedFence = true;','> ```',''].join('\n');
const deliveredText=await page.evaluate(text=>{
 const event=Object.freeze({type:'document',id:'language-labels',name:'language-labels.md',text,hasFolder:true});
 window.__readerSource=event.text;
 window.ReaderHost.receive(event);
 return event.text;
},source);
assert.equal(deliveredText,source);
await page.waitForFunction(()=>window.ReaderHost.snapshot().ready==='language-labels');
await page.waitForFunction(()=>document.querySelector('.diagram-block svg'));

const expected=['python','javascript','odd-language','텍스트','mermaid','javascript'];
assert.deepEqual(await page.locator('#document .reader-code-language').evaluateAll(labels=>labels.map(label=>label.textContent)),expected);
assert.equal(await page.locator('.front-matter .reader-code-language').count(),0);
assert.equal(await page.locator('.reader-code-language').evaluateAll(labels=>labels.every(label=>label.tagName==='SPAN'&&label.children.length===0)),true);
assert.equal(await page.locator('.reader-code-language').evaluateAll(labels=>labels.every(label=>label.parentElement.classList.contains('reader-code-frame')&&!label.closest('pre'))),true);
assert.equal(await page.locator('.reader-diagram-frame .reader-code-language').count(),1);
assert.equal(await page.locator('.reader-diagram-frame .reader-code-language').evaluate(label=>!label.closest('.diagram-block')),true);
assert.equal(await page.locator('#document input,#document textarea,#document select,#document button,#document [contenteditable=true]').count(),0);
assert.equal((await page.evaluate(()=>window.ReaderHost.snapshot())).writableElements,0);

for(const theme of ['light','dark','night']){
 await page.getByRole('button',{name:'읽기 설정',exact:true}).click();
 const labelsBefore=await page.locator('.reader-code-language').allTextContents();
 await page.getByRole('button',{name:theme==='light'?'라이트':theme==='dark'?'다크':'나이트',exact:true}).click();
 await page.waitForFunction(value=>document.documentElement.dataset.theme===value,theme);
 await page.waitForFunction(()=>document.querySelector('#loading').hidden);
 assert.deepEqual(await page.locator('#document .reader-code-language').evaluateAll(labels=>labels.map(label=>label.textContent)),labelsBefore);
 assert.equal(await page.locator('.reader-code-language').evaluateAll(labels=>labels.every(label=>{
   const style=getComputedStyle(label), rect=label.getBoundingClientRect();
   return style.display==='block'&&style.color!=='rgba(0, 0, 0, 0)'&&rect.width>0&&rect.height>0;
 })),true);
 await page.locator('#settings .primary').click();
}

const diagramBefore=await page.locator('.diagram-block svg').innerHTML();
await page.locator('.reader-code-language').filter({hasText:'mermaid'}).tap();
await page.locator('.reader-code-language').filter({hasText:'python'}).tap();
assert.equal(await page.locator('.diagram-block svg').innerHTML(),diagramBefore);
assert.equal(await page.locator('.reader-code-language').first().textContent(),'python');

await page.getByRole('button',{name:'본문 검색',exact:true}).click();
await page.locator('#query').fill('python');
await page.waitForFunction(()=>document.querySelector('#match-count').textContent==='일치하는 내용이 없습니다');
assert.equal(await page.locator('#match-count').innerText(),'일치하는 내용이 없습니다');
assert.equal(await page.locator('.reader-code-language mark.reader-match').count(),0);
await page.getByRole('button',{name:'검색 닫기',exact:true}).click();

assert.equal(await page.evaluate(()=>window.__readerSource),source);
assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
const overflow=await page.locator('#document pre').nth(2).evaluate(pre=>pre.scrollWidth>pre.clientWidth);
assert.equal(overflow,true,'long code should scroll inside its own pre');
assert.deepEqual(errors,[]);
await page.evaluate(()=>{document.querySelector('#reading').scrollTop=0;});
await fs.mkdir('Android/test-results',{recursive:true});
await page.screenshot({path:'Android/test-results/code-language-night.png'});
console.log(JSON.stringify({passed:true,checks:['Python/JavaScript/unknown/unlabeled/Mermaid labels','nested language-class label','front matter excluded','labels survive diagram rendering and taps','search excludes labels','all three themes','read-only document','phone width and local code scrolling','source text preserved','no renderer exceptions']},null,2));
await browser.close();
