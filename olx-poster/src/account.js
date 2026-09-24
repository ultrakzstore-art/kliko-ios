// Аккаунт OLX: вход прямо в окне приложения, проверка «вошли ли», выход.
// Проверяем честно, без угадывания куки: открываем «Мой профиль» в невидимом окне той же
// сессии. Вошедшего OLX пускает, остальных уводит на страницу входа.

const { BrowserWindow } = require('electron');

const MY_ACCOUNT_URL = 'https://www.olx.kz/myaccount/';

// Страницы входа OLX и чужие окна входа (Google, Facebook, Apple), которым нужен настоящий
// всплывающий попап: они передают результат обратно в OLX через window.opener.
const LOGIN_POPUP_HOSTS = /(^|\.)(login\.olx\.kz|accounts\.google\.com|facebook\.com|appleid\.apple\.com)$/i;

function isLoginUrl(url) {
  try {
    const u = new URL(url);
    return /^login\./i.test(u.hostname) || (/\/(account|login)(\/|$)/i.test(u.pathname) && !/\/myaccount/i.test(u.pathname));
  } catch {
    return false;
  }
}

class Account {
  constructor(session, log) {
    this.session = session;
    this.log = log;
    this.loggedIn = null; // null — ещё не знаем (нет сети или проверка не закончилась)
    this.checking = null;
    this.listeners = new Set();
  }

  onChange(fn) { this.listeners.add(fn); }

  set(value) {
    if (value === this.loggedIn) return;
    this.loggedIn = value;
    if (value === true) this.log('OLX: вход выполнен');
    if (value === false) this.log('OLX: не выполнен вход в аккаунт');
    for (const fn of this.listeners) fn(value);
  }

  // Несколько одновременных вызовов делят одну проверку.
  check() {
    if (!this.checking) this.checking = this.probe().finally(() => { this.checking = null; });
    return this.checking;
  }

  async probe() {
    const w = new BrowserWindow({ show: false, width: 1200, height: 800, webPreferences: { session: this.session, sandbox: true } });
    try {
      // Страница ошибки Chromium сохраняет адрес OLX, поэтому смотрим на сбой загрузки
      // и код ответа последнего перехода, а не только на адрес.
      let failed = false;
      let httpCode = 0;
      w.webContents.on('did-fail-load', (_e, code, _desc, _url, isMainFrame) => { if (isMainFrame && code !== -3) failed = true; });
      w.webContents.on('did-navigate', (_e, _url, code) => { httpCode = code; });
      const done = new Promise((resolve) => {
        const t = setTimeout(resolve, 25_000);
        w.webContents.on('did-stop-loading', () => { clearTimeout(t); setTimeout(resolve, 800); });
      });
      await w.loadURL(MY_ACCOUNT_URL).catch(() => {});
      await done;
      const url = w.webContents.getURL();
      const reachable = !failed && httpCode >= 200 && httpCode < 400 && /^https?:\/\/([^/]+\.)?olx\.kz\//i.test(url);
      if (!reachable) { this.set(null); return null; } // нет сети или OLX не ответил
      const ok = !isLoginUrl(url);
      this.set(ok);
      return ok;
    } catch {
      this.set(null);
      return null;
    } finally {
      w.destroy();
    }
  }

  async logout() {
    await this.session.clearStorageData();
    await this.session.clearCache();
    this.set(false);
    this.log('OLX: вышли из аккаунта, данные входа удалены');
  }
}

module.exports = { Account, MY_ACCOUNT_URL, LOGIN_POPUP_HOSTS, isLoginUrl };
