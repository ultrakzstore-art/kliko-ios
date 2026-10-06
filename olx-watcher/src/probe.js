// Диагностика без Телеграма: что OLX реально отдаёт на этой машине.
//   npm run probe -- "<ссылка на поиск>"          — выдача поиска и карточка самого свежего
//   npm run probe -- "<ссылка на объявление>"     — карточка по номеру и 5 следующих номеров
//   npm run probe -- olx race [минут]             — кто раньше отдаёт новое объявление: API v2, v1 или лента
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
// впервые открылось через API v2, через API v1 и когда появилось в ленте свежих. Запросов немного
// (до ~3 в секунду); на 403 замер останавливается и печатает, что успел.
async function olxRace(ms) {
  const H = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36', 'Accept-Language': 'ru-RU,ru;q=0.9', Accept: 'application/json' };
  const card = async (v, id) => {
    const url = v === 2 ? `${olx.BASE}/api/v2/offers/${id}` : `${olx.BASE}/api/v1/offers/${id}/`;
    const res = await fetch(url, { headers: H, signal: AbortSignal.timeout(15_000) });
    if (res.status === 403 || res.status === 429) throw new olx.HttpError(res.status, url);
    if (!res.ok) return null;
    try { const j = await res.json(); const d = j.data || j; return Number(d.id) === id ? d : null; } catch { return null; }
  };
  const seen = new Map();   // id → { v2, v1, list, created, status }
  const rec = (id) => { if (!seen.has(id)) seen.set(id, {}); return seen.get(id); };
  let edge = 0;
  const end = Date.now() + ms;
  console.log(`Гонка источников OLX ${Math.round(ms / 60_000)} мин: API v2, API v1, лента свежих…\n`);
  let stop = '';
  while (Date.now() < end && !stop) {
    const t0 = Date.now();
    try {
      const list = await olx.fetchLatest();
      for (const a of list) {
        const r = rec(a.id);
        if (!r.list) r.list = Date.now();
        if (!r.created && a.createdAt) r.created = a.createdAt;
        edge = Math.max(edge, a.id);
      }
      // Номера за краем и недавние, которые видел не каждый источник.
      const ids = edge ? [edge + 1, edge + 2, edge + 3] : [];
      for (const [id, r] of [...seen].sort((a, b) => b[0] - a[0])) {
        if (ids.length >= 6) break;
        if (id > edge - 40 && (!r.v1 || !r.v2) && !ids.includes(id)) ids.push(id);
      }
      for (const id of ids) {
        for (const v of [2, 1]) {
          const r = seen.get(id);
          if (r?.[`v${v}`]) continue;
          const d = await card(v, id);
          if (!d) continue;
          const x = rec(id);
          x[`v${v}`] = Date.now();
          const c = Date.parse(d.created_time || d.createdTime || '');
          if (!x.created && Number.isFinite(c)) x.created = c;
          if (d.status) x.status = d.status;
          edge = Math.max(edge, id);
        }
      }
    } catch (e) {
      if (e instanceof olx.HttpError && (e.status === 403 || e.status === 429)) stop = `OLX ответил ${e.status} — остановил замер`;
      else console.log(`  ошибка: ${e.message}`);
    }
    const min = Math.floor((Date.now() - (end - ms)) / 60_000);
    if (min > (olxRace.shown || 0)) {
      olxRace.shown = min;
      const r = [...seen.values()];
      console.log(`  ${min} мин: новых номеров ${seen.size} · v2 открыл ${r.filter((x) => x.v2).length} · v1 ${r.filter((x) => x.v1).length} · в ленте ${r.filter((x) => x.list).length}`);
    }
    const wait = 4000 - (Date.now() - t0);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  }
  if (stop) console.log(stop);
  const rows = [...seen].filter(([, r]) => r.created && r.created > Date.now() - ms - 120_000 && (r.v1 || r.v2 || r.list)).sort((a, b) => a[0] - b[0]);
  const ago = (t, c) => (t ? `${Math.round((t - c) / 1000)} с` : '—');
  console.log('\nномер        подано    API v2   API v1   лента   статус');
  const first = { v2: 0, v1: 0, list: 0 };
  for (const [id, r] of rows) {
    const at = new Date(r.created).toLocaleTimeString('ru-RU');
    console.log(`${id}  ${at}  ${ago(r.v2, r.created).padStart(7)}  ${ago(r.v1, r.created).padStart(7)}  ${ago(r.list, r.created).padStart(6)}   ${r.status || ''}`);
    const ts = [['v2', r.v2], ['v1', r.v1], ['list', r.list]].filter(([, t]) => t);
    ts.sort((a, b) => a[1] - b[1]);
    if (ts.length > 1 && ts[1][1] - ts[0][1] >= 1000) first[ts[0][0]] += 1;   // ничья (разница меньше секунды) — не в счёт
  }
  console.log(`\nКто увидел первым (где видели хотя бы двое): API v2 — ${first.v2}, API v1 — ${first.v1}, лента — ${first.list}`);
  console.log('Время — сколько секунд прошло от подачи до того, как источник отдал объявление. Пришлите этот вывод.');
}

(async () => {
  const url = process.argv[2];
  if (/^\d{6,}$/.test(String(url || '').trim())) return deepProbe(Number(url.trim()));
  // «olx race 10» — из программы на ПК приходит одной строкой, из консоли — тремя словами.
  const race = /^olx\s*race(?:\s+(\d+))?$/i.exec([url, ...process.argv.slice(3)].join(' ').trim());
  if (race) return olxRace((Number(race[1]) || 10) * 60_000);
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
