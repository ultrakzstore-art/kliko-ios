// Подходит ли объявление, пойманное «турбо» (по номеру, в обход поиска), под подписку.
// Поиск OLX фильтрует сам; для турбо фильтры восстанавливаем из ссылки поиска, а рубрику и
// город выучиваем по тому, что этот поиск реально выдаёт.

// Из ссылки: слова запроса (/q-hp-250/ или search[q]) и цена от/до.
function filtersFromUrl(searchUrl) {
  const u = new URL(searchUrl);
  const q = /\/q-([^/]+)\/?/.exec(decodeURIComponent(u.pathname));
  const words = (q ? q[1].replace(/-/g, ' ') : u.searchParams.get('search[q]') || '')
    .toLowerCase().split(/\s+/).filter((w) => w.length > 1);
  const from = Number(u.searchParams.get('search[filter_float_price:from]')) || null;
  const to = Number(u.searchParams.get('search[filter_float_price:to]')) || null;
  return { words, priceFrom: from, priceTo: to };
}

// Учим подписку по выдаче её поиска: какие рубрики там встречаются и один ли там город.
function learn(learned, ads) {
  const cats = new Set(learned.categoryIds || []);
  const cities = new Set(learned.cities || []);
  let total = learned.total || 0;
  for (const a of ads) {
    if (a.categoryId) cats.add(a.categoryId);
    if (a.city) cities.add(a.city);
    total += 1;
  }
  return { categoryIds: [...cats], cities: [...cities].slice(0, 50), total };
}

// Почему объявление не подходит поиску (null — подходит). Для ленты и турбо: поиск OLX
// фильтрует сам, а тут фильтры восстанавливаем из ссылки и из выученного по выдаче.
function mismatch(sub, ad) {
  const f = filtersFromUrl(sub.url);
  const L = sub.learned || {};
  const title = `${ad.title} ${ad.description || ''}`.toLowerCase();
  // Слова — по основе: «ноутбуки» найдёт «ноутбук», «ноутбука»; поиск OLX тоже так ищет.
  const missing = f.words.find((w) => !title.includes(stem(w)));
  if (missing) return `нет слова «${missing}»`;
  // Обмен, «Отдам даром» и объявления без цены проходят любой фильтр цены.
  if (!noPrice(ad)) {
    if (f.priceFrom && ad.price < f.priceFrom) return 'цена ниже «от»';
    if (f.priceTo && ad.price > f.priceTo) return 'цена выше «до»';
  }
  // Рубрика: пока поиск не показал ни одной — не судим; потом только знакомые рубрики.
  if ((L.categoryIds || []).length && ad.categoryId && !L.categoryIds.includes(ad.categoryId)) return `рубрика ${ad.categoryId} в этом поиске ещё не встречалась`;
  // Город: если за 20+ объявлений поиск показывал ровно один город — значит, в ссылке фильтр по городу.
  if ((L.total || 0) >= 20 && (L.cities || []).length === 1 && ad.city && ad.city !== L.cities[0]) return `город ${ad.city}, а поиск — ${L.cities[0]}`;
  // Совсем без фильтров (ни слов, ни рубрик ещё не выучено) не шлём — иначе полетит весь OLX.
  if (!f.words.length && !(L.categoryIds || []).length) return 'поиск ещё не выучил рубрику';
  return null;
}

function matches(sub, ad) {
  return mismatch(sub, ad) === null;
}

// Без цены: обмен, бесплатно (цена 0) или цена не указана.
function noPrice(ad) {
  return !(ad.price > 0) || /обмен|бесплат|даром/i.test(ad.priceLabel || '');
}

// Грубая основа слова: у длинных слов отбрасываем окончание (до 2 букв).
function stem(w) {
  return w.length > 5 ? w.slice(0, w.length - 2) : w;
}

module.exports = { filtersFromUrl, learn, matches, mismatch, stem, noPrice };
