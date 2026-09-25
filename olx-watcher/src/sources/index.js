// Площадки: у каждой — как развернуть поиск «сначала новые», как достать номера из выдачи,
// как открыть карточку, и (если есть) выбор кнопками. Новизна везде — по номеру объявления
// (водяная отметка), поэтому поднятое старьё не приходит. Турбо — пока только OLX: у
// остальных сначала проверим `npm run probe`, открываются ли карточки по номеру.

const olx = require('../olx');
const cats = require('../categories');
const { getHtml, idsFromListing, parseDetail } = require('./page');

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

// ---------- Kaspi Объявления (экспериментально) ----------
// Устройство ссылок Kaspi Объявлений не проверено: номер берём как последнее длинное число в
// ссылке на объявление. Выбора кнопками нет — поиск задаётся ссылкой с сайта.

const KASPI = {
  key: 'kaspi', title: 'Kaspi Объявления', emoji: '🔴', hostRe: /(^|\.)kaspi\.kz$/i, turbo: false,
  normalize: (url) => { checkHost(url, /(^|\.)kaspi\.kz$/i, 'Kaspi'); return url.split('#')[0]; },
  isAdUrl: () => false,
  async fetchSearch(url) {
    const html = await getHtml(this.normalize(url));
    if (html == null) throw new Error('Kaspi ответил 404 — проверьте ссылку');
    const out = new Map();
    for (const m of html.matchAll(/href=["']([^"']*(?:obyavleni|\/ads?\/|advert|classified)[^"']*)["']/gi)) {
      const nums = m[1].match(/\d{6,}/g);
      if (!nums) continue;
      const id = Number(nums[nums.length - 1]);
      if (!out.has(id)) out.set(id, { id, title: '', url: new URL(m[1], 'https://kaspi.kz').toString() });
    }
    return [...out.values()];
  },
  async fetchDetail(ad) {
    const html = await getHtml(ad.url);
    return html == null ? null : parseDetail(html, { id: ad.id, url: ad.url });
  },
  link: (ad) => ad.url,
  wizard: null,
};

const ALL = [OLX, KOLESA, KRISHA, KASPI];
const BY_KEY = Object.fromEntries(ALL.map((s) => [s.key, s]));

function byUrl(url) {
  let host;
  try { host = new URL(url).hostname; } catch { return null; }
  return ALL.find((s) => s.hostRe.test(host)) || null;
}

module.exports = { ALL, BY_KEY, byUrl, get: (key) => BY_KEY[key] || OLX, CITIES, olxCategories: cats };
