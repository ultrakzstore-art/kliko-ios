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

// Запасной список подрубрик — если страница рубрики OLX не открылась или не разобралась
// (например, OLX ответил 403). Тот же, что в приложении.
const FALLBACK = {
  'elektronika': [
    ['Телефоны и аксессуары', 'telefony-i-aksesuary'],
    ['Компьютеры и комплектующие', 'kompyutery-i-komplektuyuschie'],
    ['Ноутбуки и аксессуары', 'noutbuki-i-aksesuary'],
    ['Планшеты, эл. книги', 'planshety-el-knigi-i-aksessuary'],
    ['ТВ и видеотехника', 'tv-videotehnika'],
    ['Аудиотехника', 'audiotehnika'],
    ['Игры и приставки', 'igry-i-igrovye-pristavki'],
    ['Фото и видео', 'foto-video'],
    ['Техника для дома', 'tehnika-dlya-doma'],
    ['Техника для кухни', 'tehnika-dlya-kuhni'],
    ['Климатическое оборудование', 'klimaticheskoe-oborudovanie'],
    ['Индивидуальный уход', 'individualnyy-uhod'],
    ['Прочая электроника', 'prochaja-electronika'],
  ],
  'transport': [
    ['Легковые автомобили', 'legkovye-avtomobili'],
    ['Грузовые автомобили', 'gruzovye-avtomobili'],
    ['Мото', 'moto'],
    ['Спецтехника', 'spetstehnika'],
    ['Сельхозтехника', 'selhoztehnika'],
    ['Автобусы', 'avtobusy'],
    ['Водный транспорт', 'vodnyy-transport'],
    ['Прицепы', 'pritsepy-doma-na-kolesah'],
    ['Другой транспорт', 'drugoy-transport'],
  ],
  'zapchasti-dlya-transporta': [
    ['Автозапчасти', 'avtozapchasti'],
    ['Шины, диски и колёса', 'shiny-diski-i-kolesa'],
    ['Аксессуары для авто', 'aksessuary-dlya-avto'],
    ['Мотозапчасти', 'motozapchasti'],
    ['Запчасти для спецтехники', 'zapchasti-dlya-spetstehniki'],
  ],
  'nedvizhimost': [
    ['Квартиры', 'kvartiry'],
    ['Дома', 'doma'],
    ['Земля', 'zemlya'],
    ['Коммерческая', 'kommercheskaya-nedvizhimost'],
    ['Посуточно', 'posutochno-pochasovo'],
    ['Гаражи и парковки', 'garazhy-parkovki'],
  ],
  'dom-i-sad': [
    ['Мебель', 'mebel'],
    ['Предметы интерьера', 'predmety-interera'],
    ['Строительство и ремонт', 'stroitelstvo-remont'],
    ['Инструменты', 'instrumenty'],
    ['Сад и огород', 'sad-ogorod'],
    ['Посуда', 'posuda-kuhonnaya-utvar'],
    ['Хозинвентарь', 'hozyaystvennyy-inventar'],
    ['Прочее для дома', 'prochie-tovary-dlya-doma'],
  ],
  'moda-i-stil': [
    ['Женская одежда', 'zhenskaya-odezhda'],
    ['Мужская одежда', 'muzhskaya-odezhda'],
    ['Женская обувь', 'zhenskaya-obuv'],
    ['Мужская обувь', 'muzhskaya-obuv'],
    ['Аксессуары', 'aksessuary'],
    ['Наручные часы', 'naruchnye-chasy'],
    ['Красота и здоровье', 'krasota-zdorove'],
  ],
  'detskiy-mir': [
    ['Детская одежда', 'detskaya-odezhda'],
    ['Детская обувь', 'detskaya-obuv'],
    ['Игрушки', 'igrushki'],
    ['Коляски', 'detskie-kolyaski'],
    ['Детская мебель', 'detskaya-mebel'],
    ['Автокресла', 'detskie-avtokresla'],
  ],
  'hobbi-otdyh-i-sport': [
    ['Спорт и отдых', 'sport-otdyh'],
    ['Велосипеды', 'velo'],
    ['Музыкальные инструменты', 'muzykalnye-instrumenty'],
    ['Книги и журналы', 'knigi-zhurnaly'],
    ['Антиквариат и коллекции', 'antikvariat-kollektsii'],
    ['Туризм', 'turizm'],
    ['Рыбалка и охота', 'ohota-rybalka'],
  ],
  'zhivotnye': [
    ['Собаки', 'sobaki'],
    ['Кошки', 'koshki'],
    ['Птицы', 'ptitsy'],
    ['Аквариумистика', 'akvariumnye-rybki'],
    ['Сельхоз животные', 'selskohozyaystvennye-zhivotnye'],
    ['Зоотовары', 'zootovary'],
  ],
};
const FALLBACK_CHILDREN = Object.fromEntries(Object.entries(FALLBACK).map(([parent, list]) =>
  [parent, list.map(([name, slug]) => ({ name, path: `${parent}/${slug}` }))]));

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
  if (!list.length && FALLBACK_CHILDREN[path]) {
    // С OLX не вышло — встроенный список; живой попробуем снова через час, а не через сутки.
    cache.set(path, { at: Date.now() - 23 * 3600_000, list: FALLBACK_CHILDREN[path] });
    return FALLBACK_CHILDREN[path];
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
  TOP, CITIES, FALLBACK_CHILDREN, children, parseChildren, buildSearchUrl, parsePrice,
  _setFetch: (fn) => { fetchHtml = fn; cache.clear(); },
};
