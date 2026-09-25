// Сборщик на подставном OLX: у бесплатного и платного своя частота и своя новизна,
// турбо — только платным, одна ссылка у двух людей — один запрос.
const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');

const olx = require('../src/olx');
const { Db, DAY } = require('../src/db');
const { Watcher } = require('../src/watcher');

test('бесплатный и платный доступ, поиск и турбо', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: `https://www.olx.kz/d/obyavlenie/x-ID${olx.encodeId(id)}.html`, price: 200000, city: 'Алматы', categoryId: 1234, createdAt: now, ...extra });

  let listing = [ad(100, 'HP 250 старое'), ad(99, 'HP 250 ещё старее')];
  const offers = new Map();
  let searches = 0;
  const origSearch = olx.fetchSearch;
  const origOffer = olx.fetchOffer;
  olx.fetchSearch = async () => { searches += 1; return { source: 'state', ads: listing }; };
  olx.fetchOffer = async (id) => offers.get(id) || null;

  const sent = [];
  const w = new Watcher({
    db, config: { pollSec: 30, freePollSec: 600, turboSec: 5, turboWindow: 5, freshMs: 30 * 60_000 },
    notify: async (userId, a, subs, via) => { if (via !== 'ready') sent.push({ user: userId, id: a.id, via }); },
    alert: async () => {}, log: () => {},
  });
  try {
    db.touchUser(1, 'Платный');
    db.touchUser(2, 'Бесплатный');
    db.extend(1, 7);
    const url = 'https://www.olx.kz/d/elektronika/q-hp-250/';
    const paidSub = db.addSub(1, 'HP платный', url);
    const freeSub = db.addSub(2, 'HP бесплатный', url);

    // Первый проход: одна ссылка у двоих — один запрос; никому ничего не шлём.
    await w.searchTick();
    assert.strictEqual(searches, 1, 'одна ссылка — один запрос');
    assert.deepStrictEqual(sent, []);
    assert.strictEqual(db.sub(paidSub.id).watermark, 100);

    // Новое объявление. Сразу после — платному пора (прошло 30+ сек), бесплатному нет (10 мин).
    listing = [ad(105, 'HP 250 G9 новое'), ...listing];
    db.updateSub(paidSub.id, { last_poll: 0 });
    await w.searchTick();
    assert.deepStrictEqual(sent, [{ user: 1, id: 105, via: 'search' }], 'бесплатному ещё рано');

    // Через 10 минут доходит очередь и до бесплатного — он тоже получает 105, но один раз.
    db.updateSub(freeSub.id, { last_poll: Date.now() - 11 * 60_000 });
    await w.searchTick();
    assert.deepStrictEqual(sent.slice(1), [{ user: 2, id: 105, via: 'search' }]);

    // Поднятое старьё (подано 3 часа назад) — не новое ни для кого.
    listing = [ad(106, 'HP 250 из Топа', { createdAt: now - 3 * 3600_000, promoted: true }), ...listing];
    db.updateSub(paidSub.id, { last_poll: 0 });
    await w.searchTick();
    assert.strictEqual(sent.length, 2, 'старьё не прислано');

    // Турбо: только платному. 107 — чужое (телефон), 108 — наше, на проверке.
    offers.set(107, ad(107, 'iPhone 13', { categoryId: 555 }));
    offers.set(108, ad(108, 'HP 250 G8 на проверке', { status: 'moderated' }));
    await w.turboTick();
    assert.deepStrictEqual(sent.slice(2), [{ user: 1, id: 108, via: 'turbo' }], 'турбо — только платному');

    // Когда 108 доедет до поиска — платному второй раз не придёт, бесплатному придёт в свою очередь.
    listing = [ad(108, 'HP 250 G8'), ...listing];
    db.updateSub(paidSub.id, { last_poll: 0 });
    db.updateSub(freeSub.id, { last_poll: 0 });
    await w.searchTick();
    assert.deepStrictEqual(sent.slice(3), [{ user: 2, id: 108, via: 'search' }]);

    // Платный срок кончился — турбо ему больше не работает.
    db.db.prepare('UPDATE users SET paid_until = ? WHERE id = 1').run(Date.now() - DAY);
    offers.set(110, ad(110, 'HP 250 G10'));
    const before = sent.length;
    await w.turboTick();
    assert.strictEqual(sent.length, before, 'без платного доступа — без турбо');
  } finally {
    olx.fetchSearch = origSearch;
    olx.fetchOffer = origOffer;
  }
});

test('продление доступа считается от конца текущего срока', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-'));
  const db = new Db(path.join(dir, 'w.db'));
  db.touchUser(5, 'X');
  const first = db.extend(5, 7);
  const second = db.extend(5, 14);
  assert.ok(Math.abs(second - first - 14 * DAY) < 1000, '14 дней добавлены к концу 7-дневного срока');
  assert.ok(db.isPaid(5));
});
