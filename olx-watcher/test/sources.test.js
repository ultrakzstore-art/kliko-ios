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
    const w = new Watcher({ db, config: { pollSec: 30, freePollSec: 600, turboSec: 5, turboWindow: 5, freshMs: 1800_000 },
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
