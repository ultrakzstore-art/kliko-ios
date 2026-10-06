// Диагностика без Телеграма: что OLX реально отдаёт на этой машине.
//   npm run probe -- "<ссылка на поиск>"          — выдача поиска и карточка самого свежего
//   npm run probe -- "<ссылка на объявление>"     — карточка по номеру и 5 следующих номеров
//   npm run probe -- olx race [минут]             — кто раньше отдаёт новое объявление: карточки v2/v1, JSON-список, витрина
//   npm run probe -- olx track <номер> [минут]    — одно объявление во времени: где и когда оно появилось
const olx = require('./olx');
const cats = require('./categories');
const sources = require('./sources');
const { getHtml, parseDetail, postedFromCode } = require('./sources/page');

// Номер объявления (или ссылка на него) — пробуем все известные способы открыть его по номеру:
// какой из них видит объявления, которые ещё на модерации. Ответ OLX показываем как есть.
async function deepProbe(id) {
  const code = olx.encodeId(id);
  const H = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36', 'Accept-Language': 'ru-RU,ru;q=0.9' };
  const tries = [
    ['API v1', `${olx.BASE}/api/v1/offers/${id}/`, 'application/json'],
    ['API v2', `${olx.BASE}/api/v2/offers/${id}/`, 'application/json'],
    ['API v1 (без слэша)', `${olx.BASE}/api/v1/offers/${id}`, 'application/json'],
    ['API телефоны', `${olx.BASE}/api/v1/offers/${id}/limited-phones/`, 'application/json'],
    ['Страница', `${olx.BASE}/d/obyavlenie/-ID${code}.html`, 'text/html'],
    ['Мобильная страница', `https://m.olx.kz/d/obyavlenie/-ID${code}.html`, 'text/html'],
    ['Список по номеру', `${olx.BASE}/api/v1/offers/?offer_id=${id}`, 'application/json'],
  ];
  console.log(`Номер ${id} (код в ссылке ${code})\n`);
  for (const [name, url, accept] of tries) {
    try {
      const res = await fetch(url, { headers: { ...H, Accept: accept }, redirect: 'manual', signal: AbortSignal.timeout(20_000) });
      const text = await res.text();
      let info = '';
      if (/json/.test(res.headers.get('content-type') || '')) {
        try {
          const j = JSON.parse(text);
          const d = j.data || j;
          // Список может не понять фильтр и отдать просто свежие объявления — тогда
          // первое в нём чужое. Показываем только наше, иначе прямо пишем, что его нет.
          const one = Array.isArray(d) ? d.find((x) => Number(x.id) === id) : d;
          if (Array.isArray(d) && !one) info = `этого номера в ответе нет (в списке ${d.length} других объявлений)`;
          else info = one && typeof one === 'object'
            ? `статус «${one.status ?? '—'}» · ${one.title ?? ''}${Array.isArray(d) ? ` · в списке ${d.length}` : ''}`
            : text.slice(0, 160);
        } catch { info = text.slice(0, 160); }
      } else {
        const title = (/<title>([^<]*)<\/title>/i.exec(text) || [])[1] || '';
        // Где именно стоит слово — чтобы отличить «объявление на модерации» от общего текста страницы.
        const hit = /модерац|на проверке|moderat/i.exec(text);
        const mod = hit ? ` · есть слово «модерация»: «…${text.slice(Math.max(0, hit.index - 60), hit.index + 60).replace(/<[^>]+>/g, ' ')}…»` : '';
        const st = (/\\?"status\\?"\s*:\s*\\?"([a-z_]+)/i.exec(text) || [])[1];
        info = `${title.trim().slice(0, 90)}${st ? ` · status=${st}` : ''}${mod}`;
      }
      const loc = res.headers.get('location');
      console.log(`${name}: HTTP ${res.status}${loc ? ` → ${loc}` : ''}\n   ${info.replace(/\s+/g, ' ')}`);
    } catch (e) {
      console.log(`${name}: ошибка ${e.message}`);
    }
  }
  console.log('\nЕсли объявление на модерации видит только один из способов — пришлите этот вывод.');
}

// Даты карточки: что на экране рядом со словами «опубликовано / сегодня / вчера», какие поля с
// датой есть в коде страницы и что взял бот. По этому видно, откуда брать точное время подачи.
function printDates(html, took) {
  const tz = { timeZone: 'Asia/Almaty' };
  const text = html.replace(/\\"/g, '"');
  const found = [...text.matchAll(/["']?\b([A-Za-z_]{2,40})["']?\s*[:=]\s*["']?(\d{4}-\d{2}-\d{2}[T ][\d:.]+(?:Z|[+-]\d{2}:?\d{2})?|1[5-9]\d{8}(?:\d{3})?)["']?/g)]
    .map((m) => `${m[1]} = ${m[2]}${/^\d+$/.test(m[2]) ? ` (${new Date(Number(m[2]) * (m[2].length === 10 ? 1000 : 1)).toLocaleString('ru-RU', tz)})` : ''}`);
  const screen = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;|\s+/g, ' ');
  const near = [...screen.matchAll(/(опубликован|размещен|подано|добавлен|сегодня|вчера|\d{1,2}\s+(?:январ|феврал|март|апрел|ма[яй]|июн|июл|август|сентябр|октябр|ноябр|декабр)[а-я]*|\d{2}\.\d{2}\.20\d{2})/gi)]
    .slice(0, 6).map((m) => screen.slice(Math.max(0, m.index - 30), m.index + 40).trim());
  const at = took ?? postedFromCode(html);
  console.log(`\nДата на экране: ${near.length ? '' : 'не видна'}`);
  [...new Set(near)].forEach((x) => console.log(`  …${x}…`));
  console.log(`Даты в коде страницы: ${found.length ? '' : 'нет'}`);
  [...new Set(found)].slice(0, 12).forEach((f) => console.log(`  ${f}`));
  console.log(`Время подачи, как понял бот: ${at ? new Date(at).toLocaleString('ru-RU', tz) + ' (по Алматы)' : 'не нашлось'}`);
}

// «kaspi watch» — 5 минут: витрина Kaspi раз в 5 с (каждое новое — с временем подачи, платное /
// поднятое помечаем) и номера за самым большим (⚡ — номера идут по порядку подачи). Итог: сколько
// новых, за сколько после подачи видно, сколько поймано по номеру.
async function kaspiWatch(ms) {
  const k = sources.get('kaspi');
  const t0 = Date.now();
  const tz = { timeZone: 'Asia/Almaty' };
  const clock = (t = Date.now()) => new Date(t).toLocaleTimeString('ru-RU', tz);
  const onShow = new Map();   // номер → когда впервые на витрине
  const fresh = [];           // новые: { id, posted, seen }
  let first = true;
  let last = 0;               // последняя выкладка — самое позднее время подачи
  let edge = 0;               // самый большой номер: номера идут по порядку подачи
  const byNum = new Map();    // номер → когда открылся по номеру
  const misses = new Map();   // номер → сколько раз «нет такого»
  let lastShow = 0;
  let jump = 0;
  let startEdge = 0;
  console.log(`Наблюдаю за Kaspi ${Math.round(ms / 60_000)} мин (витрина «Самые новые»). Строки ниже — по мере появления.\n`);
  while (Date.now() - t0 < ms) {
    try {
      // Витрина — раз в 15 с (там почти одно платное), номера — каждые 2 с.
      const due = first || Date.now() - lastShow >= 15_000;
      const show = due ? await k.fetchShowcase('') : [];
      if (due) lastShow = Date.now();
      if (show == null) { console.log('Витрины (главной) нет — наблюдать нечего'); return; }
      if (first && !show.length) { console.log('Витрина пустая — наблюдать не от чего'); return; }
      if (first) {
        console.log(`${clock()} старт: на витрине ${show.length}`);
        console.log(`   номера по порядку витрины: ${show.slice(0, 12).map((a) => a.id).join(', ')}${show.length > 12 ? ', …' : ''}`);
        // Время подачи первых трёх — видно, по дате ли порядок и где платные.
        for (const a of show.slice(0, 3)) {
          const d = await k.fetchDetail(a).catch(() => null);
          console.log(`   ${a.id}: ${d?.createdAt ? `подано ${new Date(d.createdAt).toLocaleString('ru-RU', tz)}` : 'время подачи не найдено'} · ${String(d?.title || '').slice(0, 40)}`);
          if (d?.createdAt > last) last = d.createdAt;
        }
        show.forEach((a) => onShow.set(a.id, 0));
        edge = Math.max(...show.map((a) => a.id));
        // Витрина отстаёт на минуты — сразу ищем настоящий последний номер: шаг вперёд удваиваем,
        // где объявлений уже нет — делим пополам (пустых подряд бывает до 5 — смотрим по 6).
        const exists = async (n) => { for (let id = n; id <= n + 5; id++) if (await k.fetchById(id).catch(() => null)) return id; return 0; };
        const from = edge;
        let step = 8;
        let hit;
        while ((hit = await exists(edge + step))) { edge = hit; step *= 2; }
        let hi = edge + step;
        while (hi - edge > 6) {
          const mid = Math.floor((edge + hi) / 2);
          if ((hit = await exists(mid))) edge = hit; else hi = mid;
        }
        for (let n = edge + 1; n <= hi + 5; n++) if (await k.fetchById(n).catch(() => null)) edge = n;
        startEdge = edge;
        console.log(`${clock()} последний номер: ${edge} (витрина отставала на ${edge - from} номеров) — дальше ловлю каждый следующий\n`);
        lastShow = Date.now();
        first = false;
      } else {
        let paid = 0;
        for (const [i, a] of show.entries()) {
          if (onShow.has(a.id)) continue;
          onShow.set(a.id, Date.now());
          // Номера идут по порядку подачи: далеко позади края — платное / поднятое, карточку не открываем.
          if (a.id < edge - 5000) { paid += 1; continue; }
          const d = await k.fetchDetail(a).catch(() => null);
          const posted = d?.createdAt || 0;
          const old = posted && (Date.now() - posted > 3 * 3600_000 || (last && posted < last - 3600_000));
          const when = posted ? `подано ${clock(posted)}, на витрине через ${Math.round((Date.now() - posted) / 1000)} с` : 'время подачи не найдено';
          console.log(`${clock()} ${old ? '⏭ платное / поднятое' : '🆕 новое'} ${a.id} (место ${i + 1}) · ${String(d?.title || '').slice(0, 45)} · ${d?.priceLabel || 'цена —'} · ${d?.city || 'город —'} · ${when}`);
          if (!old) {
            fresh.push({ id: a.id, posted, seen: Date.now() });
            if (posted > last) last = posted;
            if (a.id > edge) edge = a.id;
          }
        }
        if (paid) console.log(`${clock()} ⏭ витрина: ${paid} платных / поднятых (номера далеко позади) — пропущено`);
      }
      // По номеру. Номер выдаётся при подаче, но пока объявление на проверке у Kaspi — заглушка.
      // Край — последний опубликованный; те, что на проверке, почти все впереди него. Смотрим
      // +1, +2 и два номера подальше (+3…+40 по кругу), а каждую заглушку держим в очереди и
      // перепроверяем по кругу (давно проверенные — первыми): позади края до часа, впереди — 15 мин.
      jump = (jump % 37) + 1;
      const ahead = [edge + 1, edge + 2, edge + 3 + jump, edge + 3 + ((jump + 18) % 37) + 1];
      const behind = [...misses.entries()].filter(([n, m]) => !ahead.includes(n)
        && Date.now() - m.added < (n > edge ? 15 * 60_000 : 3600_000))
        .sort((x, y) => (x[1].checked || 0) - (y[1].checked || 0)).slice(0, 8).map(([n]) => n);
      // Все номера прохода — одновременно.
      const batch = [...ahead, ...behind].filter((n) => !byNum.has(n));
      const got = new Map(await Promise.all(batch.map((n) => k.fetchById(n).catch(() => null).then((d) => [n, d]))));
      for (const n of batch.sort((x, y) => x - y)) {
        const d = got.get(n);
        if (!d) {
          const m = misses.get(n) || { tries: 0, added: Date.now() };
          m.tries += 1;
          m.checked = Date.now();
          misses.set(n, m);
          continue;
        }
        byNum.set(n, Date.now());
        const was = misses.get(n)?.tries;
        misses.delete(n);
        const when = d.createdAt ? `подано ${clock(d.createdAt)}, открылось через ${Math.round((Date.now() - d.createdAt) / 1000)} с` : 'время подачи не найдено';
        console.log(`${clock()} ⚡ по номеру ${n} · ${String(d.title).slice(0, 45)} · ${d.priceLabel || 'цена —'} · ${d.city || 'город —'} · ${when}${was ? ` · ${was} раз была заглушка — ждало проверки Kaspi` : ''}`);
        if (d.createdAt > last) last = d.createdAt;
        for (let m = edge + 1; m < n; m++) if (!misses.has(m) && !byNum.has(m)) misses.set(m, { tries: 0, added: Date.now(), checked: 0 });
        edge = Math.max(edge, n);
      }
      for (const [n, m] of misses) if (n < edge - 1500 || Date.now() - m.added > (n > edge ? 15 * 60_000 : 3600_000)) misses.delete(n);
    } catch (e) {
      console.log(`${clock()} ошибка: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  const mins = (Date.now() - t0) / 60_000;
  console.log('\nИтог:');
  if (startEdge) {
    const issued = edge - startEdge;
    const got = [...byNum.keys()].filter((n) => n > startEdge).length;
    const wait = [...misses.keys()].filter((n) => n > startEdge && n <= edge).length;
    console.log(`  номера после старта: ${issued} (${startEdge + 1}…${edge}) — поймано ${got}, ещё на проверке у Kaspi ${wait}, остальные ${Math.max(0, issued - got - wait)} — сняты / отклонены`);
    if (got) console.log(`  ловим по номеру ~${(got / ((Date.now() - t0) / 60_000)).toFixed(1)} в минуту`);
  }
  console.log(`  новых: ${fresh.length} за ${mins.toFixed(1)} мин (${(fresh.length / mins).toFixed(1)} в минуту)`);
  const lag = fresh.filter((f) => f.posted).map((f) => (f.seen - f.posted) / 1000);
  if (lag.length) console.log(`  от подачи до витрины: мин ${Math.min(...lag).toFixed(0)} с, макс ${Math.max(...lag).toFixed(0)} с, в среднем ${(lag.reduce((x, y) => x + y, 0) / lag.length).toFixed(0)} с`);
  if (fresh.length > 1) {
    const up = fresh.slice(1).filter((f, i) => f.id > fresh[i].id).length;
    console.log(`  номер больше предыдущего нового: ${up} из ${fresh.length - 1} — ${up === fresh.length - 1 ? 'номера растут по порядку' : 'номера не по порядку, ловим по дате'}`);
  }
  console.log(`  номеров на проверке у Kaspi (заглушка) сейчас: ${misses.size}`);
  console.log(`  поймано по номеру: ${byNum.size}${byNum.size ? `, из них позже на витрине: ${[...byNum.keys()].filter((id) => onShow.get(id)).length}` : ''} · самый большой номер: ${edge}`);
  if (last) console.log(`  последняя выкладка: ${new Date(last).toLocaleString('ru-RU', tz)}`);
  console.log('\nПришлите весь этот вывод — по нему видно, как Kaspi выдаёт новые объявления.');
}

// Kaspi по номеру: ссылка на объявление — /a/<название>-<номер>/. Пробуем, открывается ли оно без
// названия (сайт может перенаправить на полный адрес) — тогда объявления можно ловить по номерам.
async function kaspiProbe(id) {
  const H = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36', 'Accept-Language': 'ru-RU,ru;q=0.9', Accept: 'text/html' };
  const base = 'https://obyavleniya.kaspi.kz';
  const tries = [`${base}/a/${id}/`, `${base}/a/-${id}/`, `${base}/a/x-${id}/`, `${base}/a/show/${id}`, `${base}/${id}/`];
  console.log(`Kaspi, номер ${id}\n`);
  for (const u of tries) {
    try {
      const res = await fetch(u, { headers: H, redirect: 'manual', signal: AbortSignal.timeout(20_000) });
      const text = await res.text();
      const title = ((/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)/i.exec(text) || [])[1]
        || (/<title>([^<]*)<\/title>/i.exec(text) || [])[1] || '').trim().slice(0, 90);
      const loc = res.headers.get('location');
      console.log(`${u.replace(base, '')}: HTTP ${res.status}${loc ? ` → ${loc}` : ''}${title ? ` · ${title}` : ''}`);
    } catch (e) {
      console.log(`${u.replace(base, '')}: ошибка ${e.message}`);
    }
  }
  for (const n of [id + 1, id + 2, id + 3]) {
    try {
      const res = await fetch(`${base}/a/x-${n}/`, { headers: H, redirect: 'manual', signal: AbortSignal.timeout(20_000) });
      console.log(`следующий ${n}: HTTP ${res.status}${res.headers.get('location') ? ` → ${res.headers.get('location')}` : ''}`);
    } catch (e) {
      console.log(`следующий ${n}: ошибка ${e.message}`);
    }
  }
  try {
    const show = await sources.get('kaspi').fetchShowcase('');
    if (show == null) console.log('\nВитрина (главная Kaspi): нет такой страницы');
    else {
      const top = show.reduce((m, a) => Math.max(m, a.id), 0);
      console.log(`\nВитрина (главная Kaspi): ${show.length} объявлений, самый большой номер ${top}${top ? ` (на ${top - id > 0 ? '+' : ''}${top - id} от проверяемого)` : ''}`);
      show.slice(0, 5).forEach((a) => console.log(`  ${a.id} · ${a.url}`));
    }
  } catch (e) {
    console.log(`\nВитрина: ошибка ${e.message}`);
  }
  // Даты в коде страницы: какие поля есть и что в них — по ним видно точное время подачи.
  try {
    const html = await getHtml(`https://obyavleniya.kaspi.kz/a/${id}/`);
    if (html) {
      printDates(html);
    }
  } catch (e) {
    console.log(`\nДаты: ошибка ${e.message}`);
  }
  try {
    const d = await sources.get('kaspi').fetchById(id);
    console.log(d
      ? `\nКак бот видит объявление: ${d.title} · ${d.priceLabel || 'цена —'} · ${d.city || 'город —'}\nРубрика (крошки): ${d.crumbs.length ? d.crumbs.join('  |  ') : 'не нашлась — по номеру такие объявления не придут, только из выдачи'}`
      : '\nКак бот видит объявление: не открылось (нет такого номера или ещё на проверке)');
  } catch (e) {
    console.log(`\nКак бот видит объявление: ошибка ${e.message}`);
  }
  console.log('\nПришлите этот вывод, если по номеру объявления Kaspi что-то не так.');
}

// npm run probe -- olx race [минут] — гонка источников OLX: для новых номеров — когда объявление
// впервые открылось карточкой API v2 и v1, когда появилось в JSON-списке свежих и на витрине.
// Сначала находит настоящий край номеров (список может отставать на минуты), часы ПК сверяет
// с часами OLX (заголовок Date). До ~3 запросов в секунду; на 403 останавливается.
async function olxRace(ms) {
  const H = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36', 'Accept-Language': 'ru-RU,ru;q=0.9', Accept: 'application/json' };
  let skew = null;   // часы OLX минус часы ПК, мс
  const now = () => Date.now() + (skew || 0);
  const ask = async (url, timeout = 8_000) => {
    const sent = Date.now();
    const res = await fetch(url, { headers: H, signal: AbortSignal.timeout(timeout) });
    const d = Date.parse(res.headers.get('date') || '');
    if (skew === null && Number.isFinite(d)) skew = d + 500 - (sent + Date.now()) / 2;   // Date — с точностью до секунды
    if (res.status === 403 || res.status === 429) throw new olx.HttpError(res.status, url);
    return res;
  };
  const card = async (v, id) => {
    const res = await ask(v === 2 ? `${olx.BASE}/api/v2/offers/${id}` : `${olx.BASE}/api/v1/offers/${id}/`);
    if (!res.ok) return null;
    try { const j = await res.json(); const d = j.data || j; return Number(d.id) === id ? d : null; } catch { return null; }
  };
  // JSON-список — именно он, без запасного пути через витрину: их сравниваем отдельно.
  const jsonList = async () => {
    const res = await ask(`${olx.BASE}/api/v1/offers/?offset=0&limit=40&sort_by=created_at:desc`, 15_000);
    if (!res.ok) return [];
    try { return ((await res.json()).data || []).map(olx.normalizeOffer); } catch { return []; }
  };
  const seen = new Map();   // id → { v2, v1, list, show, created, status }
  const rec = (id) => { if (!seen.has(id)) seen.set(id, {}); return seen.get(id); };
  const note = (id, d, key, t) => {
    const x = rec(id);
    if (!x[key]) x[key] = t;
    const c = Date.parse(d?.created_time || d?.createdTime || '');
    if (!x.created && Number.isFinite(c)) x.created = c;
    if (d?.status) x.status = d.status;
  };
  // Настоящий край: от номера из списка шагаем вперёд 8, 16, 32… пока карточки открываются,
  // потом делением пополам. Пропуски в номерах бывают — смотрим по три номера подряд.
  const opens = async (id) => {
    for (const n of [id, id + 1, id + 2]) if (await card(2, n)) return true;
    return false;
  };
  const findEdge = async (from) => {
    let lo = from;
    let step = 8;
    while (await opens(lo + step)) { lo += step; step *= 2; if (step > 4096) break; }
    let hi = lo + step;
    while (hi - lo > 3) { const mid = Math.floor((lo + hi) / 2); if (await opens(mid)) lo = mid; else hi = mid; }
    return lo;
  };

  const end = Date.now() + ms;
  console.log(`Гонка источников OLX ${Math.round(ms / 60_000)} мин: карточки API v2 и v1, JSON-список, витрина…`);
  let stop = '';
  let edge = 0;
  let slow = 0;
  let longest = 0;
  let shown = 0;
  try {
    const list = await jsonList();
    const top = Math.max(0, ...list.map((a) => a.id));
    if (!top) throw new Error('JSON-список пуст — не от чего искать край');
    edge = await findEdge(top);
    console.log(`Часы ПК ${skew === null ? 'не сверены' : `${skew > 0 ? 'отстают от' : 'спешат относительно'} OLX на ${Math.abs(Math.round(skew / 1000))} с — поправлено`}.`);
    console.log(`Последний номер в JSON-списке ${top}, настоящий край ${edge}: список отстаёт на ${edge - top} номеров.\n`);
  } catch (e) {
    stop = e instanceof olx.HttpError ? `OLX ответил ${e.status} — остановил замер` : `Не начал: ${e.message}`;
  }
  const t1 = Date.now();
  while (Date.now() < end && !stop) {
    const t0 = Date.now();
    try {
      for (const a of await jsonList()) note(a.id, null, 'list', now());
      try {
        for (const a of (await olx.fetchSearch(`${olx.BASE}/list/`)).ads) if (a.id > edge - 300) note(a.id, null, 'show', now());
      } catch (e) { if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) throw e; }
      // Номера за краем (пять — с запасом на пропуски) и недавние, где не ответила одна из версий.
      const ids = [1, 2, 3, 4, 5].map((k) => edge + k);
      for (const [id, r] of [...seen].sort((x, y) => y[0] - x[0])) {
        if (ids.length >= 8) break;
        if (id > edge - 40 && (r.v1 || r.v2) && (!r.v1 || !r.v2) && !ids.includes(id)) ids.push(id);
      }
      const asks = ids.flatMap((id) => [2, 1].filter((v) => !seen.get(id)?.[`v${v}`]).map((v) => ({ id, v })));
      const got = await Promise.all(asks.map(({ id, v }) => card(v, id).then((d) => ({ id, v, d, t: now() }), (e) => ({ id, v, e }))));
      const limited = got.find((g) => g.e instanceof olx.HttpError);
      if (limited) throw limited.e;
      for (const { id, v, d, t, e } of got) {
        if (e) { slow += 1; continue; }
        if (!d) continue;
        note(id, d, `v${v}`, t);
        edge = Math.max(edge, id);
      }
    } catch (e) {
      if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) stop = `OLX ответил ${e.status} — остановил замер`;
      else console.log(`  ошибка: ${e.message}`);
    }
    longest = Math.max(longest, Date.now() - t0);
    const min = Math.floor((Date.now() - t1) / 60_000);
    if (min > shown) {
      shown = min;
      const r = [...seen.values()].filter((x) => x.v2 || x.v1);
      console.log(`  ${min} мин: номеров открыто ${r.length} · из них в списке ${r.filter((x) => x.list).length} · на витрине ${r.filter((x) => x.show).length}${longest > 10_000 ? ` · OLX тормозил: круг до ${Math.round(longest / 1000)} с, без ответа ${slow}` : ''}`);
      longest = 0;
    }
    const wait = 3000 - (Date.now() - t0);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  }
  if (stop) console.log(stop);

  // Только номера, открытые карточкой во время замера (а не старые из списка).
  const rows = [...seen].filter(([, r]) => r.created && (r.v2 || r.v1)).sort((x, y) => x[0] - y[0]);
  const sec = (t, c) => (t ? Math.round((t - c) / 1000) : null);
  const cell = (t, c, w) => (t ? `${sec(t, c)} с` : '—').padStart(w);
  console.log('\nномер        подано    API v2   API v1  список  витрина  статус');
  for (const [id, r] of rows) {
    console.log(`${id}  ${new Date(r.created).toLocaleTimeString('ru-RU')}  ${cell(r.v2, r.created, 7)}  ${cell(r.v1, r.created, 7)}  ${cell(r.list, r.created, 6)}  ${cell(r.show, r.created, 7)}   ${r.status || ''}`);
  }
  const med = (a) => { if (!a.length) return '—'; const s2 = [...a].sort((x, y) => x - y); return `${s2[Math.floor(s2.length / 2)]} с`; };
  const cardT = (r) => Math.min(r.v2 || Infinity, r.v1 || Infinity);
  const v2first = rows.filter(([, r]) => r.v2 && r.v1 && r.v1 - r.v2 >= 1000).length;
  const v1first = rows.filter(([, r]) => r.v2 && r.v1 && r.v2 - r.v1 >= 1000).length;
  const both = rows.filter(([, r]) => r.list);
  console.log(`\nИтог (${rows.length} новых объявлений):`);
  console.log(`  карточка (v2 или v1) — через ${med(rows.map(([, r]) => sec(cardT(r), r.created)))} после подачи (медиана)`);
  console.log(`  v2 раньше v1: ${v2first}, v1 раньше v2: ${v1first}, одновременно: ${rows.length - v2first - v1first}`);
  console.log(`  JSON-список — через ${med(both.map(([, r]) => sec(r.list, r.created)))}; карточка раньше списка у ${both.filter(([, r]) => r.list - cardT(r) >= 1000).length} из ${both.length}, на сколько — ${med(both.map(([, r]) => sec(r.list, cardT(r))))}`);
  console.log(`  в список попали ${both.length} из ${rows.length}, на витрину — ${rows.filter(([, r]) => r.show).length} (там только 40 самых свежих — быстрые потоки проскакивают)`);
  console.log('Секунды — от времени подачи (по часам OLX) до первого ответа источника. Опрос раз в 3 с: точность ±3 с.');
}

// npm run probe -- olx track <номер> [минут] — одно (своё, только что поданное) объявление во
// времени: когда впервые открылась карточка v2 и v1, когда оно попало в JSON-список свежих и на
// витрину «сначала новые», как менялся статус. Раз в 2 секунды, до 30 минут или пока не увидят все.
async function olxTrack(id, ms) {
  const H = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36', 'Accept-Language': 'ru-RU,ru;q=0.9', Accept: 'application/json' };
  const json = async (url) => {
    const res = await fetch(url, { headers: H, signal: AbortSignal.timeout(15_000) });
    if (res.status === 403 || res.status === 429) throw new olx.HttpError(res.status, url);
    if (!res.ok) return { code: res.status };
    try { return { code: res.status, body: await res.json() }; } catch { return { code: res.status }; }
  };
  const start = Date.now();
  const clock = () => new Date().toLocaleTimeString('ru-RU');
  const since = () => `+${Math.round((Date.now() - start) / 1000)} с`;
  const first = {};
  const status = { v2: '', v1: '' };
  const event = (key, text) => { if (!first[key]) { first[key] = Date.now(); console.log(`${clock()}  ${since().padStart(7)}  ${text}`); } };
  console.log(`Слежу за объявлением ${id}: карточка v2, карточка v1, JSON-список, витрина — раз в 2 с.\nЗапишите рядом время из кабинета OLX и время уведомлений.\n`);
  let created = null;
  while (Date.now() - start < ms) {
    const t0 = Date.now();
    try {
      for (const v of ['v2', 'v1']) {
        const r = await json(v === 'v2' ? `${olx.BASE}/api/v2/offers/${id}` : `${olx.BASE}/api/v1/offers/${id}/`);
        const d = r.body && (r.body.data || r.body);
        if (d && Number(d.id) === id) {
          event(v, `карточка ${v} открылась (статус «${d.status || '—'}»)`);
          if (d.status && d.status !== status[v]) {
            if (status[v]) console.log(`${clock()}  ${since().padStart(7)}  карточка ${v}: статус «${status[v]}» → «${d.status}»`);
            status[v] = d.status;
          }
          const c = Date.parse(d.created_time || d.createdTime || '');
          if (!created && Number.isFinite(c)) { created = c; console.log(`           время подачи по карточке: ${new Date(c).toLocaleTimeString('ru-RU')}`); }
        } else if (first[v] && !first[`${v}-gone`]) {
          first[`${v}-gone`] = Date.now();
          console.log(`${clock()}  ${since().padStart(7)}  карточка ${v} снова не открывается (ответ ${r.code})`);
        }
      }
      const list = await json(`${olx.BASE}/api/v1/offers/?offset=0&limit=40&sort_by=created_at:desc`);
      if ((list.body?.data || []).some((a) => Number(a.id) === id)) event('list', 'появилось в JSON-списке свежих');
      const show = await olx.fetchSearch(`${olx.BASE}/list/`);
      if (show.ads.some((a) => a.id === id)) event('show', 'появилось на витрине «сначала новые»');
    } catch (e) {
      if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) { console.log(`OLX ответил ${e.status} — остановил`); break; }
      console.log(`  ошибка: ${e.message}`);
    }
    if (first.v2 && first.v1 && first.list && first.show) break;
    const wait = 2000 - (Date.now() - t0);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  }
  const at = (k) => (first[k] ? new Date(first[k]).toLocaleTimeString('ru-RU') : 'не видели');
  console.log(`\nИтог по ${id}${created ? ` (подано ${new Date(created).toLocaleTimeString('ru-RU')})` : ''}:`);
  console.log(`  карточка v2: ${at('v2')}\n  карточка v1: ${at('v1')}\n  JSON-список: ${at('list')}\n  витрина:     ${at('show')}`);
  console.log('Список и витрина показывают только 40 самых свежих по всей доске: если объявление успело уйти ниже, там будет «не видели».');
}

(async () => {
  const url = process.argv[2];
  if (/^\d{6,}$/.test(String(url || '').trim())) return deepProbe(Number(url.trim()));
  // «olx race 10» — из программы на ПК приходит одной строкой, из консоли — тремя словами.
  const race = /^olx\s*race(?:\s+(\d+))?$/i.exec([url, ...process.argv.slice(3)].join(' ').trim());
  if (race) return olxRace((Number(race[1]) || 10) * 60_000);
  const track = /^olx\s*track\s+(\d{6,})(?:\s+(\d+))?$/i.exec([url, ...process.argv.slice(3)].join(' ').trim());
  if (track) return olxTrack(Number(track[1]), (Number(track[2]) || 30) * 60_000);
  // npm run probe -- categories [путь] — подрубрики, как их увидит мастер /new
  if (url === 'categories') {
    const p = process.argv[3];
    const list = p ? await cats.children(p) : cats.TOP;
    console.log(list.length ? list.map((c) => `  ${c.path}  —  ${c.name}`).join('\n') : 'подрубрик не нашлось (конечная рубрика или OLX не отдал страницу)');
    return;
  }
  // Kolesa, Krisha, Kaspi: выдача и карточка самого свежего — как их увидит бот.
  // «kaspi 123558941» — номер объявления Kaspi без ссылки: какие адреса по нему открываются.
  if (/^kaspi\s*watch$/i.test(String(url || '').trim())) return kaspiWatch(5 * 60_000);
  const kaspiNum = /^kaspi\D*(\d{6,})$/i.exec(String(url || '').trim());
  if (kaspiNum) return kaspiProbe(Number(kaspiNum[1]));
  const src = url && sources.byUrl(url);
  // Ссылка на одно объявление Kolesa / Krisha / Kaspi: как бот понял продавца и почему.
  if (src && src.key !== 'olx' && src.isAdUrl(url)) {
    try {
      const html = await getHtml(url);
      if (html == null) { console.log('Объявление не найдено (404)'); return; }
      const d = parseDetail(html, { id: Number((/(\d{6,})\/?$/.exec(new URL(url).pathname) || [])[1]) || 0, url });
      console.log(`${src.title}: ${d.title || 'без заголовка'} · ${d.priceLabel || 'цена —'} · ${d.city || 'город —'}`);
      console.log(`Продавец: ${d.owner === true ? 'хозяин / частник' : d.owner === false ? 'автосалон / дилер / агент — «только от хозяев» его отсеет' : 'не определён — «только от хозяев» его пропустит'}`);
      const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;|\s+/g, ' ');
      const words = /(дил+ер|салон|частн|собствен|хозя|компани|агент)/gi;
      const seen = new Set();
      console.log('\nГде на странице эти слова (пришлите, если продавец определён неверно):');
      for (const m of text.matchAll(words)) {
        const snip = text.slice(Math.max(0, m.index - 50), m.index + 60).trim();
        if (seen.has(snip) || seen.size >= 12) continue;
        seen.add(snip);
        console.log(`  …${snip}…`);
      }
      printDates(html, d.createdAt);
      const ld = [...html.matchAll(/"@type"\s*:\s*"([A-Za-z]+)"/g)].map((m) => m[1]);
      if (ld.length) console.log(`\nРазметка страницы: ${[...new Set(ld)].join(', ')}`);
    } catch (e) {
      console.error('Ошибка:', e.message);
      process.exit(1);
    }
    return;
  }
  if (src && src.key !== 'olx') {
    try {
      const ads = await src.fetchSearch(url);
      console.log(`${src.title}: в выдаче ${ads.length} объявлений`);
      if (src.key === 'kaspi') {
        const s = sources.kaspiSortInUse();
        console.log(s ? `Сортировка «Самые новые»: нашлась — ${s[0]}=${s[1]}` : 'Сортировка «Самые новые» на странице не нашлась — выберите её на сайте и пришлите ссылку из адресной строки');
      }
      ads.slice(0, 8).forEach((a) => console.log(`  ${a.id} · ${a.url}`));
      const top = [...ads].sort((a, b) => b.id - a.id)[0];
      if (top) console.log('\nКарточка самого свежего:', await src.fetchDetail(top));
      if (src.key !== 'kaspi' && top) {
        console.log('\nСледующие номера (для турбо):');
        for (let n = top.id + 1; n <= top.id + 5; n++) {
          const d = await src.fetchDetail({ id: n }).catch((e) => `ошибка: ${e.message}`);
          console.log(`  ${n}:`, d === null ? 'нет' : typeof d === 'string' ? d : d.title);
        }
      }
    } catch (e) {
      console.error('Ошибка:', e.message);
      process.exit(1);
    }
    return;
  }
  if (!url) {
    console.log('Использование: npm run probe -- "<ссылка на поиск или объявление с olx.kz>"');
    process.exit(1);
  }
  const id = olx.idFromUrl(url);
  try {
    if (id) {
      await deepProbe(id);
      console.log('');
      console.log(`Номер объявления: ${id} (код ${olx.encodeId(id)})`);
      console.log('Карточка:', await olx.fetchOffer(id));
      for (let n = id + 1; n <= id + 5; n++) {
        const o = await olx.fetchOffer(n).catch((e) => `ошибка: ${e.message}`);
        console.log(`  ${n}:`, o === null ? 'нет такого на OLX.kz' : typeof o === 'string' ? o : `${o.title} · ${o.city} · статус ${o.status || '—'}`);
      }
    } else {
      const r = await olx.fetchSearch(url);
      console.log(`Поиск: ${r.ads.length} объявлений (разбор: ${r.source === 'state' ? 'данные страницы' : 'только ссылки'})`);
      for (const a of r.ads.slice(0, 8)) console.log(`  ${a.id} · ${a.title || ''} · ${a.priceLabel || a.price || ''} · ${a.city || ''} · рубрика ${a.categoryId ?? '—'}${a.promoted ? ' · ТОП' : ''}`);
      const top = r.ads.filter((a) => !a.promoted).sort((a, b) => b.id - a.id)[0];
      if (top) console.log('\nКарточка самого свежего:', await olx.fetchOffer(top.id));
    }
  } catch (e) {
    console.error('Ошибка:', e.message);
    process.exit(1);
  }
})();
