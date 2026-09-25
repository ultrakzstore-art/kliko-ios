// Площадки: у каждой — как развернуть поиск «сначала новые», как достать номера из выдачи,
// как открыть карточку, и (если есть) выбор кнопками. Новизна везде — по номеру объявления
// (водяная отметка), поэтому поднятое старьё не приходит. Турбо — пока только OLX: у
// остальных сначала проверим `npm run probe`, открываются ли карточки по номеру.

const olx = require('../olx');
const cats = require('../categories');
const { getHtml, idsFromListing, parseDetail } = require('./page');
const { stem } = require('../match');

const CITIES = [
  ['Алматы', 'almaty'], ['Астана', 'astana'], ['Шымкент', 'shymkent'], ['Караганда', 'karaganda'],
  ['Актобе', 'aktobe'], ['Тараз', 'taraz'], ['Павлодар', 'pavlodar'], ['Усть-Каменогорск', 'ust-kamenogorsk'],
  ['Семей', 'semey'], ['Костанай', 'kostanay'], ['Атырау', 'atyrau'], ['Актау', 'aktau'],
].map(([name, slug]) => ({ name, slug }));

function withParams(url, params) {
  const u = new URL(url);
  for (const [k, v] of Object.entries(params)) if (v != null && v !== '') u.searchParams.set(k, String(v));
  u.hash = '';
  return u.toString();
}

function checkHost(url, re, title) {
  let u;
  try { u = new URL(url); } catch { throw new Error(`Нужна ссылка на поиск ${title}`); }
  if (!re.test(u.hostname)) throw new Error(`Нужна ссылка на поиск ${title}`);
  return u;
}

// ---------- OLX ----------

const OLX = {
  key: 'olx',
  title: 'OLX',
  emoji: '🟣',
  hostRe: /(^|\.)olx\.kz$/i,
  turbo: true,
  normalize: (url) => olx.newestFirst(url),
  isAdUrl: (url) => olx.idFromUrl(url) != null,
  // Через модуль olx — чтобы тесты могли подменять сеть.
  fetchSearch: (url, page) => olx.fetchSearch(url, page).then((r) => r.ads),
  fetchDetail: (ad) => olx.fetchOffer(ad.id),
  link: (ad) => {
    const base = ad.url && /^https?:/.test(ad.url) ? ad.url.split('#')[0] : `${olx.BASE}/d/obyavlenie/-ID${olx.encodeId(ad.id)}.html`;
    return base;
  },
  wizard: 'olx',   // свой мастер с подрубриками (wizard.js)
};

// ---------- Kolesa.kz и Krisha.kz (один движок Kolesa Group) ----------

function kolesaGroup({ key, title, emoji, host, categories, priceFrom, priceTo }) {
  const base = `https://${host}`;
  const hostRe = new RegExp(`(^|\\.)${host.replace('.', '\\.')}$`, 'i');
  const adRe = /\/a\/show\/(\d{5,})/g;
  return {
    key, title, emoji, hostRe, turbo: false,
    normalize: (url) => { checkHost(url, hostRe, title); return withParams(url, { sort_by: 'add_date-desc' }); },
    isAdUrl: (url) => /\/a\/show\/\d+/.test(url),
    async fetchSearch(url) {
      const html = await getHtml(this.normalize(url));
      if (html == null) throw new Error(`${title} ответил 404 — проверьте ссылку`);
      return idsFromListing(html, adRe).map((a) => ({ ...a, url: `${base}/a/show/${a.id}` }));
    },
    async fetchDetail(ad) {
      const html = await getHtml(`${base}/a/show/${ad.id}`);
      return html == null ? null : parseDetail(html, { id: ad.id, url: `${base}/a/show/${ad.id}` });
    },
    link: (ad) => `${base}/a/show/${ad.id}`,
    wizard: {
      categories,
      cities: CITIES,
      build: ({ path, city, params, priceFrom: pf, priceTo: pt }) =>
        withParams(`${base}/${path}/${city ? `${city}/` : ''}`, { ...(params || {}), [priceFrom]: pf, [priceTo]: pt }),
    },
  };
}

