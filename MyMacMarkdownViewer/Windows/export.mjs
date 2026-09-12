import { BrowserWindow } from 'electron';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// A complete, inert document is printed; the virtualized editing view is never captured.
export async function outputDocument(html, format, parent) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'mymarkdown-output-'));
  let window;
  try {
    const file = path.join(directory, 'document.html');
    await fs.writeFile(file, html, { mode: 0o600 });
    window = new BrowserWindow({ show: false, parent, width: 900, height: 900,
      webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false, javascript: false } });
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    window.webContents.on('will-navigate', event => event.preventDefault());
    await window.loadFile(file);
    if (format === 'pdf') return await window.webContents.printToPDF({
      printBackground: true, pageSize: 'A4', preferCSSPageSize: true,
      margins: { top: 0.5, bottom: 0.5, left: 0.5, right: 0.5 },
    });
    await new Promise((resolve, reject) => window.webContents.print({ silent: false, printBackground: true },
      (success, reason) => success || /cancel/i.test(reason) ? resolve() : reject(new Error(reason || '인쇄하지 못했습니다.'))));
    return null;
  } finally {
    if (window && !window.isDestroyed()) window.destroy();
    await fs.rm(directory, { recursive: true, force: true });
  }
}
