// Откуда берутся товары:
//  1) папка-«входящие» (куда синхронизируется камера телефона: OneDrive, Google Диск, USB);
//     подпапка = один товар, свободные фото группируются по времени съёмки;
//  2) страница для телефона в локальной сети (QR-код в приложении): сфоткал → «Отправить».

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const crypto = require('crypto');

const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif']);
const SETTLE_MS = 20_000; // файлы должны «успокоиться»: синхронизация могла ещё не докачать

function isImage(name) {
  return IMAGE_EXT.has(path.extname(name).toLowerCase());
}

class FolderIntake {
  constructor(store, log) {
    this.store = store;
    this.log = log;
    this.timer = null;
  }

  start() {
    this.stop();
    this.timer = setInterval(() => this.scan().catch((e) => this.log(`Папка: ${e.message}`)), 10_000);
    this.scan().catch(() => {});
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async scan() {
    const inbox = this.store.settings.inboxDir;
    if (!inbox) return;
    fs.mkdirSync(inbox, { recursive: true });
    const now = Date.now();
    const entries = fs.readdirSync(inbox, { withFileTypes: true });
    const done = path.join(inbox, '_добавлено');

    // Подпапки: одна папка — один товар. Имя папки — подсказка («кроссовки 42 15000»).
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('_')) continue;
      const dir = path.join(inbox, e.name);
      const files = listImages(dir);
      if (!files.length || files.some((f) => now - f.mtime < SETTLE_MS)) continue;
      const { note, price } = parseHint(e.name);
      const item = this.store.addItem(files.map((f) => f.path), { source: 'folder', note, price });
      moveInto(dir, done);
      this.log(`Новый товар из папки «${e.name}» (${files.length} фото) → ${item.id}`);
    }

    // Свободные фото: группируем по разрыву во времени между кадрами.
    const loose = listImages(inbox);
    if (!loose.length) return;
    if (now - loose[loose.length - 1].mtime < Math.max(SETTLE_MS, this.store.settings.groupGapSec * 1000)) return;
    const gap = this.store.settings.groupGapSec * 1000;
    const groups = [];
    for (const f of loose) {
      const last = groups[groups.length - 1];
      if (last && f.mtime - last[last.length - 1].mtime <= gap) last.push(f);
      else groups.push([f]);
    }
    fs.mkdirSync(done, { recursive: true });
    for (const g of groups) {
      const item = this.store.addItem(g.map((f) => f.path), { source: 'folder' });
      for (const f of g) moveInto(f.path, done);
      this.log(`Новый товар из свободных фото (${g.length} шт.) → ${item.id}`);
    }
  }
}

function listImages(dir) {
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && isImage(e.name))
    .map((e) => {
      const p = path.join(dir, e.name);
      return { path: p, mtime: fs.statSync(p).mtimeMs };
    })
    .sort((a, b) => a.mtime - b.mtime);
}

function moveInto(src, destDir) {
  fs.mkdirSync(destDir, { recursive: true });
  let dest = path.join(destDir, path.basename(src));
  if (fs.existsSync(dest)) dest = path.join(destDir, `${Date.now()}-${path.basename(src)}`);
  fs.renameSync(src, dest);
}

// «кроссовки nike 42 — 15000» → note «кроссовки nike 42», price 15000 (последнее число от 1000).
function parseHint(name) {
  const m = name.match(/(\d[\d\s]{3,})\s*(тг|тенге|₸)?\s*$/i);
  const price = m ? parseInt(m[1].replace(/\s/g, ''), 10) : null;
  const note = (m ? name.slice(0, m.index) : name).replace(/[-—_]+\s*$/, '').trim();
  return { note, price: price && price >= 100 ? price : null };
}

// ---------- Страница для телефона ----------

class PhoneIntake {
  constructor(store, log) {
    this.store = store;
    this.log = log;
    this.server = null;
    this.port = 0;
    this.token = crypto.randomBytes(6).toString('hex');
    this.page = fs.readFileSync(path.join(__dirname, 'phone', 'index.html'), 'utf8');
  }

  start(port = 8765) {
    this.server = http.createServer((req, res) => this.handle(req, res).catch((e) => {
      this.log(`Телефон: ${e.message}`);
      if (!res.headersSent) res.writeHead(500);
      res.end('error');
    }));
    return new Promise((resolve) => {
      this.server.once('error', () => this.server.listen(0, '0.0.0.0'));
      this.server.listen(port, '0.0.0.0', () => {
        this.port = this.server.address().port;
        resolve(this.urls());
      });
    });
  }

  urls() {
    const out = [];
    for (const list of Object.values(os.networkInterfaces())) {
      for (const a of list || []) {
        if (a.family === 'IPv4' && !a.internal) out.push(`http://${a.address}:${this.port}/?t=${this.token}`);
      }
    }
    return out;
  }

  async handle(req, res) {
    const url = new URL(req.url, 'http://x');
    if (url.searchParams.get('t') !== this.token) {
      res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Откройте ссылку из QR-кода в приложении.');
    }
    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(this.page);
    }
    if (req.method === 'GET' && url.pathname === '/queue') {
      const counts = {};
      for (const it of this.store.items) counts[it.status] = (counts[it.status] || 0) + 1;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify(counts));
    }
    if (req.method === 'POST' && url.pathname === '/upload') {
      // Тело — JSON { note, price, photos: [dataURL, …] }; фото уже ужаты на телефоне.
      const body = JSON.parse(await readBody(req, 60 * 1024 * 1024));
      const photos = (body.photos || []).slice(0, 8);
      if (!photos.length) throw new Error('нет фото');
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'olx-'));
      const files = photos.map((dataUrl, i) => {
        const m = /^data:image\/(\w+);base64,(.+)$/.exec(dataUrl);
        if (!m) throw new Error('не картинка');
        const p = path.join(tmp, `${i + 1}.${m[1] === 'jpeg' ? 'jpg' : m[1]}`);
        fs.writeFileSync(p, Buffer.from(m[2], 'base64'));
        return p;
      });
      const price = parseInt(String(body.price || '').replace(/\D/g, ''), 10) || null;
      const item = this.store.addItem(files, { source: 'phone', note: String(body.note || '').slice(0, 500), price });
      fs.rmSync(tmp, { recursive: true, force: true });
      this.log(`Новый товар с телефона (${files.length} фото) → ${item.id}`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ ok: true, id: item.id }));
    }
    res.writeHead(404);
    res.end();
  }
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { reject(new Error('слишком большой запрос')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

module.exports = { FolderIntake, PhoneIntake, parseHint };
