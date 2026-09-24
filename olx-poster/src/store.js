// Настройки и очередь объявлений — JSON-файлы в папке данных приложения.
// Фото каждого товара лежат в items/<id>/, в очереди — только пути и статусы.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { app, safeStorage } = require('electron');

const DEFAULTS = {
  apiKeyEnc: '',            // ключ Claude API, зашифрован safeStorage (DPAPI на Windows)
  model: 'claude-opus-5',
  effort: 'medium',         // глубина размышлений робота-подачи: low | medium | high
  intervalMin: 5,           // одно объявление раз в N минут
  workStart: '09:00',       // окно работы — 10 часов по умолчанию
  workEnd: '19:00',
  inboxDir: '',             // папка, куда падают фото (OneDrive/Google Диск/USB)
  groupGapSec: 90,          // свободные фото в папке, снятые с разрывом меньше этого, — один товар
  city: 'Алматы',
  contactName: '',
  phone: '',
  priceHint: 'Цены — как у похожих б/у товаров на OLX.kz, чуть ниже рынка, чтобы продалось быстро.',
  extraRules: '',           // свободные правила продавца: «всегда пиши „торг уместен“» и т.п.
  running: false,           // расписание включено
};

// Статусы товара: new → describing → ready → posting → published | failed | needs_user
class Store {
  constructor() {
    this.dir = app.getPath('userData');
    this.itemsDir = path.join(this.dir, 'items');
    fs.mkdirSync(this.itemsDir, { recursive: true });
    this.settingsFile = path.join(this.dir, 'settings.json');
    this.queueFile = path.join(this.dir, 'queue.json');
    this.notesFile = path.join(this.dir, 'olx-notes.txt');
    this.settings = { ...DEFAULTS, inboxDir: path.join(app.getPath('pictures'), 'OLX') };
    Object.assign(this.settings, readJson(this.settingsFile, {}));
    this.items = readJson(this.queueFile, []);
    // Пачки: куча фото разом, которую Claude ещё не разложил по товарам.
    this.batchesFile = path.join(this.dir, 'batches.json');
    this.batchesDir = path.join(this.dir, 'batches');
    this.batches = readJson(this.batchesFile, []);
    // После падения посреди работы — вернуть «зависшие» статусы в очередь.
    for (const it of this.items) {
      if (it.status === 'describing') it.status = 'new';
      if (it.status === 'posting') it.status = 'ready';
    }
    this.listeners = new Set();
  }

  onChange(fn) { this.listeners.add(fn); }
  emit() { for (const fn of this.listeners) fn(); }

  saveSettings(patch) {
    Object.assign(this.settings, patch);
    writeJson(this.settingsFile, this.settings);
    this.emit();
  }

  getApiKey() {
    const enc = this.settings.apiKeyEnc;
    if (!enc) return process.env.ANTHROPIC_API_KEY || '';
    try {
      return safeStorage.decryptString(Buffer.from(enc, 'base64'));
    } catch {
      return '';
    }
  }

  setApiKey(key) {
    const trimmed = (key || '').trim();
    const enc = trimmed && safeStorage.isEncryptionAvailable()
      ? safeStorage.encryptString(trimmed).toString('base64')
      : '';
    this.saveSettings({ apiKeyEnc: enc });
  }

  // Новый товар: копируем фото к себе, чтобы исходную папку можно было чистить.
  addItem(photoPaths, { source, note = '', price = null } = {}) {
    const id = new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14) + '-' + crypto.randomBytes(3).toString('hex');
    const dir = path.join(this.itemsDir, id);
    fs.mkdirSync(dir, { recursive: true });
    const photos = photoPaths.map((src, i) => {
      const dest = path.join(dir, `${String(i + 1).padStart(2, '0')}${path.extname(src).toLowerCase() || '.jpg'}`);
      fs.copyFileSync(src, dest);
      return dest;
    });
    const item = {
      id, photos, source, note, price,
      status: 'new', createdAt: Date.now(),
      listing: null, error: '', olxUrl: '', postedAt: null, attempts: 0, costUsd: 0,
    };
    this.items.push(item);
    this.saveQueue();
    return item;
  }

  // Пачка фото: копируем к себе, запоминаем время съёмки (файловое) — оно пригодится,
  // если раскладка через Claude не удастся и придётся делить по разрывам во времени.
  addBatch(photoPaths, { source }) {
    const id = new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14) + '-' + crypto.randomBytes(3).toString('hex');
    const dir = path.join(this.batchesDir, id);
    fs.mkdirSync(dir, { recursive: true });
    const photos = photoPaths.map((src, i) => {
      const dest = path.join(dir, `${String(i + 1).padStart(3, '0')}${path.extname(src).toLowerCase() || '.jpg'}`);
      fs.copyFileSync(src, dest);
      let mtime = Date.now();
      try { mtime = fs.statSync(src).mtimeMs; } catch {}
      return { path: dest, mtime };
    });
    const batch = { id, source, photos, attempts: 0, createdAt: Date.now() };
    this.batches.push(batch);
    this.saveBatches();
    return batch;
  }

  removeBatch(id) {
    this.batches = this.batches.filter((b) => b.id !== id);
    fs.rmSync(path.join(this.batchesDir, id), { recursive: true, force: true });
    this.saveBatches();
  }

  saveBatches() {
    writeJson(this.batchesFile, this.batches);
    this.emit();
  }

  update(id, patch) {
    const it = this.items.find((x) => x.id === id);
    if (!it) return null;
    Object.assign(it, patch);
    this.saveQueue();
    return it;
  }

  remove(id) {
    const it = this.items.find((x) => x.id === id);
    if (!it) return;
    this.items = this.items.filter((x) => x.id !== id);
    fs.rmSync(path.join(this.itemsDir, id), { recursive: true, force: true });
    this.saveQueue();
  }

  nextWith(status) {
    return this.items.find((x) => x.status === status) || null;
  }

  saveQueue() {
    writeJson(this.queueFile, this.items);
    this.emit();
  }

  // Заметки робота о форме OLX: что сработало в прошлый раз. Растут с опытом, но не бесконечно.
  readNotes() {
    try { return fs.readFileSync(this.notesFile, 'utf8'); } catch { return ''; }
  }

  appendNote(text) {
    const line = `- ${text.trim().replace(/\s+/g, ' ')}\n`;
    let notes = this.readNotes() + line;
    if (notes.length > 4000) notes = notes.slice(notes.length - 4000).replace(/^[^\n]*\n/, '');
    fs.writeFileSync(this.notesFile, notes);
  }
}

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJson(file, data) {
  const tmp = file + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, file);
}

module.exports = { Store };
