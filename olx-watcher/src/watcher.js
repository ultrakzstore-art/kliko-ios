// Ловля новых объявлений для всех пользователей.
//  • поиск — ссылки поисков «сначала новые»; платные — раз в POLL_SEC, тестовые — раз в
//    тоже (тест от платного отличается только сроком); без доступа — не проверяются.
//    Одинаковые ссылки — один запрос.
//  • турбо — только для платных: следующие номера после самого свежего известного,
//    напрямую и одновременно, раз в TURBO_SEC. Ловит объявление до попадания в поиск.
// Новизна у каждого поиска своя (водяная отметка по номеру + таблица «отправлено»).

const olx = require('./olx');
const sources = require('./sources');
const { learn, matches } = require('./match');
const vip = require('./vip');

const MISS_GIVE_UP = 12;

class Watcher {
  constructor({ db, config, notify, alert, log }) {
    this.db = db;
    this.cfg = config;
    this.notify = notify;   // (userId, ad, subs[], via)
    this.alert = alert;     // (text) → владельцу бота
    this.log = log;
    this.frontier = db.get('frontier', 0);
    this.misses = new Map();
    this.backoffUntil = 0;
    this.backoffMs = 0;
    this.stats = { searchOk: 0, searchErr: 0, turboFound: 0, turboProbes: 0, lastTurboHit: null, sent: 0 };
    this.timers = [];
    this.lockSeen = new Map();   // VIP-рубрика → номера объявлений из выдачи её поиска
    this.lockCache = { at: 0, list: [] };
  }

  // VIP-рубрики (раз в 2 секунды из базы — их мало, а спрашиваем на каждое объявление).
  activeLocks() {
    if (Date.now() - this.lockCache.at > 2000) this.lockCache = { at: Date.now(), list: this.db.locks() };
    return this.lockCache.list;
  }

  // Жёсткое правило VIP: объявление из чужой закреплённой рубрики и города — не отправляем.
  allowed(userId, ad) {
    const owner = vip.lockOwner(this.activeLocks(), ad, this.lockSeen);
    return owner == null || owner === userId;
  }

  start() {
    this.timers.push(setInterval(() => this.searchTick().catch((e) => this.log(`поиск: ${e.message}`)), 1_000));
    this.timers.push(setInterval(() => this.boardTick().catch((e) => this.log(`доска: ${e.message}`)), (this.cfg.boardSec || 2) * 1000));
    if (this.cfg.discounts !== false) {
      this.timers.push(setInterval(() => this.recheckTick().catch((e) => this.log(`скидки: ${e.message}`)), 10_000));
    }
    this.timers.push(setInterval(() => this.turboTick().catch((e) => this.log(`турбо: ${e.message}`)), this.cfg.turboSec * 1000));
    this.timers.push(setInterval(() => this.db.prune(), 6 * 3600_000));
  }

  stop() {
    this.timers.forEach(clearInterval);
  }

  blocked() {
    return Date.now() < this.backoffUntil;
  }

