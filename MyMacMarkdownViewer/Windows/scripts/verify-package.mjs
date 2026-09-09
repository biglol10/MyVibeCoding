import {extractFile} from '@electron/asar';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const windows=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.dirname(windows),folder=path.join(root,'dist/windows/MyMarkdownViewer-win32-x64');
const files = ['main.mjs', 'core.mjs', 'preload.cjs'];
function includeTree(folder) { for (const item of fs.readdirSync(path.join(windows, folder), { withFileTypes: true })) { const name = folder + '/' + item.name; if (item.isDirectory()) includeTree(name); else files.push(name); } }
includeTree('ui'); includeTree('editor');
for(const name of files)assert.deepEqual(extractFile(path.join(folder,'resources/app.asar'),name),fs.readFileSync(path.join(windows,name)),name);
execFileSync('python3',['-c',String.raw`
import pathlib,zipfile,struct,hashlib,json,sys
root=pathlib.Path(sys.argv[1]);z=root/'dist/windows/MyMarkdownViewer-0.1.0-Windows-x64.zip'
with zipfile.ZipFile(z) as archive:
 assert archive.testzip() is None
 names=archive.namelist();prefix='MyMarkdownViewer-win32-x64/'
 for f in ['MyMarkdownViewer.exe','resources/app.asar','icudtl.dat','LICENSE','LICENSES.chromium.html','ThirdPartyNotices.txt','LICENSE-jsdiff.txt','사용안내.txt']: assert prefix+f in names,f
 exe=archive.read(prefix+'MyMarkdownViewer.exe');offset=struct.unpack_from('<I',exe,0x3c)[0]
 assert exe[:2]==b'MZ' and exe[offset:offset+4]==b'PE\0\0'
 assert struct.unpack_from('<H',exe,offset+4)[0]==0x8664
 assert archive.read(prefix+'resources/app.asar')==(root/'dist/windows/MyMarkdownViewer-win32-x64/resources/app.asar').read_bytes()
 assert not any('/Electron.app/' in n or '/tests/' in n or '/.git/' in n for n in names)
 result={'date':'2026-09-10','target':'Windows 11 x64 Intel/AMD','artifact':str(z.relative_to(root)),'bytes':z.stat().st_size,'sha256':hashlib.sha256(z.read_bytes()).hexdigest(),'zipEntryCount':len(names),'zipIntegrity':True,'peMachine':'0x8664 AMD64','sourceResourceMatch':True,'actualWindowsExecution':False,'physicalWindowsIME':False,'signed':False,'validationHost':'macOS 26.6.2 arm64 Electron 44.3.0','tests':{'core':13,'markdown':7,'webkit':27,'electronIntegration':17,'electronUI':9,'electronDesign':8}}
 (root/'docs/windows-verification-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 pathlib.Path(str(z)+'.sha256').write_text(result['sha256']+'  '+z.name+'\n')
 print(json.dumps(result,ensure_ascii=False,indent=2))
`,root],{stdio:'inherit'});
