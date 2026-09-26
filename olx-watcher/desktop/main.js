// OLX Watcher для ПК: окно, в котором настраивается и работает телеграм-бот.
// Бот — тот же src/index.js, но в отдельном процессе (utilityProcess): настройки из окна
// передаются ему как переменные окружения, счётчики он присылает сюда сам. Упал — поднимаем
// заново; закрыли окно — бот продолжает работать из трея.

const fs = require('fs');
const path = require('path');
const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, shell, safeStorage, utilityProcess, Notification, dialog } = require('electron');

const BOT_ENTRY = path.join(__dirname, '..', 'src', 'index.js');
const PROBE_ENTRY = path.join(__dirname, '..', 'src', 'probe.js');
const PRODUCTS = ['OLX', 'KOLESA', 'KRISHA', 'KASPI', 'ALL'];

// Значения по умолчанию — как в .env.example.
const DEFAULTS = {
  ADMIN_ID: '',
  TRIAL_HOURS: '24',
  POLL_SEC: '2',
  PAID_SUBS: '20',
  FRESH_MIN: '30',
  TURBO_SEC: '1',
  BOARD_SEC: '2',
  DISCOUNTS: 'on',
  MIN_DROP: '3',
  TURBO_WINDOW: '10',
  CARD_SECTIONS: 'specs,description,seller',
  WATERMARK: 'auto',
  KASPI_DETAILS: 'Перевод на Kaspi по номеру +7 7XX XXX XX XX (Имя Ф.)',
  // Цены: 24 часа, 7, 14, 30 дней.
  STARS_PRICES_OLX: '20,100,180,300',
  STARS_PRICES_KOLESA: '20,100,180,300',
  STARS_PRICES_KRISHA: '20,100,180,300',
  STARS_PRICES_KASPI: '20,80,150,250',
  STARS_PRICES_ALL: '50,250,450,800',
  STARS_PRICES_VIP: '5000,9000,15000',   // VIP-рубрика — без суток
  KASPI_PRICES_OLX: '500,2990,4990,8990',
  KASPI_PRICES_KOLESA: '500,2990,4990,8990',
  KASPI_PRICES_KRISHA: '500,2990,4990,8990',
  KASPI_PRICES_KASPI: '500,1990,3990,6990',
  KASPI_PRICES_ALL: '990,4990,8990,14990',
  KASPI_PRICES_VIP: '75000,125000,225000',
};
const KEYS = Object.keys(DEFAULTS);

let win, tray;
let quitting = false;
const hiddenStart = process.argv.includes('--hidden');

// ---------- настройки ----------

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
let settings = { env: { ...DEFAULTS }, tokenEnc: '', tokenPlain: '', autoStart: true, openAtLogin: false };

// Цена тарифа «24 часа» для тех, у кого цены сохранены ещё без него.
const DAY_PRICE = {
  STARS_PRICES_OLX: 20, STARS_PRICES_KOLESA: 20, STARS_PRICES_KRISHA: 20, STARS_PRICES_KASPI: 20, STARS_PRICES_ALL: 50,
  KASPI_PRICES_OLX: 500, KASPI_PRICES_KOLESA: 500, KASPI_PRICES_KRISHA: 500, KASPI_PRICES_KASPI: 500, KASPI_PRICES_ALL: 990,
};

function loadSettings() {
  try {
    const saved = JSON.parse(fs.readFileSync(settingsFile(), 'utf8'));
    settings = { ...settings, ...saved, env: { ...DEFAULTS, ...(saved.env || {}) } };
    // Появился тариф на 24 часа: к сохранённым ценам из трёх чисел один раз дописываем цену суток.
    if (!settings.dayPlan) {
      for (const [k, day] of Object.entries(DAY_PRICE)) {
        const list = String(settings.env[k] || '').split(',').map((x) => x.trim()).filter(Boolean);
        if (list.length === 3) settings.env[k] = [day, ...list].join(',');
      }
      settings.dayPlan = true;
      try { saveSettings(); } catch { /* сохраним при следующем «Сохранить» */ }
    }
  } catch { /* первый запуск */ }
}


function saveSettings() {
  fs.mkdirSync(path.dirname(settingsFile()), { recursive: true });
  fs.writeFileSync(settingsFile(), JSON.stringify(settings, null, 2));
}

