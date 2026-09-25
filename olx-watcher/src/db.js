// SQLite (встроен в Node 22): пользователи и их доступ, поиски, отправленное, платежи.
//
// Новизна объявления для поиска — по «водяной отметке» (номера объявлений растут): новым
// для поиска считается номер больше его отметки, которого ему ещё не отправляли. Так у
// каждого поиска своя новизна, даже если ссылка у двух людей одна.

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const DAY = 86400_000;

class Db {
  constructor(file) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    this.db = new DatabaseSync(file);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,               -- Telegram ID
        name TEXT NOT NULL DEFAULT '',
        username TEXT NOT NULL DEFAULT '',
        paid_until INTEGER NOT NULL DEFAULT 0,
        blocked INTEGER NOT NULL DEFAULT 0,   -- пользователь остановил бота
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS subs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        paused INTEGER NOT NULL DEFAULT 0,
        initialized INTEGER NOT NULL DEFAULT 0,
        learned TEXT NOT NULL DEFAULT '{}',
        last_poll INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        sent INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS sent (
        sub_id INTEGER NOT NULL,
        ad_id INTEGER NOT NULL,
        at INTEGER NOT NULL,
        PRIMARY KEY (sub_id, ad_id)
      );
      CREATE TABLE IF NOT EXISTS payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        method TEXT NOT NULL,                 -- stars | kaspi | admin
        days INTEGER NOT NULL,
        amount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,                 -- pending | paid | rejected
        charge_id TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS ad_prices (
        source TEXT NOT NULL,
        ad_id INTEGER NOT NULL,
        price REAL NOT NULL,                  -- последняя известная цена
        checked_at INTEGER NOT NULL,          -- когда последний раз видели цену
        PRIMARY KEY (source, ad_id)
      );
      CREATE TABLE IF NOT EXISTS discount_sent (
        sub_id INTEGER NOT NULL,
        ad_id INTEGER NOT NULL,
        price REAL NOT NULL,
        PRIMARY KEY (sub_id, ad_id, price)
      );
      CREATE TABLE IF NOT EXISTS vip_locks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,             -- VIP, за которым закреплена рубрика
        source TEXT NOT NULL DEFAULT 'olx',
        path TEXT NOT NULL,                   -- рубрика: elektronika/noutbuki-i-aksesuary
        city TEXT NOT NULL,                   -- город: almaty
        until INTEGER NOT NULL,
        category_ids TEXT NOT NULL DEFAULT '[]', -- номера рубрик OLX, выученные по выдаче VIP
        sub_id INTEGER NOT NULL DEFAULT 0,    -- поиск VIP по этой рубрике
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS access (
        user_id INTEGER NOT NULL,
        source TEXT NOT NULL,                 -- olx | kolesa | krisha | kaspi
        until INTEGER NOT NULL,
        PRIMARY KEY (user_id, source)
      );
    `);
    // Миграции с личной версии: у поиска появляется хозяин и водяная отметка.
    const cols = this.db.prepare('PRAGMA table_info(subs)').all().map((c) => c.name);
    if (!cols.includes('user_id')) this.db.exec('ALTER TABLE subs ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
    if (!cols.includes('watermark')) this.db.exec('ALTER TABLE subs ADD COLUMN watermark INTEGER NOT NULL DEFAULT 0');
    if (!cols.includes('source')) this.db.exec("ALTER TABLE subs ADD COLUMN source TEXT NOT NULL DEFAULT 'olx'");
    // Продавец: all — все, private — частные, business — бизнес-аккаунты.
    if (!cols.includes('seller')) this.db.exec("ALTER TABLE subs ADD COLUMN seller TEXT NOT NULL DEFAULT 'all'");
    const pcols = this.db.prepare('PRAGMA table_info(payments)').all().map((c) => c.name);
    if (!pcols.includes('product')) this.db.exec("ALTER TABLE payments ADD COLUMN product TEXT NOT NULL DEFAULT 'olx'");
    // Платный доступ до площадок был только к OLX — переносим его в таблицу доступа.
    this.db.exec(`INSERT OR IGNORE INTO access (user_id, source, until)
      SELECT id, 'olx', paid_until FROM users WHERE paid_until > 0`);
    this.db.exec('DROP TABLE IF EXISTS seen');
    const ucols = this.db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
    if (!ucols.includes('trial_until')) {
      this.db.exec('ALTER TABLE users ADD COLUMN trial_until INTEGER NOT NULL DEFAULT 0');
      // Кто был до появления теста — получает тест от момента обновления, а не нулевой.
      this.db.prepare('UPDATE users SET trial_until = ?').run(Date.now() + 7 * DAY);
    }
    this.trialMs = 7 * DAY;
  }

  get(k, fallback = null) {
    const r = this.db.prepare('SELECT v FROM kv WHERE k = ?').get(k);
    return r ? JSON.parse(r.v) : fallback;
  }

  set(k, v) {
    this.db.prepare('INSERT INTO kv (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').run(k, JSON.stringify(v));
  }

  // ---------- пользователи и доступ ----------

  // Новый пользователь сразу получает тестовый доступ на trialMs (TRIAL_DAYS).
  touchUser(id, name = '', username = '') {
    const now = Date.now();
    this.db.prepare(`INSERT INTO users (id, name, username, created_at, trial_until) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET name = excluded.name, username = excluded.username, blocked = 0`).run(id, name, username, now, now + this.trialMs);
    return this.user(id);
  }

  user(id) {
    return this.db.prepare('SELECT * FROM users WHERE id = ?').get(id) || null;
  }

  users() {
    return this.db.prepare('SELECT * FROM users ORDER BY created_at DESC').all();
  }

  // Платный доступ к площадке (source) или к любой (source = 'any').
  isPaid(userOrId, source = 'any', now = Date.now()) {
    const id = typeof userOrId === 'object' ? userOrId?.id : userOrId;
    if (id == null) return false;
    const row = source === 'any'
      ? this.db.prepare('SELECT MAX(until) AS until FROM access WHERE user_id = ?').get(id)
      : this.db.prepare('SELECT until FROM access WHERE user_id = ? AND source = ?').get(id, source);
    return !!row && (row.until || 0) > now;
  }

  paidUntil(userId, source) {
    const row = this.db.prepare('SELECT until FROM access WHERE user_id = ? AND source = ?').get(userId, source);
    return row ? row.until : 0;
  }

  accessList(userId) {
    return this.db.prepare('SELECT source, until FROM access WHERE user_id = ? AND until > ? ORDER BY source').all(userId, Date.now());
  }

  // Тестовый доступ: ни к одной площадке не оплачено, но срок теста не вышел. Даёт все площадки.
  isTrial(userOrId, now = Date.now()) {
    const u = typeof userOrId === 'object' ? userOrId : this.user(userOrId);
    return !!u && !this.isPaid(u, 'any', now) && u.trial_until > now;
  }

  hasAccess(userOrId, source = 'any', now = Date.now()) {
    return this.isPaid(userOrId, source, now) || this.isTrial(userOrId, now);
  }

  // Продление считается от конца текущего срока каждой площадки — оплаченное не сгорает.
  extend(userId, days, sources = ['olx']) {
    let last = 0;
    for (const src of sources) {
      const from = Math.max(Date.now(), this.paidUntil(userId, src));
      const until = from + days * DAY;
      this.db.prepare(`INSERT INTO access (user_id, source, until) VALUES (?, ?, ?)
        ON CONFLICT(user_id, source) DO UPDATE SET until = excluded.until`).run(userId, src, until);
      last = Math.max(last, until);
    }
    const max = this.db.prepare('SELECT MAX(until) AS m FROM access WHERE user_id = ?').get(userId).m || 0;
    this.db.prepare('UPDATE users SET paid_until = ? WHERE id = ?').run(max, userId);
    return last;
  }

  // Забрать доступ: платный по всем площадкам и тестовый — с этой минуты.
  revoke(userId, now = Date.now()) {
    this.db.prepare('UPDATE vip_locks SET until = ? WHERE user_id = ? AND until > ?').run(now, userId, now);
    this.db.prepare('UPDATE access SET until = ? WHERE user_id = ? AND until > ?').run(now, userId, now);
    this.db.prepare('UPDATE users SET trial_until = MIN(trial_until, ?), paid_until = MIN(paid_until, ?) WHERE id = ?').run(now, now, userId);
  }

  setBlocked(userId, blocked) {
    this.db.prepare('UPDATE users SET blocked = ? WHERE id = ?').run(blocked ? 1 : 0, userId);
  }

  // ---------- VIP-рубрики ----------
  // Рубрика + город закрепляется за одним VIP на срок. Пока закреплена — объявления из неё
  // получает только он (проверка по каждому объявлению в сборщике, см. Watcher.allowed).

  locks(now = Date.now()) {
    return this.db.prepare('SELECT * FROM vip_locks WHERE until > ? ORDER BY id').all(now)
      .map((l) => ({ ...l, category_ids: JSON.parse(l.category_ids) }));
  }

  // Пересекается ли с чужой закреплённой: тот же город и одна рубрика внутри другой.
  lockConflict(userId, source, path, city, now = Date.now()) {
    return this.locks(now).find((l) => l.user_id !== userId && l.source === source && l.city === city
      && (path === l.path || path.startsWith(`${l.path}/`) || l.path.startsWith(`${path}/`))) || null;
  }

  // Закрепить или продлить (у того же VIP — от конца текущего срока).
  addLock(userId, source, path, city, days, subId = 0, now = Date.now()) {
    const conflict = this.lockConflict(userId, source, path, city, now);
    if (conflict) return { ok: false, conflict };
    const mine = this.locks(now).find((l) => l.user_id === userId && l.source === source && l.path === path && l.city === city);
    if (mine) {
      const until = mine.until + days * DAY;
      this.db.prepare('UPDATE vip_locks SET until = ?, sub_id = CASE WHEN ? > 0 THEN ? ELSE sub_id END WHERE id = ?').run(until, subId, subId, mine.id);
      return { ok: true, id: mine.id, until };
    }
    const until = now + days * DAY;
    const r = this.db.prepare('INSERT INTO vip_locks (user_id, source, path, city, until, sub_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(userId, source, path, city, until, subId, now);
    return { ok: true, id: Number(r.lastInsertRowid), until };
  }

  endLock(id, now = Date.now()) {
    this.db.prepare('UPDATE vip_locks SET until = ? WHERE id = ? AND until > ?').run(now, id, now);
  }

  learnLock(id, categoryIds) {
    const row = this.db.prepare('SELECT category_ids FROM vip_locks WHERE id = ?').get(id);
    if (!row) return;
    const set = new Set(JSON.parse(row.category_ids));
    const before = set.size;
    for (const c of categoryIds) if (c) set.add(c);
    if (set.size !== before) this.db.prepare('UPDATE vip_locks SET category_ids = ? WHERE id = ?').run(JSON.stringify([...set]), id);
  }

  // ---------- платежи ----------

  addPayment(p) {
    const r = this.db.prepare(`INSERT INTO payments (user_id, method, days, amount, status, charge_id, created_at, product)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(p.userId, p.method, p.days, p.amount || 0, p.status, p.chargeId || '', Date.now(), p.product || 'olx');
    return this.payment(Number(r.lastInsertRowid));
  }

  payment(id) {
    return this.db.prepare('SELECT * FROM payments WHERE id = ?').get(id) || null;
  }

  setPaymentStatus(id, status) {
    this.db.prepare('UPDATE payments SET status = ? WHERE id = ?').run(status, id);
  }

  paidTotals() {
    return this.db.prepare(`SELECT method, product, COUNT(*) AS n, SUM(amount) AS sum FROM payments WHERE status = 'paid' GROUP BY method, product`).all();
  }

  // ---------- поиски ----------

  addSub(userId, name, url, source = 'olx', seller = 'all') {
    const r = this.db.prepare('INSERT INTO subs (user_id, name, url, source, seller, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(userId, name, url, source, seller, Date.now());
    return this.sub(Number(r.lastInsertRowid));
  }

  sub(id) {
    const r = this.db.prepare('SELECT * FROM subs WHERE id = ?').get(id);
    return r ? { ...r, learned: JSON.parse(r.learned) } : null;
  }

  subs(userId = null) {
    const rows = userId == null
      ? this.db.prepare('SELECT * FROM subs ORDER BY id').all()
      : this.db.prepare('SELECT * FROM subs WHERE user_id = ? ORDER BY id').all(userId);
    return rows.map((r) => ({ ...r, learned: JSON.parse(r.learned) }));
  }

  updateSub(id, patch) {
    const allowed = ['name', 'paused', 'initialized', 'learned', 'last_poll', 'last_error', 'sent', 'watermark', 'user_id', 'seller'];
    const keys = Object.keys(patch).filter((k) => allowed.includes(k));
    if (!keys.length) return;
    const vals = keys.map((k) => (k === 'learned' ? JSON.stringify(patch[k]) : patch[k]));
    this.db.prepare(`UPDATE subs SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`).run(...vals, id);
  }

  deleteSub(id) {
    this.db.prepare('DELETE FROM subs WHERE id = ?').run(id);
    this.db.prepare('DELETE FROM sent WHERE sub_id = ?').run(id);
  }

  // Отправлено ли этому поиску; true — отметили только что (раньше не отправляли).
  markSent(subId, adId) {
    return this.db.prepare('INSERT OR IGNORE INTO sent (sub_id, ad_id, at) VALUES (?, ?, ?)').run(subId, adId, Date.now()).changes > 0;
  }

  wasSent(subId, adId) {
    return !!this.db.prepare('SELECT 1 FROM sent WHERE sub_id = ? AND ad_id = ?').get(subId, adId);
  }

  prune() {
    this.db.prepare('DELETE FROM sent WHERE at < ?').run(Date.now() - 7 * DAY);
    this.db.prepare('DELETE FROM ad_prices WHERE checked_at < ?').run(Date.now() - 14 * DAY);
  }

  // ---------- цены и скидки ----------

  // Запомнить цену; вернуть прежнюю, если новая ниже (иначе null).
  notePrice(source, adId, price, now = Date.now()) {
    if (!(price > 0)) return null;
    const row = this.db.prepare('SELECT price FROM ad_prices WHERE source = ? AND ad_id = ?').get(source, adId);
    this.db.prepare(`INSERT INTO ad_prices (source, ad_id, price, checked_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(source, ad_id) DO UPDATE SET price = excluded.price, checked_at = excluded.checked_at`).run(source, adId, price, now);
    return row && price < row.price ? row.price : null;
  }

  // true — эту скидку (объявление + новая цена) этому поиску ещё не присылали; отмечаем.
  markDiscount(subId, adId, price) {
    return this.db.prepare('INSERT OR IGNORE INTO discount_sent (sub_id, ad_id, price) VALUES (?, ?, ?)').run(subId, adId, price).changes > 0;
  }

  // Объявления OLX, которые приходили за последние дни, — давно не проверенные первыми.
  toRecheck(limit, since = Date.now() - 3 * DAY) {
    return this.db.prepare(`SELECT DISTINCT s.ad_id AS id FROM sent s
      LEFT JOIN ad_prices p ON p.source = 'olx' AND p.ad_id = s.ad_id
      WHERE s.at > ? ORDER BY COALESCE(p.checked_at, 0) LIMIT ?`).all(since, limit).map((r) => r.id);
  }

  // Поиски, которым это объявление уже отправляли.
  subsSent(adId) {
    return this.db.prepare('SELECT sub_id FROM sent WHERE ad_id = ?').all(adId).map((r) => r.sub_id);
  }
}

module.exports = { Db, DAY };
