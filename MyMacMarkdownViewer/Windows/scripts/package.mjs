import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { packager } from '@electron/packager';
const windows = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.dirname(windows), pkg = JSON.parse(await fs.readFile(path.join(windows, 'package.json'), 'utf8'));
const staging = await fs.mkdtemp(path.join(os.tmpdir(), 'mymarkdown-package-'));
for (const name of ['main.mjs','session.mjs','core.mjs','export.mjs','preload.cjs','ui','editor','icon.ico','icon.png']) await fs.cp(path.join(windows,name), path.join(staging,name), { recursive: true });
await fs.writeFile(path.join(staging,'package.json'), JSON.stringify({ name: pkg.name, version: pkg.version, main: pkg.main, type: 'module', dependencies: pkg.dependencies }));
await fs.mkdir(path.join(staging,'node_modules'), { recursive:true });
await fs.cp(path.join(windows,'node_modules/diff'),path.join(staging,'node_modules/diff'),{recursive:true});
await fs.copyFile(path.join(root,'Sources/App/Resources/ThirdPartyNotices.txt'),path.join(staging,'ThirdPartyNotices.txt'));
const out = path.join(root,'dist/windows'); await fs.mkdir(out,{recursive:true});
const existing = path.join(out,'MyMarkdownViewer-win32-x64');
try { await fs.access(existing); await fs.rename(existing, path.join(root,'build',`previous-windows-${Date.now()}`)); } catch(e) { if(e.code!=='ENOENT')throw e; }
const paths = await packager({ dir: staging, name:'MyMarkdownViewer', executableName:'MyMarkdownViewer', platform:'win32',arch:'x64',electronVersion:pkg.devDependencies.electron,out,asar:true,prune:false,icon:path.join(windows,'icon.ico'),win32metadata:{CompanyName:'MyMarkdownViewer',FileDescription:'MyMarkdownViewer Markdown Editor',ProductName:'MyMarkdownViewer'} });
await fs.copyFile(path.join(windows,'사용안내.txt'),path.join(paths[0],'사용안내.txt'));
await fs.copyFile(path.join(root,'Sources/App/Resources/ThirdPartyNotices.txt'),path.join(paths[0],'ThirdPartyNotices.txt'));
await fs.copyFile(path.join(windows,'node_modules/diff/LICENSE'),path.join(paths[0],'LICENSE-jsdiff.txt'));
// No deployment or upload: produce a normal ZIP containing the EXE and all runtime files.
const zip = path.join(out,`MyMarkdownViewer-${pkg.version}-Windows-x64.zip`);
try { await fs.access(zip); await fs.rename(zip,path.join(root,'build',`previous-windows-${Date.now()}.zip`)); } catch(e){if(e.code!=='ENOENT')throw e;}
execFileSync('python3',['-c','import shutil,sys; shutil.make_archive(sys.argv[1],"zip",sys.argv[2],sys.argv[3])',zip.slice(0,-4),path.dirname(paths[0]),path.basename(paths[0])],{stdio:'inherit'});
console.log(zip);
