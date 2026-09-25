// VIP-рубрика: объявления из закреплённой рубрики и города получает только VIP — как бы ни
// был настроен чужой поиск (родительская рубрика, весь Казахстан, слова), и через турбо тоже.
const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');

const olx = require('../src/olx');
const vip = require('../src/vip');
const { Db, DAY } = require('../src/db');
const { Watcher } = require('../src/watcher');

test('разбор ссылки поиска: рубрика и город', () => {
  assert.deepStrictEqual(vip.parseSearchUrl('https://www.olx.kz/d/elektronika/noutbuki-i-aksesuary/almaty/q-hp/?x=1'),
    { path: 'elektronika/noutbuki-i-aksesuary', city: 'almaty' });
  assert.deepStrictEqual(vip.parseSearchUrl('https://www.olx.kz/d/kk/elektronika/'), { path: 'elektronika', city: '' });
});

test('VIP-рубрика: жёсткое правило по каждому объявлению', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-vip-'));
  const db = new Db(path.join(dir, 'w.db'));
  const now = Date.now();
  const NOTE = 1234;   // рубрика «ноутбуки»
  const ad = (id, title, extra = {}) => ({ id, title, url: `https://www.olx.kz/d/obyavlenie/x-ID${olx.encodeId(id)}.html`, price: 200000, city: 'Алматы', categoryId: NOTE, createdAt: now, ...extra });

  const listings = new Map();   // ссылка → выдача
  const origSearch = olx.fetchSearch;
  const origOffer = olx.fetchOffer;
  const offers = new Map();
  olx.fetchSearch = async (url) => ({ source: 'state', ads: listings.get(url) || [] });
  olx.fetchOffer = async (id) => offers.get(id) || null;
  const sent = [];
  const w = new Watcher({
    db, config: { pollSec: 2, turboSec: 1, turboWindow: 5, freshMs: 30 * 60_000 },
    notify: async (userId, a, subs, via) => { if (via !== 'ready') sent.push(`${userId}:${a.id}`); },
    alert: async () => {}, log: () => {},
  });
  const tick = async () => { for (const s of db.subs()) db.updateSub(s.id, { last_poll: 0 }); await w.searchTick(); };

  try {
    db.touchUser(1, 'VIP');
    db.touchUser(2, 'Другой');
    const g = vip.grant(db, 1, 'elektronika/noutbuki-i-aksesuary', 'almaty', 30);
    assert.ok(g.ok, 'VIP выдан');
    assert.ok(db.isPaid(1, 'olx'), 'VIP получает и доступ к OLX');
    const vipUrl = db.subs(1)[0].url;

    // Второй раз ту же рубрику и город другому — нельзя; рубрику внутри неё — тоже.
    assert.ok(!vip.grant(db, 2, 'elektronika/noutbuki-i-aksesuary', 'almaty', 7).ok);
    assert.ok(db.lockConflict(2, 'olx', 'elektronika/noutbuki-i-aksesuary/noutbuki', 'almaty'), 'подрубрика внутри закреплённой');
    assert.ok(db.lockConflict(2, 'olx', 'elektronika', 'almaty'), 'родительская рубрика в том же городе');
    assert.ok(!db.lockConflict(2, 'olx', 'elektronika/noutbuki-i-aksesuary', 'astana'), 'другой город свободен');

    // Другой обходит: вся «Электроника» по Казахстану и поиск по словам.
    const wide = 'https://www.olx.kz/d/elektronika/';
    const words = 'https://www.olx.kz/d/q-noutbuk/';
    db.addSub(2, 'Вся электроника', wide);
    db.addSub(2, 'Слова', words);
    listings.set(vipUrl, [ad(100, 'Ноутбук старый')]);
    listings.set(wide, [ad(100, 'Ноутбук старый')]);
    listings.set(words, [ad(100, 'Ноутбук старый')]);
    await tick();                       // первый проход — только отметки
    assert.deepStrictEqual(sent, []);

    // Новый ноутбук в Алматы — только VIP. Ноутбук в Астане — другому можно.
    const almaty = ad(105, 'Ноутбук HP');
    const astana = ad(106, 'Ноутбук Dell', { city: 'Астана' });
    listings.set(vipUrl, [almaty, ad(100, 'Ноутбук старый')]);
    listings.set(wide, [astana, almaty, ad(100, 'Ноутбук старый')]);
    listings.set(words, [astana, almaty, ad(100, 'Ноутбук старый')]);
    await tick();
    assert.ok(sent.includes('1:105'), 'VIP получил своё');
    assert.ok(!sent.includes('2:105'), 'другому — нет, ни по рубрике, ни по словам');
    assert.ok(sent.includes('2:106'), 'другой город — можно');

    // Турбо: новый ноутбук в Алматы (рубрика уже выучена) — только VIP.
    offers.set(107, ad(107, 'Ноутбук Lenovo'));
    sent.length = 0;
    await w.turboTick();
    assert.deepStrictEqual(sent.filter((x) => x.endsWith(':107')), ['1:107'], 'турбо — тоже только VIP');

    // Срок VIP кончился — рубрика снова общая.
    db.db.prepare('UPDATE vip_locks SET until = ?').run(Date.now() - DAY);
    w.lockCache.at = 0;
    assert.ok(w.allowed(2, ad(108, 'Ноутбук')), 'после срока — можно всем');
  } finally {
    olx.fetchSearch = origSearch;
    olx.fetchOffer = origOffer;
  }
});
