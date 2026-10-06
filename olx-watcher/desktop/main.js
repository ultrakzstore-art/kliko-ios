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
  const { tokenEnc, tokenPlain, serverPassEnc, ...rest } = settings;
  rest.hasServerPass = !!serverPassEnc;
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
// Закрыть базу окна (перед тем как отдать файл на сервер или заменить его): записи из WAL
// попадут в сам файл, и следующий запрос откроет её заново.
function closeDbHandle() {
  try { dbHandle?.db?.close(); } catch { /* уже закрыта */ }
  dbHandle = null;
}
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
// Новые версии — в GitHub Releases; запасной источник — ваш сервер обновлений
// (deploy/updates: http://<IP>:8787/). Раз в час проверяем,
// скачиваем в фоне и спрашиваем: перезапустить сейчас или позже. «Позже» — поставится само
// при следующем выходе из приложения.

const UPDATE_PORT = 8787;
const update = { status: '', version: '' };
let askInstall = null;   // показать вопрос «обновить сейчас?» снова (по кнопке)
function setupAutoUpdate() {
  if (!app.isPackaged) {
    ipcMain.handle('check-update', () => { update.status = 'dev'; pushState(); return false; });
    return;
  }
  let autoUpdater;
  try { ({ autoUpdater } = require('electron-updater')); } catch { return; }
  // Сначала GitHub Releases. Не ответил (репозиторий закрыт, аккаунт ограничен) — ваш сервер
  // обновлений, если он известен; переключаемся до перезапуска программы.
  let fromServer = false;
  const toServer = () => {
    const host = settings.updateHost || settings.server?.host;
    if (fromServer || !host) return false;
    fromServer = true;
    autoUpdater.setFeedURL({ provider: 'generic', url: `http://${host}:${UPDATE_PORT}/` });
    // Сервер отдаёт файлы целиком, без докачки кусками.
    autoUpdater.disableDifferentialDownload = true;
    log(`Обновления: GitHub не ответил — проверяю сервер ${host}`);
    return true;
  };
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
  const check = () => autoUpdater.checkForUpdates().catch((e) => {
    if (toServer()) return autoUpdater.checkForUpdates().catch((e2) => log(`Обновление: ${e2.message}`));
    log(`Обновление: ${e.message}`);
  });
  setTimeout(check, 10_000);
  setInterval(check, 3600_000);
  // Кнопка «Проверить обновления» — работает и пока бот запущен (бот не останавливается).
  ipcMain.handle('check-update', async () => {
    if (update.status === 'ready' && askInstall) { await askInstall(); return true; }
    check();
    return true;
  });
}

// ---------- установка на сервер (VPS) ----------
// Кнопкой из окна: по IP и паролю заходим на сервер по SSH, кладём бота в свою папку
// /opt/olx-watcher (другие папки и программы на сервере не трогаем, ничего не удаляем), пишем
// .env из настроек этого окна, при первой установке переносим базу (подписчики, поиски, оплаты)
// и запускаем deploy/install.sh — он ставит свой Node.js и службу systemd. Бот на ПК при этом
// выключаем: один токен — одна работающая копия. Пароль нигде не сохраняется.

const REMOTE_DIR = '/opt/olx-watcher';
const APP_ROOT = path.join(__dirname, '..');

// Файлы бота для сервера: src/, deploy/, package.json, package-lock.json, .env.example.
function botFiles() {
  const out = [];
  const walk = (rel) => {
    for (const name of fs.readdirSync(path.join(APP_ROOT, rel))) {
      const r = path.posix.join(rel, name);
      const st = fs.statSync(path.join(APP_ROOT, r));
      if (st.isDirectory()) walk(r); else out.push(r);
    }
  };
  walk('src');
  walk('deploy');
  for (const f of ['package.json', 'package-lock.json', '.env.example']) if (fs.existsSync(path.join(APP_ROOT, f))) out.push(f);
  return out;
}

