// Общий разбор страниц объявлений для площадок без своего JSON (Kolesa, Krisha, Kaspi):
// номера из ссылок на объявления в выдаче, подробности — из карточки: og-метки и JSON-LD,
// которые сайты кладут для поисковиков и соцсетей. Устройство этих сайтов изнутри не
// проверено — `npm run probe -- <ссылка>` покажет, что реально разобралось.

const { HttpError } = require('../olx');

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  'Accept-Language': 'ru-RU,ru;q=0.9,kk;q=0.8',
  Accept: 'text/html',
};

async function getHtml(url) {
  const res = await fetch(url, { headers: HEADERS, redirect: 'follow', signal: AbortSignal.timeout(20_000) });
  if (res.status === 404 || res.status === 410) return null;
  if (!res.ok) throw new HttpError(res.status, url);
  return res.text();
}

// Номера объявлений из ссылок выдачи (по шаблону площадки) и текст ссылки как черновой заголовок.
function idsFromListing(html, linkRe) {
  const out = new Map();
  for (const m of html.matchAll(linkRe)) {
    const id = Number(m[1]);
    if (!id || out.has(id)) continue;
    out.set(id, { id, title: '' });
  }
  return [...out.values()];
}

function meta(html, prop) {
  const re = new RegExp(`<meta[^>]+(?:property|name)=["']${prop.replace(/[:.]/g, '\\$&')}["'][^>]*content=["']([^"']*)["']|<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${prop.replace(/[:.]/g, '\\$&')}["']`, 'gi');
  const all = [];
  for (const m of html.matchAll(re)) all.push(decode(m[1] ?? m[2] ?? ''));
  return all;
}

function jsonLd(html) {
  const out = [];
  for (const m of html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const v = JSON.parse(m[1].trim());
      (Array.isArray(v) ? v : [v]).forEach((x) => out.push(...(x['@graph'] || [x])));
    } catch { /* битый JSON-LD пропускаем */ }
  }
  return out;
}

// Карточка объявления → общий вид (как у OLX): заголовок, цена, город, фото, описание, дата.
function parseDetail(html, { id, url, currency = '₸' }) {
  const ld = jsonLd(html);
  const product = ld.find((x) => x && (x.offers || /Product|Offer|Car|Vehicle|Apartment|House|Residence|Accommodation/i.test(String(x['@type']))));
  const offer = product && (Array.isArray(product.offers) ? product.offers[0] : product.offers);
  const title = decode(product?.name || meta(html, 'og:title')[0] || (/<title>([^<]*)<\/title>/i.exec(html) || [])[1] || '').trim();
  const description = decode(product?.description || meta(html, 'og:description')[0] || meta(html, 'description')[0] || '').trim();
  const images = [
    ...[].concat(product?.image || []).map((i) => (typeof i === 'string' ? i : i?.url)).filter(Boolean),
    ...meta(html, 'og:image'),
  ];
  let price = Number(offer?.price ?? offer?.lowPrice);
  if (!Number.isFinite(price) || price <= 0) {
    const m = /(\d[\d\s\u00a0]{3,})\s*(?:₸|〒|тг|тенге|KZT)/i.exec(`${title} ${description}`);
    price = m ? Number(m[1].replace(/[\s\u00a0]/g, '')) : null;
  }
  const city = decode(product?.address?.addressLocality || offer?.availableAtOrFrom?.address?.addressLocality || '')
    || (/ в ([А-ЯЁ][а-яё-]+(?:\s[А-ЯЁ][а-яё-]+)?)\s*$/.exec(title) || [])[1] || '';
  const sellerUrl = findSeller(html, url, product, offer);
  // Krisha подписывает продавца: «Хозяин недвижимости» или «Агент» / «Специалист».
  // Kolesa: автосалон / дилер — не хозяин; «Частное лицо» — хозяин. Во множественном числе
  // («Автосалоны», «Дилеры») это пункты меню сайта, а «в автосалоне», «у дилера» — текст
  // описания; такое не считаем. Только слово-подпись с большой буквы.
  const owner = /kolesa\.kz/i.test(url)
    ? (/"@type"\s*:\s*"(AutoDealer|AutomotiveBusiness|CarDealer)"/i.test(html)
      || /(^|[>\s"])(Автосалон|Автодилер|Официальный дилер|Проверенный дилер|Дилл?ер)(?![а-яё])/.test(html) ? false
      : /Частное\s+лицо|Собственник|Хозяин/i.test(html) ? true : null)
    : /Хозяин\s+недвижимости/i.test(html) ? true
    : /(^|[>\s])(Агент|Специалист|Агентство недвижимости|Риэлтор|Риелтор)([<\s,.]|$)/i.test(html) ? false : null;
  const posted = Date.parse(product?.datePosted || product?.datePublished || offer?.validFrom || '');
  return {
    id,
    url,
    title,
    description: description.slice(0, 2000),
    price: Number.isFinite(price) && price > 0 ? price : null,
    priceLabel: Number.isFinite(price) && price > 0 ? `${Number(price).toLocaleString('ru-RU')} ${currency}` : '',
    city,
    region: '',
    categoryId: null,
    createdAt: Number.isFinite(posted) ? posted : null,
    status: '',
    promoted: false,
    business: false,
    userId: null,
    userName: '',
    sellerUrl,
    owner,
    business: owner === false,
    params: [],
    photo: [...new Set(images)][0] || '',
    photos: [...new Set(images)].slice(0, 12),
  };
}

// Страница продавца — «все объявления автора». Сначала из JSON-LD (seller/author с url),
// потом из ссылок карточки на тот же сайт вида /user/…, /pro/…, /seller/…, /company/….
// Не нашлась — пусто, и кнопки не будет.
function findSeller(html, url, product, offer) {
  let host;
  try { host = new URL(url).host; } catch { return ''; }
  const sameSite = (u) => {
    try {
      const x = new URL(decode(u), `https://${host}`);
      const base = (h) => h.replace(/^(www|m)\./, '');
      return base(x.host) === base(host) && x.protocol.startsWith('http') ? x.href : '';
    } catch { return ''; }
  };
  for (const p of [offer?.seller, product?.seller, offer?.offeredBy, product?.author]) {
    const u = p && (typeof p === 'string' ? p : p.url || p['@id']);
    const ok = u && sameSite(u);
    if (ok) return ok;
  }
  const re = /href=["']([^"']*\/(?:user|users|seller|sellers|profile|pro|agent|agents|company|companies|shop|dealer|dealers)\/[\w.-]+\/?[^"'#]*)["']/gi;
  for (const m of html.matchAll(re)) {
    const ok = sameSite(m[1]);
    if (ok && !/\/(login|register|auth|settings|cabinet)\b/i.test(ok)) return ok;
  }
  return '';
}

function decode(s) {
  return String(s)
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
}

module.exports = { getHtml, idsFromListing, parseDetail, meta, jsonLd, HEADERS };
