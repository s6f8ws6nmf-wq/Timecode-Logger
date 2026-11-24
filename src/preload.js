const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('api', {
  saveProject: (args) => ipcRenderer.invoke('save-project', args),
  openProject: () => ipcRenderer.invoke('open-project'),
  askExport: () => ipcRenderer.invoke('ask-export'),
  exportTxt: (args) => ipcRenderer.invoke('export-txt', args),
  confirm: (args) => ipcRenderer.invoke('confirm', args),
  onMenu: (cb) => ipcRenderer.on('menu', (_e, cmd) => cb(cmd))
});
