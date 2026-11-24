'use strict';
const FPS = 25;
const FRAME_MS = 1000 / FPS;              // 40 ms
const DAY_FRAMES = 24 * 3600 * FPS;

const $ = (id) => document.getElementById(id);
const pad = (n) => String(n).padStart(2, '0');

// ---------- Timecode engine (freerun) ----------
let offsetMs = 0;
try { offsetMs = Number(localStorage.getItem('tcOffsetMs')) || 0; } catch (_) {}

function msSinceMidnight() {
  const d = new Date();
  return ((d.getHours() * 60 + d.getMinutes()) * 60 + d.getSeconds()) * 1000 + d.getMilliseconds();
}
function currentFrames() {
  const f = Math.floor((msSinceMidnight() + offsetMs) / FRAME_MS);
  return ((f % DAY_FRAMES) + DAY_FRAMES) % DAY_FRAMES;
}
function framesToTc(f) {
  f = ((f % DAY_FRAMES) + DAY_FRAMES) % DAY_FRAMES;
  const ff = f % FPS, s = Math.floor(f / FPS);
  return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}:${pad(ff)}`;
}
// Accepts "HH:MM:SS:FF", "HH:MM:SS.FF", "HHMMSSFF", or shorter right-aligned digits.
function parseTc(str) {
  if (str == null) return null;
  str = String(str).trim();
  let parts;
  if (/^\d{1,8}$/.test(str)) {
    const d = str.padStart(8, '0');
    parts = [d.slice(0, 2), d.slice(2, 4), d.slice(4, 6), d.slice(6, 8)];
  } else {
    parts = str.split(/[:;.,\s]/).filter(Boolean);
    if (parts.length !== 4 || !parts.every((p) => /^\d{1,2}$/.test(p))) return null;
  }
  const [h, m, s, f] = parts.map(Number);
  if (h > 23 || m > 59 || s > 59 || f >= FPS) return null;
  return ((h * 60 + m) * 60 + s) * FPS + f;
}
function saveOffset() {
  try { localStorage.setItem('tcOffsetMs', String(offsetMs)); } catch (_) {}
  updateSyncLabel();
}
function setTcNow(frames) {
  offsetMs = frames * FRAME_MS - msSinceMidnight();
  // keep offset in a sane range (within one day)
  const day = 24 * 3600 * 1000;
  offsetMs = ((offsetMs % day) + day) % day;
  if (offsetMs > day / 2) offsetMs -= day;
  saveOffset();
}
function updateSyncLabel() {
  if (Math.abs(offsetMs) < 1) { $('syncMode').textContent = 'čas dňa'; return; }
  const sign = offsetMs < 0 ? '−' : '+';
  const absF = Math.round(Math.abs(offsetMs) / FRAME_MS);
  $('syncMode').textContent = `manuálna synchronizácia (${sign}${framesToTc(absF)})`;
}

let lastShown = '';
function tick() {
  const tc = framesToTc(currentFrames());
  if (tc !== lastShown) { $('tc').textContent = tc; lastShown = tc; }
  requestAnimationFrame(tick);
}

// ---------- Project state ----------
let entries = [];
let filePath = null;
let dirty = false;
let created = new Date().toISOString();
let nextId = 1;

function setDirty(v) {
  dirty = v;
  $('dirtyMark').classList.toggle('on', v);
  const name = projectName();
  document.title = (v ? '• ' : '') + name + ' — Timecode Logger';
}
function projectName() { return $('projectName').value.trim() || 'Bez názvu'; }
function status(msg) { $('status').textContent = msg; }
function safeFileName(s) { return s.replace(/[\/\\:*?"<>|]/g, '-').trim() || 'Projekt'; }

// ---------- Table ----------
function render(newId) {
  const tbody = $('rows');
  tbody.innerHTML = '';
  entries.forEach((e, i) => {
    const tr = document.createElement('tr');
    tr.dataset.id = e.id;
    if (e.id === newId) tr.classList.add('new');

    const tdN = document.createElement('td'); tdN.className = 'c-n'; tdN.textContent = i + 1;

    const tdTc = document.createElement('td'); tdTc.className = 'c-tc';
    const tcIn = document.createElement('input');
    tcIn.className = 'tcin'; tcIn.value = e.tc; tcIn.spellcheck = false; tcIn.maxLength = 11;
    tcIn.title = 'Kliknite pre úpravu timecodu';
    tcIn.addEventListener('input', () => tcIn.classList.toggle('bad', parseTc(tcIn.value) === null));
    tcIn.addEventListener('change', () => {
      const f = parseTc(tcIn.value);
      if (f === null) { tcIn.value = e.tc; tcIn.classList.remove('bad'); status('Neplatný timecode – ponechaná pôvodná hodnota.'); return; }
      const v = framesToTc(f);
      tcIn.value = v; tcIn.classList.remove('bad');
      if (v !== e.tc) { e.tc = v; setDirty(true); status(`Záznam ${i + 1}: timecode upravený na ${v}`); }
    });
    tcIn.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter') { tcIn.blur(); }
      if (ev.key === 'Escape') { tcIn.value = e.tc; tcIn.classList.remove('bad'); tcIn.blur(); }
    });
    tdTc.appendChild(tcIn);

    const tdNote = document.createElement('td'); tdNote.className = 'c-note';
    const noteIn = document.createElement('input');
    noteIn.className = 'note'; noteIn.value = e.note; noteIn.placeholder = 'Poznámka…';
    noteIn.addEventListener('input', () => { e.note = noteIn.value; setDirty(true); });
    noteIn.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === 'Escape') noteIn.blur();
    });
    tdNote.appendChild(noteIn);

    const tdAct = document.createElement('td'); tdAct.className = 'c-act';
    const del = document.createElement('button');
    del.className = 'del'; del.textContent = '✕'; del.title = 'Vymazať záznam';
    del.addEventListener('click', () => {
      entries = entries.filter((x) => x.id !== e.id);
      setDirty(true); render(); status(`Záznam ${e.tc} vymazaný.`);
    });
    tdAct.appendChild(del);

    tr.append(tdN, tdTc, tdNote, tdAct);
    tbody.appendChild(tr);
  });
  $('empty').style.display = entries.length ? 'none' : 'block';
  $('addZone').style.display = entries.length ? 'block' : 'none';
  $('count').textContent = `${entries.length} ${entries.length === 1 ? 'záznam' : (entries.length >= 2 && entries.length <= 4 ? 'záznamy' : 'záznamov')}`;
}

function logTc() {
  const tc = framesToTc(currentFrames());   // capture immediately
  const e = { id: nextId++, tc, note: '' };
  entries.push(e);
  setDirty(true);
  render(e.id);
  const btn = $('btnLog');
  btn.classList.remove('flash'); void btn.offsetWidth; btn.classList.add('flash');
  const row = document.querySelector(`tr[data-id="${e.id}"]`);
  if (row) {
    row.scrollIntoView({ block: 'nearest' });
    row.querySelector('input.note').focus();
  }
  status(`Zapísaný timecode ${tc}`);
}

// ---------- Project I/O ----------
function projectData() {
  return {
    app: 'TimecodeLogger', version: 1, fps: FPS,
    name: projectName(), created, modified: new Date().toISOString(),
    entries: entries.map(({ tc, note }) => ({ tc, note }))
  };
}
function buildTxt() {
  const now = new Date();
  const d = `${now.getDate()}.${now.getMonth() + 1}.${now.getFullYear()}`;
  const lines = [
    `Projekt: ${projectName()}`,
    `Export: ${d} ${pad(now.getHours())}:${pad(now.getMinutes())}`,
    `Timecode: PAL 25 fps`,
    `Počet záznamov: ${entries.length}`,
    '-'.repeat(60)
  ];
  entries.forEach((e, i) => lines.push(`${String(i + 1).padStart(3, '0')}  ${e.tc}  ${e.note}`));
  return lines.join('\n') + '\n';
}

async function save(saveAs = false, askExport = true) {
  document.activeElement && document.activeElement.blur(); // commit pending edits
  const r = await window.api.saveProject({ data: projectData(), filePath, saveAs, suggestedName: safeFileName(projectName()) });
  if (!r.ok) { status('Uloženie zrušené.'); return false; }
  filePath = r.filePath; setDirty(false);
  status('Uložené: ' + filePath);
  if (askExport && await window.api.askExport()) await exportTxt();
  return true;
}
async function exportTxt() {
  document.activeElement && document.activeElement.blur();
  const r = await window.api.exportTxt({ text: buildTxt(), suggestedName: safeFileName(projectName()) });
  if (r.ok) status('Exportované: ' + r.filePath);
}
async function confirmDiscard() {
  if (!dirty) return true;
  const r = await window.api.confirm({
    message: 'Projekt obsahuje neuložené zmeny.',
    detail: 'Chcete ich uložiť?',
    buttons: ['Uložiť', 'Neukladať', 'Zrušiť']
  });
  if (r === 2) return false;
  if (r === 0) return await save(false, false);
  return true;
}
async function newProject() {
  if (!(await confirmDiscard())) return;
  entries = []; filePath = null; created = new Date().toISOString();
  $('projectName').value = 'Nový projekt';
  render(); setDirty(false); status('Nový projekt.');
}
async function openProject() {
  if (!(await confirmDiscard())) return;
  const r = await window.api.openProject();
  if (!r.ok) return;
  const d = r.data || {};
  entries = (d.entries || []).map((e) => ({ id: nextId++, tc: framesToTc(parseTc(e.tc) ?? 0), note: e.note || '' }));
  $('projectName').value = d.name || 'Projekt';
  created = d.created || new Date().toISOString();
  filePath = r.filePath;
  render(); setDirty(false); status('Otvorené: ' + filePath);
}

// ---------- Set TC modal ----------
function openSetTc() {
  $('modal').classList.remove('hidden');
  const inp = $('setTcInput');
  inp.value = framesToTc(currentFrames());
  inp.classList.remove('bad');
  inp.focus(); inp.select();
}
function closeSetTc() { $('modal').classList.add('hidden'); }
function applySetTc() {
  const f = parseTc($('setTcInput').value);
  if (f === null) { $('setTcInput').classList.add('bad'); return; }
  setTcNow(f); closeSetTc(); status('Timecode nastavený na ' + framesToTc(f));
}

// ---------- Wiring ----------
function isTyping() {
  const a = document.activeElement;
  return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
}
function modalOpen() { return !$('modal').classList.contains('hidden'); }

document.addEventListener('keydown', (ev) => {
  if (modalOpen()) {
    if (ev.key === 'Escape') closeSetTc();
    if (ev.key === 'Enter') { ev.preventDefault(); applySetTc(); }
    return;
  }
  if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') { ev.preventDefault(); logTc(); return; }
  if (ev.code === 'Space' && !isTyping()) { ev.preventDefault(); logTc(); }
});

// buttons shouldn't keep focus (so Space never re-clicks them)
document.addEventListener('mouseup', () => {
  const a = document.activeElement;
  if (a && a.tagName === 'BUTTON') a.blur();
});

$('btnLog').addEventListener('click', logTc);
$('addZone').addEventListener('click', logTc);
$('empty').addEventListener('click', logTc);
$('btnNew').addEventListener('click', newProject);
$('btnOpen').addEventListener('click', openProject);
$('btnSave').addEventListener('click', () => save(false));
$('btnExport').addEventListener('click', exportTxt);
$('btnSetTc').addEventListener('click', openSetTc);
$('btnTod').addEventListener('click', () => { offsetMs = 0; saveOffset(); status('Synchronizované na systémový čas dňa.'); });
$('btnZero').addEventListener('click', () => { setTcNow(0); status('Timecode beží od 00:00:00:00.'); });
$('setTcOk').addEventListener('click', applySetTc);
$('setTcCancel').addEventListener('click', closeSetTc);
$('setTcInput').addEventListener('input', (e) => e.target.classList.toggle('bad', parseTc(e.target.value) === null));
$('modal').addEventListener('mousedown', (e) => { if (e.target.id === 'modal') closeSetTc(); });
$('projectName').addEventListener('input', () => setDirty(true));
$('projectName').addEventListener('keydown', (e) => { if (e.key === 'Enter') e.target.blur(); });
document.querySelectorAll('[data-nudge]').forEach((b) => b.addEventListener('click', () => {
  offsetMs += Number(b.dataset.nudge) * 1000; saveOffset();
}));
document.querySelectorAll('[data-nudge-f]').forEach((b) => b.addEventListener('click', () => {
  offsetMs += Number(b.dataset.nudgeF) * FRAME_MS; saveOffset();
}));

window.api.onMenu((cmd) => {
  if (modalOpen() && cmd !== 'setTc') return;
  ({
    new: newProject, open: openProject, save: () => save(false), saveAs: () => save(true),
    export: exportTxt, log: logTc, setTc: openSetTc,
    tod: () => { offsetMs = 0; saveOffset(); status('Synchronizované na systémový čas dňa.'); }
  }[cmd] || (() => {}))();
});

window.__isDirty = () => dirty;
window.__saveForClose = () => save(false, false);

updateSyncLabel();
render();
setDirty(false);
requestAnimationFrame(tick);