// Токен — зашифрованным средствами Windows (safeStorage), если они доступны.
function getToken() {
  if (settings.tokenEnc && safeStorage.isEncryptionAvailable()) {
    try { return safeStorage.decryptString(Buffer.from(settings.tokenEnc, 'base64')); } catch { return ''; }
  }
  return settings.tokenPlain || '';
}

function setToken(token) {
  token = String(token || '').trim();
  if (safeStorage.isEncryptionAvailable()) {
    settings.tokenEnc = token ? safeStorage.encryptString(token).toString('base64') : '';
    settings.tokenPlain = '';
  } else {
    settings.tokenPlain = token;
  }
}

const tokenLooksValid = (t) => /^\d{5,}:[\w-]{30,}$/.test(t);

// ---------- журнал ----------

const logLines = [];
function log(line) {
  const text = String(line).replace(/\s+$/, '');
  if (!text) return;
  for (const l of text.split(/\r?\n/)) {
    logLines.push(/^\d{1,2}:\d{2}:\d{2} /.test(l) ? l : `${new Date().toLocaleTimeString('ru-RU')} ${l}`);
  }
  if (logLines.length > 1000) logLines.splice(0, logLines.length - 1000);
  send('log', logLines.slice(-text.split(/\r?\n/).length));
}

function send(channel, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
}

// ---------- бот ----------

const bot = {
  child: null,
  status: 'stopped',     // stopped | starting | running | error
  username: '',
  error: '',
  startedAt: 0,
  stats: null,
  wanted: false,         // пользователь хочет, чтобы бот работал (для перезапуска после падения)
  restarts: 0,
  restartTimer: null,
};

function publicState() {
  const { tokenEnc, tokenPlain, ...rest } = settings;
  const token = getToken();
  return {
    settings: rest,
    hasToken: !!token,
    tokenHint: token ? `${token.split(':')[0]}:…${token.slice(-4)}` : '',
    bot: { status: bot.status, username: bot.username, error: bot.error, startedAt: bot.startedAt, stats: bot.stats },
    dataDir: app.getPath('userData'),
    version: app.getVersion(),
    update,
    log: logLines.slice(-300),
  };
}

function pushState() {
  send('state', publicState());
  updateTray();
}

function startBot() {
  if (bot.child) return;
  clearTimeout(bot.restartTimer);
  const token = getToken();
  if (!token) {
    bot.status = 'error';
    bot.error = 'Нет токена бота. Создайте бота у @BotFather и вставьте токен в «Настройки».';
    pushState();
    return;
  }
  bot.wanted = true;
  bot.status = 'starting';
  bot.error = '';
  bot.username = '';
  bot.stats = null;
  const env = { ...process.env, BOT_TOKEN: token, DB_FILE: path.join(app.getPath('userData'), 'watcher.db') };
  for (const k of KEYS) env[k] = String(settings.env[k] ?? '').trim();
  const child = utilityProcess.fork(BOT_ENTRY, [], { env, stdio: 'pipe', serviceName: 'OLX Watcher bot' });
  bot.child = child;
  child.stdout?.on('data', (d) => log(d.toString()));
  child.stderr?.on('data', (d) => log(d.toString()));
  child.on('message', (m) => {
    if (m?.type === 'why') { whyWaiters.get(m.reqId)?.(m.text); whyWaiters.delete(m.reqId); return; }
    if (m?.type === 'ready') {
      bot.status = 'running';
      bot.error = '';
      bot.username = m.username;
      bot.startedAt = Date.now();
      bot.restarts = 0;
    } else if (m?.type === 'stats') {
      bot.stats = m;
    } else if (m?.type === 'fatal') {
      bot.error = m.text;
      bot.wanted = false;   // токен неверный или бот запущен в другом месте — перезапуск не поможет
    }
    pushState();
  });
  child.on('exit', (code) => {
    bot.child = null;
    bot.startedAt = 0;
    if (bot.wanted) {
      // Упал сам — поднимаем заново с нарастающей паузой.
      bot.restarts += 1;
      const delay = Math.min(60, 5 * bot.restarts);
      bot.status = 'error';
      bot.error = `Бот остановился (код ${code}). Перезапуск через ${delay} с…`;
      log(bot.error);
      bot.restartTimer = setTimeout(startBot, delay * 1000);
    } else {
      bot.status = bot.error ? 'error' : 'stopped';
    }
    pushState();
  });
  setTimeout(() => {
    if (bot.child === child && bot.status === 'starting') {
      bot.error = 'Telegram не отвечает уже 30 секунд — проверьте интернет. Бот продолжает пытаться.';
      pushState();
    }
  }, 30_000);
  log('Запускаю бота…');
  pushState();
}

