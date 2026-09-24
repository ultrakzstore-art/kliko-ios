// Окно приложения: слева панель очереди, справа — OLX.kz в своём браузере (вход сохраняется).
// Здесь же расписание: черновики пишутся сразу по мере поступления фото, подача — раз в N минут
// внутри рабочего окна.

const path = require('path');
const { pathToFileURL } = require('url');
const { app, BaseWindow, WebContentsView, ipcMain, session, Notification, shell, dialog } = require('electron');
const QRCode = require('qrcode');

const { Store } = require('./store');
const { FolderIntake, PhoneIntake } = require('./intake');
const { describeItem } = require('./describe');
const { groupPhotos, MAX_PER_ITEM } = require('./grouping');
const { postItem, START_URL } = require('./poster');
const { PageTools } = require('./page-tools');

const PANEL_WIDTH = 460;

let win, panel, olx, store, folder, phone;
let phoneUrls = [];
let phoneQr = '';
const logLines = [];
const state = { groupingId: null, describingId: null, postingId: null, stopRequested: false, lastPostAt: 0 };

function log(line) {
  const stamp = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  logLines.push(`${stamp} ${line}`);
  if (logLines.length > 500) logLines.splice(0, logLines.length - 500);
  send('log', logLines[logLines.length - 1]);
}

function send(channel, payload) {
  if (panel && !panel.webContents.isDestroyed()) panel.webContents.send(channel, payload);
}

function publicState() {
  const { apiKeyEnc, ...settings } = store.settings;
  return {
    settings,
    hasKey: !!store.getApiKey(),
    items: store.items.map((it) => ({ ...it, photoUrls: it.photos.map((p) => pathToFileURL(p).href) })),
    batches: store.batches.map((b) => ({ id: b.id, count: b.photos.length, attempts: b.attempts })),
    groupingId: state.groupingId,
    phoneUrls,
    phoneQr,
    describingId: state.describingId,
    postingId: state.postingId,
    nextPostAt: nextPostAt(),
    inHours: inWorkHours(),
    log: logLines.slice(-200),
  };
}

function pushState() {
  send('state', publicState());
}

// ---------- расписание ----------