// Текстовые файлы уходят на сервер с переносами LF — так же считаем и их суммы для сравнения.
const TEXT_FILE = /\.(sh|service|js|json|example|md|txt)$/;
function botFileData(f) {
  const data = fs.readFileSync(path.join(APP_ROOT, f));
  return TEXT_FILE.test(f) ? Buffer.from(data.toString('utf8').replace(/\r\n/g, '\n'), 'utf8') : data;
}
function localSums() {
  const crypto = require('crypto');
  const out = {};
  for (const f of botFiles()) if (!f.endsWith('.example')) out[f] = crypto.createHash('sha256').update(botFileData(f)).digest('hex');
  return out;
}
// Сравнить файлы и .env на сервере с тем, что поставила бы программа.
function compareServer(sumsText, envText) {
  const remote = {};
  for (const line of String(sumsText).split('\n')) {
    const m = /^([0-9a-f]{64})\s+\*?(.+)$/.exec(line.trim());
    if (m) remote[m[2].replace(/^\.\//, '')] = m[1];
  }
  const local = localSums();
  const changed = Object.keys(remote).filter((f) => local[f] && local[f] !== remote[f]);
  const added = Object.keys(remote).filter((f) => !local[f] && !/^package-lock\.json$/.test(f));
  const missing = Object.keys(local).filter((f) => !remote[f] && f !== 'package-lock.json');
  const env = {};
  for (const line of String(envText).split('\n')) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (m) env[m[1]] = m[2].trim();
  }
  const clean = (v) => String(v ?? '').replace(/[\r\n]+/g, ' ').replace(/"/g, "'").trim();
  const envDiff = KEYS.filter((k) => k in env && env[k] !== clean(settings.env[k])).map((k) => ({ k, server: env[k], app: clean(settings.env[k]) }));
  const envExtra = Object.keys(env).filter((k) => !KEYS.includes(k) && k !== 'BOT_TOKEN');
  return { changed, added, missing, env, envDiff, envExtra };
}

function envFileText(token) {
  // Значения — одной строкой, без кавычек: так их одинаково прочитает node --env-file.
  const clean = (v) => String(v ?? '').replace(/[\r\n]+/g, ' ').replace(/"/g, "'").trim();
  const lines = ['# Настройки бота — записаны приложением OLX Watcher для ПК.', `BOT_TOKEN=${clean(token)}`];
  for (const k of KEYS) lines.push(`${k}=${clean(settings.env[k])}`);
  return lines.join('\n') + '\n';
}

let deploying = false;
async function deployToServer(opts) {
  const { host, port, username } = opts;
  const password = serverPassword(opts);
  if (deploying) return { ok: false, error: 'Установка уже идёт.' };
  const token = getToken();
  if (!token) return { ok: false, error: 'Сначала вставьте токен бота во вкладке «Настройки».' };
  if (!host || !password) return { ok: false, error: 'Нужны IP сервера и пароль.' };
  deploying = true;
  const out = (t) => send('deploy-log', t);
  const { Client } = require('ssh2');
  const conn = new Client();
  const wasRunning = !!bot.child;
  try {
    out(`Подключаюсь к ${host}…\n`);
    await new Promise((resolve, reject) => {
      conn.once('ready', resolve).once('error', reject)
        .connect({ host: String(host).trim(), port: Number(port) || 22, username: String(username || 'root').trim(), password, readyTimeout: 25000, keepaliveInterval: 15000 });
    });
    const exec = (cmd, quiet = false) => new Promise((resolve, reject) => {
      conn.exec(cmd, (err, stream) => {
        if (err) return reject(err);
        let code = null;
        let text = '';
        const onData = (d) => { text += d; if (!quiet) out(d.toString()); };
        stream.on('data', onData);
        stream.stderr.on('data', onData);
        stream.on('exit', (c) => { code = c; });
        stream.on('close', () => resolve({ code, text }));
      });
    });
    out('Подключился.\n');
    const who = await exec('id -u', true);
    if (who.text.trim() !== '0') throw new Error('Нужен пользователь root (или с правами root). Войдите как root.');
    if ((await exec('command -v systemctl >/dev/null && echo yes', true)).text.trim() !== 'yes') throw new Error('На сервере нет systemd — нужен обычный Linux (Ubuntu / Debian).');
    // База на сервере «своя» только после удачной установки (есть служба). Иначе — это остаток
    // прошлой неудачной попытки, и свежая с ПК важнее.
    const hadDb = (await exec(`test -f ${REMOTE_DIR}/data/watcher.db && test -f /etc/systemd/system/olx-watcher.service && echo yes`, true)).text.trim() === 'yes';

    // На сервере правили файлы или .env вручную — без подтверждения не перезаписываем.
    if (!opts.force) {
      const sums = await exec(`cd ${REMOTE_DIR} 2>/dev/null && find src deploy package.json -type f -exec sha256sum {} + 2>/dev/null`, true);
      const envT = await exec(`cat ${REMOTE_DIR}/.env 2>/dev/null`, true);
      if (sums.text.trim()) {
        const c = compareServer(sums.text, envT.text);
        if (c.changed.length || c.added.length || c.envExtra.length) {
          out('На сервере есть ручные изменения — установка их перезапишет. Подтвердите в окне.\n');
          return { ok: false, needConfirm: true, changed: c.changed, added: c.added, envExtra: c.envExtra };
        }
      }
    }

    // Один токен — одна копия: бот на ПК останавливаем до запуска на сервере.
    if (bot.child) { out('Останавливаю бота на этом компьютере…\n'); await stopBot(); }

    const files = botFiles();
    const dirs = [...new Set(files.map((f) => path.posix.dirname(f)).filter((d) => d !== '.'))];
    await exec(`mkdir -p ${REMOTE_DIR}/data ${dirs.map((d) => `'${REMOTE_DIR}/${d}'`).join(' ')}`, true);
    // Файлы — по SFTP, а если он на сервере выключен — через «cat > файл».
    const sftp = await new Promise((resolve) => conn.sftp((e, s) => resolve(e ? null : s)));
    const put = (remote, data) => new Promise((resolve, reject) => {
      if (sftp) return sftp.writeFile(remote, data, (e) => (e ? reject(e) : resolve()));
      conn.exec(`cat > '${remote.replace(/'/g, "'\\''")}'`, (err, stream) => {
        if (err) return reject(err);
        let code = null;
        stream.on('exit', (c) => { code = c; });
        stream.on('close', () => (code === 0 ? resolve() : reject(new Error(`не удалось записать ${remote}`))));
        stream.stderr.on('data', () => {});
        stream.on('data', () => {});
        stream.end(data);
      });
    });
    out(`Загружаю бота (${files.length} файлов) в ${REMOTE_DIR}…\n`);
    // Сборка для Windows может хранить текстовые файлы с переносами CRLF — Linux их не понимает
    // («set: pipefail\r: invalid option»). Текст отправляем с переносами LF.
    for (const f of files) await put(`${REMOTE_DIR}/${f}`, botFileData(f));
    await put(`${REMOTE_DIR}/.env`, envFileText(token));
    out('Настройки (токен, цены, реквизиты) записаны.\n');

    // База — только при первой установке: на сервере уже работающую не перезаписываем.
    const dbFile = path.join(app.getPath('userData'), 'watcher.db');
    if (!hadDb) closeDbHandle();
    if (!hadDb && fs.existsSync(dbFile)) {
      out('Переношу подписчиков, поиски и оплаты…\n');
      await put(`${REMOTE_DIR}/data/watcher.db`, fs.readFileSync(dbFile));
    } else if (hadDb) {
      out('На сервере уже есть база — оставляю её (подписчики и оплаты там свежее).\n');
    }

    out('\nУстанавливаю и запускаю (1–3 минуты)…\n');
    const r = await exec(`cd ${REMOTE_DIR} && sed -i 's/\\r$//' deploy/*.sh deploy/*.service && bash deploy/install.sh 2>&1`);
    const active = (await exec('systemctl is-active olx-watcher', true)).text.trim() === 'active';
    if (r.code !== 0 || !active) throw new Error('Бот на сервере не запустился — смотрите строки выше.');

    settings.server = { host: String(host).trim(), port: Number(port) || 22, username: String(username || 'root').trim(), at: Date.now() };
    rememberUpdateHost(host);
    settings.autoStart = false;   // на ПК больше не запускаем сам — бот живёт на сервере
    bot.wanted = false;
    saveSettings();
    pushState();
    out(`\n✅ Готово: бот работает на сервере ${host} круглосуточно. На этом компьютере он выключен.\n`);
    return { ok: true };
  } catch (e) {
    const msg = /authentication/i.test(e.message) ? 'Неверный логин или пароль от сервера.'
      : /ECONNREFUSED|ETIMEDOUT|EHOSTUNREACH|ENOTFOUND|Timed out/i.test(e.message) ? `Не удалось подключиться к ${host}: проверьте IP и что сервер включён.`
        : e.message;
    out(`\n✖ ${msg}\n`);
    if (wasRunning && !bot.child) { out('Бот на этом компьютере снова запущен.\n'); startBot(); }
    return { ok: false, error: msg };
  } finally {
    deploying = false;
    conn.end();
  }
}

ipcMain.handle('deploy', (_e, opts) => deployToServer(opts || {}));

// Вернуть бота с сервера на ПК: на сервере — остановить и выключить автозапуск службы (файлы
// остаются), свежую базу — забрать сюда (прежнюю копию на ПК сохраняем рядом), бот — запустить тут.
async function bringBack(opts) {
  const { host, port, username } = opts;
  const password = serverPassword(opts);
  if (deploying) return { ok: false, error: 'Уже идёт работа с сервером.' };
  if (!host || !password) return { ok: false, error: 'Нужны IP сервера и пароль.' };
  deploying = true;
  const out = (t) => send('deploy-log', t);
  const { Client } = require('ssh2');
  const conn = new Client();
  try {
    out(`Подключаюсь к ${host}…\n`);
    await new Promise((resolve, reject) => {
      conn.once('ready', resolve).once('error', reject)
        .connect({ host: String(host).trim(), port: Number(port) || 22, username: String(username || 'root').trim(), password, readyTimeout: 25000 });
    });
    const exec = (cmd) => new Promise((resolve, reject) => {
      conn.exec(cmd, (err, stream) => {
        if (err) return reject(err);
        const chunks = [];
        let code = null;
        stream.on('data', (d) => chunks.push(d));
        stream.stderr.on('data', () => {});
        stream.on('exit', (c) => { code = c; });
        stream.on('close', () => resolve({ code, data: Buffer.concat(chunks) }));
      });
    });
    out('Останавливаю бота на сервере…\n');
    await exec('systemctl stop olx-watcher; systemctl disable olx-watcher >/dev/null 2>&1; true');
    const db = await exec(`test -f ${REMOTE_DIR}/data/watcher.db && base64 -w0 ${REMOTE_DIR}/data/watcher.db`);
    const local = path.join(app.getPath('userData'), 'watcher.db');
    if (db.code === 0 && db.data.length) {
      await stopBot();
      closeDbHandle();
      if (fs.existsSync(local)) fs.copyFileSync(local, `${local}.before-server-${Date.now()}`);
      for (const ext of ['-wal', '-shm']) { try { fs.rmSync(local + ext); } catch { /* нет — и хорошо */ } }
      fs.writeFileSync(local, Buffer.from(db.data.toString('ascii').trim(), 'base64'));
      out('Забрал с сервера подписчиков, поиски и оплаты (прежняя копия на ПК сохранена рядом).\n');
    } else {
      out('Базы на сервере нет — остаётся та, что на ПК.\n');
    }
    settings.server = null;
    settings.autoStart = true;
    saveSettings();
    startBot();
    pushState();
    out('\n✅ Бот снова работает на этом компьютере. На сервере он остановлен (файлы остались).\n');
    return { ok: true };
  } catch (e) {
    const msg = /authentication/i.test(e.message) ? 'Неверный логин или пароль от сервера.' : e.message;
    out(`\n✖ ${msg}\n`);
    return { ok: false, error: msg };
  } finally {
    deploying = false;
    conn.end();
  }
}

ipcMain.handle('bring-back', (_e, opts) => bringBack(opts || {}));

// Пароль сервера — по желанию, зашифрованным средствами Windows (как токен). Пустой пароль
// в окне — берём сохранённый.
function serverPassword(opts) {
  if (opts.password) {
    if (opts.remember && safeStorage.isEncryptionAvailable()) settings.serverPassEnc = safeStorage.encryptString(opts.password).toString('base64');
    else if (opts.remember === false) delete settings.serverPassEnc;
    saveSettings();
    return opts.password;
  }
  if (settings.serverPassEnc && safeStorage.isEncryptionAvailable()) {
    try { return safeStorage.decryptString(Buffer.from(settings.serverPassEnc, 'base64')); } catch { return ''; }
  }
  return '';
}

// Сервер, с которым получилось соединиться, — он же источник обновлений (со следующего запуска).
function rememberUpdateHost(host) {
  const h = String(host || '').trim();
  if (h && settings.updateHost !== h) { settings.updateHost = h; saveSettings(); }
}

// Одна команда на сервере: вывод целиком.
async function sshRun(opts, cmd) {
  const password = serverPassword(opts);
  if (!opts.host || !password) throw new Error('Нужны IP сервера и пароль.');
  const { Client } = require('ssh2');
  const conn = new Client();
  try {
    await new Promise((resolve, reject) => {
      conn.once('ready', resolve).once('error', reject)
        .connect({ host: String(opts.host).trim(), port: Number(opts.port) || 22, username: String(opts.username || 'root').trim(), password, readyTimeout: 20000 });
    });
    rememberUpdateHost(opts.host);
    return await new Promise((resolve, reject) => {
      conn.exec(cmd, (err, stream) => {
        if (err) return reject(err);
        let text = '';
        stream.on('data', (d) => { text += d; });
        stream.stderr.on('data', (d) => { text += d; });
        stream.on('close', () => resolve(text));
      });
    });
  } catch (e) {
    throw new Error(/authentication/i.test(e.message) ? 'Неверный логин или пароль от сервера.'
      : /ECONNREFUSED|ETIMEDOUT|EHOSTUNREACH|ENOTFOUND|Timed out/i.test(e.message) ? `Не удалось подключиться к ${opts.host}.` : e.message);
  } finally {
    conn.end();
  }
}

// Статус бота на сервере: работает ли, с какого времени, сколько 403 от площадок за час, журнал.
const STATUS_CMD = [
  'echo "STATE=$(systemctl is-active olx-watcher 2>/dev/null)"',
  'echo "SINCE=$(systemctl show olx-watcher -p ActiveEnterTimestamp --value 2>/dev/null)"',
  'echo "BLOCK=$(journalctl -u olx-watcher --since \'1 hour ago\' --no-pager -o cat 2>/dev/null | grep -ci \'ограничил запросы\')"',
  'echo "OLXBLOCK=$(journalctl -u olx-watcher --since \'1 hour ago\' --no-pager -o cat 2>/dev/null | grep -i \'ограничил запросы\' | grep -ci olx)"',
  'echo "MEM=$(free -m 2>/dev/null | awk \'/Mem:/{print $3\"/\"$2\" МБ\"}\')"',
  'echo ---LOG---',
  'journalctl -u olx-watcher -n 30 --no-pager -o short-iso 2>/dev/null | cut -c1-240',
].join('; ');

ipcMain.handle('server-status', async (_e, opts = {}) => {
  try {
    const text = await sshRun(opts, STATUS_CMD);
    const val = (k) => (new RegExp(`^${k}=(.*)$`, 'm').exec(text) || [])[1]?.trim() || '';
    return {
      ok: true, state: val('STATE'), since: val('SINCE'), blocks: Number(val('BLOCK')) || 0,
      olxBlocks: Number(val('OLXBLOCK')) || 0, mem: val('MEM'), log: text.split('---LOG---')[1]?.trim() || '',
    };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

// «Проверить сервер»: только чтение. Служба, Node.js, диск и память, настройки (токен скрыт) и
// отличия от программы, изменённые вручную файлы, доступность площадок с сервера, база.
const CHECK_CMD = `cd ${REMOTE_DIR} 2>/dev/null || { echo NODIR; exit 0; }
echo "STATE=$(systemctl is-active olx-watcher 2>/dev/null)"
echo "SINCE=$(systemctl show olx-watcher -p ActiveEnterTimestamp --value 2>/dev/null)"
NODEBIN=$(grep -o '^ExecStart=[^ ]*' /etc/systemd/system/olx-watcher.service 2>/dev/null | cut -d= -f2)
echo "NODEV=$($NODEBIN -v 2>/dev/null)"
echo "DISK=$(df -h ${REMOTE_DIR} | awk 'NR==2{print $4" свободно из "$2}')"
echo "MEM=$(free -m | awk '/Mem:/{print $3"/"$2" МБ"}')"
echo ---ENV---
sed 's/^BOT_TOKEN=.*/BOT_TOKEN=(скрыт)/' .env 2>/dev/null
echo ---SUMS---
find src deploy package.json -type f -exec sha256sum {} + 2>/dev/null
echo ---NET---
for u in https://www.olx.kz/ https://kolesa.kz/ https://krisha.kz/ https://obyavleniya.kaspi.kz/ https://api.telegram.org/; do
  if command -v curl >/dev/null; then c=$(curl -s -o /dev/null -m 12 -A 'Mozilla/5.0' -w '%{http_code}' "$u"); else c=нет-curl; fi
  echo "$u $c"
done
echo ---DB---
[ -n "$NODEBIN" ] && $NODEBIN --no-warnings -e "const {DatabaseSync}=require('node:sqlite');const d=new DatabaseSync('data/watcher.db',{readOnly:true});for(const t of ['users','subs','payments','vip_locks'])try{console.log(t+'='+d.prepare('SELECT COUNT(*) n FROM '+t).get().n)}catch{}" 2>/dev/null
echo ---END---`;

ipcMain.handle('server-check', async (_e, opts = {}) => {
  try {
    const text = await sshRun(opts, CHECK_CMD);
    if (/^NODIR/m.test(text)) return { ok: false, error: `На сервере нет папки ${REMOTE_DIR} — бот туда не установлен.` };
    const part = (a, b) => (text.split(`---${a}---`)[1] || '').split(`---${b}---`)[0].trim();
    const val = (k) => (new RegExp(`^${k}=(.*)$`, 'm').exec(text) || [])[1]?.trim() || '';
    const c = compareServer(part('SUMS', 'NET'), part('ENV', 'SUMS'));
    const net = part('NET', 'DB').split('\n').filter(Boolean).map((l) => { const [u, code] = l.split(' '); return { host: new URL(u).host, code }; });
    const db = Object.fromEntries(part('DB', 'END').split('\n').filter((l) => l.includes('=')).map((l) => l.split('=')));
    return { ok: true, state: val('STATE'), since: val('SINCE'), node: val('NODEV'), disk: val('DISK'), mem: val('MEM'), ...c, net, db };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('server-restart', async (_e, opts = {}) => {
  try {
    await sshRun(opts, 'systemctl restart olx-watcher; sleep 3; systemctl is-active olx-watcher');
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});



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
