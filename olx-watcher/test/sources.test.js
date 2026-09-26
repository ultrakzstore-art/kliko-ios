// Площадки: определение по ссылке, «сначала новые», разбор выдачи и карточки, полный цикл
// сборщика на Kolesa — сеть подменена, настоящих запросов нет.
const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');

const sources = require('../src/sources');
const { parseDetail, idsFromListing } = require('../src/sources/page');
const { Db } = require('../src/db');
const { Watcher } = require('../src/watcher');

test('площадка по ссылке и «сначала новые»', () => {
  assert.strictEqual(sources.byUrl('https://www.olx.kz/d/elektronika/').key, 'olx');
  assert.strictEqual(sources.byUrl('https://kolesa.kz/cars/toyota/camry/almaty/').key, 'kolesa');
  assert.strictEqual(sources.byUrl('https://krisha.kz/prodazha/kvartiry/almaty/').key, 'krisha');
  assert.strictEqual(sources.byUrl('https://kaspi.kz/obyavleniya/').key, 'kaspi');
  assert.strictEqual(sources.byUrl('https://evilkolesa.kz.example.com/'), null);
  assert.strictEqual(sources.byUrl('https://example.com/'), null);

  const k = new URL(sources.get('kolesa').normalize('https://kolesa.kz/cars/almaty/?price[to]=5000000'));
  assert.strictEqual(k.searchParams.get('sort_by'), 'add_date-desc');
  assert.strictEqual(k.searchParams.get('price[to]'), '5000000');
  assert.ok(sources.get('kolesa').isAdUrl('https://kolesa.kz/a/show/176543210'));
  assert.throws(() => sources.get('krisha').normalize('https://kolesa.kz/cars/'));

  assert.strictEqual(
    sources.get('krisha').wizard.build({ path: 'prodazha/kvartiry', city: 'almaty', priceTo: 40000000 }),
    'https://krisha.kz/prodazha/kvartiry/almaty/?das%5Bprice%5D%5Bto%5D=40000000',
  );
});

test('выдача: номера из ссылок /a/show/; карточка: og-метки и JSON-LD', () => {
  const listing = '<a href="/a/show/176543210">Toyota Camry</a><a href="https://kolesa.kz/a/show/176543211?x=1">x</a><a href="/a/show/176543210">дубль</a>';
  assert.deepStrictEqual(idsFromListing(listing, /\/a\/show\/(\d{5,})/g).map((a) => a.id), [176543210, 176543211]);

  const detail = `<html><head>
    <meta property="og:title" content="Toyota Camry 2018 года за 12 000 000 тг. в Алматы">
    <meta property="og:image" content="https://photos.kolesa.kz/1.jpg"><meta property="og:image" content="https://photos.kolesa.kz/2.jpg">
    <meta name="description" content="Продаю Камри, звоните 8 707 123 45 67">
    <script type="application/ld+json">{"@type":"Car","name":"Toyota Camry 2018","offers":{"price":"12000000","priceCurrency":"KZT"},"datePosted":"2026-09-25T10:00:00+05:00"}</script>
  </head></html>`;
  const ad = parseDetail(detail, { id: 176543210, url: 'https://kolesa.kz/a/show/176543210' });
  assert.strictEqual(ad.title, 'Toyota Camry 2018');
  assert.strictEqual(ad.price, 12000000);
  assert.strictEqual(ad.photo, 'https://photos.kolesa.kz/1.jpg');
  assert.strictEqual(ad.photos.length, 2);
  assert.match(ad.description, /8 707 123 45 67/);
  assert.ok(ad.createdAt > 0);

  assert.strictEqual(ad.sellerUrl, '');

  // Ссылка на продавца: из JSON-LD или из ссылок карточки на тот же сайт; чужие сайты — нет.
  const withSeller = parseDetail('<a href="https://evil.example/user/1">x</a><a href="/user/55123/">Все объявления</a>', { id: 2, url: 'https://kolesa.kz/a/show/2' });
  assert.strictEqual(withSeller.sellerUrl, 'https://kolesa.kz/user/55123/');
  const ldSeller = parseDetail('<script type="application/ld+json">{"@type":"Apartment","name":"x","offers":{"price":"1","seller":{"url":"https://krisha.kz/pro/agency-7"}}}</script>', { id: 3, url: 'https://krisha.kz/a/show/3' });
  assert.strictEqual(ldSeller.sellerUrl, 'https://krisha.kz/pro/agency-7');

  // Без JSON-LD — цена из заголовка, город из «… в Алматы».
  const bare = parseDetail('<meta property="og:title" content="3-комнатная квартира, 75 м² за 55 000 000 〒 в Алматы">', { id: 1, url: 'u' });
  assert.strictEqual(bare.price, 55000000);
  assert.strictEqual(bare.city, 'Алматы');
});

