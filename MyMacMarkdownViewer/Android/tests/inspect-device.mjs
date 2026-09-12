import {_android} from '../../Editor/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
const devices=await _android.devices();const device=devices.find(d=>d.serial()==='emulator-5580');
if(!device)throw Error('Dedicated QA emulator not found');
const web=await device.webView({pkg:'com.personal.markdownreader'});const page=await web.page();
console.log(await page.evaluate(()=>({url:location.href,text:document.body.innerText,snapshot:window.ReaderHost?.snapshot(),height:innerHeight,width:innerWidth})));
await fs.writeFile('Android/test-results/android-current.png',await device.screenshot());
await device.close();

process.exit(0);