function minutes(hhmm) {
  const [h, m] = String(hhmm).split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

function inWorkHours(d = new Date()) {
  const now = d.getHours() * 60 + d.getMinutes();
  const a = minutes(store.settings.workStart);
  const b = minutes(store.settings.workEnd);
  return a <= b ? now >= a && now < b : now >= a || now < b; // окно может переходить через полночь
}

function nextPostAt() {
  if (!store.settings.running) return null;
  return state.lastPostAt + store.settings.intervalMin * 60_000;
}

// Пачка → товары. Claude раскладывает фото; если три раза не вышло — делим по разрывам
// во времени съёмки, чтобы пачка не застряла навсегда.
async function groupLoop() {
  if (state.groupingId) return;
  const batch = store.batches[0];
  const apiKey = store.getApiKey();
  if (!batch || !apiKey) return;
  state.groupingId = batch.id;
  pushState();
  log(`Claude раскладывает ${batch.photos.length} фото по товарам…`);
  let groups;
  let cost = 0;
  try {
    const r = await groupPhotos({ apiKey, settings: store.settings, photos: batch.photos.map((p) => p.path), log });
    groups = r.groups;
    cost = r.cost;
  } catch (e) {
    batch.attempts += 1;
    log(`Не удалось разложить пачку: ${e.message}`);
    if (batch.attempts < 3) { store.saveBatches(); state.groupingId = null; return; }
    groups = splitByTime(batch.photos, store.settings.groupGapSec * 1000);
    log(`Делю пачку по времени съёмки: ${groups.length} товаров`);
  }
  for (const g of groups) {
    const it = store.addItem(g.photos, { source: batch.source, note: g.what || '' });
    if (cost) store.update(it.id, { costUsd: cost / groups.length });
  }
  store.removeBatch(batch.id);
  state.groupingId = null;
}

function splitByTime(photos, gap) {
  const groups = [];
  for (const p of [...photos].sort((a, b) => a.mtime - b.mtime)) {
    const last = groups[groups.length - 1];
    if (last && p.mtime - last.lastMtime <= gap && last.photos.length < MAX_PER_ITEM) {
      last.photos.push(p.path);
      last.lastMtime = p.mtime;
    } else {
      groups.push({ photos: [p.path], lastMtime: p.mtime, what: '' });
    }
  }
  return groups;
}

async function describeLoop() {
  if (state.describingId) return;
  const item = store.nextWith('new');
  const apiKey = store.getApiKey();
  if (!item || !apiKey) return;
  state.describingId = item.id;
  store.update(item.id, { status: 'describing', error: '' });
  log(`Claude описывает товар ${item.id}…`);
  try {
    const { listing, costUsd } = await describeItem({ apiKey, settings: store.settings, item });
    store.update(item.id, { status: 'ready', listing, costUsd: item.costUsd + costUsd });
    log(`Черновик готов: «${listing.title}» — ${listing.price} ₸${listing.warning ? ` (⚠ ${listing.warning})` : ''}`);
  } catch (e) {
    store.update(item.id, { status: 'failed', error: `Описание: ${e.message}` });
    log(`Не удалось описать ${item.id}: ${e.message}`);
  } finally {
    state.describingId = null;
  }
}

async function postLoop() {
  if (state.postingId || !store.settings.running || !inWorkHours()) return;
  if (Date.now() < nextPostAt()) return;
  const item = store.nextWith('ready');
  if (!item) return;
  await postOne(item.id);
}

async function postOne(id) {
  const item = store.items.find((x) => x.id === id);
  const apiKey = store.getApiKey();
  if (!item || !item.listing || state.postingId || !apiKey) return;
  state.postingId = id;
  state.stopRequested = false;
  state.lastPostAt = Date.now();
  store.update(id, { status: 'posting', error: '', attempts: item.attempts + 1 });
  log(`Подаю на OLX: «${item.listing.title}»`);
  let result;
  try {
    result = await postItem({
      apiKey,
      settings: store.settings,
      item,
      page: new PageTools(olx.webContents),
      notes: store.readNotes(),
      onNote: (n) => { store.appendNote(n); log(`  · заметка: ${n}`); },
      log,
      shouldStop: () => state.stopRequested,
    });
  } catch (e) {
    result = { status: 'failed', reason: e.message, cost: 0 };
  }
  state.postingId = null;
  const cost = item.costUsd + (result.cost || 0);

  if (result.status === 'published') {
    store.update(id, { status: 'published', olxUrl: result.adUrl || '', postedAt: Date.now(), costUsd: cost });
    log(`✓ Опубликовано: «${item.listing.title}»`);
    return;
  }
  const limit = /лимит/i.test(result.reason || '');
  if (result.status === 'needs_user' || limit) {
    store.update(id, { status: 'needs_user', error: result.reason, costUsd: cost });
    store.saveSettings({ running: false });
    log(`Пауза: ${result.reason}`);
    notify('OLX Poster на паузе', result.reason || 'Нужны ваши действия в окне OLX');
    return;
  }
  // Обычная неудача: одна повторная попытка позже, в конце очереди.
  const retry = item.attempts < 2; // attempts уже увеличен в начале подачи
  store.items = store.items.filter((x) => x.id !== id).concat(item);
  store.update(id, { status: retry ? 'ready' : 'failed', error: result.reason, costUsd: cost });
  log(`✗ Не вышло: ${result.reason}${retry ? ' — попробую ещё раз позже' : ''}`);
}

function notify(title, body) {
  if (Notification.isSupported()) new Notification({ title, body }).show();
  if (win) { win.show(); win.focus(); }
}

// ---------- окно ----------

function layout() {
  const { width, height } = win.getContentBounds();
  panel.setBounds({ x: 0, y: 0, width: PANEL_WIDTH, height });
  olx.setBounds({ x: PANEL_WIDTH, y: 0, width: Math.max(0, width - PANEL_WIDTH), height });
}

function createWindow() {
  win = new BaseWindow({ width: 1500, height: 950, minWidth: 1100, minHeight: 700, title: 'OLX Poster', backgroundColor: '#111418' });

  panel = new WebContentsView({
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false },
  });
  panel.webContents.loadFile(path.join(__dirname, 'ui', 'index.html'));

  // Отдельная постоянная сессия для OLX: вход и куки живут между запусками.
  const olxSession = session.fromPartition('persist:olx');
  const ua = olxSession.getUserAgent().replace(/\s(Electron|olx-poster|OLX Poster)\/\S+/gi, '');
  olxSession.setUserAgent(ua);
  olx = new WebContentsView({ webPreferences: { session: olxSession, contextIsolation: true, sandbox: true } });
  olx.webContents.setWindowOpenHandler(({ url }) => {
    olx.webContents.loadURL(url); // ссылки «в новом окне» открываем здесь же
    return { action: 'deny' };
  });
  olx.webContents.loadURL('https://www.olx.kz/');

  win.contentView.addChildView(panel);
  win.contentView.addChildView(olx);
  win.on('resize', layout);
  layout();
  win.on('closed', () => app.quit());
}