test('сборщик на Kolesa: первый проход молчит, новое по номеру приходит один раз', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-src-'));
  const db = new Db(path.join(dir, 'w.db'));
  let listing = [176000100, 176000099];
  const origFetch = global.fetch;
  global.fetch = async (url) => {
    const u = String(url);
    const html = /\/a\/show\/(\d+)/.test(u)
      ? `<meta property="og:title" content="Авто ${u.match(/show\/(\d+)/)[1]} за 5 000 000 тг. в Алматы">`
      : listing.map((id) => `<a href="/a/show/${id}">x</a>`).join('');
    return { ok: true, status: 200, text: async () => html };
  };
  const sent = [];
  try {
    db.touchUser(1, 'Платный');
    db.extend(1, 7, ['kolesa']);
    const sub = db.addSub(1, 'Camry', 'https://kolesa.kz/cars/toyota/camry/', 'kolesa');
    const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
      notify: async (userId, ad, subs, via) => { if (via !== 'ready') sent.push({ id: ad.id, source: ad.source, title: ad.title }); },
      alert: async () => {}, log: () => {} });
    await w.searchTick();
    assert.deepStrictEqual(sent, []);
    assert.strictEqual(db.sub(sub.id).watermark, 176000100);

    listing = [176000105, 176000100, 176000099];
    db.updateSub(sub.id, { last_poll: 0 });
    await w.searchTick();
    db.updateSub(sub.id, { last_poll: 0 });
    await w.searchTick();
    assert.deepStrictEqual(sent, [{ id: 176000105, source: 'kolesa', title: 'Авто 176000105 за 5 000 000 тг. в Алматы' }]);
    assert.strictEqual(w.frontier, 0, 'номера Kolesa не двигают турбо OLX');
  } finally {
    global.fetch = origFetch;
  }
});

