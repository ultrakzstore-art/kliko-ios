// OLX Watcher для ПК: окно, в котором настраивается и работает телеграм-бот.
// Бот — тот же src/index.js, но в отдельном процессе (utilityProcess): настройки из окна
// передаются ему как переменные окружения, счётчики он присылает сюда сам. Упал — поднимаем
// заново; закрыли окно — бот продолжает работать из трея.

const fs = require('fs');
const path = require('path');
const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, shell, safeStorage, utilityProcess, Notification } = require('electron');

const BOT_ENTRY = path.join(__dirname, '..', 'src', 'index.js');
const PROBE_ENTRY = path.join(__dirname, '..', 'src', 'probe.js');
const PRODUCTS = ['OLX', 'KOLESA', 'KRISHA', 'KASPI', 'ALL'];

// Значения по умолчанию — как в .env.example.
const DEFAULTS = {
  ADMIN_ID: '',
  TRIAL_DAYS: '7',
  POLL_SEC: '2',
  PAID_SUBS: '20',
  FRESH_MIN: '30',
  TURBO_SEC: '1',
  TURBO_WINDOW: '10',
  CARD_SECTIONS: 'specs,description,seller',
  WATERMARK: 'auto',
  KASPI_DETAILS: 'Перевод на Kaspi по номеру +7 7XX XXX XX XX (Имя Ф.)',
  STARS_PRICES_OLX: '100,180,300',
  STARS_PRICES_KOLESA: '100,180,300',
  STARS_PRICES_KRISHA: '100,180,300',
  STARS_PRICES_KASPI: '60,100,180',
  STARS_PRICES_ALL: '250,450,800',
  KASPI_PRICES_OLX: '1500,2500,4500',
  KASPI_PRICES_KOLESA: '1500,2500,4500',
  KASPI_PRICES_KRISHA: '1500,2500,4500',
  KASPI_PRICES_KASPI: '900,1500,2700',
  KASPI_PRICES_ALL: '4000,7000,12000',
};
const KEYS = Object.keys(DEFAULTS);

let win, tray;
let quitting = false;
const hiddenStart = process.argv.includes('--hidden');

// ---------- настройки ----------

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
let settings = { env: { ...DEFAULTS }, tokenEnc: '', tokenPlain: '', autoStart: true, openAtLogin: false };

function loadSettings() {
  try {
    const saved = JSON.parse(fs.readFileSync(settingsFile(), 'utf8'));
    settings = { ...settings, ...saved, env: { ...DEFAULTS, ...(saved.env || {}) } };
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

// ---------- проверка площадок (probe) ----------

function runProbe(url) {
  return new Promise((resolve) => {
    const out = [];
    const child = utilityProcess.fork(PROBE_ENTRY, [url], { stdio: 'pipe', serviceName: 'OLX Watcher probe' });
    const add = (d) => { out.push(d.toString()); send('probe', out.join('')); };
    child.stdout?.on('data', add);
    child.stderr?.on('data', add);
    const timer = setTimeout(() => { out.push('\n…долго нет ответа — остановил проверку.'); child.kill(); }, 90_000);
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
    dbHandle.trialMs = (parseInt(settings.env.TRIAL_DAYS, 10) || 7) * 86400_000;
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
      payments: d.db.prepare("SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS sum FROM payments WHERE user_id = ? AND status = 'paid' AND method != 'admin'").get(u.id),
    };
  });
}

function tellUser(userId, text) {
  if (bot.child) bot.child.postMessage({ type: 'tell', userId, text });
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
ipcMain.handle('start', () => startBot());
ipcMain.handle('stop', () => stopBot());
ipcMain.handle('restart', async () => { await stopBot(); startBot(); });
ipcMain.handle('probe', (_e, url) => runProbe(String(url || '').trim()));
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
    updateTray();
    if (settings.autoStart && getToken()) startBot();
  });
  app.on('window-all-closed', () => { /* живём в трее */ });
  app.on('before-quit', () => { quitting = true; });
}

module.exports = { tokenLooksValid, DEFAULTS, PRODUCTS };
