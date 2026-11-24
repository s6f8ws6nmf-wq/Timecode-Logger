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

// ---------- Quick label buttons ----------
const DEFAULT_LABELS = ['PTZ', 'CAM A', 'CAM B', 'CAM C', 'CAM D', 'IBA ZVUK'];
let labels = DEFAULT_LABELS.slice();
try {
  const saved = JSON.parse(localStorage.getItem('quickLabels') || 'null');
  if (Array.isArray(saved) && saved.every((x) => typeof x === 'string')) labels = saved;
} catch (_) {}
let editQuick = false;
function saveLabels() { try { localStorage.setItem('quickLabels', JSON.stringify(labels)); } catch (_) {} }

function renderQuick() {
  const box = $('quick');
  box.innerHTML = '';
  box.classList.toggle('editing', editQuick);
  labels.forEach((lab, i) => {
    if (editQuick) {
      const wrap = document.createElement('div'); wrap.className = 'qedit';
      const inp = document.createElement('input');
      inp.value = lab; inp.maxLength = 24; inp.spellcheck = false;
      inp.addEventListener('input', () => { labels[i] = inp.value; saveLabels(); });
      inp.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') inp.blur(); });
      const del = document.createElement('button');
      del.className = 'qdel'; del.textContent = '✕'; del.title = 'Odstrániť tlačidlo';
      del.addEventListener('click', () => { labels.splice(i, 1); saveLabels(); renderQuick(); });
      wrap.append(inp, del);
      box.appendChild(wrap);
    } else {
      const b = document.createElement('button');
      b.className = 'qbtn';
      b.innerHTML = '';
      const t = document.createElement('span'); t.textContent = lab || '(bez názvu)';
      b.appendChild(t);
      if (i < 9) { const k = document.createElement('kbd'); k.textContent = i + 1; b.appendChild(k); }
      b.title = `Zapísať TC so štítkom „${lab}“` + (i < 9 ? ` (kláves ${i + 1})` : '');
      b.addEventListener('click', () => logTc(lab, b));
      box.appendChild(b);
    }
  });
  if (editQuick) {
    const add = document.createElement('button'); add.className = 'qadd'; add.textContent = '+ Pridať';
    add.addEventListener('click', () => {
      labels.push('NOVÉ'); saveLabels(); renderQuick();
      const ins = box.querySelectorAll('.qedit input'); const last = ins[ins.length - 1];
      if (last) { last.focus(); last.select(); }
    });
    const reset = document.createElement('button'); reset.className = 'qadd'; reset.textContent = 'Predvolené';
    reset.title = 'Obnoviť PTZ, CAM A–D, IBA ZVUK';
    reset.addEventListener('click', () => { labels = DEFAULT_LABELS.slice(); saveLabels(); renderQuick(); });
    box.append(add, reset);
  }
  $('btnEditQuick').textContent = editQuick ? 'Hotovo' : 'Upraviť tlačidlá';
  $('btnEditQuick').classList.toggle('primary', editQuick);
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
function sequenceName() { return $('sequenceName').value.trim(); }
function shootDay() { return $('shootDay').value.trim(); }
// File name for saving/exports: SEKVENCIA_VYROBNYDEN_PROJEKT (empty parts are skipped)
function exportBase() {
  const parts = [sequenceName(), shootDay(), $('projectName').value.trim()]
    .map((p) => p.replace(/[\/\\:*?"<>|]/g, '-').trim()).filter(Boolean);
  return parts.length ? parts.join('_') : 'Projekt';
}

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

    const tdLab = document.createElement('td'); tdLab.className = 'c-lab';
    const labIn = document.createElement('input');
    labIn.className = 'labin'; labIn.value = e.label || ''; labIn.placeholder = '—'; labIn.spellcheck = false;
    labIn.setAttribute('list', 'labelList');
    labIn.addEventListener('input', () => { e.label = labIn.value; setDirty(true); });
    labIn.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' || ev.key === 'Escape') labIn.blur(); });
    tdLab.appendChild(labIn);

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

    tr.append(tdN, tdTc, tdLab, tdNote, tdAct);
    tbody.appendChild(tr);
  });
  $('empty').style.display = entries.length ? 'none' : 'block';
  $('addZone').style.display = entries.length ? 'block' : 'none';
  $('count').textContent = `${entries.length} ${entries.length === 1 ? 'záznam' : (entries.length >= 2 && entries.length <= 4 ? 'záznamy' : 'záznamov')}`;
}

function logTc(label, srcBtn) {
  const tc = framesToTc(currentFrames());   // capture immediately
  if (typeof label !== 'string') label = '';
  const e = { id: nextId++, tc, label, note: '' };
  entries.push(e);
  setDirty(true);
  render(e.id);
  const btn = srcBtn || $('btnLog');
  btn.classList.remove('flash'); void btn.offsetWidth; btn.classList.add('flash');
  const row = document.querySelector(`tr[data-id="${e.id}"]`);
  if (row) {
    row.scrollIntoView({ block: 'nearest' });
    row.querySelector('input.note').focus();
  }
  status(`Zapísaný timecode ${tc}` + (label ? ` · ${label}` : ''));
}

// ---------- Project I/O ----------
function projectData() {
  return {
    app: 'TimecodeLogger', version: 1, fps: FPS,
    name: projectName(), sequence: sequenceName(), shootDay: shootDay(), created, modified: new Date().toISOString(),
    entries: entries.map(({ tc, label, note }) => ({ tc, label: label || '', note }))
  };
}
function buildTxt() {
  const now = new Date();
  const d = `${now.getDate()}.${now.getMonth() + 1}.${now.getFullYear()}`;
  const lines = [
    `Projekt: ${projectName()}`,
    ...(sequenceName() ? [`Sekvencia: ${sequenceName()}`] : []),
    ...(shootDay() ? [`Výrobný deň: ${shootDay()}`] : []),
    `Export: ${d} ${pad(now.getHours())}:${pad(now.getMinutes())}`,
    `Timecode: PAL 25 fps`,
    `Počet záznamov: ${entries.length}`,
    '-'.repeat(60)
  ];
  const w = Math.max(0, ...entries.map((e) => (e.label || '').length));
  entries.forEach((e, i) => {
    const parts = [String(i + 1).padStart(3, '0'), e.tc];
    if (w) parts.push((e.label || '').padEnd(w));
    parts.push(e.note);
    lines.push(parts.join('  ').trimEnd());
  });
  return lines.join('\n') + '\n';
}

async function save(saveAs = false, askExport = true) {
  document.activeElement && document.activeElement.blur(); // commit pending edits
  const r = await window.api.saveProject({ data: projectData(), filePath, saveAs, suggestedName: exportBase() });
  if (!r.ok) { status('Uloženie zrušené.'); return false; }
  filePath = r.filePath; setDirty(false);
  status('Uložené: ' + filePath);
  if (askExport) {
    const choice = await window.api.askExport();
    if (choice === 'txt') await exportTxt();
    if (choice === 'avid') await exportAvid();
    if (choice === 'premiere') await exportPremiere();
    if (choice === 'resolve') await exportResolve();
  }
  return true;
}
async function exportTxt() {
  document.activeElement && document.activeElement.blur();
  const r = await window.api.exportTxt({ text: buildTxt(), suggestedName: exportBase() });
  if (r.ok) status('Exportované: ' + r.filePath);
}
// Avid Media Composer marker list (Tools/Markers > Import Markers):
// one marker per line, tab separated: User, Timecode, Track, Color, Comment, Duration
const AVID_COLORS = ['red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white', 'black'];
function avidColor(label) {
  const i = labels.findIndex((l) => l.toLowerCase() === (label || '').toLowerCase());
  return i >= 0 ? AVID_COLORS[i % AVID_COLORS.length] : 'red';
}
function buildAvid() {
  const clean = (s) => String(s || '').replace(/[\t\r\n]+/g, ' ').trim();
  return entries.map((e) => {
    const comment = [clean(e.label), clean(e.note)].filter(Boolean).join(' - ') || clean(e.tc);
    return ['TCLogger', e.tc, 'V1', avidColor(e.label), comment, '1'].join('\t');
  }).join('\n') + '\n';
}
async function exportAvid() {
  document.activeElement && document.activeElement.blur();
  if (!entries.length) { status('Žiadne záznamy na export.'); return; }
  const r = await window.api.exportTxt({ text: buildAvid(), suggestedName: exportBase(), title: 'Exportovať Avid markery' });
  if (r.ok) status('Avid markery exportované: ' + r.filePath);
}

// ---------- Adobe Premiere Pro: FCP7 XML (xmeml) sequence with sequence markers ----------
const xmlEsc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const oneLine = (s) => String(s || '').replace(/[\t\r\n]+/g, ' ').trim();
function sortedEntries() {
  return entries.map((e) => ({ ...e, f: parseTc(e.tc) ?? 0 })).sort((a, b) => a.f - b.f);
}
function buildPremiere() {
  const list = sortedEntries();
  const hourF = 3600 * FPS;
  const start = Math.floor(list[0].f / hourF) * hourF;          // sequence starts on the full hour (e.g. 10:00:00:00)
  const dur = list[list.length - 1].f - start + 60 * FPS;       // + 1 min tail
  const rate = '<rate><timebase>25</timebase><ntsc>FALSE</ntsc></rate>';
  const markers = list.map((e) => {
    const name = oneLine(e.label) || oneLine(e.note) || e.tc;
    const comment = oneLine(e.label) ? oneLine(e.note) : '';
    return `    <marker>
      <name>${xmlEsc(name)}</name>
      <comment>${xmlEsc(comment)}</comment>
      <in>${e.f - start}</in>
      <out>-1</out>
    </marker>`;
  }).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xmeml>
<xmeml version="4">
  <sequence id="sequence-1">
    <name>${xmlEsc(exportBase())}</name>
    <duration>${dur}</duration>
    ${rate}
    <timecode>
      ${rate}
      <string>${framesToTc(start)}</string>
      <frame>${start}</frame>
      <displayformat>NDF</displayformat>
    </timecode>
    <in>-1</in>
    <out>-1</out>
    <media>
      <video>
        <format>
          <samplecharacteristics>
            ${rate}
            <width>1920</width>
            <height>1080</height>
            <anamorphic>FALSE</anamorphic>
            <pixelaspectratio>square</pixelaspectratio>
            <fielddominance>none</fielddominance>
          </samplecharacteristics>
        </format>
        <track></track>
      </video>
      <audio>
        <track></track>
      </audio>
    </media>
${markers}
  </sequence>
</xmeml>
`;
}

// ---------- DaVinci Resolve: timeline markers EDL ----------
const RESOLVE_COLORS = { red: 'Red', green: 'Green', blue: 'Blue', cyan: 'Cyan', magenta: 'Fuchsia', yellow: 'Yellow', white: 'Cream', black: 'Cocoa' };
function buildResolve() {
  const lines = [`TITLE: ${oneLine(exportBase())}`, 'FCM: NON-DROP FRAME', ''];
  sortedEntries().forEach((e, i) => {
    const n = String(i + 1).padStart(3, '0');
    const tin = framesToTc(e.f), tout = framesToTc(e.f + 1);
    const name = ([oneLine(e.label), oneLine(e.note)].filter(Boolean).join(' - ') || e.tc).replace(/\|/g, '/');
    lines.push(`${n}  001      V     C        ${tin} ${tout} ${tin} ${tout}  `);
    lines.push(` |C:ResolveColor${RESOLVE_COLORS[avidColor(e.label)]} |M:${name} |D:1`);
    lines.push('');
  });
  return lines.join('\n');
}

async function exportMarkers(kind) {
  document.activeElement && document.activeElement.blur();
  if (!entries.length) { status('Žiadne záznamy na export.'); return; }
  const cfg = {
    premiere: { text: buildPremiere, ext: 'xml', filterName: 'Premiere Pro XML', suffix: 'Premiere markers', title: 'Exportovať markery pre Premiere Pro', label: 'Premiere Pro' },
    resolve: { text: buildResolve, ext: 'edl', filterName: 'EDL', suffix: 'Resolve markers', title: 'Exportovať markery pre DaVinci Resolve', label: 'DaVinci Resolve' }
  }[kind];
  const r = await window.api.exportTxt({ text: cfg.text(), suggestedName: exportBase(), title: cfg.title, ext: cfg.ext, filterName: cfg.filterName });
  if (r.ok) status(`Markery pre ${cfg.label} exportované: ${r.filePath}`);
}
const exportPremiere = () => exportMarkers('premiere');
const exportResolve = () => exportMarkers('resolve');

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
  $('sequenceName').value = ''; $('shootDay').value = '';
  render(); setDirty(false); status('Nový projekt.');
}
async function openProject() {
  if (!(await confirmDiscard())) return;
  const r = await window.api.openProject();
  if (!r.ok) return;
  const d = r.data || {};
  entries = (d.entries || []).map((e) => ({ id: nextId++, tc: framesToTc(parseTc(e.tc) ?? 0), label: e.label || '', note: e.note || '' }));
  $('projectName').value = d.name || 'Projekt';
  $('sequenceName').value = d.sequence || ''; $('shootDay').value = d.shootDay || '';
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
  if (ev.code === 'Space' && !isTyping()) { ev.preventDefault(); logTc(); return; }
  if (!isTyping() && !editQuick && !ev.metaKey && !ev.ctrlKey && !ev.altKey && /^Digit[1-9]$/.test(ev.code)) {
    const i = Number(ev.code.slice(5)) - 1;
    if (i < labels.length) {
      ev.preventDefault();
      logTc(labels[i], $('quick').querySelectorAll('.qbtn')[i]);
    }
  }
});

// buttons shouldn't keep focus (so Space never re-clicks them)
document.addEventListener('mouseup', () => {
  const a = document.activeElement;
  if (a && a.tagName === 'BUTTON') a.blur();
});

$('btnLog').addEventListener('click', () => logTc());
$('btnEditQuick').addEventListener('click', () => {
  editQuick = !editQuick;
  if (!editQuick) labels = labels.map((l) => l.trim()).filter(Boolean);
  saveLabels(); renderQuick(); updateLabelList();
});
function updateLabelList() {
  let dl = $('labelList');
  if (!dl) { dl = document.createElement('datalist'); dl.id = 'labelList'; document.body.appendChild(dl); }
  dl.innerHTML = '';
  labels.forEach((l) => { const o = document.createElement('option'); o.value = l; dl.appendChild(o); });
}
$('addZone').addEventListener('click', () => logTc());
$('empty').addEventListener('click', () => logTc());
$('btnNew').addEventListener('click', newProject);
$('btnOpen').addEventListener('click', openProject);
$('btnSave').addEventListener('click', () => save(false));
$('btnMarkers').addEventListener('click', async () => {
  const r = $('btnMarkers').getBoundingClientRect();
  const choice = await window.api.markerMenu({ x: r.left, y: r.bottom + 4 });
  if (choice === 'txt') exportTxt();
  if (choice === 'avid') exportAvid();
  if (choice === 'premiere') exportPremiere();
  if (choice === 'resolve') exportResolve();
});
$('btnSetTc').addEventListener('click', openSetTc);
$('btnTod').addEventListener('click', () => { offsetMs = 0; saveOffset(); status('Synchronizované na systémový čas dňa.'); });
$('btnZero').addEventListener('click', () => { setTcNow(0); status('Timecode beží od 00:00:00:00.'); });
$('setTcOk').addEventListener('click', applySetTc);
$('setTcCancel').addEventListener('click', closeSetTc);
$('setTcInput').addEventListener('input', (e) => e.target.classList.toggle('bad', parseTc(e.target.value) === null));
$('modal').addEventListener('mousedown', (e) => { if (e.target.id === 'modal') closeSetTc(); });
['projectName', 'sequenceName', 'shootDay'].forEach((id) => {
  $(id).addEventListener('input', () => setDirty(true));
  $(id).addEventListener('keydown', (e) => { if (e.key === 'Enter') e.target.blur(); });
});
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
    export: exportTxt, exportAvid, exportPremiere, exportResolve, log: () => logTc(), setTc: openSetTc,
    tod: () => { offsetMs = 0; saveOffset(); status('Synchronizované na systémový čas dňa.'); }
  }[cmd] || (() => {}))();
});

window.__isDirty = () => dirty;
window.__saveForClose = () => save(false, false);

updateSyncLabel();
renderQuick();
updateLabelList();
render();
setDirty(false);
requestAnimationFrame(tick);