test('Kaspi Объявления: весь Казахстан, город, слова; номера из ссылок выдачи', () => {
  const k = sources.get('kaspi');
  assert.strictEqual(k.wizard.build({ path: 'elektronika/computery/noutbuki' }), 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/');
  assert.strictEqual(k.wizard.build({ path: 'elektronika/computery/noutbuki', city: 'astana' }), 'https://obyavleniya.kaspi.kz/astana/elektronika/computery/noutbuki/');
  assert.strictEqual(k.wizard.build({ path: 'elektronika/telefony', words: 'iphone 13' }), 'https://obyavleniya.kaspi.kz/elektronika/telefony/k--iphone-13/');
  assert.ok(sources.byUrl('https://obyavleniya.kaspi.kz/astana/elektronika/computery/noutbuki/').key === 'kaspi');
  assert.ok(!k.isAdUrl('https://obyavleniya.kaspi.kz/astana/elektronika/computery/noutbuki/'));
  const html = '<a href="/astana/elektronika/computery/noutbuki/">рубрика</a><a href="/elektronika/computery/noutbuki/asus--143/">бренд</a>'
    + '<a href="/a/iphone-15-112633239/">iPhone 15</a><a href="https://obyavleniya.kaspi.kz/a/iphone-15-pro-max-512-gb-112856030/?x=1">Ещё</a>'
    + '<a href="/a/iphone-15-112633239/">дубль</a>{"url":"/a/macbook-air-m1-116605153/"}';
  assert.deepStrictEqual(sources.kaspiIds(html).map((a) => a.id), [112633239, 112856030, 116605153]);
  assert.ok(k.isAdUrl('https://obyavleniya.kaspi.kz/a/iphone-15-112633239/'));
  // Ссылки только с номером: /a/123509497 (без названия и со слэшем в конце или без).
  const short = '<a href="/a/123509497">Ноутбук</a><a href="https://obyavleniya.kaspi.kz/a/123558941/">Ещё</a>{"href":"/a/123600000"}';
  assert.deepStrictEqual(sources.kaspiIds(short).map((a) => a.id), [123509497, 123558941, 123600000]);
  assert.ok(k.isAdUrl('https://obyavleniya.kaspi.kz/a/123509497'));
  assert.ok(!k.isAdUrl('https://obyavleniya.kaspi.kz/a/'));
});

test('Krisha: хозяин или агент по подписи в карточке; «только от хозяев» пропускает только хозяев', async () => {
  const owner = parseDetail('<meta property="og:title" content="2-комнатная квартира"><div class="owners__label">Хозяин недвижимости</div>', { id: 1007150930, url: 'https://krisha.kz/a/show/1007150930' });
  const agent = parseDetail('<meta property="og:title" content="3-комнатная квартира"><div class="label">Агент</div>', { id: 1012391406, url: 'https://krisha.kz/a/show/1012391406' });
  assert.strictEqual(owner.owner, true);
  assert.strictEqual(agent.owner, false);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-krisha-'));
  const db = new Db(path.join(dir, 'w.db'));
  let listing = [1000000001];
  const pages = { 1000000002: 'Хозяин недвижимости', 1000000003: 'Агент' };
  const origFetch = global.fetch;
  global.fetch = async (url) => {
    const u = String(url);
    const m = /show\/(\d+)/.exec(u);
    const html = m ? `<meta property="og:title" content="Квартира ${m[1]}"><span>${pages[m[1]] || ''}</span>` : listing.map((id) => `<a href="/a/show/${id}">x</a>`).join('');
    return { ok: true, status: 200, text: async () => html };
  };
  const sent = [];
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 7, ['krisha']);
    const sub = db.addSub(1, 'Квартиры от хозяев', 'https://krisha.kz/prodazha/kvartiry/almaty/?das[who]=1', 'krisha');
    const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
      notify: async (u, a, s, via) => { if (via !== 'ready') sent.push(a.id); }, alert: async () => {}, log: () => {} });
    await w.searchTick();
    listing = [1000000003, 1000000002, 1000000001];
    db.updateSub(sub.id, { last_poll: 0 });
    await w.searchTick();
    assert.deepStrictEqual(sent, [1000000002], 'агент отсеян, хозяин пришёл');
  } finally {
    global.fetch = origFetch;
  }
});

test('Kolesa: автосалон / дилер — не хозяин; «в автосалоне» в описании и меню «Автосалоны» не считаются', () => {
  const u = { id: 180000001, url: 'https://kolesa.kz/a/show/180000001' };
  const menu = '<nav><a href="/dealers">Автосалоны</a><a>Дилеры</a></nav>';
  const dealer = parseDetail(`${menu}<meta property="og:title" content="Toyota Camry"><div class="seller">Автосалон</div>`, u);
  const ld = parseDetail(`${menu}<meta property="og:title" content="Kia Rio"><script type="application/ld+json">{"@type":"AutoDealer","name":"X"}</script>`, u);
  const priv = parseDetail(`${menu}<meta property="og:title" content="Lada"><div class="descr">Куплена в автосалоне, обслуживалась у дилера. Салон чистый.</div>`, u);
  const named = parseDetail(`${menu}<meta property="og:title" content="Lada"><div class="seller">Частное лицо</div>`, u);
  assert.strictEqual(dealer.owner, false);
  assert.strictEqual(ld.owner, false);
  assert.strictEqual(priv.owner, null, 'не угадали — не отсеиваем');
  assert.strictEqual(named.owner, true);
});

