// Ловля новых объявлений для всех пользователей.
//  • поиск — ссылки поисков «сначала новые»; платные — раз в POLL_SEC, тестовые — раз в
//    тоже (тест от платного отличается только сроком); без доступа — не проверяются.
//    Одинаковые ссылки — один запрос.
//  • турбо — только для платных: следующие номера после самого свежего известного,
//    напрямую и одновременно, раз в TURBO_SEC. Ловит объявление до попадания в поиск.
// Новизна у каждого поиска своя (водяная отметка по номеру + таблица «отправлено»).

const olx = require('./olx');
const sources = require('./sources');
const { learn, matches, mismatch } = require('./match');
const vip = require('./vip');

const MISS_GIVE_UP = 12;
// Объявление с номером ниже отметки поиска (было на проверке у OLX и попало в выдачу позже
// соседей) — всё равно новое, если подано после создания поиска и не старше этого срока.
const LATE_MS = 3 * 3600_000;
const KASPI_SLACK_MS = 60 * 60_000;   // Kaspi: насколько раньше последней выкладки ещё «новое»
// Пропуск у края ленты (обычно — на проверке) перепроверяем столько: модерация бывает и
// через час-два, объявление всё равно должно прийти, как только OLX его покажет.
const GAP_LIFE_MS = LATE_MS;
// Как часто перепроверять пропуск в зависимости от его возраста: свежие — каждый проход,
// старше 10 минут — раз в 30 секунд, старше часа — раз в 2 минуты.
function gapDue(g, now) {
  const age = now - g.added;
  const every = age < 10 * 60_000 ? 0 : age < 3600_000 ? 30_000 : 120_000;
  return now - g.checked >= every;
}

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
    this.otherBackoff = new Map();   // Kaspi / Kolesa / Krisha → { ms, until }
    this.stats = { searchOk: 0, searchErr: 0, turboFound: 0, turboProbes: 0, lastTurboHit: null, sent: 0 };
    this.timers = [];
    this.lockSeen = new Map();
    // Пропуски у края ленты доски — номера, которых в ленте нет: обычно объявления на проверке
    // (номер выдан при подаче, в ленту попадут после проверки). Турбо перепроверяет их до 3 часов.
    this.gaps = new Map();   // номер → { added, checked }
    this.found = new Set();  // номера, которые уже видели (в ленте или по номеру), — не пропуски   // VIP-рубрика → номера объявлений из выдачи её поиска
    this.lockCache = { at: 0, list: [] };
    this.traceLog = new Map();   // номер → последние события («почему не пришло?»)
    this.lastBoardOK = 0;
  }

  // История по номеру: где видели, кому подошло, почему нет. Последние 4000 номеров.
  trace(id, line) {
    const lines = this.traceLog.get(id) || [];
    if (lines.length && lines[lines.length - 1].endsWith(line)) return;
    if (!this.traceLog.has(id) && this.traceLog.size >= 4000) this.traceLog.delete(this.traceLog.keys().next().value);
    const t = new Date().toLocaleTimeString('ru-RU', { timeZone: 'Asia/Almaty' });
    lines.push(`${t} ${line}`);
    if (lines.length > 10) lines.shift();
    this.traceLog.set(id, lines);
  }

  // «Почему не пришло?» — по номеру объявления OLX.
  why(id) {
    const out = [...(this.traceLog.get(id) || [])];
    const g = this.gaps.get(id);
    if (g) out.push(`Сейчас в очереди перепроверки — его нет в ленте OLX (обычно это модерация).`);
    const m = this.misses.get(id);
    if (m) out.push(`По номеру OLX ответил «нет такого» ${m} раз.`);
    const sent = this.db.subsSent(id);
    if (sent.length) out.unshift(`✅ Отправлено поискам: ${sent.map((sid) => `#${sid}`).join(', ')}`);
    if (!out.length) {
      out.push(id > this.frontier
        ? `До этого номера бот ещё не дошёл — он новее последнего известного (${this.frontier}).`
        : 'Бот этот номер не видел: ни в ленте, ни в поисках, ни по номеру. Так бывает, если объявление было на модерации и OLX по номеру его не отдавал, или бот был выключен.');
    }
    return out.join('\n');
  }

  // 403 по одному номеру — не блокировка (лента и поиски при этом отвечают): так OLX, похоже,
  // отвечает на скрытые объявления — на модерации, удалённые. Паузу не включаем, только считаем.
  hiddenOffer(id, e) {
    if (!(e instanceof olx.HttpError) || e.status !== 403) return false;
    this.stats.hidden = (this.stats.hidden || 0) + 1;
    this.misses.set(id, (this.misses.get(id) || 0) + 1);
    this.trace(id, 'по номеру: OLX ответил 403 — объявление скрыто');
    return true;
  }

  // VIP-рубрики (раз в 2 секунды из базы — их мало, а спрашиваем на каждое объявление).
  activeLocks() {
    if (Date.now() - this.lockCache.at > 2000) this.lockCache = { at: Date.now(), list: this.db.locks() };
    return this.lockCache.list;
  }

  // Продавец: все / частные / бизнес (у OLX; у остальных площадок признака нет — все).
  sellerOk(sub, ad) {
    const want = sub.seller || 'all';
    if (want === 'all' || (sub.source || 'olx') !== 'olx') return true;
    return want === 'business' ? !!ad.business : !ad.business;
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
    // Kaspi по номеру: номера идут по порядку подачи (KASPI_TURBO=0 — выключить).
    if (this.cfg.kaspiTurbo) this.timers.push(setInterval(() => this.kaspiTurboTick().catch((e) => this.log(`турбо Kaspi: ${e.message}`)), 2_000));
    this.timers.push(setInterval(() => this.kaspiShowcaseTick().catch((e) => this.log(`витрина Kaspi: ${e.message}`)), 3_000));
    this.timers.push(setInterval(() => this.db.prune(), 6 * 3600_000));
  }

  stop() {
    this.timers.forEach(clearInterval);
  }

  // Пауза — своя у каждой площадки: OLX ограничил запросы — Kaspi, Kolesa, Krisha работают
  // дальше, а их удачный ответ не сбрасывает паузу OLX (раньше сбрасывал — и бот снова бил
  // в закрытую дверь OLX каждую минуту, продлевая ограничение).
  blocked(source = 'olx') {
    return Date.now() < (source === 'olx' ? this.backoffUntil : (this.otherBackoff.get(source)?.until || 0));
  }

  handleError(e, source = 'olx') {
    if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) {
      const b = source === 'olx' ? { ms: this.backoffMs } : (this.otherBackoff.get(source) || { ms: 0 });
      b.ms = Math.min(15 * 60_000, b.ms ? b.ms * 2 : 2 * 60_000);
      b.until = Date.now() + b.ms;
      if (source === 'olx') {
        this.backoffMs = b.ms;
        this.backoffUntil = b.until;
        olx.slowDown();   // после паузы — реже, скорость поднимется сама, пока OLX отвечает
      } else {
        this.otherBackoff.set(source, b);
      }
      const name = source === 'olx' ? 'OLX' : sources.get(source).title;
      this.alert(`${name} ограничил запросы (${e.status}). Пауза ${Math.round(b.ms / 60_000)} мин, потом продолжу реже.`);
      return true;
    }
    return false;
  }

  okRequest(source = 'olx') {
    if (source === 'olx') this.backoffMs = 0;
    else this.otherBackoff.delete(source);
  }

  bumpFrontier(id) {
    if (id > this.frontier) {
      this.frontier = id;
      this.db.set('frontier', id);
    }
  }

  markFound(id) {
    this.found.add(id);
    if (this.found.size > 20_000) this.found.delete(this.found.values().next().value);
  }

  isFresh(ad, ms = this.cfg.freshMs) {
    return !ad.createdAt || Date.now() - ad.createdAt <= ms;
  }

  // Kaspi: новизна — по дате подачи (dateCreate). Витрина и даже «Самые новые» полны платных и
  // поднятых: они поданы давно. Старьё — подано больше 3 ч назад или сильно раньше последней
  // выкладки (запас 60 мин — на долгую модерацию). Только день — старое, если раньше вчерашнего.
  // Даты нет совсем (у старых объявлений её в коде нет) — по номеру: номера идут по порядку подачи
  // (~9 в минуту), и отстающий от самого нового больше чем на 5000 — подан много часов назад.
  kaspiOld(ad) {
    if (ad.createdAt) {
      return Date.now() - ad.createdAt > LATE_MS || (this.kaspiLast > 0 && ad.createdAt < this.kaspiLast - KASPI_SLACK_MS);
    }
    if (ad.postedDay) return Date.now() - ad.postedDay > 48 * 3600_000;
    const edge = this.kaspiFrontier || 0;
    return edge > 0 && ad.id < edge - 5000;
  }

  // Последняя выкладка Kaspi — самое позднее время подачи среди увиденных новых.
  kaspiSaw(ad) {
    if (ad?.createdAt && ad.createdAt <= Date.now() + 60_000 && ad.createdAt > (this.kaspiLast || 0)) this.kaspiLast = ad.createdAt;
  }

  // Номер ниже отметки поиска: новое, только если подано после создания поиска и недавно
  // (OLX; у других площадок даты подачи надёжно нет — там ниже отметки ничего не шлём).
  lateOk(sub, ad, source = sub.source || 'olx') {
    if (source !== 'olx' || ad.promoted || !ad.createdAt) return false;
    return ad.createdAt > sub.created_at && Date.now() - ad.createdAt <= LATE_MS;
  }

  // ---------- поиск ----------

  intervalFor(sub) {
    return this.cfg.pollSec * 1000;   // тест и платный — одинаково, разница только в сроке
  }

  async searchTick() {
    if (this.searchBusy) return;
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
        if (this.blocked(key.slice(0, key.indexOf('|')))) continue;
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
      this.okRequest(src.key);
      this.stats.searchOk += 1;
      ads = await this.morePages(src, url, subs, ads);
    } catch (e) {
      this.stats.searchErr += 1;
      for (const s of subs) this.db.updateSub(s.id, { last_poll: Date.now(), last_error: e.message });
      if (!this.handleError(e, src.key)) this.log(`поиск ${url}: ${e.message}`);
      return;
    }
    if (src.key === 'olx') for (const a of ads) this.bumpFrontier(a.id);
    if (src.key === 'kaspi') this.bumpKaspi(ads.reduce((m, a) => Math.max(m, a.id), 0));
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
        this.db.markSentMany(sub.id, ads.map((a) => a.id));
        this.db.updateSub(sub.id, { ...patch, initialized: 1, watermark: maxId });
        this.notifyReady(sub, ads.length);
        continue;
      }
      let sent = sub.sent;
      for (const a of ads) {
        if (this.db.wasSent(sub.id, a.id)) continue;
        // Kaspi «весь Казахстан»: город впервые после запуска — только запоминаем, что уже есть.
        if (a.seedOnly) { this.db.markSent(sub.id, a.id); continue; }
        // Номера из разных городов идут вперемешку: для них «ниже отметки» ничего не значит.
        // Kaspi: из разных городов и после модерации номера приходят вразнобой — решает дата.
        const late = !a.anyOrder && src.key !== 'kaspi' && a.id <= sub.watermark;
        // Ниже отметки: по дате из выдачи сразу отсекаем то, что было ещё до поиска.
        if (late && (src.key !== 'olx' || a.promoted || (a.createdAt && a.createdAt <= sub.created_at))) continue;
        const full = await enrich(a);
        // Окно новизны: не меньше FRESH_MIN, а если поиск не проверялся дольше (ПК спал, бот был
        // выключен) — всё время с прошлой проверки, иначе поданное за это время терялось бы.
        // Продвигаемые (Топ) — строго: это и есть «старьё сверху».
        const window = full.promoted || !sub.last_poll ? this.cfg.freshMs
          : Math.max(this.cfg.freshMs, Math.min(24 * 3600_000, Date.now() - sub.last_poll + 120_000));
        // Решение принято — больше это объявление этому поиску не проверяем.
        const pass = (late ? this.lateOk(sub, full, src.key) : this.isFresh(full, window))   // не старьё
          && !(src.key === 'kaspi' && this.kaspiOld(full))                            // Kaspi: платное старьё
          && this.allowed(sub.user_id, full)                                         // чужая VIP-рубрика
          && this.sellerOk(sub, full)                                                // частные / бизнес
          && ownerOk(sub, full);                                                     // Krisha / Kolesa: от хозяев
        if (src.key === 'kaspi' && !this.kaspiOld(full)) this.kaspiSaw(full);
        if (!this.db.markSent(sub.id, a.id)) continue;
        if (!pass) { this.trace(a.id, `поиск #${sub.id}: отсеяно (старое / продавец / VIP)`); continue; }
        this.trace(a.id, `поиск #${sub.id}: отправлено`);
        await this.notify(sub.user_id, full, [sub], 'search');
        this.stats.sent += 1;
        sent += 1;
      }
      this.db.updateSub(sub.id, { ...patch, sent, watermark: Math.max(sub.watermark, maxId) });
    }
  }

  // ---------- турбо Kaspi ----------
  // Как у OLX: номера объявлений Kaspi сквозные, и /a/<номер>/ открывает объявление без названия.
  // Проверяем следующие номера за самым большим, что видели в выдаче, — новое приходит раньше,
  // чем попадёт в выдачу поиска (и из любого города). Подошло ли поиску — по рубрике из крошек
  // карточки, городу и словам; не понятно — не шлём, его принесёт обход выдачи.

  bumpKaspi(id) {
    if (!id) return;
    if (!this.kaspiFrontier) this.kaspiFrontier = this.db.get('kaspi_edge', 0);
    if (id > this.kaspiFrontier) {
      this.kaspiFrontier = id;
      this.db.set('kaspi_edge', id);
    }
  }

  // ---------- витрина Kaspi ----------
  // Как лента всей доски у OLX: самые новые объявления Kaspi — с главной (без рубрики) и с
  // главных страниц городов по кругу. Новое (которого раньше не было на витрине) — открываем
  // карточку и сверяем со всеми поисками Kaspi. Заодно самый большой номер витрины — край для
  // турбо: перебор номеров стартует сразу у самых свежих.
  async kaspiShowcaseTick() {
    if (this.kaspiShowBusy || this.blocked('kaspi')) return;
    const subs = this.db.subs().filter((s) => s.source === 'kaspi' && !s.paused && s.initialized
      && this.db.hasAccess(s.user_id, 'kaspi') && !this.db.user(s.user_id)?.blocked);
    if (!subs.length) return;
    this.kaspiShowBusy = true;
    const k = sources.get('kaspi');
    if (!this.kaspiShow) this.kaspiShow = { pages: ['', ...sources.KASPI_CITY_SLUGS], next: 0, seeded: new Set(), seen: new Set() };
    const st = this.kaspiShow;
    try {
      // За проход — главная всего Kaspi и ещё один город по кругу.
      const cities = st.pages.filter(Boolean);
      const city = cities.length ? cities[st.next % cities.length] : null;
      st.next += 1;
      for (const page of [st.rootDead ? null : '', city].filter((p) => p != null)) {
        let ads;
        try {
          ads = await k.fetchShowcase(page);
          this.okRequest('kaspi');
        } catch (e) {
          if (this.handleError(e, 'kaspi')) break;
          continue;
        }
        if (ads == null) {   // такой витрины нет — больше не спрашиваем
          if (page === '') st.rootDead = true; else st.pages = st.pages.filter((p) => p !== page);
          continue;
        }
        const top = ads.reduce((m, a) => Math.max(m, a.id), 0);
        if (top > (this.kaspiFrontier || 0)) this.bumpKaspi(top);
        const seed = !st.seeded.has(page);
        st.seeded.add(page);
        if (!st.startEdge) st.startEdge = top;
        for (const a of ads) {
          if (st.seen.has(a.id)) continue;
          st.seen.add(a.id);
          if (seed) continue;   // что уже было на витрине при запуске — не новое
          let ad;
          try {
            const d = await k.fetchDetail(a);
            ad = d && { ...a, ...stripEmpty(d), id: a.id, url: a.url, source: 'kaspi' };
          } catch { ad = null; }
          if (!ad) continue;
          // Поднятое старое тоже всплывает наверх витрины. Новинка — если дата подачи свежая
          // (до 3 ч), а без даты — если номер не сильно меньше края на момент запуска (запас —
          // на вышедшие с модерации позже соседей).
          // Только день (без времени) — старое, если раньше вчерашнего.
          if (this.kaspiOld(ad)) { this.trace(a.id, 'витрина Kaspi: поднятое / платное старое — пропуск'); continue; }
          this.kaspiSaw(ad);
          this.trace(a.id, `витрина Kaspi: увидели${page ? ` (${ad.city || page})` : ''}`);
          for (const s of subs) {
            if (this.db.wasSent(s.id, a.id)) continue;
            const why = sources.kaspiMismatch(s, ad);
            if (why) { this.trace(a.id, `витрина Kaspi → поиск #${s.id}: не подошло — ${why}`); continue; }
            if (!this.allowed(s.user_id, ad) || !this.db.markSent(s.id, a.id)) continue;
            this.trace(a.id, `витрина Kaspi → поиск #${s.id}: отправлено`);
            this.db.updateSub(s.id, { sent: s.sent + 1 });
            await this.notify(s.user_id, ad, [s], 'search');
            this.stats.sent += 1;
          }
        }
      }
      if (st.seen.size > 20_000) st.seen = new Set([...st.seen].slice(-10_000));
    } finally {
      this.kaspiShowBusy = false;
    }
  }

  // Есть ли объявление с номером n или сразу за ним (номера бывают сняты — дырки по 1–2).
  async kaspiExists(n) {
    const k = sources.get('kaspi');
    // Пустых подряд бывает до 5 (на проверке, сняты) — смотрим 6 номеров.
    for (let id = n; id <= n + 5; id++) {
      const ad = await k.fetchById(id);
      this.okRequest('kaspi');
      if (ad) return id;
    }
    return 0;
  }

  // Сначала — найти самый последний номер Kaspi. Граница из выдачи может сильно отставать, и
  // тогда турбо слало бы подряд всё, что вышло между ней и сегодняшним днём. Пока ищем — ничего
  // не шлём: шагаем вперёд удваивая шаг (16, 32, 64…), где объявлений уже нет — делим пополам.
  async kaspiSync() {
    let lo = this.kaspiFrontier;
    let step = this.kaspiStep || 16;
    for (let i = 0; i < 4; i++) {
      if (!this.kaspiHi) {
        const hit = await this.kaspiExists(lo + step);
        if (hit) { lo = hit; step = Math.min(step * 2, 20_000); continue; }
        // Пусто — может быть просто дырка (снятые подряд). Проверяем ещё и вчетверо дальше.
        const far = await this.kaspiExists(lo + step * 4);
        if (far) { lo = far; step = Math.min(step * 2, 20_000); continue; }
        this.kaspiHi = lo + step;   // дальше объявлений нет — ищем край между lo и kaspiHi
      }
      if (this.kaspiHi - lo <= 3) {
        // Край найден с точностью до пары номеров — добираем их, чтобы уже вышедшее не ушло как новое.
        const k = sources.get('kaspi');
        for (let id = lo + 1; id <= this.kaspiHi + 3; id++) if (await k.fetchById(id)) lo = id;
        this.kaspiSynced = true;
        this.kaspiHi = 0;
        this.kaspiStep = 16;
        this.log(`Kaspi: последний номер ${lo} — дальше ловлю только новые`);
        break;
      }
      const mid = Math.floor((lo + this.kaspiHi) / 2);
      const hit = await this.kaspiExists(mid);
      if (hit) lo = hit; else this.kaspiHi = mid;
    }
    this.kaspiStep = step;
    this.kaspiFrontier = lo;
    this.db.set('kaspi_edge', lo);
  }

  async kaspiTurboTick() {
    if (this.kaspiBusy || this.blocked('kaspi')) return;
    if (!this.kaspiFrontier) this.kaspiFrontier = this.db.get('kaspi_edge', 0);
    if (!this.kaspiFrontier) return;
    const subs = this.db.subs().filter((s) => s.source === 'kaspi' && !s.paused && s.initialized
      && this.db.hasAccess(s.user_id, 'kaspi') && !this.db.user(s.user_id)?.blocked);
    if (!subs.length) return;
    // ПК спал или бот стоял дольше 5 минут — край снова ищем заново (пропущенное принесёт выдача).
    if (Date.now() - (this.kaspiLastTick || 0) > 5 * 60_000) this.kaspiSynced = false;
    this.kaspiLastTick = Date.now();
    this.kaspiBusy = true;
    const k = sources.get('kaspi');
    this.kaspiMisses = this.kaspiMisses || new Map();
    try {
      if (!this.kaspiSynced) {
        try { await this.kaspiSync(); } catch (e) { this.handleError(e, 'kaspi'); }
        return;
      }
      // Номер выдаётся при подаче, но пока объявление на проверке у Kaspi (обычно 2–3 мин, бывает
      // до часа), по нему открывается заглушка. Такие номера держим в очереди и перепроверяем:
      // первые 10 минут — каждые 4 с, потом — раз в 30 с, до часа. Сначала — самые давние.
      const now = Date.now();
      const ids = [this.kaspiFrontier + 1, this.kaspiFrontier + 2];
      // И один подальше (+3…+18 по кругу): так граница уходит вперёд, даже если ближние на проверке.
      this.kaspiJump = ((this.kaspiJump || 0) % 16) + 1;
      ids.push(this.kaspiFrontier + 2 + this.kaspiJump);
      const due = [...this.kaspiMisses.entries()]
        .filter(([id, m]) => id <= this.kaspiFrontier && !ids.includes(id)
          && now - m.checked >= (now - m.added < 10 * 60_000 ? 4_000 : 30_000))
        .sort((x, y) => x[1].checked - y[1].checked)
        .slice(0, 4);
      ids.push(...due.map(([id]) => id));
      const miss = (id) => {
        const m = this.kaspiMisses.get(id) || { added: now, checked: 0 };
        m.checked = now;
        this.kaspiMisses.set(id, m);
      };
      for (const id of ids) {
        let ad;
        try {
          ad = await k.fetchById(id);
          this.okRequest('kaspi');
        } catch (e) {
          if (this.handleError(e, 'kaspi')) break;
          continue;
        }
        if (!ad) { miss(id); continue; }
        this.kaspiMisses.delete(id);
        // Перескочили через номера — они тоже в очередь: скорее всего, ещё на проверке.
        for (let n = this.kaspiFrontier + 1; n < id && id - n <= 40; n++) if (!this.kaspiMisses.has(n)) this.kaspiMisses.set(n, { added: now, checked: now });
        this.bumpKaspi(id);
        this.trace(id, 'Kaspi по номеру: нашли');
        for (const s of subs) {
          if (this.db.wasSent(s.id, id)) continue;
          const why = sources.kaspiMismatch(s, ad);
          if (why) { this.trace(id, `Kaspi по номеру → поиск #${s.id}: не подошло — ${why}`); continue; }
          if (!this.allowed(s.user_id, ad) || !this.db.markSent(s.id, id)) continue;
          this.trace(id, `Kaspi по номеру → поиск #${s.id}: отправлено`);
          this.db.updateSub(s.id, { sent: s.sent + 1 });
          await this.notify(s.user_id, ad, [s], 'turbo');
          this.stats.sent += 1;
        }
      }
      for (const [id, m] of this.kaspiMisses) if (now - m.added > 3600_000 || id < this.kaspiFrontier - 1500) this.kaspiMisses.delete(id);
    } finally {
      this.kaspiBusy = false;
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
      const onBoard = new Set(ads.map((a) => a.id));
      const now = Date.now();
      const boardWindow = Math.max(this.cfg.freshMs, this.lastBoardOK ? Math.min(24 * 3600_000, now - this.lastBoardOK + 120_000) : 0);
      this.lastBoardOK = now;
      for (const id of onBoard) this.markFound(id);
      for (let id = Math.max(1, top - 300); id <= top; id++) {
        if (!this.found.has(id) && !this.gaps.has(id)) this.gaps.set(id, { added: now, checked: 0 });
      }
      for (const [id, g] of this.gaps) if (now - g.added > GAP_LIFE_MS || onBoard.has(id)) this.gaps.delete(id);
      if (top > this.frontier + this.cfg.turboWindow * 3) {
        this.frontier = top - this.cfg.turboWindow;   // прыжок: турбо проверит последние номера сам
        this.db.set('frontier', this.frontier);
      } else {
        this.bumpFrontier(top);
      }
      await this.checkDiscounts('olx', ads, subs, { matcher: true });
      for (const a of [...ads].sort((x, y) => x.id - y.id)) {
        // Прошло модерацию поздно (подано час назад, в ленте только сейчас) — тоже новое
        // для поисков, созданных до подачи: это решает lateOk ниже.
        if (a.promoted || !this.isFresh(a, Math.max(boardWindow, LATE_MS))) continue;
        const fresh = this.isFresh(a, boardWindow);
        a.source = 'olx';
        if (!this.traceLog.has(a.id)) this.trace(a.id, `лента: увидели${a.status && a.status !== 'active' ? ' (на модерации)' : ''}${posted(a)}`);
        const byUser = new Map();
        for (const s of subs) {
          if ((a.id <= s.watermark || !fresh) && !this.lateOk(s, a)) continue;
          if (this.db.wasSent(s.id, a.id)) continue;
          const why = mismatch(s, a);
          if (why) { this.trace(a.id, `лента → поиск #${s.id}: не подошло — ${why}`); continue; }
          if (!this.sellerOk(s, a) || !this.allowed(s.user_id, a) || !this.db.markSent(s.id, a.id)) continue;
          this.trace(a.id, `лента → поиск #${s.id}: отправлено`);
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
        if (!this.sellerOk(s, full) || !this.allowed(s.user_id, full) || !this.db.markDiscount(s.id, a.id, a.price)) continue;
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
        try { o = await olx.fetchOffer(id); this.okRequest(); } catch (e) { if (this.hiddenOffer(id, e)) continue; this.handleError(e); break; }
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
      // Порядок = очередь к OLX (запросы по номеру идут не чаще olx.offerRate() в секунду):
      // сначала новые номера за границей — самое свежее, потом недавние промахи и пропуски.
      const ids = [];
      for (let id = this.frontier + 1; ids.length < this.cfg.turboWindow && id <= this.frontier + this.cfg.turboWindow * 5; id++) {
        if ((this.misses.get(id) || 0) < MISS_GIVE_UP) ids.push(id);
      }
      const retry = [...this.misses.entries()]
        .filter(([id, n]) => id < this.frontier && id > this.frontier - 300 && n < MISS_GIVE_UP)
        .map(([id]) => id)
        .sort((a, b) => b - a)
        .slice(0, Math.ceil(this.cfg.turboWindow / 3))
        .filter((id) => !ids.includes(id));
      ids.push(...retry);
      // И пропуски ниже края ленты — давно не проверенные первыми.
      const tickAt = Date.now();
      const gapIds = [...this.gaps.entries()].filter(([, g]) => gapDue(g, tickAt))
        .sort((a, b) => a[1].checked - b[1].checked || b[0] - a[0])
        .filter(([id]) => !ids.includes(id))
        .slice(0, Math.ceil(this.cfg.turboWindow / 2)).map(([id]) => id);
      for (const id of gapIds) this.gaps.get(id).checked = Date.now();
      ids.push(...gapIds);
      const results = await Promise.all(ids.map((id) => olx.fetchOffer(id).then((o) => ({ id, o }), (e) => ({ id, e }))));
      // 403 на всё подряд — это не скрытые объявления, а OLX закрыл доступ целиком: пауза.
      if (results.length >= 5 && results.every((r) => r.e instanceof olx.HttpError && r.e.status === 403)) {
        this.handleError(results[0].e);
        return;
      }
      for (const { id, o, e } of results) {
        if (e) {
          if (this.hiddenOffer(id, e)) continue;
          if (this.handleError(e)) break;
          continue;
        }
        this.okRequest();
        this.stats.turboProbes += 1;
        if (!o) { this.misses.set(id, (this.misses.get(id) || 0) + 1); continue; }
        this.misses.delete(id);
        const wasGap = this.gaps.delete(id);
        this.markFound(id);
        this.bumpFrontier(id);
        this.stats.turboFound += 1;
        this.stats.lastTurboHit = Date.now();
        // Пропуск, который наконец прошёл модерацию, — новый, даже если подан час-два назад.
        if (!this.isFresh(o, Math.max(this.cfg.freshMs, wasGap ? GAP_LIFE_MS : 30 * 60_000))) { this.trace(id, 'по номеру: подано давно — пропуск'); continue; }
        o.source = 'olx';
        this.trace(id, `по номеру: нашли${o.status && o.status !== 'active' ? ' — на модерации' : ''}${posted(o)}`);
        const byUser = new Map();
        for (const s of subs) {
          if (o.createdAt && o.createdAt <= s.created_at) continue;   // подано ещё до поиска
          const why = mismatch(s, o);
          if (why) { this.trace(id, `по номеру → поиск #${s.id}: не подошло — ${why}`); continue; }
          if (!this.sellerOk(s, o) || !this.allowed(s.user_id, o) || !this.db.markSent(s.id, id)) continue;
          this.trace(id, `по номеру → поиск #${s.id}: отправлено`);
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

// «Только от хозяев». Krisha — фильтр das[who]=1 в ссылке (свой или с сайта): нужна подпись
// «Хозяин недвижимости». Kolesa — такого фильтра в ссылке нет, выбор хранится как «частные»:
// отсеиваем то, где на странице автосалон или дилер.
function ownerOk(sub, ad) {
  const source = sub.source || 'olx';
  if (source === 'krisha' && /das(%5B|\[)who(%5D|\])=1/i.test(sub.url)) return ad.owner === true;
  if (source === 'kolesa' && sub.seller === 'private') return ad.owner !== false;
  return true;
}

// «· подано 14:02» — чтобы в «почему не пришло?» было видно, сколько объявление шло до нас.
function posted(ad) {
  return ad.createdAt ? ` · подано ${new Date(ad.createdAt).toLocaleTimeString('ru-RU', { timeZone: 'Asia/Almaty' })}` : '';
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
