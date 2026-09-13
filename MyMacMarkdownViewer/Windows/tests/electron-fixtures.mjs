// Check current state as well as future events: navigation can finish between
// a frame lookup and subscribing to framenavigated during Electron startup.
export async function editorFrame(page) {
  for (let attempt = 0; attempt < 240; attempt += 1) {
    const frame = page.frames().find(value => value.url() === 'app://editor/index.html');
    if (frame) {
      await frame.waitForFunction(() => window.MarkdownHost?.snapshot);
      return frame;
    }
    await page.waitForTimeout(250);
  }
  const state = { url: page.url(), frames: page.frames().map(frame => frame.url()) };
  throw Error(`Editor frame did not load within 60 seconds: ${JSON.stringify(state)}`);
}

export async function closeElectron(app) {
  let owned;
  try { owned = app.process(); }
  catch { return; } // A restart test may already have closed this application.
  const bounded = async promise => {
    let timer;
    try {
      return await Promise.race([
        promise.then(() => true, () => true),
        new Promise(resolve => { timer = setTimeout(() => resolve(false), 2000); }),
      ]);
    } finally { clearTimeout(timer); }
  };
  await bounded(app.evaluate(({ app: electronApp }) => electronApp.exit(0)));
  if (!await bounded(app.close())) {
    console.error('[qa] Playwright close timed out; cleaning up owned Electron process', owned?.pid);
    owned?.kill('SIGKILL');
  }
  // Closing the automation connection can finish before the OS reaps the
  // process. Wait for this owned child, not a process-name-wide shutdown.
  const waitForExit = () => !owned || owned.exitCode !== null || owned.signalCode !== null
    ? Promise.resolve()
    : new Promise(resolve => owned.once('exit', resolve));
  if (!await bounded(waitForExit())) {
    owned?.kill('SIGKILL');
    if (!await bounded(waitForExit())) throw new Error(`QA Electron process ${owned?.pid} did not exit`);
  }
}