// Подрубрики Kolesa: марки (адрес вида /cars/toyota/). Модель — ссылкой с сайта.
const CAR_BRANDS = [
  ['Toyota', 'toyota'], ['Lexus', 'lexus'], ['Hyundai', 'hyundai'], ['Kia', 'kia'], ['Chevrolet', 'chevrolet'],
  ['Volkswagen', 'volkswagen'], ['Mercedes-Benz', 'mercedes-benz'], ['BMW', 'bmw'], ['Audi', 'audi'], ['Nissan', 'nissan'],
  ['Mitsubishi', 'mitsubishi'], ['Honda', 'honda'], ['ВАЗ (Lada)', 'vaz'], ['Subaru', 'subaru'], ['Mazda', 'mazda'],
  ['Skoda', 'skoda'], ['Ford', 'ford'], ['Renault', 'renault'], ['Daewoo', 'daewoo'], ['Geely', 'geely'],
  ['Chery', 'chery'], ['Haval', 'haval'], ['Changan', 'changan'], ['Land Rover', 'land-rover'],
].map(([name, slug]) => ({ name, path: `cars/${slug}` }));

// Подрубрики Krisha: число комнат (фильтр das[live.rooms]).
const ROOMS = (path) => [['1-комнатные', 1], ['2-комнатные', 2], ['3-комнатные', 3], ['4-комнатные', 4], ['5+ комнат', 5]]
  .map(([name, n]) => ({ name, path, params: { 'das[live.rooms]': n } }));

const KOLESA = kolesaGroup({
  key: 'kolesa', title: 'Kolesa', emoji: '🚗', host: 'kolesa.kz',
  priceFrom: 'price[from]', priceTo: 'price[to]',
  categories: [
    { name: 'Легковые авто', path: 'cars', subs: CAR_BRANDS },
    { name: 'Мото', path: 'moto' },
    { name: 'Спецтехника', path: 'spectehnika' },
    { name: 'Запчасти', path: 'zapchasti' },
  ],
});

const KRISHA = kolesaGroup({
  key: 'krisha', title: 'Krisha', emoji: '🏠', host: 'krisha.kz',
  priceFrom: 'das[price][from]', priceTo: 'das[price][to]',
  categories: [
    { name: 'Продажа квартир', path: 'prodazha/kvartiry', subs: ROOMS('prodazha/kvartiry') },
    { name: 'Аренда квартир', path: 'arenda/kvartiry', subs: ROOMS('arenda/kvartiry') },
    { name: 'Продажа домов', path: 'prodazha/doma' },
    { name: 'Аренда домов', path: 'arenda/doma' },
    { name: 'Участки', path: 'prodazha/uchastkov' },
  ],
});

// ---------- Kaspi Объявления ----------
// Ссылки: obyavleniya.kaspi.kz/[город/]рубрика/подрубрика/[k--слова/] — без города это весь
// Казахстан. Номер объявления — последнее длинное число в ссылке на него (устройство страницы
// объявления не проверено — `npm run probe` покажет).

const KASPI_BASE = 'https://obyavleniya.kaspi.kz';
const KASPI_CATEGORIES = [
  { name: 'Электроника', path: 'elektronika', subs: [
    { name: 'Телефоны', path: 'elektronika/telefony' },
    { name: 'Мобильные телефоны', path: 'elektronika/telefony/mobilnye-telefony' },
    { name: 'Компьютеры', path: 'elektronika/computery' },
    { name: 'Ноутбуки', path: 'elektronika/computery/noutbuki' },
    { name: 'Техника для дома', path: 'elektronika/tehnika-dlya-doma' },
  ] },
  { name: 'Apple', path: 'apple', subs: [
    { name: 'iPhone', path: 'apple/iphones' },
    { name: 'MacBook и компьютеры Apple', path: 'apple/apple-computers' },
  ] },
  { name: 'Дом и дача', path: 'dom-dacha', subs: [
    { name: 'Мебель и интерьер', path: 'dom-dacha/mebel-interer' },
  ] },
  { name: 'Животные', path: 'zhivotnye' },
  { name: 'Услуги', path: 'uslugi' },
  { name: 'Личные вещи', path: 'lichnye-vezchi' },
  { name: 'Прокат и аренда', path: 'prokat-i-arenda' },
  { name: 'Бизнес и оборудование', path: 'biznes' },
];

