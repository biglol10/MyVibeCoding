// Runs inside the isolated, unprivileged editor frame before the editor module.
window.webkit = { messageHandlers: { editor: { postMessage(message) {
  window.parent.postMessage({ kind: 'editor-event', message }, 'app://host');
} } } };
window.addEventListener('message', async event => {
  if (event.source !== window.parent || event.origin !== 'app://host') return;
  const data = event.data;
  if (data?.kind === 'host-receive') window.MarkdownHost?.receive(data.message);
  if (data?.kind === 'host-request') {
    const allowed = ['snapshot', 'prepareSaveAs', 'rebaseMoved', 'focus'];
    try {
      if (!allowed.includes(data.method) || !window.MarkdownHost) throw Error('편집기가 준비되지 않았습니다.');
      const result = await window.MarkdownHost[data.method](...(data.args || []));
      window.parent.postMessage({ kind: 'host-result', requestID: data.requestID, result }, 'app://host');
    } catch (error) {
      window.parent.postMessage({ kind: 'host-result', requestID: data.requestID, error: String(error.message) }, 'app://host');
    }
  }
});
