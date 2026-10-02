'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { openResource } = require('../launcher');

test('real local file with Unicode, spaces, %, +, # and shell syntax is passed as one encoded argument', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'paneharbor-extension-'));
  try {
    const file = path.join(root, '한글 공백 % + # & $(touch nope).txt');
    await fs.writeFile(file, 'fixture');
    const app = path.join(root, 'PaneHarbor.app');
    await fs.mkdir(path.join(app, 'Contents/MacOS'), { recursive: true });
    await fs.writeFile(path.join(app, 'Contents/MacOS/PaneHarbor'), 'fixture');
    let invocation;
    await openResource({ scheme: 'file', authority: '', fsPath: file }, app, {
      platform: 'darwin',
      execFile(command, args, options, callback) { invocation = { command, args, options }; callback(null); }
    });
    assert.equal(invocation.command, '/usr/bin/open');
    assert.deepEqual(invocation.args.slice(0, 3), ['-a', app, root]);
    assert.equal(decodeURIComponent(invocation.args[3].split('?path=')[1]), file);
    assert.equal(invocation.options.shell, undefined);
    await assert.rejects(fs.stat(path.join(root, 'nope')));
  } finally { await fs.rm(root, { recursive: true, force: true }); }
});

test('missing paths fail before launch', async () => {
  let launched = false;
  await assert.rejects(openResource({ scheme: 'file', fsPath: '/missing/한글 공백.txt' }, '/Applications/PaneHarbor.app', {
    platform: 'darwin', stat: async () => { throw Object.assign(new Error(), { code: 'ENOENT' }); },
    execFile() { launched = true; }
  }), /Path does not exist/);
  assert.equal(launched, false);
});

test('remote, virtual, absent targets and non-macOS are rejected', async () => {
  for (const target of [null, { scheme: 'vscode-remote', fsPath: '/tmp/test' }, { scheme: 'file', authority: 'server', fsPath: '/tmp/test' }]) {
    await assert.rejects(openResource(target, '/Applications/PaneHarbor.app', { platform: 'darwin' }), /local file/);
  }
  await assert.rejects(openResource({ scheme: 'file', fsPath: '/tmp/test' }, '/Applications/PaneHarbor.app', { platform: 'win32' }), /macOS/);
});

test('launch errors propagate and bundle paths cannot be shell commands', async () => {
  const target = { scheme: 'file', fsPath: '/tmp/test' };
  await assert.rejects(openResource(target, 'open whatever', { platform: 'darwin' }), /absolute/);
  await assert.rejects(openResource(target, '/Applications/PaneHarbor.app', {
    platform: 'darwin', stat: async () => ({ isDirectory: () => false }),
    execFile(command, args, options, callback) { callback(new Error('launch failed')); }
  }), /launch failed/);
});