// Объявление Kaspi: /a/<название>-<номер>/ (например /a/iphone-15-112633239/).
function kaspiIds(html) {
  const out = new Map();
  for (const m of html.matchAll(/(?:href=["']|["'(\s])((?:https?:\/\/obyavleniya\.kaspi\.kz)?\/a\/[^"'#\s)]*?-(\d{6,})\/?)(?=["'?#\s)])/gi)) {
    let u;
    try { u = new URL(m[1].replace(/&amp;/g, '&'), KASPI_BASE); } catch { continue; }
    const id = Number(m[2]);
    if (!out.has(id)) out.set(id, { id, title: '', url: `${u.origin}${u.pathname}` });
  }
  return [...out.values()];
}

// Сортировка «сначала новые». Как её зовут в ссылке Kaspi, заранее неизвестно — ищем на самой
// странице выдачи: ссылку или пункт списка со словами «новые» / «по дате» / «свежие» и берём
// его параметр (sort=…, order=…). Нашли — дальше все поиски Kaspi идут с ней.
const SORT_WORDS = /(сначала\s+нов|нов(ые|ее|инки)|по\s+дат|свеж|недавн|newest|date)/i;
function kaspiSort(html) {
  const text = String(html).replace(/&amp;/g, '&');
  // <a href="…?sort=date_desc">Сначала новые</a>
  for (const m of text.matchAll(/<a\b[^>]*href=["']([^"']*[?&](?:sort|order|sortBy|sort_by|orderBy)[^"']*)["'][^>]*>([\s\S]{0,120}?)<\/a>/gi)) {
    if (!SORT_WORDS.test(m[2].replace(/<[^>]+>/g, ' '))) continue;
    try {
      const u = new URL(m[1], KASPI_BASE);
      for (const [k, v] of u.searchParams) if (/^(sort|order|sortBy|sort_by|orderBy)$/i.test(k)) return [k, v];
    } catch { /* дальше */ }
  }
  // <option value="date_desc">Сначала новые</option> внутри <select name="sort">
  const sel = /<select\b[^>]*name=["'](sort|order|sortBy|sort_by|orderBy)["'][^>]*>([\s\S]*?)<\/select>/i.exec(text);
  if (sel) {
    for (const o of sel[2].matchAll(/<option\b[^>]*value=["']([^"']+)["'][^>]*>([^<]*)</gi)) if (SORT_WORDS.test(o[2])) return [sel[1], o[1]];
  }
  // JSON в странице: {"value":"date_desc","title":"Сначала новые"} рядом со словом sort
  for (const m of text.matchAll(/"(?:value|code|key|id)"\s*:\s*"([\w-]+)"\s*,\s*"(?:title|name|label|text)"\s*:\s*"([^"]{1,40})"/g)) {
    if (SORT_WORDS.test(m[2]) && /sort|order/i.test(text.slice(Math.max(0, m.index - 300), m.index))) return ['sort', m[1]];
  }
  return null;
}
let kaspiSortParam;   // undefined — ещё не искали, null — на странице не нашлось

// «Весь Казахстан» у Kaspi — такой выдачи нет: без города в ссылке сайт показывает один город.
// Поэтому ссылку без города обходим по городам по кругу — за проверку несколько городов, первая
// страница каждого (с сортировкой «сначала новые»). Список городов: крупные из нашего списка плюс
// все города, на которые ссылается сама страница Kaspi (выбор города), — так попадают и мелкие.
// Город, впервые увиденный после запуска, только запоминается (что уже есть — не присылаем).
const KASPI_CITIES_PER_POLL = 3;
// Запасной список: крупные и средние города. Неверный адрес города (Kaspi ответил 404) сам
// выпадает из обхода, а недостающие добавляются со страницы Kaspi.
const KASPI_CITY_SLUGS = [...CITIES.map((c) => c.slug), 'uralsk', 'kyzylorda', 'petropavlovsk',
  'taldykorgan', 'turkestan', 'kokshetau', 'ekibastuz', 'temirtau', 'zhezkazgan', 'rudnyy',
  'balkhash', 'satpaev', 'kaskelen', 'konaev', 'zhanaozen', 'aksay', 'stepnogorsk', 'shchuchinsk'];
const kaspiRounds = new Map();   // ссылка без города → { cities: [], next, seeded: Set, dead: Set }

function kaspiSplit(url) {
  const u = new URL(url);
  const parts = u.pathname.split('/').filter(Boolean);
  const citySlugs = new Set([...KASPI_CITY_SLUGS, ...[...kaspiRounds.values()].flatMap((r) => r.cities)]);
  const city = parts.length > 1 && citySlugs.has(parts[0]) ? parts[0] : '';
  return { u, city, path: (city ? parts.slice(1) : parts).join('/') };
}

// Города, на которые страница ссылается в той же рубрике: /<город>/<рубрика>/.
function kaspiCityLinks(html, path) {
  const out = new Set();
  const esc = path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(?:obyavleniya\\.kaspi\\.kz)?/([a-z][a-z0-9-]{2,30})/${esc}/?["'?#]`, 'gi');
  for (const m of String(html).matchAll(re)) {
    const slug = m[1].toLowerCase();
    if (!['a', 'k', 'api', 'static', 'img', 'search'].includes(slug)) out.add(slug);
  }
  return [...out];
}

const KASPI = {
  key: 'kaspi', title: 'Kaspi Объявления', emoji: '🔴', hostRe: /(^|\.)kaspi\.kz$/i, turbo: false,
  normalize: (url) => { checkHost(url, /(^|\.)kaspi\.kz$/i, 'Kaspi'); return url.split('#')[0]; },
  isAdUrl: (url) => { try { return /^\/a\/.+-\d{6,}\/?$/.test(new URL(url).pathname); } catch { return false; } },
  // Сортировку «сначала новые» ссылкой Kaspi не включить (не нашёл как) — смотрим 3 страницы.
  async fetchSearch(url) {
    const { city } = kaspiSplit(this.normalize(url));
    if (!city) return this.fetchAllCities(url);
    return (await this.fetchOne(url)).map((a) => ({ ...a, city: a.city || kaspiCityName(city) }));
  },

  // Ссылка без города: несколько городов за раз, по кругу.
  async fetchAllCities(url) {
    const { u, path } = kaspiSplit(this.normalize(url));
    const key = `${path}${u.search}`;
    let r = kaspiRounds.get(key);
    if (!r) {
      r = { cities: [...KASPI_CITY_SLUGS], next: 0, seeded: new Set(), dead: new Set() };
      kaspiRounds.set(key, r);
      // Страница без города: заодно берём с неё список городов (там есть выбор города).
      const html = await getHtml(this.normalize(url)).catch(() => null);
      if (html) for (const c of kaspiCityLinks(html, path)) if (!r.cities.includes(c)) r.cities.push(c);
    }
    const out = [];
    for (let i = 0; i < KASPI_CITIES_PER_POLL && r.cities.length; i++) {
      const c = r.cities[r.next % r.cities.length];
      r.next = (r.next + 1) % r.cities.length;
      const cityUrl = new URL(`${KASPI_BASE}/${c}/${path}/`);
      for (const [k, v] of u.searchParams) cityUrl.searchParams.set(k, v);
      let ads;
      try {
        ads = await this.fetchOne(cityUrl.toString(), 1);
      } catch (e) {
        if (/404/.test(e.message)) { r.cities = r.cities.filter((x) => x !== c); r.dead.add(c); continue; }
        throw e;
      }
      const seed = !r.seeded.has(c);
      r.seeded.add(c);
      // Номера у разных городов идут вперемешку — «ниже отметки» здесь не значит «старое».
      for (const a of ads) out.push({ ...a, city: a.city || kaspiCityName(c), anyOrder: true, seedOnly: seed || undefined });
    }
    return out;
  },

  // Объявление по одному номеру: /a/<номер>/ — сайт сам ведёт на полную ссылку. Нет такого (или
  // ещё на проверке) — null. Заглушка вместо карточки (ни цены, ни фото) — тоже null.
  async fetchById(id) {
    const url = `${KASPI_BASE}/a/${id}/`;
    const html = await getHtml(url);
    if (html == null) return null;
    const d = kaspiFill(parseDetail(html, { id, url }));
    return d.title && (d.price || d.photos.length) ? { ...d, id, url, source: 'kaspi' } : null;
  },

  async fetchOne(url, pages = 3) {
    let base = this.normalize(url);
    const hasSort = (u) => /[?&](sort|order|sortBy|sort_by|orderBy)=/i.test(u);
    if (!hasSort(base) && kaspiSortParam) base = withParam(base, kaspiSortParam);
    let html = await getHtml(base);
    if (html == null) throw new Error('Kaspi ответил 404 — проверьте ссылку');
    if (kaspiSortParam === undefined) {
      kaspiSortParam = kaspiSort(html);
      if (kaspiSortParam && !hasSort(base)) {
        base = withParam(base, kaspiSortParam);
        html = (await getHtml(base)) ?? html;
      }
    }
    const all = new Map(kaspiIds(html).map((a) => [a.id, a]));
    for (let page = 2; page <= pages && all.size; page++) {
      const u = new URL(base);
      u.searchParams.set('page', String(page));
      const more = await getHtml(u.toString()).catch(() => null);
      if (!more) break;
      for (const a of kaspiIds(more)) if (!all.has(a.id)) all.set(a.id, a);
    }
    return [...all.values()];
  },
  async fetchDetail(ad) {
    const html = await getHtml(ad.url);
    return html == null ? null : kaspiFill(parseDetail(html, { id: ad.id, url: ad.url }));
  },
  link: (ad) => ad.url,
  wizard: {
    categories: KASPI_CATEGORIES,
    cities: CITIES,
    words: true,     // слова — частью ссылки: k--слово
    noPrice: true,   // фильтр цены у Kaspi в ссылке не проверен — не спрашиваем
    build: ({ path, city, words }) => {
      const q = String(words || '').trim().toLowerCase().replace(/\s+/g, '-');
      return `${KASPI_BASE}/${city ? `${city}/` : ''}${path}/${q ? `k--${encodeURIComponent(q)}/` : ''}`;
    },
  },
};

function withParam(url, [k, v]) {
  const u = new URL(url);
  u.searchParams.set(k, v);
  return u.toString();
}

const ALL = [OLX, KOLESA, KRISHA, KASPI];
const BY_KEY = Object.fromEntries(ALL.map((s) => [s.key, s]));

function byUrl(url) {
  let host;
  try { host = new URL(url).hostname; } catch { return null; }
  return ALL.find((s) => s.hostRe.test(host)) || null;
}

// Город Kaspi по адресу: имя из нашего списка, иначе — сам адрес с большой буквы.
const KASPI_CITY_NAMES = {
  ...Object.fromEntries(CITIES.map((c) => [c.slug, c.name])),
  uralsk: 'Уральск', kyzylorda: 'Кызылорда', petropavlovsk: 'Петропавловск', taldykorgan: 'Талдыкорган',
  turkestan: 'Туркестан', kokshetau: 'Кокшетау', ekibastuz: 'Экибастуз', temirtau: 'Темиртау',
  zhezkazgan: 'Жезказган', rudnyy: 'Рудный', balkhash: 'Балхаш', satpaev: 'Сатпаев', kaskelen: 'Каскелен',
  konaev: 'Конаев', zhanaozen: 'Жанаозен', aksay: 'Аксай', stepnogorsk: 'Степногорск', shchuchinsk: 'Щучинск',
};
function kaspiCityName(slug) {
  return KASPI_CITY_NAMES[slug] || (slug ? slug[0].toUpperCase() + slug.slice(1).replace(/-/g, ' ') : '');
}

// Карточка Kaspi: города нет в разметке — берём из крошек (/astana/…).
function kaspiFill(d) {
  if (!d.city) {
    const cities = new Set([...KASPI_CITY_SLUGS, ...[...kaspiRounds.values()].flatMap((r) => r.cities)]);
    const c = (d.crumbs || []).map((p) => p.split('/')[0]).find((x) => cities.has(x));
    if (c) d.city = kaspiCityName(c);
  }
  return d;
}

// Подходит ли объявление Kaspi, найденное по номеру, поиску Kaspi: рубрика (по крошкам карточки),
// город, слова. Не понятно (крошек нет, город не указан) — «нет» с причиной: его принесёт поиск.
function kaspiMismatch(sub, ad) {
  let parts;
  try { parts = new URL(sub.url).pathname.split('/').filter(Boolean); } catch { return 'ссылка поиска'; }
  const cities = new Set([...KASPI_CITY_SLUGS, ...[...kaspiRounds.values()].flatMap((r) => r.cities)]);
  const city = parts.length > 1 && cities.has(parts[0]) ? parts.shift() : '';
  const wordsSeg = parts.findIndex((p) => p.startsWith('k--'));
  const words = wordsSeg >= 0 ? decodeURIComponent(parts[wordsSeg].slice(3)).split(/[-\s]+/).filter(Boolean) : [];
  const path = (wordsSeg >= 0 ? parts.slice(0, wordsSeg) : parts).join('/').toLowerCase();
  const crumbs = ad.crumbs || [];
  if (!crumbs.length) return 'рубрика объявления не видна';
  let adCity = '';
  const cats = crumbs.map((c) => {
    const p = c.split('/');
    if (p.length > 1 && cities.has(p[0])) { adCity = adCity || p[0]; return p.slice(1).join('/'); }
    return c;
  });
  if (path && !cats.some((c) => c === path || c.startsWith(`${path}/`))) return 'другая рубрика';
  if (city) {
    const name = (CITIES.find((c) => c.slug === city) || {}).name || '';
    const same = adCity ? adCity === city : !!(name && ad.city && ad.city.toLowerCase() === name.toLowerCase());
    if (!same) return adCity || ad.city ? 'другой город' : 'город объявления не виден';
  }
  if (words.length) {
    const text = `${ad.title || ''} ${ad.description || ''}`.toLowerCase();
    const miss = words.find((w) => !text.includes(stem(w.toLowerCase())));
    if (miss) return `нет слова «${miss}»`;
  }
  return null;
}

module.exports = { kaspiMismatch, kaspiIds, kaspiSort, kaspiCityLinks, kaspiRounds, kaspiSortInUse: () => kaspiSortParam, ALL, BY_KEY, byUrl, get: (key) => BY_KEY[key] || OLX, CITIES, olxCategories: cats };
