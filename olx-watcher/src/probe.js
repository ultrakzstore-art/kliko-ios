// Диагностика без Телеграма: что OLX реально отдаёт на этой машине.
//   npm run probe -- "<ссылка на поиск>"          — выдача поиска и карточка самого свежего
//   npm run probe -- "<ссылка на объявление>"     — карточка по номеру и 5 следующих номеров
const olx = require('./olx');
const cats = require('./categories');
const sources = require('./sources');
const { getHtml, parseDetail } = require('./sources/page');

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
        console.log(s ? `Сортировка «сначала новые»: нашлась — ${s[0]}=${s[1]}` : 'Сортировка «сначала новые» на странице не нашлась — пришлите ссылку, выбрав её на сайте');
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
