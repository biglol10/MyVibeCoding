import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, readFile, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { applyChanges, applyPlan, create, decode, encode, hash, listTree, move, preview, scan, Store, validateName, validateWithin } from '../core.mjs';

async function temp() { return mkdtemp(path.join(os.tmpdir(), 'mymarkdown-core-')); }
async function use(fn) { const root = await temp(); try { await fn(root); } finally { await rm(root, { recursive: true, force: true }); } }
async function rejectsCode(promise, code) { await assert.rejects(promise, error => error.code === code); }

test('UTF-8 BOM and unchanged mixed endings retain original bytes', () => use(async root => {
  const bytes = Buffer.from([0xef, 0xbb, 0xbf, ...Buffer.from('one\r\ntwo\nthree\r')]); const codec = decode(bytes);
  assert.equal(codec.originalText, 'one\ntwo\nthree\n'); assert.deepEqual(encode(codec.originalText, codec), bytes);
  assert.equal(encode('one\nchanged\nthree\n', codec).toString(), '\ufeffone\r\nchanged\r\nthree\r');
  assert.throws(() => decode(Buffer.from([0xff])), error => error.code === 'unsupportedEncoding');
}));
test('UTF-16 changes are ordered, non-overlapping, and do not split a surrogate pair', () => {
  assert.equal(applyChanges('a😀b', [{ from: 1, to: 3, insert: 'X' }]), 'aXb');
  assert.throws(() => applyChanges('a😀b', [{ from: 2, to: 3, insert: '' }]), error => error.code === 'invalidChange');
  assert.throws(() => applyChanges('abcd', [{ from: 2, to: 3, insert: '' }, { from: 1, to: 2, insert: '' }]), error => error.code === 'invalidChange');
  assert.throws(() => applyChanges('abcd', [{ from: 1, to: 2, insert: 3 }]), error => error.code === 'invalidChange');
});
test('large documents encode without quadratic line-table allocation', () => {
  const source = Array.from({ length: 20000 }, (_, index) => `line ${index}`).join('\n'); const codec = decode(Buffer.from(source)); const began = performance.now();
  const output = encode(source.replace('line 10000', 'changed'), codec);
  assert.ok(performance.now() - began < 2000); assert.ok(output.toString().includes('changed'));
});
test('store refuses stale writes and does not recreate deleted files', () => use(async root => {
  const file = path.join(root, 'a.md'), store = new Store(path.join(root, 'data')); await writeFile(file, 'one'); const disk = await store.read(file);
  await writeFile(file, 'other'); await rejectsCode(store.save(file, 'edit', disk.codec, disk.hash), 'conflict');
  await unlink(file); await rejectsCode(store.save(file, 'edit', disk.codec, disk.hash), 'deleted'); assert.equal(await readFile(file).catch(() => null), null);
}));
test('file signatures change for an external edit without reading document content', () => use(async root => {
  const file = path.join(root, 'a.md'), store = new Store(path.join(root, 'data'));
  await writeFile(file, 'one');
  const before = await store.signature(file);
  await new Promise(resolve => setTimeout(resolve, 5));
  await writeFile(file, 'longer external edit');
  assert.notEqual(await store.signature(file), before);
}));
test('Windows names and unsafe paths are rejected', async () => {
  for (const name of ['CON', 'com1.txt', 'x:stream', 'x.', 'x ', 'a/b', 'bad<name', 'bad|name', 'bad?name', '']) assert.throws(() => validateName(name), error => error.code === 'invalidName');
  await use(async root => { const outside = path.dirname(root); await rejectsCode(validateWithin(root, outside), 'unsafePath'); await mkdir(path.join(root, 'real')); await symlink(outside, path.join(root, 'link')); await rejectsCode(validateWithin(root, path.join(root, 'link', 'x'), { allowMissing: true }), 'unsafePath'); });
});
test('create and move use case-insensitive collision checks and protect workspace root', () => use(async root => {
  await create(root, root, 'Draft.md', false); await rejectsCode(create(root, root, 'draft.md', false), 'alreadyExists');
  await rejectsCode(move(root, root, path.join(root, 'other')), 'rootProtected'); await mkdir(path.join(root, 'folder'));
  await rejectsCode(move(root, path.join(root, 'folder'), path.join(root, 'folder', 'nested')), 'invalidMove');
  assert.equal(await move(root, path.join(root, 'Draft.md'), path.join(root, 'DRAFT.md')), path.join(root, 'DRAFT.md'));
}));
test('create-only saves cannot overwrite a concurrently created path', () => use(async root => {
  const file = path.join(root, 'new.md'), codec = decode(Buffer.alloc(0)), store = new Store(path.join(root, 'data'));
  const results = await Promise.allSettled([store.save(file, 'first', codec, null), store.save(file, 'second', codec, null)]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1); assert.equal(results.filter(result => result.status === 'rejected' && result.reason.code === 'conflict').length, 1);
}));
test('scan reports UTF-16 matches, partial limits, and replacement preflight', () => use(async root => {
  const a = path.join(root, 'a.md'), b = path.join(root, 'b.md'); await writeFile(a, '😀 needle\nneedle'); await writeFile(b, 'needle');
  const report = await scan(root, { query: 'needle', limit: 2 }); assert.equal(report.truncated, true); assert.deepEqual(report.files[0].matches[0].from, 3);
  assert.equal(preview(report.files[0], 'X').includes('X'), true); const plan = await scan(root, { query: 'needle' }); await writeFile(b, 'changed'); const applied = await applyPlan(plan.files, 'X', null, root); assert.equal(applied.savedCount, 0); assert.equal(applied.outcomes.find(o => o.path === a).status, 'notAttempted');
}));
test('scan bounds oversized files, retained source, and stops once the result limit is reached', () => use(async root => {
  await writeFile(path.join(root, 'large.md'), 'needle '.repeat(20));
  await writeFile(path.join(root, 'one.md'), 'needle');
  await writeFile(path.join(root, 'two.md'), 'needle');
  const oversized = await scan(root, { query: 'needle', maxFileBytes: 16 });
  assert.ok(oversized.issues.some(issue => issue.path.endsWith('large.md')));
  const retained = await scan(root, { query: 'needle', maxFileBytes: 1024, maxRetainedBytes: 5 });
  assert.equal(retained.truncated, true);
  assert.equal(retained.complete, false);
  const limited = await scan(root, { query: 'needle', limit: 1, maxFileBytes: 1024, maxRetainedBytes: 1024 });
  assert.equal(limited.files.reduce((sum, file) => sum + file.matches.length, 0), 1);
  assert.equal(limited.truncated, true);
  assert.equal(limited.cancelled, false);
}));
test('case-insensitive match offsets stay in the source UTF-16 coordinate space', () => use(async root => {
  const file = path.join(root, 'unicode.md'); await writeFile(file, 'İx\nx'); const report = await scan(root, { query: 'x' });
  assert.deepEqual(report.files[0].matches.map(match => match.from), [1, 3]);
}));
test('recovery records and bounded tree work', () => use(async root => {
  const store = new Store(path.join(root, 'data')); await store.writeRecovery({ id: 'abc_1', path: '/x', text: 'draft', codec: decode(Buffer.from('draft')), revision: 2, date: '2026-01-01T00:00:00.000Z' }); assert.equal((await store.recoveries())[0].text, 'draft'); await store.removeRecovery('abc_1'); assert.equal((await store.recoveries()).length, 0);
  await writeFile(path.join(root, '.hidden.md'), 'x'); await mkdir(path.join(root, 'nested')); await mkdir(path.join(root, 'nested', 'deeper')); await writeFile(path.join(root, 'nested', 'x.md'), 'x'); await writeFile(path.join(root, 'nested', 'notes.txt'), 'x'); const tree = await listTree(root); assert.equal(tree.some(e => e.name === '.hidden.md'), false); assert.equal(tree.some(e => e.name === 'nested' && e.directory), true); assert.equal(tree.some(e => e.name === 'deeper' && e.directory), true); assert.equal(tree.some(e => e.name === 'x.md'), true); assert.equal(tree.some(e => e.name === 'notes.txt'), false);
}));

test('exact result limit stays complete until another match is found', () => use(async root => {
  await writeFile(path.join(root,'one.md'),'needle');
  assert.equal((await scan(root,{query:'needle',limit:1})).complete,true);
  await writeFile(path.join(root,'two.md'),'needle');
  const report=await scan(root,{query:'needle',limit:1});
  assert.equal(report.truncated,true);assert.equal(report.cancelled,false);
}));