function stopBot() {
  bot.wanted = false;
  bot.error = '';
  clearTimeout(bot.restartTimer);
  const child = bot.child;
  if (!child) {
    bot.status = 'stopped';
    bot.error = '';
    pushState();
    return Promise.resolve();
  }
  log('Останавливаю бота…');
  return new Promise((resolve) => {
    const kill = setTimeout(() => child.kill(), 5000);
    child.once('exit', () => { clearTimeout(kill); resolve(); });
    child.postMessage({ type: 'stop' });
  });
}

// ---------- «почему не пришло?» — спросить работающего бота ----------

const whyWaiters = new Map();
let whySeq = 0;
function askWhy(id) {
  if (!bot.child || bot.status !== 'running') return Promise.resolve('');
  const reqId = ++whySeq;
  return new Promise((resolve) => {
    whyWaiters.set(reqId, resolve);
    bot.child.postMessage({ type: 'why', id, reqId });
    setTimeout(() => { if (whyWaiters.delete(reqId)) resolve(''); }, 3000);
  });
}

// ---------- проверка площадок (probe) ----------

function runProbe(url) {
  return new Promise((resolve) => {
    const out = [];
    const child = utilityProcess.fork(PROBE_ENTRY, [url], { stdio: 'pipe', serviceName: 'OLX Watcher probe' });
    const add = (d) => { out.push(d.toString()); send('probe', out.join('')); };
    child.stdout?.on('data', add);
    child.stderr?.on('data', add);
    // «kaspi watch» — наблюдение на 5 минут; остальные проверки — до 90 секунд.
    const limit = /^kaspi\s*watch$/i.test(url) ? 6 * 60_000 : 90_000;
    const timer = setTimeout(() => { out.push('\n…долго нет ответа — остановил проверку.'); child.kill(); }, limit);
    child.on('exit', () => { clearTimeout(timer); resolve(out.join('') || 'Пусто — площадка ничего не вернула.'); });
  });
}

// ---------- окно и трей ----------

function createWindow() {
  win = new BrowserWindow({
    width: 980,
    height: 760,
    minWidth: 760,
    minHeight: 560,
    title: 'OLX Watcher',
    icon: path.join(__dirname, 'icon.png'),
    show: !hiddenStart,
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
  });
  win.loadFile(path.join(__dirname, 'ui', 'index.html'));
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https:\/\//.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.on('close', (e) => {
    if (quitting) return;
    // Окно закрыли — бот продолжает работать из трея.
    e.preventDefault();
    win.hide();
    if (bot.child && !settings.trayHintShown) {
      settings.trayHintShown = true;
      saveSettings();
      new Notification({ title: 'OLX Watcher работает', body: 'Бот продолжает присылать объявления. Значок — возле часов, там же «Выход».' }).show();
    }
  });
}

function showWindow() {
  if (!win || win.isDestroyed()) createWindow();
  win.show();
  win.focus();
}

function updateTray() {
  if (!tray) return;
  const label = { stopped: 'остановлен', starting: 'запускается…', running: 'работает', error: 'ошибка' }[bot.status];
  tray.setToolTip(`OLX Watcher — бот ${label}${bot.username ? ` (@${bot.username})` : ''}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: `Бот: ${label}`, enabled: false },
    { type: 'separator' },
    { label: 'Открыть окно', click: showWindow },
    bot.child ? { label: 'Остановить бота', click: () => stopBot() } : { label: 'Запустить бота', click: startBot },
    ...(bot.username ? [{ label: `Открыть @${bot.username} в Telegram`, click: () => shell.openExternal(`https://t.me/${bot.username}`) }] : []),
    { type: 'separator' },
    { label: 'Выход', click: () => quit() },
  ]));
}

async function quit() {
  quitting = true;
  await stopBot();
  app.quit();
}

// ---------- подписчики ----------
// Та же база, что у бота (SQLite в режиме WAL — читать и писать можно одновременно).

