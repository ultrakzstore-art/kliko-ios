// VIP-рубрика: рубрика + город закреплены за одним подписчиком на срок. Жёсткое правило —
// проверяется каждое объявление перед отправкой, а не только поиск: обойти родительской
// рубрикой, «всем Казахстаном», словами или ссылкой с сайта нельзя.
//
// Как понять, что объявление из закреплённой рубрики:
//   • город объявления = город закрепления;
//   • и его рубрика OLX (номер) встречалась в выдаче поиска VIP по этой рубрике —
//     номера рубрик выучиваются по ходу и копятся;
//   • или само объявление уже было в выдаче поиска VIP (так ловится и то, чья рубрика
//     ещё не выучена, и площадки без номеров рубрик).

const cats = require('./categories');

const CITY_BY_SLUG = new Map(cats.CITIES.map((c) => [c.slug, c.name]));
const NOT_PATH = new Set(['d', 'kk', 'list', 'ru', 'rus']);

function cityName(slug) {
  return CITY_BY_SLUG.get(slug) || slug;
}

// Рубрика и город из ссылки поиска: /d/elektronika/noutbuki-i-aksesuary/almaty/q-hp/ →
// { path: 'elektronika/noutbuki-i-aksesuary', city: 'almaty' }. Kolesa/Krisha — так же по пути.
function parseSearchUrl(url) {
  let u;
  try { u = new URL(url); } catch { return { path: '', city: '' }; }
  const parts = u.pathname.split('/').filter(Boolean).filter((p) => !NOT_PATH.has(p));
  const until = parts.findIndex((p) => p.startsWith('q-'));
  const segs = until >= 0 ? parts.slice(0, until) : parts;
  let city = '';
  if (segs.length && CITY_BY_SLUG.has(segs[segs.length - 1])) city = segs.pop();
  return { path: segs.join('/'), city };
}

function rubricName(path) {
  if (!path) return 'Все рубрики';
  const all = [...cats.TOP, ...Object.values(cats.FALLBACK_CHILDREN).flat()];
  const hit = all.find((c) => c.path === path);
  return hit ? hit.name : path.split('/').pop();
}

function lockLabel(l) {
  return `${rubricName(l.path)} · ${cityName(l.city)}`;
}

// Чей это эксклюзив (id VIP) — или null, если объявление ничьё.
function lockOwner(locks, ad, seen) {
  const src = ad.source || 'olx';
  const city = String(ad.city || '').trim().toLowerCase();
  for (const l of locks) {
    if (l.source !== src) continue;
    if (!city || city !== cityName(l.city).toLowerCase()) continue;
    if (ad.categoryId && l.category_ids.includes(ad.categoryId)) return l.user_id;
    if (seen?.get(l.id)?.has(ad.id)) return l.user_id;
  }
  return null;
}

// Выдать VIP-рубрику: поиск VIP по ней (создаём, если нет), закрепление и доступ к OLX на
// тот же срок. Занята другим — { ok: false, conflict }.
function grant(db, userId, path, city, days) {
  const url = cats.buildSearchUrl({ path, city });
  const conflict = db.lockConflict(userId, 'olx', path, city);
  if (conflict) return { ok: false, conflict };
  let sub = db.subs(userId).find((s) => s.url === url);
  if (!sub) sub = db.addSub(userId, `👑 ${rubricName(path)} · ${cityName(city)}`.slice(0, 60), url, 'olx');
  const r = db.addLock(userId, 'olx', path, city, days, sub.id);
  if (!r.ok) return r;
  db.extend(userId, days, ['olx']);
  return { ok: true, until: r.until, label: `${rubricName(path)} · ${cityName(city)}` };
}

// Все рубрики для выбора: верхние и подрубрики (из встроенного списка).
function rubricChoices() {
  const out = [];
  for (const t of cats.TOP) {
    out.push({ path: t.path, name: t.name });
    for (const c of cats.FALLBACK_CHILDREN[t.path] || []) {
      out.push({ path: c.path, name: `${t.name} › ${c.name}` });
      for (const g of cats.FALLBACK_CHILDREN[c.path] || []) out.push({ path: g.path, name: `${t.name} › ${c.name} › ${g.name}` });
    }
  }
  return out;
}

module.exports = { parseSearchUrl, lockOwner, lockLabel, rubricName, cityName, grant, rubricChoices };