test('Kaspi: сортировка «сначала новые» находится на странице выдачи', () => {
  const { kaspiSort } = sources;
  assert.deepStrictEqual(kaspiSort('<a href="/elektronika/?sort=popular">Популярные</a><a href="/elektronika/?page=1&amp;sort=date_desc"><span>Сначала новые</span></a>'), ['sort', 'date_desc']);
  assert.deepStrictEqual(kaspiSort('<select name="order"><option value="rel">По релевантности</option><option value="new">Новые</option></select>'), ['order', 'new']);
  assert.deepStrictEqual(kaspiSort('{"sortOptions":[{"value":"cheap","title":"Дешевле"},{"value":"created_desc","title":"Сначала новые"}]}'), ['sort', 'created_desc']);
  assert.strictEqual(kaspiSort('<a href="/a/iphone-15-112633239/">iPhone 15 новый</a>'), null, 'ссылки на объявления — не сортировка');
});

test('Kaspi «весь Казахстан»: города берутся со страницы; новые из любого города приходят, хоть номер и ниже', async () => {
  const html = '<a href="/astana/elektronika/computery/noutbuki/">Астана</a><a href="https://obyavleniya.kaspi.kz/kosshy/elektronika/computery/noutbuki/?x=1">Косшы</a><a href="/a/noutbuk-hp-112633239/">HP</a>';
  assert.deepStrictEqual(sources.kaspiCityLinks(html, 'elektronika/computery/noutbuki').sort(), ['astana', 'kosshy']);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-all-'));
  const db = new Db(path.join(dir, 'w.db'));
  const k = sources.get('kaspi');
  const orig = { search: k.fetchSearch, detail: k.fetchDetail };
  let batch = [];
  k.fetchSearch = async () => batch;
  const posted = { 601: 2, 950: 1, 960: 2 * 24 * 60, 100: 100, 50: 3 };   // подано N минут назад
  k.fetchDetail = async (ad) => ({ title: `Ноутбук ${ad.id}`, createdAt: posted[ad.id] ? Date.now() - posted[ad.id] * 60_000 : undefined });
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a) => { if (a) sent.push(a.id); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 30, ['kaspi']);
    const sub = db.addSub(1, 'Ноутбуки', 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/', 'kaspi');
    batch = [{ id: 500, url: 'u', anyOrder: true, seedOnly: true }, { id: 900, url: 'u', anyOrder: true, seedOnly: true }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);           // первый проход: только запомнили
    batch = [{ id: 600, url: 'u', anyOrder: true, seedOnly: true }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);           // новый город впервые: тоже только запомнили
    batch = [{ id: 600, url: 'u', anyOrder: true }, { id: 601, url: 'u', anyOrder: true }, { id: 950, url: 'u', anyOrder: true }, { id: 960, url: 'u', anyOrder: true }, { id: 100, url: 'u', anyOrder: true }, { id: 50, url: 'u' }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);
    assert.deepStrictEqual(sent.sort((a, b) => a - b), [50, 601, 950], 'номера Kaspi не по порядку — решает дата: 601 и 50 ниже отметки, но поданы только что; платные 960 (2 дня назад) и 100 (на 99 мин раньше последней выкладки) — нет');
  } finally {
    Object.assign(k, { fetchSearch: orig.search, fetchDetail: orig.detail });
  }
});

