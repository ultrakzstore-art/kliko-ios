// Всё, что знаем про OLX.kz. Устройство сайта здесь не угадываем вслепую — каждое место,
// где OLX может поменяться, разобрано с запасными вариантами, а `npm run probe` показывает,
// что реально пришло.
//
// Проверено по живой ссылке: короткий код в адресе объявления — это его номер в 62-ричной
// записи (цифры, a–z, A–Z): «IDr9sfK» = 401214632. Номера сквозные, растут со временем.

const BASE = 'https://www.olx.kz';
const ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  'Accept-Language': 'ru-RU,ru;q=0.9,kk;q=0.8',
};

function decodeId(code) {
  let n = 0;
  for (const ch of code) {
    const v = ALPHABET.indexOf(ch);
    if (v < 0) throw new Error(`не код объявления: ${code}`);
    n = n * 62 + v;
  }
  return n;
}

function encodeId(n) {
  let s = '';
  do { s = ALPHABET[n % 62] + s; n = Math.floor(n / 62); } while (n > 0);
  return s;
}

// Номер объявления из любой его ссылки: …-IDr9sfK.html или …#401214632.
function idFromUrl(url) {
  const m = /-ID([0-9a-zA-Z]+)\.html/.exec(url);
  if (m) return decodeId(m[1]);
  const h = /#(\d{6,})/.exec(url);
  return h ? Number(h[1]) : null;
}

class HttpError extends Error {
  constructor(status, url) {
    super(`OLX ответил ${status}`);
    this.status = status;
    this.url = url;
  }
}

async function get(url, accept) {
  const res = await fetch(url, { headers: { ...HEADERS, Accept: accept }, redirect: 'follow', signal: AbortSignal.timeout(20_000) });
  if (!res.ok) throw new HttpError(res.status, url);
  return res;
}

// ---------- поиск ----------

// Ссылку поиска, которую человек скопировал с сайта, переворачиваем «сначала новые».
function newestFirst(searchUrl) {
  const u = new URL(searchUrl);
  if (!/(^|\.)olx\.kz$/.test(u.hostname)) throw new Error('Нужна ссылка на поиск olx.kz');
  u.searchParams.set('search[order]', 'created_at:desc');
  u.hash = '';
  return u.toString();
}

async function fetchSearch(searchUrl, page = 1) {
  const u = new URL(newestFirst(searchUrl));
  if (page > 1) u.searchParams.set('page', String(page));
  const html = await (await get(u.toString(), 'text/html')).text();
  return parseSearchHtml(html);
}

// Сайт кладёт данные страницы в window.__PRERENDERED_STATE__ — JSON внутри JS-строки.
// Если его нет или он другой — достаём хотя бы номера из ссылок на объявления.
function parseSearchHtml(html) {
  const state = prerenderedState(html);
  const raw = state && findAdsArray(state);
  if (raw && raw.length) return { source: 'state', ads: raw.map(normalizeListingAd).filter((a) => a.id) };
  const ids = [...new Set([...html.matchAll(/-ID([0-9a-zA-Z]+)\.html/g)].map((m) => decodeId(m[1])))];
  return { source: 'links', ads: ids.map((id) => ({ id, url: `${BASE}/d/obyavlenie/-ID${encodeId(id)}.html` })) };
}

function prerenderedState(html) {
  const m = /window\.__PRERENDERED_STATE__\s*=\s*("(?:[^"\\]|\\.)*")/.exec(html);
  if (!m) return null;
  try { return JSON.parse(JSON.parse(m[1])); } catch { return null; }
}

// Ищем массив объявлений, не завязываясь на точный путь (listing.listing.ads и т.п.).
function findAdsArray(node, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 6) return null;
  if (Array.isArray(node)) {
    if (node.length && node.every((x) => x && typeof x === 'object' && 'id' in x && ('title' in x || 'url' in x))) return node;
    return null;
  }
  if (Array.isArray(node.ads)) {
    const r = findAdsArray(node.ads, depth + 1);
    if (r) return r;
  }
  for (const v of Object.values(node)) {
    const r = findAdsArray(v, depth + 1);
    if (r) return r;
  }
  return null;
}

function normalizeListingAd(a) {
  const price = a.price || {};
  return {
    id: Number(a.id),
    title: a.title || '',
    url: a.url || '',
    price: num(price.regularPrice?.value ?? price.value),
    priceLabel: price.displayValue || price.label || '',
    city: a.location?.cityName || a.location?.city?.name || '',
    categoryId: num(a.category?.id ?? a.categoryId),
    createdAt: time(a.createdTime || a.created_time),
    promoted: !!(a.isPromoted || a.promotion?.top_ad || a.promotion?.highlighted),
    business: !!(a.isBusiness || a.business),
    userId: a.user?.id ?? a.userId ?? null,
    photo: photoUrl(a.photos?.[0]),
  };
}

