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
  k.fetchDetail = async (ad) => ({ title: `Ноутбук ${ad.id}` });
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a) => { if (a) sent.push(a.id); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    db.extend(1, 30, ['kaspi']);
    const sub = db.addSub(1, 'Ноутбуки', 'https://obyavleniya.kaspi.kz/elektronika/computery/noutbuki/', 'kaspi');
    batch = [{ id: 500, url: 'u', anyOrder: true, seedOnly: true }, { id: 900, url: 'u', anyOrder: true, seedOnly: true }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);           // первый проход: только запомнили
    batch = [{ id: 300, url: 'u', anyOrder: true, seedOnly: true }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);           // новый город впервые: тоже только запомнили
    batch = [{ id: 300, url: 'u', anyOrder: true }, { id: 301, url: 'u', anyOrder: true }, { id: 950, url: 'u', anyOrder: true }];
    await w.pollUrl(sub.url, [db.sub(sub.id)]);
    assert.deepStrictEqual(sent.sort((a, b) => a - b), [301, 950], '301 ниже отметки 900, но из другого города — новое');
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

test('витрина Kaspi: поднятое старое (маленький номер или старая дата) — не новинка', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-kaspi-bump-'));
  const db = new Db(path.join(dir, 'w.db'));
  const k = sources.get('kaspi');
  const orig = { show: k.fetchShowcase, detail: k.fetchDetail };
  let showcase = [{ id: 123600000, url: 'u0' }];
  k.fetchShowcase = async (city) => (city ? [] : showcase);
  const crumbs = ['almaty', 'almaty/elektronika/computery/noutbuki'];
  const cards = {
    120000000: { title: 'Ноутбук старый, поднят', crumbs, price: 1 },
    123599990: { title: 'Ноутбук вчерашний', crumbs, price: 1, createdAt: Date.now() - 20 * 3600_000 },
    123600005: { title: 'Ноутбук новый', crumbs, price: 1 },
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
    showcase = [{ id: 123600005, url: 'u5' }, { id: 120000000, url: 'u1' }, { id: 123599990, url: 'u2' }, ...showcase];
    await w.kaspiShowcaseTick();
    assert.deepStrictEqual(sent, [123600005]);
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