test('Kaspi по номеру: крошки карточки → рубрика и город; подходящее новое приходит сразу', async () => {
  const page = `<meta property="og:title" content="Ноутбук HP 250 G8"><meta property="og:image" content="https://x/1.jpg">
    <script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":[
      {"@type":"ListItem","position":1,"item":"https://obyavleniya.kaspi.kz/astana/"},
      {"@type":"ListItem","position":2,"item":"https://obyavleniya.kaspi.kz/astana/elektronika/"},
      {"@type":"ListItem","position":3,"item":{"@id":"https://obyavleniya.kaspi.kz/astana/elektronika/computery/noutbuki/"}}]}</script>
    <nav class="menu"><a href="/apple/iphones/">iPhone</a></nav>`;
  const ad = { ...parseDetail(page, { id: 123509497, url: 'https://obyavleniya.kaspi.kz/a/123509497/' }), id: 123509497 };
  assert.ok(ad.crumbs.includes('astana/elektronika/computery/noutbuki'));
  const sub = (url) => ({ url });
  assert.strictEqual(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/'), ad), null, 'весь Казахстан');
  assert.strictEqual(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/astana/elektronika/'), ad), null, 'родительская рубрика');
  assert.strictEqual(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/almaty/elektronika/computery/noutbuki/'), ad), 'другой город');
  assert.strictEqual(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/apple/iphones/'), ad), 'другая рубрика', 'меню не считается');
  assert.strictEqual(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/k--hp/'), ad), null);
  assert.match(sources.kaspiMismatch(sub('https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/k--lenovo/'), ad), /lenovo/);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-turbo-'));
  const db = new Db(path.join(dir, 'w.db'));
  const k = sources.get('kaspi');
  const orig = k.fetchById;
  const live = new Map([[123509497, ad]]);
  k.fetchById = async (id) => live.get(id) || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a, subs, via) => { if (a) sent.push(`${via}:${a.id}`); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 30, ['kaspi']);
    const s = db.addSub(1, 'Ноутбуки', 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/', 'kaspi');
    db.updateSub(s.id, { initialized: 1, watermark: 123509490 });
    // Граница из выдачи отстаёт на тысячи номеров: сначала край ищется, старое не шлётся.
    for (let n = 123501000; n <= 123509497; n += 3) if (!live.has(n)) live.set(n, { ...ad, id: n });
    w.bumpKaspi(123501000);
    for (let i = 0; i < 20 && !w.kaspiSynced; i++) await w.kaspiTurboTick();
    assert.ok(w.kaspiSynced, 'край найден');
    assert.ok(w.kaspiFrontier >= 123509490 && w.kaspiFrontier <= 123509497, `граница у края: ${w.kaspiFrontier}`);
    assert.deepStrictEqual(sent, [], 'пока искали край — ничего не прислали');
    // Новое за краем — сразу.
    live.set(123509499, { ...ad, id: 123509499 });
    await w.kaspiTurboTick();
    assert.deepStrictEqual(sent, ['turbo:123509499']);
    await w.kaspiTurboTick();
    assert.deepStrictEqual(sent, ['turbo:123509499'], 'второй раз не шлём');
    // 123509498 был на проверке у Kaspi (заглушка), и край ушёл дальше. Прошёл проверку — приходит.
    assert.ok(w.kaspiMisses.has(123509498), 'номер на проверке — в очереди');
    live.set(123509498, { ...ad, id: 123509498 });
    w.kaspiMisses.get(123509498).checked = 0;
    await w.kaspiTurboTick();
    assert.deepStrictEqual(sent, ['turbo:123509499', 'turbo:123509498']);
    // Ближние номера ещё на проверке, а дальний (+10) уже опубликован — находим и его.
    const far = w.kaspiFrontier + 10;
    live.set(far, { ...ad, id: far });
    for (let i = 0; i < 40 && !sent.includes(`turbo:${far}`); i++) await w.kaspiTurboTick();
    assert.ok(sent.includes(`turbo:${far}`), 'дальний опубликованный номер найден');
    assert.ok(w.kaspiMisses.has(far - 1), 'перескоченные — в очереди на перепроверку');
  } finally {
    k.fetchById = orig;
  }
});

test('карточка без JSON-LD: цена из блока цены, дата из «Опубликовано…», город Kaspi из крошек', () => {
  const html = `<meta property="og:title" content="iPhone 15 Pro"><meta property="og:image" content="https://x/1.jpg">
    <div class="menu">Kaspi Red 0 ₸</div>
    <div class="item__price">450 000 ₸</div>
    <div class="date">Опубликовано 25.09.2026 в 14:02</div>
    <ol class="breadcrumbs"><li><a href="/shymkent/">Шымкент</a></li><li><a href="/shymkent/apple/iphones/">iPhone</a></li></ol>`;
  const d = parseDetail(html, { id: 123509497, url: 'https://obyavleniya.kaspi.kz/a/123509497/' });
  assert.strictEqual(d.price, 450000);
  assert.strictEqual(new Date(d.createdAt).toISOString(), '2026-09-25T09:02:00.000Z', '14:02 по Алматы');
  assert.deepStrictEqual(d.crumbs, ['shymkent', 'shymkent/apple/iphones']);
  const { postedFromText } = require('../src/sources/page');
  const today = postedFromText('<span>Размещено: сегодня, 09:15</span>');
  assert.ok(Math.abs(today - Date.now()) < 26 * 3600_000);
  assert.strictEqual(postedFromText('<p>Добавлено 3 августа 2026</p>'), null, 'без времени — не выдумываем');
  const { dayFromText } = require('../src/sources/page');
  assert.strictEqual(new Date(dayFromText('<span class="date">25.09.2026</span>')).toISOString(), '2026-09-24T19:00:00.000Z', 'полночь по Алматы');
  const onlyDay = parseDetail('<meta property="og:title" content="X"><span>25.09.2026</span>', { id: 1, url: 'https://obyavleniya.kaspi.kz/a/1/' });
  assert.strictEqual(onlyDay.createdAt, null);
  assert.ok(onlyDay.postedDay);
});

test('витрина Kaspi: при запуске только запоминаем, новое с витрины — подходящим поискам; край для турбо', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-show-'));
  const db = new Db(path.join(dir, 'w.db'));
  const k = sources.get('kaspi');
  const orig = { show: k.fetchShowcase, detail: k.fetchDetail };
  let showcase = [{ id: 123600000, url: 'u0' }];
  k.fetchShowcase = async (city) => (city ? [] : showcase);
  const cards = {
    123600001: { title: 'Ноутбук HP', crumbs: ['almaty', 'almaty/elektronika/computery/noutbuki'], price: 200000 },
    123600002: { title: 'Диван', crumbs: ['almaty', 'almaty/dom-dacha/mebel-interer'], price: 50000 },
  };
  k.fetchDetail = async (a) => cards[a.id] || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a) => { if (a) sent.push(a.id); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 30, ['kaspi']);
    const s = db.addSub(1, 'Ноутбуки', 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/', 'kaspi');
    db.updateSub(s.id, { initialized: 1 });
    await w.kaspiShowcaseTick();
    assert.deepStrictEqual(sent, [], 'что было при запуске — не шлём');
    assert.strictEqual(w.kaspiFrontier, 123600000, 'край для турбо — с витрины');
    showcase = [{ id: 123600002, url: 'u2' }, { id: 123600001, url: 'u1' }, ...showcase];
    await w.kaspiShowcaseTick();
    assert.deepStrictEqual(sent, [123600001], 'ноутбук — да, диван — не та рубрика');
    assert.strictEqual(w.kaspiFrontier, 123600002);
  } finally {
    Object.assign(k, { fetchShowcase: orig.show, fetchDetail: orig.detail });
  }
});

test('витрина Kaspi: поднятое / платное старое (по дате подачи, а номер далеко позади — даже без карточки) — не новинка', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-bump-'));
  const db = new Db(path.join(dir, 'w.db'));
  const k = sources.get('kaspi');
  const orig = { show: k.fetchShowcase, detail: k.fetchDetail };
  let showcase = [{ id: 123600000, url: 'u0' }];
  k.fetchShowcase = async (city) => (city ? [] : showcase);
  const crumbs = ['almaty', 'almaty/elektronika/computery/noutbuki'];
  const cards = {
    120000000: { title: 'Ноутбук, поднят платно', crumbs, price: 1, createdAt: Date.now() - 2 * 3600_000 },
    99000000: { title: 'Поднятое: номер на 24 млн позади', crumbs, price: 1, createdAt: Date.now() - 60_000 },
    123599990: { title: 'Ноутбук вчерашний', crumbs, price: 1, createdAt: Date.now() - 20 * 3600_000 },
    123600005: { title: 'Ноутбук новый', crumbs, price: 1, createdAt: Date.now() - 30_000 },
  };
  k.fetchDetail = async (a) => cards[a.id] || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a) => { if (a) sent.push(a.id); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 30, ['kaspi']);
    const s = db.addSub(1, 'Ноутбуки', 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/', 'kaspi');
    db.updateSub(s.id, { initialized: 1 });
    await w.kaspiShowcaseTick();
    showcase = [{ id: 123600005, url: 'u5' }, { id: 120000000, url: 'u1' }, { id: 123599990, url: 'u2' }, { id: 99000000, url: 'u9' }, ...showcase];
    await w.kaspiShowcaseTick();
    assert.deepStrictEqual(sent, [123600005], '2 ч назад — раньше последней выкладки больше чем на час; 20 ч — старьё; номер далеко позади — не открываем');
  } finally {
    Object.assign(k, { fetchShowcase: orig.show, fetchDetail: orig.detail });
  }
});