// ---------- карточка по номеру ----------

// Карточка объявления в том же JSON, которым пользуется сайт. 404/410 — такого номера на
// OLX.kz нет (или ещё не создан, или удалён).
async function fetchOffer(id) {
  const res = await fetch(`${BASE}/api/v1/offers/${id}/`, { headers: { ...HEADERS, Accept: 'application/json' }, signal: AbortSignal.timeout(15_000) });
  if (res.status === 404 || res.status === 410) return null;
  if (!res.ok) throw new HttpError(res.status, res.url);
  const body = await res.json();
  return normalizeOffer(body.data || body);
}

function normalizeOffer(o) {
  const params = Array.isArray(o.params) ? o.params : [];
  const priceParam = params.find((p) => p.key === 'price' || p.type === 'price');
  const pv = priceParam?.value || {};
  return {
    id: Number(o.id),
    title: o.title || '',
    url: o.url || `${BASE}/d/obyavlenie/-ID${encodeId(Number(o.id))}.html`,
    description: stripHtml(o.description || '').slice(0, 2000),
    price: num(pv.value ?? o.price?.value),
    priceLabel: pv.label || (pv.value ? `${pv.value} ${pv.currency || '₸'}` : ''),
    city: o.location?.city?.name || o.location?.cityName || '',
    region: o.location?.region?.name || '',
    categoryId: num(o.category?.id),
    createdAt: time(o.created_time || o.createdTime),
    status: o.status || '',
    promoted: !!(o.promotion?.top_ad || o.promotion?.highlighted),
    business: !!o.business,
    userId: o.user?.id ?? null,
    userName: o.user?.name || '',
    // Продавец: с какого времени на OLX, частное лицо или бизнес.
    sellerSince: time(o.user?.created),
    sellerCompany: o.user?.company_name || '',
    sellerAbout: stripHtml(o.user?.about || '').slice(0, 200),
    params: params.filter((p) => p !== priceParam).map((p) => `${p.name}: ${p.value?.label ?? p.value?.value ?? ''}`).slice(0, 6),
    photo: photoUrl(o.photos?.[0]),
    photos: (o.photos || []).map(photoUrl).filter(Boolean).slice(0, 10),
  };
}

// ---------- мелочи ----------

function photoUrl(p) {
  const link = typeof p === 'string' ? p : p?.link || p?.url;
  return link ? link.replace('{width}', '800').replace('{height}', '600') : '';
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) && v !== null && v !== '' ? n : null;
}

function time(v) {
  const t = v ? Date.parse(v) : NaN;
  return Number.isFinite(t) ? t : null;
}

function stripHtml(s) {
  return s.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
}

// Самые свежие объявления всей доски OLX.kz: через тот же API, что и карточки (в списке сразу
// описание и фото), не вышло — страница всей доски.
async function fetchLatest() {
  try {
    const res = await get(`${BASE}/api/v1/offers/?offset=0&limit=40&sort_by=created_at:desc`, 'application/json');
    const list = (await res.json())?.data;
    if (Array.isArray(list) && list.length) return list.map(normalizeOffer);
  } catch (e) {
    if (e instanceof HttpError && (e.status === 403 || e.status === 429)) throw e;
  }
  return (await fetchSearch(`${BASE}/list/`)).ads;
}

// Ссылка «Все объявления автора» — со страницы самого объявления: её рисует OLX, так что
// формат всегда верный (/list/user/…, у магазинов — <имя>.olx.kz/home/). Нет — null.
function sellerLinkIn(html) {
  const text = String(html).replace(/\\\//g, '/');
  const m = /(https?:\/\/(?:www\.)?olx\.kz)?(\/(?:d\/)?(?:[a-z]{2}\/)?list\/user\/[A-Za-z0-9_-]+\/?)/.exec(text)
    || /(https?:\/\/[a-z0-9-]+\.olx\.kz\/home\/?)/.exec(text);
  if (!m) return null;
  return m[2] ? `${BASE}${m[2]}` : m[1];
}

const sellerCache = new Map();   // номер объявления → ссылка (или null)
async function sellerLink(ad) {
  if (sellerCache.has(ad.id)) return sellerCache.get(ad.id);
  const url = ad.url && /^https?:/.test(ad.url) ? ad.url.split('#')[0] : `${BASE}/d/obyavlenie/-ID${encodeId(ad.id)}.html`;
  let link = null;
  try { link = sellerLinkIn(await (await get(url, 'text/html')).text()); } catch { link = null; }
  sellerCache.set(ad.id, link);
  if (sellerCache.size > 2000) sellerCache.delete(sellerCache.keys().next().value);
  return link;
}

module.exports = {
  sellerLink, sellerLinkIn,
  fetchLatest,
  BASE, decodeId, encodeId, idFromUrl, newestFirst, fetchSearch, parseSearchHtml, fetchOffer, normalizeOffer, HttpError,
};
