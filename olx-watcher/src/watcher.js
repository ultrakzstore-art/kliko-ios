// Два источника новых объявлений:
//  • поиск — ссылки, которые вы добавили, проверяются «сначала новые» раз в POLL_SEC;
//  • турбо — номера объявлений сквозные, поэтому следующие номера после самого свежего
//    известного проверяются напрямую, раз в TURBO_SEC. Так объявление ловится до того,
//    как попадёт в поиск (в том числе пока оно на проверке).
// Оба источника пишут в одну таблицу «видели» — одно объявление приходит один раз.

const olx = require('./olx');
const { learn, matches } = require('./match');

const FRESH_MS = 60 * 60_000;     // «Топ»-объявления бывают старыми: такие не считаем новыми
const MISS_GIVE_UP = 12;          // номер пустой 12 проверок подряд — пропускаем его

class Watcher {
  constructor({ db, config, notify, alert, log }) {
    this.db = db;
    this.cfg = config;
    this.notify = notify;   // (ad, subs[], via) → отправить в Телеграм
    this.alert = alert;     // (text) → служебное сообщение владельцу
    this.log = log;
    this.frontier = db.get('frontier', 0);  // самый большой известный номер объявления
    this.misses = new Map();                // номер → сколько раз оказался пустым
    this.backoffUntil = 0;
    this.backoffMs = 0;
    this.stats = { searchOk: 0, searchErr: 0, turboFound: 0, turboProbes: 0, lastTurboHit: null };
    this.timers = [];
  }

  start() {
    this.timers.push(setInterval(() => this.searchTick().catch((e) => this.log(`поиск: ${e.message}`)), 5_000));
    this.timers.push(setInterval(() => this.turboTick().catch((e) => this.log(`турбо: ${e.message}`)), this.cfg.turboSec * 1000));
    this.timers.push(setInterval(() => this.db.prune(), 6 * 3600_000));
  }

  stop() {
    this.timers.forEach(clearInterval);
  }

  // Бережём себя от блокировки: на 403/429 OLX отдыхаем, с каждым разом дольше (до 15 мин).
  blocked() {
    return Date.now() < this.backoffUntil;
  }

  handleError(e) {
    if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) {
      this.backoffMs = Math.min(15 * 60_000, this.backoffMs ? this.backoffMs * 2 : 60_000);
      this.backoffUntil = Date.now() + this.backoffMs;
      this.alert(`OLX ограничил запросы (${e.status}). Пауза ${Math.round(this.backoffMs / 60_000)} мин. Если повторяется — увеличьте POLL_SEC или включите прокси.`);
      return true;
    }
    return false;
  }

  okRequest() {
    this.backoffMs = 0;
  }

  bumpFrontier(id) {
    if (id > this.frontier) {
      this.frontier = id;
      this.db.set('frontier', id);
    }
  }

  // ---------- поиск ----------

  async searchTick() {
    if (this.searchBusy || this.blocked()) return;
    this.searchBusy = true;
    try {
      const now = Date.now();
      const due = this.db.subs().filter((s) => !s.paused && now - s.last_poll >= this.cfg.pollSec * 1000);
      for (const sub of due) {
        if (this.blocked()) break;
        await this.pollSub(sub);
        await sleep(1500 + Math.random() * 1500); // не долбим OLX пачкой запросов
      }
    } finally {
      this.searchBusy = false;
    }
  }

  async pollSub(sub) {
    let result;
    try {
      result = await olx.fetchSearch(sub.url);
      this.okRequest();
      this.stats.searchOk += 1;
    } catch (e) {
      this.stats.searchErr += 1;
      this.db.updateSub(sub.id, { last_poll: Date.now(), last_error: e.message });
      if (!this.handleError(e)) this.log(`«${sub.name}»: ${e.message}`);
      return;
    }
    const ads = result.ads;
    for (const a of ads) this.bumpFrontier(a.id);
    const patch = { last_poll: Date.now(), last_error: ads.length ? '' : 'поиск ничего не вернул', learned: learn(sub.learned, ads.filter((a) => !a.promoted)) };

    // Первый проход — только запоминаем, что уже есть, чтобы не засыпать вас старьём.
    if (!sub.initialized) {
      for (const a of ads) this.db.markSeen(a.id);
      patch.initialized = 1;
      this.db.updateSub(sub.id, patch);
      this.alert(`«${sub.name}»: слежу. Сейчас в выдаче ${ads.length} объявлений — присылать буду только новые.`);
      return;
    }
    this.db.updateSub(sub.id, patch);

    for (const a of ads) {
      if (this.db.isSeen(a.id)) continue;
      if (a.createdAt && Date.now() - a.createdAt > FRESH_MS) { this.db.markSeen(a.id); continue; }
      this.db.markSeen(a.id);
      const full = await this.enrich(a);
      await this.notify(full, [sub], 'search');
      this.db.updateSub(sub.id, { sent: sub.sent + 1 });
      sub.sent += 1;
    }
  }

  // Подробности (описание, продавец, параметры) — из карточки; не вышло — шлём что есть.
  async enrich(ad) {
    try {
      const full = await olx.fetchOffer(ad.id);
      return full ? { ...ad, ...stripEmpty(full) } : ad;
    } catch {
      return ad;
    }
  }

  // ---------- турбо ----------

  async turboTick() {
    if (!this.db.get('turbo', true) || this.turboBusy || this.blocked() || !this.frontier) return;
    const subs = this.db.subs().filter((s) => !s.paused && s.initialized);
    if (!subs.length) return;
    this.turboBusy = true;
    try {
      const ids = [];
      for (let id = this.frontier + 1; ids.length < this.cfg.turboWindow && id <= this.frontier + this.cfg.turboWindow * 5; id++) {
        if ((this.misses.get(id) || 0) < MISS_GIVE_UP && !this.db.isSeen(id)) ids.push(id);
      }
      for (const id of ids) {
        if (this.blocked()) break;
        let offer;
        try {
          offer = await olx.fetchOffer(id);
          this.okRequest();
          this.stats.turboProbes += 1;
        } catch (e) {
          if (this.handleError(e)) break;
          continue;
        }
        if (!offer) {
          this.misses.set(id, (this.misses.get(id) || 0) + 1);
          continue;
        }
        this.misses.delete(id);
        this.bumpFrontier(id);
        this.stats.turboFound += 1;
        this.stats.lastTurboHit = Date.now();
        if (!this.db.markSeen(id)) continue;
        const hit = subs.filter((s) => matches(s, offer));
        if (hit.length) {
          await this.notify(offer, hit, 'turbo');
          for (const s of hit) this.db.updateSub(s.id, { sent: s.sent + 1 });
        }
      }
      // Пустые номера далеко позади — забываем, чтобы карта не росла.
      for (const id of this.misses.keys()) if (id < this.frontier - 500) this.misses.delete(id);
    } finally {
      this.turboBusy = false;
    }
  }
}

function stripEmpty(o) {
  const out = {};
  for (const [k, v] of Object.entries(o)) if (v !== '' && v !== null && !(Array.isArray(v) && !v.length)) out[k] = v;
  return out;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

module.exports = { Watcher };
