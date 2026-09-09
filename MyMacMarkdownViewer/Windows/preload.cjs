const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('desktop', Object.freeze({
  invoke: (action, payload = {}) => ipcRenderer.invoke('desktop', action, payload),
  onEvent: callback => {
    const listener = (_event, message) => callback(message);
    ipcRenderer.on('desktop-event', listener);
    return () => ipcRenderer.removeListener('desktop-event', listener);
  },
}));