const PRODUCT_SOURCES = {
  all: ['olx', 'kolesa', 'krisha', 'kaspi'], olx: ['olx'], kolesa: ['kolesa'], krisha: ['krisha'], kaspi: ['kaspi'],
};
const PRODUCT_TITLES = { all: 'Все площадки', olx: 'OLX', kolesa: 'Kolesa', krisha: 'Krisha', kaspi: 'Kaspi Объявления' };
let dbHandle = null;
function db() {
  if (!dbHandle) {
    const { Db } = require('../src/db');
    dbHandle = new Db(path.join(app.getPath('userData'), 'watcher.db'));
    dbHandle.trialMs = (parseInt(settings.env.TRIAL_HOURS, 10) || 24) * 3600_000;
  }
  return dbHandle;
}

function listUsers() {
  const d = db();
  const now = Date.now();
  return d.users().map((u) => {
    const access = d.accessList(u.id);
    const paid = d.isPaid(u, 'any', now);
    const trial = !paid && d.isTrial(u, now);
    return {
      id: u.id,
      name: u.name,
      username: u.username,
      createdAt: u.created_at,
      status: paid ? 'paid' : trial ? 'trial' : 'none',
      trialUntil: u.trial_until,
      access,
      subs: d.subs(u.id).length,
      blocked: !!u.blocked,
      vip: d.locks(now).filter((l) => l.user_id === u.id).map((l) => ({ id: l.id, label: vipLib().lockLabel(l), until: l.until })),
      payments: d.db.prepare("SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS sum FROM payments WHERE user_id = ? AND status = 'paid' AND method != 'admin'").get(u.id),
    };
  });
}

function vipLib() {
  return require('../src/vip');
}

function tellUser(userId, text) {
  if (bot.child) bot.child.postMessage({ type: 'tell', userId, text });
}

// ---------- автообновление ----------
// Новые версии выкладываются в GitHub Releases (репозиторий открытый). Раз в час проверяем,
// скачиваем в фоне и спрашиваем: перезапустить сейчас или позже. «Позже» — поставится само
// при следующем выходе из приложения.

const update = { status: '', version: '' };
let askInstall = null;   // показать вопрос «обновить сейчас?» снова (по кнопке)
function setupAutoUpdate() {
  if (!app.isPackaged) {
    ipcMain.handle('check-update', () => { update.status = 'dev'; pushState(); return false; });
    return;
  }
  let autoUpdater;
  try { ({ autoUpdater } = require('electron-updater')); } catch { return; }
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on('update-available', (i) => { update.status = 'downloading'; update.version = i.version; log(`Есть обновление ${i.version} — скачиваю…`); pushState(); });
  autoUpdater.on('update-not-available', () => { update.status = 'latest'; pushState(); });
  autoUpdater.on('checking-for-update', () => { if (update.status !== 'ready') { update.status = 'checking'; pushState(); } });
  autoUpdater.on('error', (e) => { update.status = 'error'; log(`Обновление: ${e.message}`); pushState(); });
  askInstall = async () => {
    const r = await dialog.showMessageBox(win && !win.isDestroyed() ? win : undefined, {
      type: 'info',
      title: 'OLX Watcher',
      message: `Вышло обновление ${update.version}`,
      detail: 'Перезапустить сейчас? Бот остановится на несколько секунд и запустится снова с новой версией.',
      buttons: ['Обновить сейчас', 'Позже'],
      defaultId: 0,
      cancelId: 1,
    });
    if (r.response === 0) {
      quitting = true;
      await stopBot();
      autoUpdater.quitAndInstall(true, true);
    }
  };
  autoUpdater.on('update-downloaded', async (i) => {
    update.status = 'ready';
    update.version = i.version;
    pushState();
    log(`Обновление ${i.version} скачано`);
    await askInstall();
  });
  const check = () => autoUpdater.checkForUpdates().catch((e) => log(`Обновление: ${e.message}`));
  setTimeout(check, 10_000);
  setInterval(check, 3600_000);
  // Кнопка «Проверить обновления» — работает и пока бот запущен (бот не останавливается).
  ipcMain.handle('check-update', async () => {
    if (update.status === 'ready' && askInstall) { await askInstall(); return true; }
    check();
    return true;
  });
}

// ---------- IPC ----------

ipcMain.handle('state', () => publicState());

