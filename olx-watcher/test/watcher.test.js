// Полный цикл на подставном OLX: первый проход молчит, новое из поиска приходит один раз,
// турбо ловит следующий номер раньше поиска и не присылает чужое.
const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');

const olx = require('../src/olx');
const { Db } = require('../src/db');
const { Watcher } = require('../src/watcher');

test('поиск и турбо', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: `https://www.olx.kz/d/obyavlenie/x-ID${olx.encodeId(id)}.html`, price: 200000, city: 'Алматы', categoryId: 1234, createdAt: now, ...extra });

  let listing = [ad(100, 'HP 250 старое'), ad(99, 'HP 250 ещё старее')];
  const offers = new Map();
  const origSearch = olx.fetchSearch;
  const origOffer = olx.fetchOffer;
  olx.fetchSearch = async () => ({ source: 'state', ads: listing });
  olx.fetchOffer = async (id) => offers.get(id) || null;

  const sent = [];
  const w = new Watcher({
    db, config: { pollSec: 10, turboSec: 5, turboWindow: 5 },
    notify: async (a, subs, via) => { sent.push({ id: a.id, via, subs: subs.map((s) => s.id) }); },
    alert: async () => {}, log: () => {},
  });
  try {
    const sub = db.addSub('Ноуты HP', 'https://www.olx.kz/d/elektronika/q-hp-250/');

    await w.pollSub(db.sub(sub.id));
    assert.deepStrictEqual(sent, [], 'первый проход только запоминает');
    assert.strictEqual(w.frontier, 100);

    // Новое объявление в поиске → одно уведомление; повторный проход — тишина.
    listing = [ad(105, 'HP 250 G9 новое'), ...listing];
    await w.pollSub(db.sub(sub.id));
    await w.pollSub(db.sub(sub.id));
    assert.deepStrictEqual(sent, [{ id: 105, via: 'search', subs: [sub.id] }]);

    // Старое объявление, поднятое в «Топ», — не новое.
    listing = [ad(50, 'HP 250 из Топа', { createdAt: now - 3 * 3600_000, promoted: true }), ...listing];
    await w.pollSub(db.sub(sub.id));
    assert.strictEqual(sent.length, 1);

    // Турбо: следующие номера после 105. 106 — чужое (телефон), 108 — наше, 107 пустой.
    offers.set(106, ad(106, 'iPhone 13', { categoryId: 555 }));
    offers.set(108, ad(108, 'HP 250 G8 на проверке', { status: 'moderated' }));
    await w.turboTick();
    assert.deepStrictEqual(sent.slice(1), [{ id: 108, via: 'turbo', subs: [sub.id] }]);
    assert.strictEqual(w.frontier, 108);

    // Когда 108 доедет до поиска — второй раз не придёт.
    listing = [ad(108, 'HP 250 G8'), ...listing];
    await w.pollSub(db.sub(sub.id));
    assert.strictEqual(sent.length, 2);
    assert.strictEqual(db.sub(sub.id).sent, 2);
  } finally {
    olx.fetchSearch = origSearch;
    olx.fetchOffer = origOffer;
  }
});
