import {build} from '../../Editor/node_modules/vite/dist/node/index.js';
import path from 'node:path';
import {copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const deps=path.join(root,'Editor/node_modules');
await build({configFile:false,root:path.join(root,'Android/reader'),base:'./',resolve:{alias:[...['markdown-it','katex','mermaid','highlight.js','@lezer/markdown','@lezer/common','@codemirror/language','@codemirror/state','@codemirror/lang-markdown','@codemirror/language-data'].map(name=>({find:name,replacement:path.join(deps,name)}))]},build:{outDir:path.join(root,'Android/app/src/main/assets/reader'),emptyOutDir:true,chunkSizeWarningLimit:1500}});

await copyFile(path.join(root,'Sources/App/Resources/ThirdPartyNotices.txt'),path.join(root,'Android/app/src/main/assets/reader/ThirdPartyNotices.txt'));
