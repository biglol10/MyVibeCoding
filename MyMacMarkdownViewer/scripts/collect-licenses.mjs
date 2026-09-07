import { readFile, readdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(await readFile(path.join(root, 'Editor/package-lock.json'), 'utf8'));
let output = 'MyMarkdownViewer — Third-party notices\n\nThis application includes the following open-source components.\n';
for (const [relative, metadata] of Object.entries(lock.packages)) {
  if (!relative || metadata.dev) continue;
  const directory = path.join(root, 'Editor', relative);
  const manifest = JSON.parse(await readFile(path.join(directory, 'package.json'), 'utf8'));
  output += `\n${'='.repeat(72)}\n${manifest.name} ${manifest.version}\nLicense: ${manifest.license ?? 'See below'}\n`;
  const names = await readdir(directory);
  for (const name of names.filter(name => /^(licen[cs]e|copying|notice|ofl)(\.|$)/i.test(name))) {
    try { output += '\n' + await readFile(path.join(directory, name), 'utf8') + '\n'; } catch {}
  }
}
await writeFile(path.join(root, 'Sources/App/Resources/ThirdPartyNotices.txt'), output);
