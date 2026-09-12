import {extractFile} from '@electron/asar';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const windows=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.dirname(windows),folder=path.join(root,'dist/windows/MyMarkdownViewer-win32-x64');
const pkg=JSON.parse(fs.readFileSync(path.join(windows,'package.json'),'utf8'));
const verificationDate=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul'}).format(new Date());
const validationHost=`${process.platform} ${os.release()} ${process.arch} Electron ${pkg.devDependencies.electron}`;
const files = ['main.mjs', 'session.mjs', 'core.mjs','export.mjs', 'preload.cjs'];
function includeTree(folder) { for (const item of fs.readdirSync(path.join(windows, folder), { withFileTypes: true })) { const name = folder + '/' + item.name; if (item.isDirectory()) includeTree(name); else files.push(name); } }
includeTree('ui'); includeTree('editor');
for(const name of files)assert.deepEqual(extractFile(path.join(folder,'resources/app.asar'),name),fs.readFileSync(path.join(windows,name)),name);
execFileSync('python3',['-c',String.raw`
import pathlib,zipfile,struct,hashlib,json,sys
root=pathlib.Path(sys.argv[1]);version=sys.argv[2];verification_date=sys.argv[3];z=root/f'dist/windows/MyMarkdownViewer-{version}-Windows-x64.zip'
with zipfile.ZipFile(z) as archive:
 assert archive.testzip() is None
 names=archive.namelist();prefix='MyMarkdownViewer-win32-x64/'
 for f in ['MyMarkdownViewer.exe','resources/app.asar','icudtl.dat','LICENSE','LICENSES.chromium.html','ThirdPartyNotices.txt','LICENSE-jsdiff.txt','사용안내.txt']: assert prefix+f in names,f
 exe=archive.read(prefix+'MyMarkdownViewer.exe');offset=struct.unpack_from('<I',exe,0x3c)[0]
 assert exe[:2]==b'MZ' and exe[offset:offset+4]==b'PE\0\0'
 assert struct.unpack_from('<H',exe,offset+4)[0]==0x8664
 assert archive.read(prefix+'resources/app.asar')==(root/'dist/windows/MyMarkdownViewer-win32-x64/resources/app.asar').read_bytes()
 assert archive.read(prefix+'사용안내.txt')==(root/'Windows/사용안내.txt').read_bytes()
 assert not any('/Electron.app/' in n or '/tests/' in n or '/.git/' in n for n in names)
 validation_host=sys.argv[4]
 result={'date':verification_date,'packageVersion':version,'target':'Windows 11 x64 Intel/AMD','artifact':str(z.relative_to(root)),'bytes':z.stat().st_size,'sha256':hashlib.sha256(z.read_bytes()).hexdigest(),'zipEntryCount':len(names),'zipIntegrity':True,'peMachine':'0x8664 AMD64','sourceResourceMatch':True,'actualWindowsExecution':False,'physicalWindowsIME':False,'signed':False,'validationHost':validation_host,'checks':['zip integrity','required runtime entries','PE x64 header','ASAR source resource match','excluded development files']}
 (root/'docs/windows-verification-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 pathlib.Path(str(z)+'.sha256').write_text(result['sha256']+'  '+z.name+'\n')
 print(json.dumps(result,ensure_ascii=False,indent=2))
`,root,pkg.version,verificationDate,validationHost],{stdio:'inherit'});