// ---------- связь с панелью ----------

function registerIpc() {
  ipcMain.handle('state', () => publicState());
  ipcMain.handle('settings:save', (_e, patch) => {
    const allowed = ['model', 'effort', 'intervalMin', 'workStart', 'workEnd', 'inboxDir', 'groupGapSec', 'city', 'contactName', 'phone', 'priceHint', 'extraRules'];
    const clean = {};
    for (const k of allowed) if (k in patch) clean[k] = patch[k];
    if ('intervalMin' in clean) clean.intervalMin = Math.max(1, Number(clean.intervalMin) || 5);
    if ('groupGapSec' in clean) clean.groupGapSec = Math.max(10, Number(clean.groupGapSec) || 90);
    store.saveSettings(clean);
    if ('inboxDir' in clean) folder.start();
  });
  ipcMain.handle('key:set', (_e, key) => store.setApiKey(key));
  ipcMain.handle('run', (_e, on) => {
    store.saveSettings({ running: !!on });
    log(on ? `Расписание включено: раз в ${store.settings.intervalMin} мин, ${store.settings.workStart}–${store.settings.workEnd}` : 'Расписание остановлено');
  });
  ipcMain.handle('stop-current', () => { state.stopRequested = true; });
  ipcMain.handle('item:post-now', (_e, id) => postOne(id));
  ipcMain.handle('item:redescribe', (_e, id) => store.update(id, { status: 'new', error: '' }));
  ipcMain.handle('item:retry', (_e, id) => {
    const it = store.items.find((x) => x.id === id);
    if (it) store.update(id, { status: it.listing ? 'ready' : 'new', error: '', attempts: 0 });
  });
  ipcMain.handle('item:remove', (_e, id) => { if (state.postingId !== id) store.remove(id); });
  ipcMain.handle('item:edit', (_e, id, patch) => {
    const it = store.items.find((x) => x.id === id);
    if (!it || !it.listing) return;
    const listing = { ...it.listing };
    if (typeof patch.title === 'string') listing.title = patch.title.slice(0, 70);
    if (typeof patch.description === 'string') listing.description = patch.description;
    if (patch.price != null) listing.price = Math.max(0, parseInt(patch.price, 10) || 0);
    store.update(id, { listing });
  });
  ipcMain.handle('items:add', (_e, paths) => {
    const photos = (paths || []).filter((p) => /\.(jpe?g|png|webp|heic|heif)$/i.test(p));
    if (photos.length) {
      store.addBatch(photos, { source: 'drop' });
      log(`Перетащили ${photos.length} фото — Claude разложит по товарам`);
    }
  });
  ipcMain.handle('inbox:choose', async () => {
    const r = await dialog.showOpenDialog(win, { properties: ['openDirectory', 'createDirectory'], defaultPath: store.settings.inboxDir });
    if (!r.canceled && r.filePaths[0]) {
      store.saveSettings({ inboxDir: r.filePaths[0] });
      folder.start();
    }
  });
  ipcMain.handle('inbox:open', () => shell.openPath(store.settings.inboxDir));
  ipcMain.handle('olx:open', (_e, url) => olx.webContents.loadURL(url || START_URL));
  ipcMain.handle('notes:read', () => store.readNotes());
}

// ---------- запуск ----------

// Второй экземпляр запустил бы второго робота на тот же аккаунт — не даём.
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
app.on('second-instance', () => { if (win) { win.show(); win.focus(); } });
app.setAppUserModelId('kz.kliko.olxposter'); // без этого Windows не показывает уведомления

app.whenReady().then(async () => {
  if (!gotLock) return;
  store = new Store();
  store.onChange(pushState);
  registerIpc();
  createWindow();

  folder = new FolderIntake(store, log);
  folder.start();
  phone = new PhoneIntake(store, log);
  phoneUrls = await phone.start();
  if (phoneUrls[0]) phoneQr = await QRCode.toDataURL(phoneUrls[0], { margin: 1, width: 260 });
  log(phoneUrls[0] ? `Страница для телефона: ${phoneUrls[0]}` : 'Нет сети — страница для телефона недоступна');

  setInterval(() => groupLoop().catch((e) => { state.groupingId = null; log(`Ошибка: ${e.message}`); }), 3000);
  setInterval(() => describeLoop().catch((e) => log(`Ошибка: ${e.message}`)), 3000);
  setInterval(() => postLoop().catch((e) => log(`Ошибка: ${e.message}`)), 15_000);
  setInterval(pushState, 30_000); // обновить обратный отсчёт в панели
  pushState();
});

app.on('window-all-closed', () => app.quit());
