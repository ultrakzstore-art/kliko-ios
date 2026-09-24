// Диагностика без Телеграма: что OLX реально отдаёт на этой машине.
//   npm run probe -- "<ссылка на поиск>"          — выдача поиска и карточка самого свежего
//   npm run probe -- "<ссылка на объявление>"     — карточка по номеру и 5 следующих номеров
const olx = require('./olx');
const cats = require('./categories');

(async () => {
  const url = process.argv[2];
  // npm run probe -- categories [путь] — подрубрики, как их увидит мастер /new
  if (url === 'categories') {
    const p = process.argv[3];
    const list = p ? await cats.children(p) : cats.TOP;
    console.log(list.length ? list.map((c) => `  ${c.path}  —  ${c.name}`).join('\n') : 'подрубрик не нашлось (конечная рубрика или OLX не отдал страницу)');
    return;
  }
  if (!url) {
    console.log('Использование: npm run probe -- "<ссылка на поиск или объявление с olx.kz>"');
    process.exit(1);
  }
  const id = olx.idFromUrl(url);
  try {
    if (id) {
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