ipcMain.handle('save', (_e, patch) => {
  if (typeof patch.token === 'string' && patch.token.trim()) {
    const t = patch.token.trim();
    if (!tokenLooksValid(t)) return { ok: false, error: 'Похоже, это не токен. Он выглядит так: 1234567890:AA…, его выдаёт @BotFather.' };
    setToken(t);
  }
  if (patch.env) for (const k of KEYS) if (k in patch.env) settings.env[k] = String(patch.env[k] ?? '').trim();
  if ('autoStart' in patch) settings.autoStart = !!patch.autoStart;
  if ('openAtLogin' in patch) {
    settings.openAtLogin = !!patch.openAtLogin;
    if (app.isPackaged) app.setLoginItemSettings({ openAtLogin: settings.openAtLogin, args: ['--hidden'] });
  }
  saveSettings();
  pushState();
  return { ok: true, restartNeeded: !!bot.child };
});

ipcMain.handle('forget-token', async () => {
  await stopBot();
  setToken('');
  saveSettings();
  pushState();
});

ipcMain.handle('users', () => { try { return { ok: true, users: listUsers() }; } catch (e) { return { ok: false, error: e.message }; } });
ipcMain.handle('grant', (_e, { userId, days, product }) => {
  const sources = PRODUCT_SOURCES[product];
  if (!sources || ![7, 14, 30].includes(days)) return { ok: false };
  const until = db().extend(userId, days, sources);
  db().addPayment({ userId, method: 'admin', product, days, status: 'paid' });
  const date = new Date(until).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
  tellUser(userId, `🎁 Вам открыт доступ: ${PRODUCT_TITLES[product]} — до ${date}.`);
  log(`Выдан доступ ${userId}: ${PRODUCT_TITLES[product]} +${days} дн`);
  return { ok: true };
});
ipcMain.handle('revoke', (_e, { userId }) => {
  db().revoke(userId);
  tellUser(userId, '⛔ Доступ закрыт. Подключить снова: /access');
  log(`Закрыт доступ ${userId}`);
  return { ok: true };
});
ipcMain.handle('vip-options', () => ({
  rubrics: vipLib().rubricChoices(),
  cities: require('../src/categories').CITIES,
}));
ipcMain.handle('vip-grant', (_e, { userId, path: rubric, city, days }) => {
  const r = vipLib().grant(db(), userId, rubric, city, days);
  if (!r.ok) {
    const c = r.conflict;
    return { ok: false, error: `Занято: ${vipLib().lockLabel(c)} — у ${c.user_id} до ${new Date(c.until).toLocaleDateString('ru-RU')}` };
  }
  const date = new Date(r.until).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
  tellUser(userId, `👑 Вам закреплена VIP-рубрика «${r.label}» до ${date}. Объявления из неё получаете только вы.`);
  log(`VIP ${userId}: ${r.label} +${days} дн`);
  return { ok: true };
});
ipcMain.handle('vip-end', (_e, { lockId }) => { db().endLock(lockId); log(`VIP-рубрика #${lockId} снята`); return { ok: true }; });
ipcMain.handle('start', () => startBot());
ipcMain.handle('stop', () => stopBot());
ipcMain.handle('restart', async () => { await stopBot(); startBot(); });
ipcMain.handle('probe', (_e, url) => runProbe(String(url || '').trim()));
ipcMain.handle('why', (_e, id) => askWhy(Number(id)));
ipcMain.handle('open-data', () => shell.openPath(app.getPath('userData')));
ipcMain.handle('open-url', (_e, url) => { if (/^https:\/\//.test(url)) shell.openExternal(url); });

// ---------- запуск ----------

if (!app.requestSingleInstanceLock()) {
  // Второй экземпляр запустил бы второго бота с тем же токеном — Telegram такого не даёт.
  app.quit();
} else {
  app.on('second-instance', showWindow);
  app.whenReady().then(() => {
    app.setAppUserModelId('kz.olxwatcher.desktop');
    loadSettings();
    createWindow();
    tray = new Tray(nativeImage.createFromPath(path.join(__dirname, 'tray.png')));
    tray.on('click', showWindow);
    setupAutoUpdate();
    updateTray();
    if (settings.autoStart && getToken()) startBot();
  });
  app.on('window-all-closed', () => { /* живём в трее */ });
  app.on('before-quit', () => { quitting = true; });
}

module.exports = { tokenLooksValid, DEFAULTS, PRODUCTS };
