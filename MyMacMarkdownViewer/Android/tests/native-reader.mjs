import {_android} from '../../Editor/node_modules/playwright/index.mjs';
import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';import os from 'node:os';import path from 'node:path';
import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const d=(await _android.devices()).find(d=>d.serial()==='emulator-5580');if(!d)throw Error('Dedicated emulator missing');
try{
 const page=await(await d.webView({pkg:'com.personal.markdownreader'})).page();page.setDefaultTimeout(20000);
 await page.waitForFunction(()=>window.ReaderHost?.snapshot().ready);
 if((await page.evaluate(()=>window.ReaderHost.snapshot().name))!=='reader-fixture.md'){
  if(!(await page.locator('#sidebar').evaluate(n=>n.classList.contains('open'))))await page.locator('#navigation').click();
  await page.locator('#files button').filter({hasText:'reader-fixture.md'}).click();await page.waitForFunction(()=>window.ReaderHost.snapshot().name==='reader-fixture.md');
 }
 assert.match(await page.locator('#document').innerText(),/안녕하세요/);
 await page.locator('.diagram-block svg').waitFor();await page.locator('#document img').scrollIntoViewIfNeeded();await page.waitForFunction(()=>document.querySelector('#document img')?.naturalWidth>0);
 await fs.writeFile('Android/test-results/android-local-image.png',await d.screenshot());
 if(!(await page.locator('#sidebar').evaluate(n=>n.classList.contains('open'))))await page.locator('#navigation').click();console.log('FOLDER',await page.locator('#files').innerText());
 assert.ok((await page.locator('#files').innerText()).includes('nestedfolder'));
 await page.locator('#files button').filter({hasText:'nestedfolder'}).click();await page.locator('#files button').filter({hasText:'relative-target.md'}).click();await page.waitForFunction(()=>window.ReaderHost.snapshot().name==='relative-target.md');
 console.log('NESTED',await page.locator('#document').innerText());
 if(!(await page.locator('#sidebar').evaluate(n=>n.classList.contains('open'))))await page.locator('#navigation').click();await page.locator('#folder-up').click();await page.locator('#files button').filter({hasText:'reader-fixture.md'}).click();await page.waitForFunction(()=>window.ReaderHost.snapshot().name==='reader-fixture.md');
 await page.locator('#find').click();await page.locator('#query').fill('한글');await page.waitForFunction(()=>document.querySelectorAll('mark.reader-match').length>0);await fs.writeFile('Android/test-results/android-search.png',await d.screenshot());await page.locator('#close-search').click();
 const before=await page.evaluate(()=>window.ReaderHost.snapshot().id);await page.locator('[data-remote-images]').click();
 await d.shell('uiautomator dump /sdcard/reader-qa-ui.xml');const xml=(await d.shell('cat /sdcard/reader-qa-ui.xml')).toString();assert.ok(xml.includes('원격 이미지를 불러올까요?'));await d.shell('input keyevent 4');assert.equal(await page.evaluate(()=>window.ReaderHost.snapshot().remoteAllowed),false);
 await page.locator('#preferences').click();await page.getByRole('button',{name:'나이트',exact:true}).click();await page.locator('#settings .primary').click();await page.waitForFunction(()=>document.querySelector('#loading').hidden);await page.evaluate(()=>document.querySelector('#reading').scrollTop=0);await fs.writeFile('Android/test-results/android-reading-night.png',await d.screenshot());
 if(!(await page.locator('#sidebar').evaluate(n=>n.classList.contains('open'))))await page.locator('#navigation').click();
 await page.locator('#files button').filter({hasText:'reader-semantics-fixture.md'}).click();await page.waitForFunction(()=>window.ReaderHost.snapshot().name==='reader-semantics-fixture.md');
 assert.equal((await page.locator('.front-matter pre').textContent()).trimEnd(),'---\ntitle: Native semantics fixture\n---');
 assert.equal(await page.locator('.footnotes').count(),1);assert.equal(await page.locator('.footnote-ref').count(),1);assert.equal(await page.locator('a[href="https://example.invalid/reference"]').textContent(),'the reference');
 assert.equal(await page.locator('.footnote-backref').evaluateAll(links=>links.every(link=>{const id=decodeURIComponent(link.getAttribute('href').slice(1));return document.getElementById(id)!==null;})),true);
 const toc=page.locator('.table-of-contents a[data-jump]').filter({hasText:'Footnote navigation'});assert.equal(await toc.count(),1);await toc.click();assert.equal(await page.locator('#footnote-navigation').count(),1);
 await page.locator('.footnote-ref a').click();assert.equal(await page.locator('#fn1').count(),1);await page.locator('.footnote-backref').click();assert.equal(await page.locator('#fnref1').count(),1);
 assert.equal(await page.locator('.katex-display').count(),1);assert.match(await page.locator('#document').innerText(),/paragraph follows the equation/);
 await page.evaluate(()=>document.querySelector('#reading').scrollTop=0);await fs.writeFile('Android/test-results/android-semantics-native.png',await d.screenshot());
 const hashes=JSON.parse(await fs.readFile('Android/tests/fixtures/android-fixture-hashes.json','utf8'));
 const pulled=await fs.mkdtemp(path.join(os.tmpdir(),'reader-original-check-'));
 for(const [index,entry] of hashes.files.entries()){const filename='/sdcard/Documents/MarkdownReader-QA/'+entry.path;const local=path.join(pulled,String(index));execFileSync(path.join(os.homedir(),'Library/Android/sdk/platform-tools/adb'),['-s','emulator-5580','pull',filename,local],{stdio:'pipe'});const actual=createHash('sha256').update(await fs.readFile(local)).digest('hex');assert.equal(actual,entry.sha256,entry.path);}

 console.log(JSON.stringify({passed:true,checks:['native UTF8 BOM Korean document','local image through selected folder','Mermaid in Android WebView','restored folder navigation','nested document and parent navigation','native search UI','remote confirmation and cancel','night theme','native Front Matter, TOC, reference link, footnote navigation, and multiline math','original fixture hashes unchanged']},null,2));
}finally{await d.close();}
process.exit(0);