test('точное время подачи из кода страницы, хоть на экране только дата', () => {
  const { postedFromCode } = require('../src/sources/page');
  const iso = postedFromCode('<script>window.__DATA__={"id":123509497,"updatedAt":"2026-09-25T15:00:00","createdAt":"2026-09-25T14:02:11"}</script>');
  assert.strictEqual(new Date(iso).toISOString(), '2026-09-25T09:02:11.000Z', 'без пояса — Алматы');
  assert.strictEqual(postedFromCode('{"created_at":1790000000}'), 1790000000 * 1000);
  assert.strictEqual(postedFromCode('<script>{\\"publishedAt\\":\\"2026-09-25T14:02:11Z\\"}</script>'), Date.parse('2026-09-25T14:02:11Z'));
  assert.strictEqual(postedFromCode('{"updatedAt":"2026-09-25T15:00:00"}'), null, 'изменение — не подача');
  const d = parseDetail('<meta property="og:title" content="X"><span>25.09.2026</span><script>{"createdAt":"2026-09-25T14:02:11"}</script>', { id: 1, url: 'https://obyavleniya.kaspi.kz/a/1/' });
  assert.strictEqual(new Date(d.createdAt).toISOString(), '2026-09-25T09:02:11.000Z');
});

test('Kaspi: время и цена из данных страницы без кавычек у названий (как на живой странице)', () => {
  const { postedFromCode } = require('../src/sources/page');
  const live = '<script>window.__NUXT__=(function(a,b){return {data:[{advert:{address:r,dateCreate:"2026-09-25T17:54:34+05:00",dateUpdate:"2026-09-25T17:55:04+05:00",id:123560852,isOwner:b,categoryIds:["5",g,"268"],phonePrefix:"+7 (778)",price:"450 000 ₸",priceType:"price",expiryDate:"2026-10-23T17:55:04+05:00",alias:"noutbuk"}}]}}(1,2))</script>';
  assert.strictEqual(new Date(postedFromCode(live)).toISOString(), '2026-09-25T12:54:34.000Z', 'dateCreate, не dateUpdate');
  const d = parseDetail(`<meta property="og:title" content="Ноутбук">${live}`, { id: 123560852, url: 'https://obyavleniya.kaspi.kz/a/noutbuk-123560852/' });
  assert.strictEqual(d.price, 450000);
  assert.strictEqual(new Date(d.createdAt).toISOString(), '2026-09-25T12:54:34.000Z');
});

