import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from '../../Editor/node_modules/esbuild/lib/main.js';
const windows = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await fs.mkdir(path.join(windows, '../build'), { recursive: true });
try { await fs.rename(path.join(windows, 'editor'), path.join(windows, '../build', `previous-windows-editor-${Date.now()}`)); } catch (error) { if (error.code !== 'ENOENT') throw error; }
await fs.cp(path.join(windows, '../Editor/dist'), path.join(windows, 'editor'), { recursive: true });
let html = await fs.readFile(path.join(windows, 'editor/index.html'), 'utf8');
html = html.replace('<head>', '<head><script src="/editor-bridge.js"></script>');
html = html.replace('</head>', '<link rel="stylesheet" href="/editor-style.css"></head>');
await fs.copyFile(path.join(windows, 'editor-style.css'), path.join(windows, 'editor/editor-style.css'));
await fs.writeFile(path.join(windows, 'editor/index.html'), html);
await fs.copyFile(path.join(windows, 'editor-bridge.js'), path.join(windows, 'editor/editor-bridge.js'));
await build({ entryPoints: [path.join(windows, '../Editor/src/markdown.ts')], outfile: path.join(windows, 'editor/rebase.mjs'), bundle: true, platform: 'node', format: 'esm', target: 'node22' });
console.log('Shared editor and relocation parser prepared.');
