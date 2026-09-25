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
  const ad = (id, title, extra = {}) => ({ id, title, url: `https://www.olx.kz/d/obyavlenie/x-ID${olx.encodeId(id)}.html`, price: 200000, city: 'Алматы', categoryId: 1234, createdAt: Date.now() + 60_000, ...extra });

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
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 200000, city: 'Алматы', categoryId: 1234, createdAt: Date.now() + 60_000, ...extra });
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
    latest = [ad(5000, 'HP 250 G9'), ad(4999, 'iPhone 13'), ad(900, 'HP старое, ниже отметки', { createdAt: now - 2 * 3600_000 }), ad(4998, 'HP старьё', { createdAt: now - 5 * 3600_000 })];
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
  const ad = (id, price, extra = {}) => ({ id, title: `HP ${id}`, url: 'u', price, city: 'Алматы', categoryId: 1234, createdAt: Date.now() + 60_000, ...extra });
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

test('продавец: все / частные / бизнес', () => {
  const w = new Watcher({ db: { get: () => 0 }, config: {}, notify: async () => {}, alert: async () => {}, log: () => {} });
  const shop = { business: true };
  const person = { business: false };
  assert.ok(w.sellerOk({ seller: 'all' }, shop) && w.sellerOk({ seller: 'all' }, person), 'по умолчанию — все');
  assert.ok(w.sellerOk({ seller: 'private' }, person) && !w.sellerOk({ seller: 'private' }, shop));
  assert.ok(w.sellerOk({ seller: 'business' }, shop) && !w.sellerOk({ seller: 'business' }, person));
  assert.ok(w.sellerOk({ seller: 'business', source: 'kolesa' }, person), 'у Kolesa признака нет — фильтр не мешает');
});

test('на проверке: номер ниже края ленты (его нет в ленте) турбо находит и присылает', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-gap-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 200000, city: 'Алматы', categoryId: 1234, createdAt: Date.now() + 60_000, ...extra });
  const origLatest = olx.fetchLatest;
  const origOffer = olx.fetchOffer;
  const offers = new Map();
  olx.fetchLatest = async () => [ad(5000, 'iPhone'), ad(4990, 'Диван')];
  olx.fetchOffer = async (id) => offers.get(id) || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a, subs, via) => sent.push(`${via}:${a.id}`), alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    const sub = db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    db.updateSub(sub.id, { initialized: 1, watermark: 1000 });
    db.db.prepare('UPDATE subs SET created_at = ?').run(now - 3600_000);   // поиск создан час назад
    offers.set(4995, ad(4995, 'HP 250 на проверке', { status: 'moderated', createdAt: now - 4 * 60_000 }));
    await w.boardTick();
    assert.ok(w.gaps.has(4995), 'пропуск запомнен');
    for (let i = 0; i < 40 && !sent.length; i++) await w.turboTick();
    assert.deepStrictEqual(sent, ['turbo:4995'], 'поймано, хотя ниже края ленты');
  } finally {
    olx.fetchLatest = origLatest;
    olx.fetchOffer = origOffer;
  }
});

test('без провалов: вышло с проверки позже соседей (номер ниже отметки) — всё равно приходит', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-late-'));
  const db = new Db(path.join(dir, 'w.db'));
  const t0 = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 1, city: 'Алматы', categoryId: 1, ...extra });
  const orig = olx.fetchSearch;
  const origOffer = olx.fetchOffer;
  let listing = [ad(100, 'HP было до поиска', { createdAt: t0 - 3600_000 })];
  olx.fetchSearch = async () => ({ source: 'state', ads: listing });
  olx.fetchOffer = async () => null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (u, a, s, via) => { if (via !== 'ready') sent.push(a.id); }, alert: async () => {}, log: () => {} });
  const tick = async () => { for (const s of db.subs()) db.updateSub(s.id, { last_poll: 0 }); await w.searchTick(); };
  try {
    db.touchUser(1, 'Я');
    db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    await tick();
    // 103 подано раньше 105, но прошло проверку позже: сначала в выдаче только 105.
    listing = [ad(105, 'HP 105', { createdAt: Date.now() + 1000 }), ...listing];
    await tick();
    listing = [ad(105, 'HP 105', { createdAt: Date.now() + 1000 }), ad(103, 'HP 103 после проверки', { createdAt: Date.now() + 500 }), ...listing];
    await tick();
    await tick();
    assert.deepStrictEqual(sent, [105, 103], '103 пришло, хотя ниже отметки; 100 (было до поиска) — нет; повторов нет');
  } finally {
    olx.fetchSearch = orig;
    olx.fetchOffer = origOffer;
  }
});

