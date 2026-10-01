'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const { execFile } = require('node:child_process');

async function openResource(resource, applicationPath, runtime = {}) {
  if ((runtime.platform ?? process.platform) !== 'darwin') throw new Error('macOS is required.');
  if (!resource || resource.scheme !== 'file' || resource.authority) {
    throw new Error('Select a local file or folder. Remote and virtual resources are not supported.');
  }
  const filePath = resource.fsPath;
  if (typeof filePath !== 'string' || !path.isAbsolute(filePath) || filePath.includes('\0')) {
    throw new Error('An absolute local path is required.');
  }
  if (typeof applicationPath !== 'string' || !path.isAbsolute(applicationPath) || !applicationPath.endsWith('.app')) {
    throw new Error('Set an absolute MyMacFinder .app path in Settings.');
  }
  const stat = runtime.stat ?? fs.stat;
  let targetStatus;
  try { targetStatus = await stat(filePath); } catch (error) {
    throw new Error(error.code === 'ENOENT' ? `Path does not exist: ${filePath}` : `Cannot access path: ${filePath} (${error.code})`);
  }
  try { await stat(path.join(applicationPath, 'Contents/MacOS/MyMacFinder')); } catch {
    throw new Error(`Install MyMacFinder first or update its application path: ${applicationPath}`);
  }
  const url = `mymacfinder://open?path=${encodeURIComponent(filePath)}`;
  const folderPath = targetStatus.isDirectory() ? filePath : path.dirname(filePath);
  await new Promise((resolve, reject) => {
    // execFile uses separate arguments and never evaluates shell syntax in filenames.
    // Passing the folder as a native file URL also conveys the user's folder-open intent to macOS.
    // The reveal URL comes last so the app's ordered receiver finishes with the requested selection.
    (runtime.execFile ?? execFile)('/usr/bin/open', ['-a', applicationPath, folderPath, url], { timeout: 10000 }, (error) => {
      if (error) reject(new Error(`Could not open MyMacFinder: ${error.message}`));
      else resolve();
    });
  });
}

module.exports = { openResource };