test('Kaspi: город и заголовок с живой страницы — не из верхних крошек (там город смотрящего)', () => {
  const html = `<meta property="og:title" content="Ноутбук: №123560852 — ноутбуки в Астане — Kaspi Объявления">
<nav class="breadcrumbs"><a href="/shymkent/">Шымкент</a><a href="/shymkent/elektronika/">Электроника</a></nav>
<h1 class="desktop-template__title">Ноутбук</h1><p class="desktop-template__price">450 000 ₸</p>
<div class="desktop-template__breadcrumbs bread-crumbs"><a href="/astana/elektronika/?advertSource=x" data-test-id="breadcrumb_section">Электроника</a>
<a href="/astana/elektronika/computery/noutbuki/?advertSource=x" data-test-id="breadcrumb_category">Ноутбуки</a></div>`;
  const d = parseDetail(html, { id: 123560852, url: 'https://obyavleniya.kaspi.kz/a/noutbuk-123560852/' });
  assert.strictEqual(d.title, 'Ноутбук');
  assert.deepStrictEqual(d.crumbs, ['astana/elektronika', 'astana/elektronika/computery/noutbuki']);
  assert.strictEqual(d.price, 450000);
  const nuxt = parseDetail('<meta property="og:title" content="Ноутбук: №1 — x"><nav class="breadcrumbs"><a href="/shymkent/">Ш</a></nav><script>{breadcrumbsList:[{url:"\\u002Falmaty\\u002Felektronika\\u002F",name:a}]}</script>', { id: 1, url: 'https://obyavleniya.kaspi.kz/a/1/' });
  assert.strictEqual(nuxt.title, 'Ноутбук');
  assert.deepStrictEqual(nuxt.crumbs, ['almaty/elektronika']);
});

