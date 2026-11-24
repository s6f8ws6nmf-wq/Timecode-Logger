const { app, BrowserWindow, ipcMain, dialog, Menu } = require('electron');
const path = require('path');
const fs = require('fs');

let win = null;
let forceClose = false;

function send(cmd) { if (win) win.webContents.send('menu', cmd); }

function buildMenu() {
  const isMac = process.platform === 'darwin';
  const template = [
    ...(isMac ? [{ role: 'appMenu', label: app.name }] : []),
    {
      label: 'Súbor',
      submenu: [
        { label: 'Nový projekt', accelerator: 'CmdOrCtrl+N', click: () => send('new') },
        { label: 'Otvoriť projekt…', accelerator: 'CmdOrCtrl+O', click: () => send('open') },
        { type: 'separator' },
        { label: 'Uložiť projekt', accelerator: 'CmdOrCtrl+S', click: () => send('save') },
        { label: 'Uložiť projekt ako…', accelerator: 'CmdOrCtrl+Shift+S', click: () => send('saveAs') },
        { type: 'separator' },
        { label: 'Exportovať poznámky (TXT)…', accelerator: 'CmdOrCtrl+E', click: () => send('export') },
        {
          label: 'Exportovať markery',
          submenu: [
            { label: 'Avid Media Composer (.txt)…', accelerator: 'CmdOrCtrl+Shift+E', click: () => send('exportAvid') },
            { label: 'Adobe Premiere Pro (.xml)…', accelerator: 'CmdOrCtrl+Shift+P', click: () => send('exportPremiere') },
            { label: 'DaVinci Resolve (.edl)…', accelerator: 'CmdOrCtrl+Shift+R', click: () => send('exportResolve') }
          ]
        },
        ...(isMac ? [] : [{ type: 'separator' }, { role: 'quit', label: 'Koniec' }])
      ]
    },
    { role: 'editMenu', label: 'Upraviť' },
    {
      label: 'Timecode',
      submenu: [
        { label: 'Zapísať timecode', accelerator: 'CmdOrCtrl+Enter', click: () => send('log') },
        { label: 'Nastaviť timecode…', accelerator: 'CmdOrCtrl+T', click: () => send('setTc') },
        { type: 'separator' },
        { label: 'Synchronizovať na čas dňa', click: () => send('tod') }
      ]
    },
    { role: 'windowMenu', label: 'Okno' }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  win = new BrowserWindow({
    width: 1000,
    height: 840,
    minWidth: 720,
    minHeight: 600,
    title: 'Timecode Logger',
    backgroundColor: '#111317',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.loadFile(path.join(__dirname, 'index.html'));

  win.on('close', async (e) => {
    if (forceClose) return;
    e.preventDefault();
    const dirty = await win.webContents.executeJavaScript('window.__isDirty && window.__isDirty()').catch(() => false);
    if (!dirty) { forceClose = true; win.close(); return; }
    const r = await dialog.showMessageBox(win, {
      type: 'warning',
      buttons: ['Uložiť', 'Neukladať', 'Zrušiť'],
      defaultId: 0, cancelId: 2,
      message: 'Projekt obsahuje neuložené zmeny.',
      detail: 'Chcete ich pred zatvorením uložiť?'
    });
    if (r.response === 2) return;
    if (r.response === 0) {
      const ok = await win.webContents.executeJavaScript('window.__saveForClose()').catch(() => false);
      if (!ok) return;
    }
    forceClose = true;
    win.close();
  });
  win.on('closed', () => { win = null; forceClose = false; });
}

// ---- IPC ----
ipcMain.handle('save-project', async (_e, { data, filePath, saveAs, suggestedName }) => {
  let target = filePath;
  if (!target || saveAs) {
    const r = await dialog.showSaveDialog(win, {
      title: 'Uložiť projekt',
      defaultPath: (suggestedName || 'Projekt') + '.tclog',
      filters: [{ name: 'Timecode Logger projekt', extensions: ['tclog'] }]
    });
    if (r.canceled || !r.filePath) return { ok: false };
    target = r.filePath;
  }
  fs.writeFileSync(target, JSON.stringify(data, null, 2), 'utf8');
  return { ok: true, filePath: target };
});

ipcMain.handle('open-project', async () => {
  const r = await dialog.showOpenDialog(win, {
    title: 'Otvoriť projekt',
    properties: ['openFile'],
    filters: [{ name: 'Timecode Logger projekt', extensions: ['tclog', 'json'] }]
  });
  if (r.canceled || !r.filePaths.length) return { ok: false };
  try {
    const data = JSON.parse(fs.readFileSync(r.filePaths[0], 'utf8'));
    return { ok: true, data, filePath: r.filePaths[0] };
  } catch (err) {
    dialog.showErrorBox('Chyba', 'Súbor sa nepodarilo načítať:\n' + err.message);
    return { ok: false };
  }
});

ipcMain.handle('ask-export', async () => {
  const r = await dialog.showMessageBox(win, {
    type: 'info',
    buttons: ['Poznámky (TXT)', 'Avid Media Composer', 'Adobe Premiere Pro', 'DaVinci Resolve', 'Neexportovať'],
    defaultId: 0, cancelId: 4,
    message: 'Projekt bol uložený.',
    detail: 'Chcete vyexportovať poznámky (.txt) alebo markery pre strižňu?'
  });
  return ['txt', 'avid', 'premiere', 'resolve', null][r.response];
});

// native drop-down menu under the "Export markerov" button
ipcMain.handle('marker-menu', (_e, { x, y }) => new Promise((resolve) => {
  let picked = null;
  const m = Menu.buildFromTemplate([
    { label: 'Poznámky – textový súbor (.txt)', click: () => { picked = 'txt'; } },
    { type: 'separator' },
    { label: 'Markery: Avid Media Composer (.txt)', click: () => { picked = 'avid'; } },
    { label: 'Markery: Adobe Premiere Pro (.xml)', click: () => { picked = 'premiere'; } },
    { label: 'Markery: DaVinci Resolve (.edl)', click: () => { picked = 'resolve'; } }
  ]);
  m.popup({ window: win, x: Math.round(x), y: Math.round(y), callback: () => setTimeout(() => resolve(picked), 0) });
}));

ipcMain.handle('export-txt', async (_e, { text, suggestedName, title, ext, filterName }) => {
  ext = ext || 'txt';
  const r = await dialog.showSaveDialog(win, {
    title: title || 'Exportovať poznámky',
    defaultPath: (suggestedName || 'Poznamky') + '.' + ext,
    filters: [{ name: filterName || 'Textový súbor', extensions: [ext] }]
  });
  if (r.canceled || !r.filePath) return { ok: false };
  fs.writeFileSync(r.filePath, text, 'utf8');
  return { ok: true, filePath: r.filePath };
});

ipcMain.handle('confirm', async (_e, { message, detail, buttons }) => {
  const r = await dialog.showMessageBox(win, {
    type: 'question', buttons: buttons || ['OK', 'Zrušiť'],
    defaultId: 0, cancelId: (buttons || [1, 1]).length - 1, message, detail
  });
  return r.response;
});

app.whenReady().then(() => {
  app.setName('Timecode Logger');
  buildMenu();
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => { app.quit(); });
