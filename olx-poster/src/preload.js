const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('api', {
  state: () => ipcRenderer.invoke('state'),
  onState: (fn) => ipcRenderer.on('state', (_e, s) => fn(s)),
  onLog: (fn) => ipcRenderer.on('log', (_e, line) => fn(line)),
  saveSettings: (patch) => ipcRenderer.invoke('settings:save', patch),
  setKey: (key) => ipcRenderer.invoke('key:set', key),
  run: (on) => ipcRenderer.invoke('run', on),
  stopCurrent: () => ipcRenderer.invoke('stop-current'),
  postNow: (id) => ipcRenderer.invoke('item:post-now', id),
  redescribe: (id) => ipcRenderer.invoke('item:redescribe', id),
  retry: (id) => ipcRenderer.invoke('item:retry', id),
  remove: (id) => ipcRenderer.invoke('item:remove', id),
  edit: (id, patch) => ipcRenderer.invoke('item:edit', id, patch),
  addFiles: (files) => ipcRenderer.invoke('items:add', [...files].map((f) => webUtils.getPathForFile(f))),
  chooseInbox: () => ipcRenderer.invoke('inbox:choose'),
  openInbox: () => ipcRenderer.invoke('inbox:open'),
  openOlx: (url) => ipcRenderer.invoke('olx:open', url),
  olxLogin: () => ipcRenderer.invoke('olx:login'),
  olxLogout: () => ipcRenderer.invoke('olx:logout'),
  olxCheck: () => ipcRenderer.invoke('olx:check'),
  readNotes: () => ipcRenderer.invoke('notes:read'),
});
