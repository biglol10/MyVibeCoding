import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readingPosition, lastSession, documentArgument } from '../session.mjs';

test('stored reading positions clamp invalid numbers and shortened documents', () => {
  assert.deepEqual(readingPosition({anchor: 200, head: -4, scrollTop: Infinity}, 50), {anchor:50, head:0, scrollTop:0});
  assert.deepEqual(readingPosition({anchor: 7, scrollTop:1240.5}), {anchor:7,head:7,scrollTop:1240.5});
  assert.deepEqual(readingPosition(null), {anchor:0,head:0,scrollTop:0});
});
test('legacy settings and invalid session fields keep the welcome fallback', () => {
  assert.deepEqual(lastSession({root:'/tmp'}), {documentPath:null,position:{anchor:0,head:0,scrollTop:0},blank:false});
  assert.equal(lastSession({session:{documentPath:4,blank:'yes'}}).documentPath,null);
  assert.equal(lastSession({session:{blank:true}}).blank,true);
});
test('explicit file launch does not mistake QA option values or app paths for documents', () => {
  const file=path.resolve('example.MARKDOWN');
  assert.equal(documentArgument(['electron','/app','--qa-data',path.resolve('qa.md')]),null);
  assert.equal(documentArgument(['electron','/app','--qa-data','/tmp/qa',file]),file);
  assert.equal(documentArgument(['electron','/app','--open','example.MARKDOWN']),file);
});
