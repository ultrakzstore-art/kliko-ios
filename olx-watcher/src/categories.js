// Рубрики и города OLX.kz для выбора кнопками — чтобы не копировать ссылку с сайта.
//
// Подрубрики берём с самого OLX: открываем страницу рубрики и собираем ссылки вида
// /d/<рубрика>/<подрубрика>/. Верхний уровень и города — встроенным списком (он же
// запасной вариант, если страница OLX не разобралась). Любую собранную ссылку бот
// перед сохранением проверяет пробным запросом — неверный адрес не сохранится молча.

const { BASE } = require('./olx');

const TOP = [
  ['Электроника', 'elektronika'],
  ['Транспорт', 'transport'],
  ['Запчасти для транспорта', 'zapchasti-dlya-transporta'],
  ['Недвижимость', 'nedvizhimost'],
  ['Дом и сад', 'dom-i-sad'],
  ['Мода и стиль', 'moda-i-stil'],
  ['Детский мир', 'detskiy-mir'],
  ['Хобби, отдых и спорт', 'hobbi-otdyh-i-sport'],
  ['Животные', 'zhivotnye'],
  ['Работа', 'rabota'],
  ['Услуги', 'uslugi'],
  ['Отдам даром', 'otdam-darom'],
].map(([name, path]) => ({ name, path }));

const CITIES = [
  ['Алматы', 'almaty'], ['Астана', 'astana'], ['Шымкент', 'shymkent'], ['Караганда', 'karaganda'],
  ['Актобе', 'aktobe'], ['Тараз', 'taraz'], ['Павлодар', 'pavlodar'], ['Усть-Каменогорск', 'ust-kamenogorsk'],
  ['Семей', 'semey'], ['Костанай', 'kostanay'], ['Атырау', 'atyrau'], ['Актау', 'aktau'],
  ['Уральск', 'uralsk'], ['Кызылорда', 'kyzylorda'], ['Петропавловск', 'petropavlovsk'], ['Талдыкорган', 'taldykorgan'],
].map(([name, slug]) => ({ name, slug }));

const CITY_SLUGS = new Set(CITIES.map((c) => c.slug));
// Служебные разделы, которые тоже выглядят как /d/<что-то>/.
const NOT_CATEGORY = new Set(['obyavlenie', 'kk', 'list', 'myaccount', 'account', 'post-new-ad', 'rus', 'ru']);

let fetchHtml = async (url) => {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
      'Accept-Language': 'ru-RU,ru;q=0.9',
      Accept: 'text/html',
    },
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) throw new Error(`OLX ответил ${res.status}`);
  return res.text();
};

const cache = new Map(); // путь рубрики → { at, list }

// Подрубрики на один уровень ниже: [{ name, path }]. Пустой список — это конечная рубрика.
async function children(path) {
  const hit = cache.get(path);
  if (hit && Date.now() - hit.at < 24 * 3600_000) return hit.list;
  let list = [];
  try {
    list = parseChildren(await fetchHtml(`${BASE}/d/${path}/`), path);
  } catch {
    list = [];
  }
  cache.set(path, { at: Date.now(), list });
  return list;
}

function parseChildren(html, path) {
  const depth = path.split('/').length + 1;
  const out = new Map();
  const re = /<a\b[^>]*href="(?:https?:\/\/(?:www\.)?olx\.kz)?\/d\/(?:kk\/)?([a-z0-9-]+(?:\/[a-z0-9-]+)*)\/?(?:\?[^"]*)?"[^>]*>([\s\S]*?)<\/a>/gi;
  for (const m of html.matchAll(re)) {
    const p = m[1].toLowerCase();
    const parts = p.split('/');
    if (parts.length !== depth || !p.startsWith(path + '/')) continue;
    const last = parts[parts.length - 1];
    if (CITY_SLUGS.has(last) || NOT_CATEGORY.has(last) || last.startsWith('q-')) continue;
    const name = decodeEntities(m[2].replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').replace(/\s*\d[\d\s]*$/, '').trim();
    if (!name || name.length > 60 || out.has(p)) continue;
    out.set(p, { name, path: p });
  }
  return [...out.values()].slice(0, 40);
}

function decodeEntities(s) {
  return s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}

// Ссылка поиска из выбранного: рубрика, город, слова, цена.
function buildSearchUrl({ path, city, words, priceFrom, priceTo }) {
  let url = `${BASE}/d/`;
  if (path) url += `${path}/`;
  if (city) url += `${city}/`;
  const q = (words || '').toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, ' ').trim().split(/\s+/).filter(Boolean).join('-');
  if (q) url += `q-${encodeURIComponent(q).replace(/%2D/gi, '-')}/`;
  const params = new URLSearchParams();
  if (priceFrom) params.set('search[filter_float_price:from]', String(priceFrom));
  if (priceTo) params.set('search[filter_float_price:to]', String(priceTo));
  const qs = params.toString();
  return qs ? `${url}?${qs}` : url;
}

// «до 300000», «от 100 до 250 тыс», «150000-300000», «300к» → { from, to }.
function parsePrice(text) {
  const t = text.toLowerCase().replace(/\s+/g, ' ').trim();
  const nums = [...t.matchAll(/(\d+(?:[.,]\d+)?)\s*(к|k|тыс|млн)?/g)].map((m) => {
    let n = parseFloat(m[1].replace(',', '.'));
    if (m[2] === 'к' || m[2] === 'k' || m[2] === 'тыс') n *= 1000;
    if (m[2] === 'млн') n *= 1_000_000;
    return Math.round(n);
  });
  if (!nums.length) return null;
  if (nums.length >= 2) return { from: Math.min(nums[0], nums[1]), to: Math.max(nums[0], nums[1]) };
  if (/^от(\s|\d)/.test(t)) return { from: nums[0], to: null }; // \b в JS не видит границ кириллицы
  return { from: null, to: nums[0] };
}

module.exports = {
  TOP, CITIES, children, parseChildren, buildSearchUrl, parsePrice,
  _setFetch: (fn) => { fetchHtml = fn; cache.clear(); },
};
