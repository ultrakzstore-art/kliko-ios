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

test('тест и платный работают одинаково: поиск, турбо; без доступа — ничего', async () => {
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
    db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 30 * 60_000 },
    notify: async (userId, a, subs, via) => { if (via !== 'ready') sent.push({ user: userId, id: a.id, via }); },
    alert: async () => {}, log: () => {},
  });
  const both = () => { for (const s of db.subs()) db.updateSub(s.id, { last_poll: 0 }); };
  const byUser = (list) => [...list].sort((x, y) => x.user - y.user);
  try {
    db.touchUser(1, 'Платный');
    db.touchUser(2, 'Тест');
    db.extend(1, 7);
    const url = 'https://www.olx.kz/d/elektronika/q-hp-250/';
    const paidSub = db.addSub(1, 'HP платный', url);
    db.addSub(2, 'HP тест', url);

    // Первый проход: одна ссылка у двоих — один запрос; никому ничего не шлём.
    await w.searchTick();
    assert.strictEqual(searches, 1, 'одна ссылка — один запрос');
    assert.deepStrictEqual(sent, []);
    assert.strictEqual(db.sub(paidSub.id).watermark, 100);

    // Новое объявление — приходит обоим сразу, каждому один раз.
    listing = [ad(105, 'HP 250 G9 новое'), ...listing];
    both();
    await w.searchTick();
    assert.deepStrictEqual(byUser(sent), [{ user: 1, id: 105, via: 'search' }, { user: 2, id: 105, via: 'search' }]);

    // Поднятое старьё (подано 3 часа назад) — не новое ни для кого.
    listing = [ad(106, 'HP 250 из Топа', { createdAt: now - 3 * 3600_000, promoted: true }), ...listing];
    both();
    await w.searchTick();
    assert.strictEqual(sent.length, 2, 'старьё не прислано');

    // Турбо — и платному, и тесту. 107 — чужое (телефон), 108 — наше, на проверке.
    offers.set(107, ad(107, 'iPhone 13', { categoryId: 555 }));
    offers.set(108, ad(108, 'HP 250 G8 на проверке', { status: 'moderated' }));
    await w.turboTick();
    assert.deepStrictEqual(byUser(sent.slice(2)), [{ user: 1, id: 108, via: 'turbo' }, { user: 2, id: 108, via: 'turbo' }]);

    // Когда 108 доедет до поиска — второй раз не придёт никому.
    listing = [ad(108, 'HP 250 G8'), ...listing];
    both();
    await w.searchTick();
    assert.strictEqual(sent.length, 4, 'повтора нет');

    // Сроки кончились у обоих — турбо больше не работает.
    db.db.prepare('UPDATE access SET until = ? WHERE user_id = 1').run(Date.now() - DAY);
    db.db.prepare('UPDATE users SET trial_until = ?').run(Date.now() - DAY);
    offers.set(110, ad(110, 'HP 250 G10'));
    await w.turboTick();
    assert.strictEqual(sent.length, 4, 'без доступа — без турбо');
  } finally {
    olx.fetchSearch = origSearch;
    olx.fetchOffer = origOffer;
  }
});

test('тестовый доступ: новичку есть, после срока — поиски не проверяются', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-'));
  const db = new Db(path.join(dir, 'w.db'));
  db.trialMs = 7 * DAY;
  db.touchUser(9, 'Новичок');
  assert.ok(db.isTrial(9) && db.hasAccess(9) && !db.isPaid(9), 'новичок — на тесте');
  const sub = db.addSub(9, 'x', 'https://www.olx.kz/d/elektronika/q-x/');
  db.db.prepare('UPDATE users SET trial_until = ? WHERE id = 9').run(Date.now() - 1000);
  assert.ok(!db.hasAccess(9), 'тест кончился');
  let searches = 0;
  const orig = olx.fetchSearch;
  olx.fetchSearch = async () => { searches += 1; return { source: 'state', ads: [] }; };
  try {
    const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 }, notify: async () => {}, alert: async () => {}, log: () => {} });
    await w.searchTick();
    assert.strictEqual(searches, 0, 'без доступа OLX не спрашиваем');
    db.extend(9, 7);
    await w.searchTick();
    assert.strictEqual(searches, 1, 'оплатил — снова проверяем');
    assert.ok(db.sub(sub.id).initialized);
  } finally {
    olx.fetchSearch = orig;
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

test('лента всей доски: подходящее новое приходит сразу, граница прыгает к краю ленты', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-board-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 200000, city: 'Алматы', categoryId: 1234, createdAt: now, ...extra });
  const origLatest = olx.fetchLatest;
  let latest = [];
  olx.fetchLatest = async () => latest;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a) => sent.push(`${userId}:${a.id}`), alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    const sub = db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    db.updateSub(sub.id, { initialized: 1, watermark: 1000 });
    latest = [ad(5000, 'HP 250 G9'), ad(4999, 'iPhone 13'), ad(900, 'HP старое, ниже отметки'), ad(4998, 'HP старьё', { createdAt: now - 5 * 3600_000 })];
    await w.boardTick();
    assert.deepStrictEqual(sent, ['1:5000'], 'только подходящее, свежее и новее отметки');
    assert.strictEqual(w.frontier, 4995, 'турбо продолжит от края ленты');
    await w.boardTick();
    assert.deepStrictEqual(sent, ['1:5000'], 'второй раз не приходит');
  } finally {
    olx.fetchLatest = origLatest;
  }
});

test('скидки: цена знакомого объявления упала — «Цена снижена» один раз; и по уже присланным', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-disc-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, price, extra = {}) => ({ id, title: `HP ${id}`, url: 'u', price, city: 'Алматы', categoryId: 1234, createdAt: now, ...extra });
  const origSearch = olx.fetchSearch;
  const origOffer = olx.fetchOffer;
  let listing = [ad(100, 300000)];
  const offers = new Map();
  olx.fetchSearch = async () => ({ source: 'state', ads: listing });
  olx.fetchOffer = async (id) => offers.get(id) || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000, minDropPct: 3 },
    notify: async (userId, a, subs, via) => { if (via !== 'ready') sent.push(`${via}:${a.id}:${a.oldPrice || ''}->${a.price}`); },
    alert: async () => {}, log: () => {} });
  const tick = async () => { for (const s of db.subs()) db.updateSub(s.id, { last_poll: 0 }); await w.searchTick(); };
  try {
    db.touchUser(1, 'Я');
    db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    await tick();                                   // первый проход: цены запомнили
    listing = [ad(100, 299000)];                    // −0,3% — меньше порога
    await tick();
    assert.deepStrictEqual(sent, []);
    listing = [ad(100, 250000)];                    // −16%
    await tick();
    await tick();
    assert.deepStrictEqual(sent, ['discount:100:299000->250000'], 'скидка — один раз');

    // Новое пришло поиском, потом продавец снизил цену — ловим фоновой перепроверкой.
    listing = [ad(105, 500000), ad(100, 250000)];
    await tick();
    assert.ok(sent.includes('search:105:->500000'));
    offers.set(105, ad(105, 450000));
    await w.recheckTick();
    assert.ok(sent.includes('discount:105:500000->450000'), 'скидка на уже присланное');
  } finally {
    olx.fetchSearch = origSearch;
    olx.fetchOffer = origOffer;
  }
});
