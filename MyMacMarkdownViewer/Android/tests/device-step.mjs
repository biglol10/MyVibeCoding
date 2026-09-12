import {_android} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
const device=(await _android.devices()).find(d=>d.serial()==='emulator-5580');if(!device)throw Error('No dedicated emulator');
try{
 const action=process.argv[2];
 if(action==='open-folder'){const page=await(await device.webView({pkg:'com.personal.markdownreader'})).page();await page.locator('#welcome [data-native=openFolder]').click();}
 else if(action==='tap'){
  await device.shell('uiautomator dump /sdcard/reader-qa-ui.xml'); const xml=(await device.shell('cat /sdcard/reader-qa-ui.xml')).toString();
  const node=[...xml.matchAll(/<node[^>]+/g)].map(m=>m[0]).find(n=>n.match(/ text="([^"]*)"/)?.[1]===process.argv[3]);if(!node)throw Error('Visible text not found: '+process.argv[3]);
  const b=node.match(/ bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/).slice(1).map(Number);await device.shell('input tap '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));
 }
 else if(action==='web'){const page=await(await device.webView({pkg:'com.personal.markdownreader'})).page();console.log(await page.evaluate(()=>({text:document.body.innerText,snapshot:window.ReaderHost.snapshot()})));}
 await fs.writeFile('Android/test-results/android-current.png',await device.screenshot());
 await device.shell('uiautomator dump /sdcard/reader-qa-ui.xml');
 const xml=(await device.shell('cat /sdcard/reader-qa-ui.xml')).toString();
 console.log([...xml.matchAll(/<node[^>]+/g)].map(m=>{const n=m[0];return {text:n.match(/ text="([^"]*)"/)?.[1],desc:n.match(/ content-desc="([^"]*)"/)?.[1],bounds:n.match(/ bounds="([^"]*)"/)?.[1]};}).filter(n=>n.text||n.desc));
}finally{await device.close();}

process.exit(0);
