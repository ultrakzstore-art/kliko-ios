// SQLite (встроен в Node 22): пользователи и их доступ, поиски, отправленное, платежи.
//
// Новизна объявления для поиска — по «водяной отметке» (номера объявлений растут): новым
// для поиска считается номер больше его отметки, которого ему ещё не отправляли. Так у
// бесплатного поиска (раз в 10 минут) и платного (раз в 30 секунд) своя новизна.

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
    `);
    // Миграции с личной версии: у поиска появляется хозяин и водяная отметка.
    const cols = this.db.prepare('PRAGMA table_info(subs)').all().map((c) => c.name);
    if (!cols.includes('user_id')) this.db.exec('ALTER TABLE subs ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0');
    if (!cols.includes('watermark')) this.db.exec('ALTER TABLE subs ADD COLUMN watermark INTEGER NOT NULL DEFAULT 0');
    this.db.exec('DROP TABLE IF EXISTS seen');
    const ucols = this.db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
    if (!ucols.includes('trial_until')) this.db.exec('ALTER TABLE users ADD COLUMN trial_until INTEGER NOT NULL DEFAULT 0');
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

  isPaid(userOrId, now = Date.now()) {
    const u = typeof userOrId === 'object' ? userOrId : this.user(userOrId);
    return !!u && u.paid_until > now;
  }

  // Тестовый доступ: ещё не оплачено, но срок теста не вышел.
  isTrial(userOrId, now = Date.now()) {
    const u = typeof userOrId === 'object' ? userOrId : this.user(userOrId);
    return !!u && !this.isPaid(u, now) && u.trial_until > now;
  }

  hasAccess(userOrId, now = Date.now()) {
    return this.isPaid(userOrId, now) || this.isTrial(userOrId, now);
  }

  // Продление считается от конца текущего срока, если он ещё идёт, — оплаченное не сгорает.
  extend(userId, days) {
    const u = this.user(userId);
    const from = Math.max(Date.now(), u ? u.paid_until : 0);
    const until = from + days * DAY;
    this.db.prepare('UPDATE users SET paid_until = ? WHERE id = ?').run(until, userId);
    return until;
  }

  setBlocked(userId, blocked) {
    this.db.prepare('UPDATE users SET blocked = ? WHERE id = ?').run(blocked ? 1 : 0, userId);
  }

  // ---------- платежи ----------

  addPayment(p) {
    const r = this.db.prepare(`INSERT INTO payments (user_id, method, days, amount, status, charge_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)`).run(p.userId, p.method, p.days, p.amount || 0, p.status, p.chargeId || '', Date.now());
    return this.payment(Number(r.lastInsertRowid));
  }

  payment(id) {
    return this.db.prepare('SELECT * FROM payments WHERE id = ?').get(id) || null;
  }

  setPaymentStatus(id, status) {
    this.db.prepare('UPDATE payments SET status = ? WHERE id = ?').run(status, id);
  }

  paidTotals() {
    return this.db.prepare(`SELECT method, COUNT(*) AS n, SUM(amount) AS sum FROM payments WHERE status = 'paid' GROUP BY method`).all();
  }

  // ---------- поиски ----------

  addSub(userId, name, url) {
    const r = this.db.prepare('INSERT INTO subs (user_id, name, url, created_at) VALUES (?, ?, ?, ?)').run(userId, name, url, Date.now());
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
    const allowed = ['name', 'paused', 'initialized', 'learned', 'last_poll', 'last_error', 'sent', 'watermark', 'user_id'];
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
  }
}

module.exports = { Db, DAY };
