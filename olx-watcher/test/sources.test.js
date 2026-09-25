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