test('без провалов: 403 по номеру — не пауза; после простоя ПК поданное за это время приходит; не подошедшее в ленте приносит поиск', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-nomiss-'));
  const db = new Db(path.join(dir, 'w.db'));
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 1, city: 'Алматы', categoryId: 1, createdAt: Date.now() + 1000, ...extra });
  const orig = { search: olx.fetchSearch, offer: olx.fetchOffer, latest: olx.fetchLatest };
  let listing = [ad(100, 'HP старое', { createdAt: Date.now() - 7200_000 })];
  let latest = [];
  const hidden = new Set();
  olx.fetchSearch = async () => ({ source: 'state', ads: listing });
  olx.fetchLatest = async () => latest;
  olx.fetchOffer = async (id) => { if (hidden.has(id)) throw new olx.HttpError(403, 'u'); return null; };
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (u, a, s, via) => { if (via !== 'ready') sent.push(`${via}:${a.id}`); }, alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    const sub = db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    db.db.prepare('UPDATE subs SET created_at = ?').run(Date.now() - 10 * 3600_000);
    await w.searchTick();                                          // первый проход
    // 1) 403 по номеру — скрытое объявление, а не блокировка: паузы нет.
    w.frontier = 200;
    hidden.add(201);
    await w.turboTick();
    assert.ok(!w.blocked(), '403 по одному номеру не ставит бота на паузу');
    assert.match(w.why(201), /403/);
    // 2) ПК спал 2 часа: объявление подано 90 минут назад (старше FRESH_MIN=30) — всё равно новое.
    db.updateSub(sub.id, { last_poll: Date.now() - 2 * 3600_000 });
    listing = [ad(150, 'HP подано пока ПК спал', { createdAt: Date.now() - 90 * 60_000 }), ...listing];
    await w.searchTick();
    assert.ok(sent.includes('search:150'), 'поданное во время простоя пришло');
    // 3) В ленте объявление не подошло (рубрика 7 поиску ещё не встречалась) — не теряется: его приносит поиск.
    db.updateSub(sub.id, { learned: { categoryIds: [1], cities: ['Алматы'], total: 5 } });
    latest = [ad(160, 'HP в новой подрубрике', { categoryId: 7 })];
    await w.boardTick();
    assert.ok(!sent.includes('search:160'), 'по признакам в ленте не подошло');
    assert.match(w.why(160), /рубрика 7/);
    listing = [ad(160, 'HP в новой подрубрике', { categoryId: 7 }), ...listing];
    db.updateSub(sub.id, { last_poll: 0 });
    await w.searchTick();
    assert.ok(sent.includes('search:160'), 'поиск принёс то, что лента не отправила');
  } finally {
    Object.assign(olx, { fetchSearch: orig.search, fetchOffer: orig.offer, fetchLatest: orig.latest });
  }
});

test('без провалов: модерация прошла через 40 минут — по номеру и в ленте всё равно приходит', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-late-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const ad = (id, title, extra = {}) => ({ id, title, url: 'u', price: 200000, city: 'Алматы', categoryId: 1234, createdAt: now, ...extra });
  const orig = { latest: olx.fetchLatest, offer: olx.fetchOffer };
  const offers = new Map();
  let latest = [ad(5000, 'iPhone'), ad(4990, 'Диван')];
  olx.fetchLatest = async () => latest;
  olx.fetchOffer = async (id) => offers.get(id) || null;
  const sent = [];
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async (userId, a, subs, via) => sent.push(`${via}:${a.id}`), alert: async () => {}, log: () => {} });
  try {
    db.touchUser(1, 'Я');
    const sub = db.addSub(1, 'HP', 'https://www.olx.kz/d/elektronika/q-hp/');
    db.updateSub(sub.id, { initialized: 1, watermark: 1000 });
    db.db.prepare('UPDATE subs SET created_at = ?').run(now - 3 * 3600_000);   // поиск создан раньше
    await w.boardTick();
    assert.ok(w.gaps.has(4995), 'пропуск запомнен');
    // 40 минут OLX по номеру отвечает «нет такого»; пропуск всё ещё в очереди.
    w.gaps.get(4995).added = now - 40 * 60_000;
    w.gaps.get(4995).checked = 0;
    await w.turboTick();
    assert.ok(w.gaps.has(4995), 'через 40 минут всё ещё перепроверяем');
    // Прошло модерацию: подано 40 минут назад — всё равно новое.
    offers.set(4995, ad(4995, 'HP 250', { createdAt: now - 40 * 60_000 }));
    w.gaps.get(4995).checked = 0;
    await w.turboTick();
    assert.deepStrictEqual(sent, ['turbo:4995'], 'пришло по номеру');
    // Другое, прошедшее модерацию поздно, сразу появилось в ленте — тоже приходит.
    latest = [ad(5010, 'HP 15 поздно', { createdAt: now - 50 * 60_000 }), ...latest];
    await w.boardTick();
    assert.ok(sent.includes('search:5010'), 'пришло из ленты');
  } finally {
    olx.fetchLatest = orig.latest;
    olx.fetchOffer = orig.offer;
  }
});

test('пауза своя у площадки: OLX ограничил — Kaspi работает и не сбрасывает паузу OLX', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-block-'));
  const db = new Db(path.join(dir, 'w.db'));
  const w = new Watcher({ db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 1800_000 },
    notify: async () => {}, alert: async () => {}, log: () => {} });
  assert.ok(w.handleError(new olx.HttpError(403, 'u'), 'olx'));
  assert.ok(w.blocked('olx'));
  assert.ok(!w.blocked('kaspi'), 'Kaspi не на паузе');
  w.okRequest('kaspi');
  assert.strictEqual(w.backoffMs, 2 * 60_000, 'ответ Kaspi не сбросил паузу OLX');
  assert.ok(w.handleError(new olx.HttpError(429, 'u'), 'olx'));
  assert.strictEqual(w.backoffMs, 4 * 60_000, 'второй отказ подряд — пауза дольше');
});
