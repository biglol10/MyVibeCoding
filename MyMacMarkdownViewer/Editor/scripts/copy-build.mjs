import { access, cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const source = new URL('../dist/', import.meta.url);
const destination = new URL('../../Sources/App/Resources/Editor/', import.meta.url);
await access(new URL('index.html', source));
// This directory contains only generated, ignored web resources. Remove obsolete hashed bundles.
await rm(fileURLToPath(destination), { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(fileURLToPath(source), fileURLToPath(destination), { recursive: true });
await writeFile(new URL('.gitkeep', destination), '');
