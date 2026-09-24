// SQLite (встроен в Node 22): подписки, уже виденные объявления, служебные значения.

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

class Db {
  constructor(file) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    this.db = new DatabaseSync(file);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS subs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        paused INTEGER NOT NULL DEFAULT 0,
        initialized INTEGER NOT NULL DEFAULT 0,
        learned TEXT NOT NULL DEFAULT '{}',   -- рубрики и город, выученные по выдаче поиска
        last_poll INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        sent INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS seen (
        ad_id INTEGER PRIMARY KEY,
        seen_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
    `);
  }

  get(k, fallback = null) {
    const r = this.db.prepare('SELECT v FROM kv WHERE k = ?').get(k);
    return r ? JSON.parse(r.v) : fallback;
  }

  set(k, v) {
    this.db.prepare('INSERT INTO kv (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').run(k, JSON.stringify(v));
  }

  addSub(name, url) {
    const r = this.db.prepare('INSERT INTO subs (name, url, created_at) VALUES (?, ?, ?)').run(name, url, Date.now());
    return this.sub(Number(r.lastInsertRowid));
  }

  sub(id) {
    const r = this.db.prepare('SELECT * FROM subs WHERE id = ?').get(id);
    return r ? { ...r, learned: JSON.parse(r.learned) } : null;
  }

  subs() {
    return this.db.prepare('SELECT * FROM subs ORDER BY id').all().map((r) => ({ ...r, learned: JSON.parse(r.learned) }));
  }

  updateSub(id, patch) {
    const keys = Object.keys(patch);
    if (!keys.length) return;
    const vals = keys.map((k) => (k === 'learned' ? JSON.stringify(patch[k]) : patch[k]));
    this.db.prepare(`UPDATE subs SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`).run(...vals, id);
  }

  deleteSub(id) {
    this.db.prepare('DELETE FROM subs WHERE id = ?').run(id);
  }

  // true — объявление новое (и теперь помечено виденным), false — уже было.
  markSeen(adId) {
    const r = this.db.prepare('INSERT OR IGNORE INTO seen (ad_id, seen_at) VALUES (?, ?)').run(adId, Date.now());
    return r.changes > 0;
  }

  isSeen(adId) {
    return !!this.db.prepare('SELECT 1 FROM seen WHERE ad_id = ?').get(adId);
  }

  // Старые записи «видели» не нужны: объявление старше недели заново в выдачу «новые» не попадёт.
  prune() {
    this.db.prepare('DELETE FROM seen WHERE seen_at < ?').run(Date.now() - 7 * 86400_000);
  }
}

module.exports = { Db };