  handleError(e) {
    if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) {
      this.backoffMs = Math.min(15 * 60_000, this.backoffMs ? this.backoffMs * 2 : 60_000);
      this.backoffUntil = Date.now() + this.backoffMs;
      this.alert(`OLX ограничил запросы (${e.status}). Пауза ${Math.round(this.backoffMs / 60_000)} мин.`);
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

  isFresh(ad) {
    return !ad.createdAt || Date.now() - ad.createdAt <= this.cfg.freshMs;
  }

  // ---------- поиск ----------

  intervalFor(sub) {
    return this.cfg.pollSec * 1000;   // тест и платный — одинаково, разница только в сроке
  }

  async searchTick() {
    if (this.searchBusy || this.blocked()) return;
    this.searchBusy = true;
    try {
      const now = Date.now();
      const due = this.db.subs().filter((s) => {
        if (s.paused) return false;
        const u = this.db.user(s.user_id);
        if (!u || u.blocked || !this.db.hasAccess(u, s.source || 'olx')) return false;   // нет доступа к площадке — не проверяем
        return now - s.last_poll >= this.intervalFor(s);
      });
      // Одна ссылка — один запрос, сколько бы людей на неё ни подписалось. Поиски VIP по их
      // рубрикам — первыми: так эксклюзив узнаётся раньше, чем его увидит чужой поиск.
      const vipSubs = new Set(this.activeLocks().map((l) => l.sub_id));
      due.sort((a, b) => Number(vipSubs.has(b.id)) - Number(vipSubs.has(a.id)));
      const byUrl = new Map();
      for (const s of due) {
        const key = `${s.source || 'olx'}|${s.url}`;
        byUrl.set(key, [...(byUrl.get(key) || []), s]);
      }
      for (const [key, subs] of byUrl) {
        if (this.blocked()) break;
        await this.pollUrl(key.slice(key.indexOf('|') + 1), subs);
        await sleep(150 + Math.random() * 250);
      }
    } finally {
      this.searchBusy = false;
    }
  }

  async pollUrl(url, subs) {
    const src = sources.get(subs[0].source || 'olx');
    let ads;
    try {
      ads = await src.fetchSearch(url);
      this.okRequest();
      this.stats.searchOk += 1;
      ads = await this.morePages(src, url, subs, ads);
    } catch (e) {
      this.stats.searchErr += 1;
      for (const s of subs) this.db.updateSub(s.id, { last_poll: Date.now(), last_error: e.message });
      if (!this.handleError(e)) this.log(`поиск ${url}: ${e.message}`);
      return;
    }
    if (src.key === 'olx') for (const a of ads) this.bumpFrontier(a.id);
    // Выдача поиска VIP по его рубрике: запоминаем объявления и учим номера рубрик.
    for (const l of this.activeLocks()) {
      if (!subs.some((s) => s.id === l.sub_id)) continue;
      const set = this.lockSeen.get(l.id) || new Set();
      for (const a of ads) set.add(a.id);
      if (set.size > 5000) this.lockSeen.set(l.id, new Set([...set].slice(-2000)));
      else this.lockSeen.set(l.id, set);
      this.db.learnLock(l.id, ads.map((a) => a.categoryId));
      this.lockCache.at = 0;
    }
    const maxId = ads.reduce((m, a) => Math.max(m, a.id), 0);
    const enriched = new Map();   // карточка по номеру — одна на всех подписчиков ссылки
    const enrich = async (ad) => {
      if (!enriched.has(ad.id)) {
        enriched.set(ad.id, Promise.resolve(src.fetchDetail(ad))
          .then((f) => ({ ...ad, ...(f ? stripEmpty(f) : {}), source: src.key }))
          .catch(() => ({ ...ad, source: src.key })));
      }
      return enriched.get(ad.id);
    };

    // Скидки: цена знакомого объявления из этой выдачи стала ниже — всем поискам этой ссылки.
    await this.checkDiscounts(src.key, ads, subs);

    for (const sub of subs) {
      const patch = {
        last_poll: Date.now(),
        last_error: ads.length ? '' : 'поиск ничего не вернул',
        learned: learn(sub.learned, ads.filter((a) => !a.promoted)),
      };
      // Первый проход — только отметка: что уже есть, не присылаем.
      if (!sub.initialized) {
        this.db.updateSub(sub.id, { ...patch, initialized: 1, watermark: maxId });
        this.notifyReady(sub, ads.length);
        continue;
      }
      let sent = sub.sent;
      for (const a of ads) {
        if (a.id <= sub.watermark || this.db.wasSent(sub.id, a.id)) continue;
        const full = await enrich(a);
        if (!this.isFresh(full)) continue;   // поднятое или продвинутое старьё
        if (!this.allowed(sub.user_id, full)) continue;   // чужая VIP-рубрика
        if (!this.db.markSent(sub.id, a.id)) continue;
        await this.notify(sub.user_id, full, [sub], 'search');
        this.stats.sent += 1;
        sent += 1;
      }
      this.db.updateSub(sub.id, { ...patch, sent, watermark: Math.max(sub.watermark, maxId) });
    }
  }

  // Вся первая страница новее отметки — значит, между проверками вышло больше, чем на ней
  // помещается (бывает после паузы или в очень живой рубрике). Дочитываем ещё до 2 страниц, чтобы
  // не потерять объявления, которые уже уехали со страницы 1.
  async morePages(src, url, subs, ads) {
    if (src.key !== 'olx') return ads;
    const ready = subs.filter((s) => s.initialized);
    if (!ready.length) return ads;
    const mark = Math.min(...ready.map((s) => s.watermark));
    let all = ads;
    let page = ads;
    for (let n = 2; n <= 3; n++) {
      const regular = page.filter((a) => !a.promoted);
      if (regular.length < 20 || Math.min(...regular.map((a) => a.id)) <= mark) break;
      await sleep(700);
      try {
        page = await src.fetchSearch(url, n);
      } catch {
        break;
      }
      const have = new Set(all.map((a) => a.id));
      const fresh = page.filter((a) => !have.has(a.id));
      if (!fresh.length) break;
      all = [...all, ...fresh];
    }
    return all;
  }

  notifyReady(sub, count) {
    this.notify(sub.user_id, null, [sub], 'ready', count);
  }

  // ---------- лента всей доски ----------
  // Самые свежие объявления всего OLX.kz раз в BOARD_SEC: отсюда приходит большая часть нового
  // — сразу, без ожидания своего поиска. Граница турбо прыгает к краю ленты, а не бредёт по
  // номерам. Подходит ли объявление поиску — как у турбо (слова, цена, выученные рубрика и город).

  async boardTick() {
    if (this.boardBusy || this.blocked()) return;
    const subs = this.db.subs().filter((s) => (s.source || 'olx') === 'olx' && !s.paused && s.initialized
      && this.db.hasAccess(s.user_id, 'olx') && !this.db.user(s.user_id)?.blocked);
    if (!subs.length) return;
    this.boardBusy = true;
    try {
      let ads;
      try {
        ads = await olx.fetchLatest();
        this.okRequest();
      } catch (e) {
        if (!this.handleError(e)) this.log(`доска: ${e.message}`);
        return;
      }
      const top = ads.reduce((m, a) => Math.max(m, a.id), 0);
      if (top > this.frontier + this.cfg.turboWindow * 3) {
        this.frontier = top - this.cfg.turboWindow;   // прыжок: турбо проверит последние номера сам
        this.db.set('frontier', this.frontier);
      } else {
        this.bumpFrontier(top);
      }
      await this.checkDiscounts('olx', ads, subs, { matcher: true });
      for (const a of [...ads].sort((x, y) => x.id - y.id)) {
        if (a.promoted || !this.isFresh(a)) continue;
        a.source = 'olx';
        const byUser = new Map();
        for (const s of subs) {
          if (a.id <= s.watermark || !matches(s, a) || !this.allowed(s.user_id, a) || !this.db.markSent(s.id, a.id)) continue;
          byUser.set(s.user_id, [...(byUser.get(s.user_id) || []), s]);
          this.db.updateSub(s.id, { sent: s.sent + 1 });
        }
        for (const [userId, hit] of byUser) {
          await this.notify(userId, a, hit, 'search');
          this.stats.sent += 1;
        }
      }
    } finally {
      this.boardBusy = false;
    }
  }

  // ---------- скидки ----------
  // Цену каждого объявления, которое видим (выдача поисков, лента доски, турбо, перепроверка),
  // запоминаем. Стала ниже хотя бы на MIN_DROP % — «📉 Цена снижена» тем, чьему поиску оно
  // подходит (или кому уже приходило). Одна и та же скидка — один раз.

  async checkDiscounts(source, ads, subs, { onlySent = false, matcher = false } = {}) {
    if (this.cfg.discounts === false) return;
    const minDrop = (this.cfg.minDropPct ?? 3) / 100;
    for (const a of ads) {
      const old = this.db.notePrice(source, a.id, a.price);
      if (!old || a.price > old * (1 - minDrop)) continue;
      const full = { ...a, source, oldPrice: old };
      const sentTo = new Set(this.db.subsSent(a.id));
      const byUser = new Map();
      for (const s of subs) {
        if (!s.initialized || s.paused) continue;
        if (onlySent && !sentTo.has(s.id)) continue;
        if (matcher && !matches(s, full)) continue;   // лента доски: только подходящим поискам
        if (!this.db.hasAccess(s.user_id, source) || this.db.user(s.user_id)?.blocked) continue;
        if (!this.allowed(s.user_id, full) || !this.db.markDiscount(s.id, a.id, a.price)) continue;
        byUser.set(s.user_id, [...(byUser.get(s.user_id) || []), s]);
      }
      for (const [userId, hit] of byUser) {
        await this.notify(userId, full, hit, 'discount');
        this.stats.discounts = (this.stats.discounts || 0) + 1;
      }
    }
  }

  // Фоном: объявления OLX, которые уже кому-то приходили, — не снизили ли цену.
  async recheckTick() {
    if (this.recheckBusy || this.blocked()) return;
    this.recheckBusy = true;
    try {
      const ids = this.db.toRecheck(3);
      for (const id of ids) {
        let o;
        try { o = await olx.fetchOffer(id); this.okRequest(); } catch (e) { this.handleError(e); break; }
        if (o) {
          const subs = this.db.subsSent(id).map((sid) => this.db.sub(sid)).filter(Boolean);
          await this.checkDiscounts('olx', [o], subs, { onlySent: true });
        }
        // Проверено (или объявление снято) — в конец очереди.
        this.db.db.prepare(`INSERT INTO ad_prices (source, ad_id, price, checked_at) VALUES ('olx', ?, 0, ?)
          ON CONFLICT(source, ad_id) DO UPDATE SET checked_at = excluded.checked_at`).run(id, Date.now());
      }
    } finally {
      this.recheckBusy = false;
    }
  }

  // ---------- турбо (только платные) ----------

  async turboTick() {
    if (!this.db.get('turbo', true) || this.turboBusy || this.blocked() || !this.frontier) return;
    // Турбо — только OLX (у остальных площадок пока не проверено), всем, у кого есть доступ.
    const subs = this.db.subs().filter((s) => (s.source || 'olx') === 'olx' && !s.paused && s.initialized
      && this.db.hasAccess(s.user_id, 'olx') && !this.db.user(s.user_id)?.blocked);
    if (!subs.length) return;
    this.turboBusy = true;
    try {
      // Сначала — пропущенные номера чуть ниже границы: номер мог ещё не открыться, когда
      // следующий уже появился и граница ушла вперёд. Дальше — новые номера за границей.
      const ids = [];
      const retry = [...this.misses.entries()]
        .filter(([id, n]) => id < this.frontier && id > this.frontier - 300 && n < MISS_GIVE_UP)
        .map(([id]) => id)
        .sort((a, b) => b - a)
        .slice(0, Math.ceil(this.cfg.turboWindow / 3));
      ids.push(...retry);
      for (let id = this.frontier + 1; ids.length < this.cfg.turboWindow + retry.length && id <= this.frontier + this.cfg.turboWindow * 5; id++) {
        if ((this.misses.get(id) || 0) < MISS_GIVE_UP) ids.push(id);
      }
      // Все номера прохода — одновременно.
      const results = await Promise.all(ids.map((id) => olx.fetchOffer(id).then((o) => ({ id, o }), (e) => ({ id, e }))));
      for (const { id, o, e } of results) {
        if (e) { if (this.handleError(e)) break; continue; }
        this.okRequest();
        this.stats.turboProbes += 1;
        if (!o) { this.misses.set(id, (this.misses.get(id) || 0) + 1); continue; }
        this.misses.delete(id);
        this.bumpFrontier(id);
        this.stats.turboFound += 1;
        this.stats.lastTurboHit = Date.now();
        if (!this.isFresh(o)) continue;
        o.source = 'olx';
        const byUser = new Map();
        for (const s of subs) {
          if (!matches(s, o) || !this.allowed(s.user_id, o) || !this.db.markSent(s.id, id)) continue;
          byUser.set(s.user_id, [...(byUser.get(s.user_id) || []), s]);
          this.db.updateSub(s.id, { sent: s.sent + 1 });
        }
        for (const [userId, hit] of byUser) {
          await this.notify(userId, o, hit, 'turbo');
          this.stats.sent += 1;
        }
      }
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