test('Kaspi: без даты подачи — по номеру (номера идут по порядку подачи)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-old-'));
  const w = new Watcher({ db: new Db(path.join(dir, 'w.db')), config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async () => {}, alert: async () => {}, log: () => {} });
  w.kaspiFrontier = 123561147;
  assert.strictEqual(w.kaspiOld({ id: 113528655 }), true, 'IKEA-скатерть с витрины: номер на 10 млн позади');
  assert.strictEqual(w.kaspiOld({ id: 123561000 }), false);
  assert.strictEqual(w.kaspiOld({ id: 123387073, createdAt: Date.now() - 14 * 86400_000 }), true, 'платный iPhone: 14 дней');
  assert.strictEqual(w.kaspiOld({ id: 123561100, createdAt: Date.now() - 18 * 60_000 }), false);
});

test('Kaspi по номеру: заглушка «Kaspi Объявления» с логотипом — не объявление', () => {
  const { kaspiReal } = sources;
  const stub = parseDetail('<title>Kaspi Объявления</title><meta property="og:title" content="Kaspi Объявления"><meta property="og:image" content="https://obyavleniya.kaspi.kz/logo.png">', { id: 123561300, url: 'https://obyavleniya.kaspi.kz/a/123561300/' });
  assert.strictEqual(kaspiReal(stub), false);
  const job = parseDetail('<h1 class="desktop-template__title">Механик</h1><script>{dateCreate:"2026-09-25T18:42:52+05:00"}</script>', { id: 123561285, url: 'https://obyavleniya.kaspi.kz/a/123561285/' });
  assert.strictEqual(kaspiReal(job), true, 'вакансия без цены, но с временем подачи');
});

test('подрубрики на любую глубину: OLX (ссылки с /d/ и без), Kaspi (со страницы и из встроенного списка)', async () => {
  const cats = require('../src/categories');
  const olxHtml = '<a href="/elektronika/telefony-i-aksesuary/mobilnye-telefony-smartfony/">Мобильные телефоны / смартфоны 1 234</a>'
    + '<a href="https://www.olx.kz/d/elektronika/telefony-i-aksesuary/aksessuary-dlya-telefonov/">Аксессуары</a>'
    + '<a href="/elektronika/telefony-i-aksesuary/almaty/">Алматы</a><a href="/d/obyavlenie/x-IDabc.html">x</a>';
  assert.deepStrictEqual(cats.parseChildren(olxHtml, 'elektronika/telefony-i-aksesuary').map((c) => c.name), ['Мобильные телефоны / смартфоны', 'Аксессуары']);

  const kHtml = '<a href="/almaty/elektronika/computery/noutbuki/?advertSource=x">Ноутбуки 512</a><a href="/elektronika/computery/monitory/">Мониторы</a><a href="/elektronika/computery/k--hp/">hp</a>';
  assert.deepStrictEqual(sources.parseKaspiChildren(kHtml, 'elektronika/computery').map((c) => c.path), ['elektronika/computery/noutbuki', 'elektronika/computery/monitory']);

  // Сайт недоступен — встроенный список, тоже по уровням.
  const w = sources.get('kaspi').wizard;
  const lvl1 = (await w.children('elektronika')).map((c) => c.path);
  assert.ok(lvl1.includes('elektronika/computery') && !lvl1.includes('elektronika/computery/noutbuki'), lvl1.join());
  assert.ok((await w.children('elektronika/computery')).some((c) => c.path === 'elektronika/computery/noutbuki'));
});
