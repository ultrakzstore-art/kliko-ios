// Диагностика без Телеграма: что OLX реально отдаёт на этой машине.
//   npm run probe -- "<ссылка на поиск>"          — выдача поиска и карточка самого свежего
//   npm run probe -- "<ссылка на объявление>"     — карточка по номеру и 5 следующих номеров
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

// «kaspi watch» — 5 минут наблюдаем, как у Kaspi появляются новые объявления: витрина раз в 5 с,
// номера за самым большим — по одному. Итог: сколько новых в минуту, идут ли номера подряд, как
// быстро номер попадает на витрину после того, как открылся по ссылке.
async function kaspiWatch(ms) {
  const k = sources.get('kaspi');
  const t0 = Date.now();
  const clock = () => new Date().toLocaleTimeString('ru-RU', { timeZone: 'Asia/Almaty' });
  const onShow = new Map();   // номер → когда впервые на витрине
  const byNum = new Map();    // номер → когда впервые открылся по ссылке
  const dead = new Set();
  let first = true;
  let edge = 0;
  console.log(`Наблюдаю за Kaspi ${Math.round(ms / 60_000)} мин. Строки ниже — по мере появления.\n`);
  while (Date.now() - t0 < ms) {
    try {
      const show = await k.fetchShowcase('');
      if (show == null) { console.log('Витрины (главной) нет — наблюдать нечего'); return; }
      const ids = show.map((a) => a.id);
      if (first) {
        edge = Math.max(...ids);
        console.log(`${clock()} старт: на витрине ${ids.length}, номера ${Math.min(...ids)}…${edge}`);
        console.log(`   порядок на витрине: ${ids.slice(0, 12).join(', ')}${ids.length > 12 ? ', …' : ''}`);
        ids.forEach((id) => onShow.set(id, 0));
        first = false;
      } else {
        for (const [i, id] of ids.entries()) {
          if (onShow.has(id)) continue;
          onShow.set(id, Date.now());
          const seenByNum = byNum.get(id);
          console.log(`${clock()} витрина: новое ${id} (место ${i + 1})${id < edge ? ` — НИЖЕ прежнего края ${edge}` : ''}${seenByNum ? ` — по номеру открылось раньше на ${Math.round((Date.now() - seenByNum) / 1000)} с` : ''}`);
          if (id > edge) edge = id;
        }
      }
      // Номера за краем: открываются ли раньше витрины.
      for (let n = edge + 1; n <= edge + 3; n++) {
        if (byNum.has(n) || dead.has(n)) continue;
        const d = await k.fetchById(n).catch(() => null);
        if (d) {
          byNum.set(n, Date.now());
          console.log(`${clock()} по номеру: открылся ${n} · ${String(d.title).slice(0, 50)}${onShow.has(n) ? '' : ' — на витрине его ещё нет'}`);
        }
      }
    } catch (e) {
      console.log(`${clock()} ошибка: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  const fresh = [...onShow.entries()].filter(([, t]) => t).map(([id]) => id).sort((a, b) => a - b);
  const mins = (Date.now() - t0) / 60_000;
  console.log('\nИтог:');
  console.log(`  новых на витрине: ${fresh.length} за ${mins.toFixed(1)} мин (${(fresh.length / mins).toFixed(1)} в минуту)`);
  if (fresh.length > 1) {
    const steps = fresh.slice(1).map((id, i) => id - fresh[i]);
    console.log(`  шаг между соседними новыми номерами: мин ${Math.min(...steps)}, макс ${Math.max(...steps)}, средний ${(steps.reduce((a, b) => a + b, 0) / steps.length).toFixed(1)}`);
    console.log(`  номера за время наблюдения выросли на ${fresh[fresh.length - 1] - fresh[0]}`);
  }
  console.log(`  открылись по номеру раньше витрины: ${[...byNum.keys()].filter((id) => !onShow.get(id) || onShow.get(id) > byNum.get(id)).length} из ${byNum.size}`);
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
      const text = html.replace(/\\"/g, '"');
      const found = [...text.matchAll(/["']?\b([A-Za-z_]{2,40})["']?\s*:\s*"?(\d{4}-\d{2}-\d{2}[T ][\d:.]+(?:Z|[+-]\d{2}:?\d{2})?|1[5-9]\d{8}(?:\d{3})?)"?/g)]
        .map((m) => `${m[1]} = ${m[2]}`);
      const onPage = (/(\d{2}\.\d{2}\.20\d{2})(?:[^\d]{1,5}(\d{1,2}:\d{2}))?/.exec(html.replace(/<[^>]+>/g, ' ')) || []).slice(1).filter(Boolean).join(' ');
      const at = postedFromCode(html);
      console.log(`\nДата на экране: ${onPage || 'не видна'}`);
      console.log(`Даты в коде страницы: ${found.length ? '' : 'нет'}`);
      [...new Set(found)].slice(0, 10).forEach((f) => console.log(`  ${f}`));
      console.log(`Точное время подачи: ${at ? new Date(at).toLocaleString('ru-RU', { timeZone: 'Asia/Almaty' }) + ' (по Алматы)' : 'в коде не нашлось'}`);
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

(async () => {
  const url = process.argv[2];
  if (/^\d{6,}$/.test(String(url || '').trim())) return deepProbe(Number(url.trim()));
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
