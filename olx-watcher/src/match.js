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

function matches(sub, ad) {
  const f = filtersFromUrl(sub.url);
  const L = sub.learned || {};
  const title = `${ad.title} ${ad.description || ''}`.toLowerCase();
  // Слова — по основе: «ноутбуки» найдёт «ноутбук», «ноутбука»; поиск OLX тоже так ищет.
  if (f.words.length && !f.words.every((w) => title.includes(stem(w)))) return false;
  if (f.priceFrom && ad.price != null && ad.price < f.priceFrom) return false;
  if (f.priceTo && ad.price != null && ad.price > f.priceTo) return false;
  // Рубрика: пока поиск не показал ни одной — не судим; потом только знакомые рубрики.
  if ((L.categoryIds || []).length && ad.categoryId && !L.categoryIds.includes(ad.categoryId)) return false;
  // Город: если за 20+ объявлений поиск показывал ровно один город — значит, в ссылке фильтр по городу.
  if ((L.total || 0) >= 20 && (L.cities || []).length === 1 && ad.city && ad.city !== L.cities[0]) return false;
  // Совсем без фильтров (ни слов, ни рубрик ещё не выучено) турбо не шлёт — иначе полетит весь OLX.
  if (!f.words.length && !(L.categoryIds || []).length) return false;
  return true;
}

// Грубая основа слова: у длинных слов отбрасываем окончание (до 2 букв).
function stem(w) {
  return w.length > 5 ? w.slice(0, w.length - 2) : w;
}

module.exports = { filtersFromUrl, learn, matches, stem };
