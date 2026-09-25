const test = require('node:test');
const assert = require('node:assert');

const olx = require('../src/olx');
const { filtersFromUrl, learn, matches } = require('../src/match');
const { adLink, nameFromUrl, card } = require('../src/bot');

test('короткий код в ссылке — номер объявления в 62-ричной записи (живой пример)', () => {
  const url = 'https://www.olx.kz/d/kk/obyavlenie/hp-250r-g9-i5-1335u-16gb-256gb-ssd-full-hd-akb-100-IDr9sfK.html#401214632';
  assert.strictEqual(olx.decodeId('r9sfK'), 401214632);
  assert.strictEqual(olx.encodeId(401214632), 'r9sfK');
  assert.strictEqual(olx.encodeId(401214633), 'r9sfL');
  assert.strictEqual(olx.idFromUrl(url), 401214632);
  assert.strictEqual(olx.idFromUrl('https://www.olx.kz/d/elektronika/q-hp/'), null);
  // Свежая ссылка, пока объявление без кода: /d/ru/obyavlenie/<название>.html#<номер>
  assert.strictEqual(olx.idFromUrl('https://www.olx.kz/d/ru/obyavlenie/prodam-noutbuk.html#401224244'), 401224244);
  assert.strictEqual(olx.idFromUrl('https://www.olx.kz/d/ru/obyavlenie/prodam-noutbuk.html#401224244;promoted'), 401224244);
});

test('поиск переворачивается «сначала новые», чужие сайты не принимаются', () => {
  const u = new URL(olx.newestFirst('https://www.olx.kz/d/elektronika/q-hp-250/?search%5Bfilter_float_price%3Ato%5D=300000#x'));
  assert.strictEqual(u.searchParams.get('search[order]'), 'created_at:desc');
  assert.strictEqual(u.searchParams.get('search[filter_float_price:to]'), '300000');
  assert.throws(() => olx.newestFirst('https://example.com/d/'));
});

test('разбор выдачи: данные страницы, а без них — номера из ссылок', () => {
  const state = { listing: { listing: { ads: [
    { id: 401214632, title: 'HP 250 G9', url: 'https://www.olx.kz/d/obyavlenie/hp-IDr9sfK.html', price: { regularPrice: { value: 250000 }, displayValue: '250 000 ₸' }, location: { cityName: 'Алматы' }, category: { id: 1234 }, createdTime: '2026-09-24T10:00:00+05:00', isPromoted: false, photos: ['https://img/x;s={width}x{height}'] },
  ] } } };
  const html = `<script>window.__PRERENDERED_STATE__= ${JSON.stringify(JSON.stringify(state))};</script>`;
  const r = olx.parseSearchHtml(html);
  assert.strictEqual(r.source, 'state');
  assert.deepStrictEqual(
    { id: r.ads[0].id, price: r.ads[0].price, city: r.ads[0].city, cat: r.ads[0].categoryId, photo: r.ads[0].photo },
    { id: 401214632, price: 250000, city: 'Алматы', cat: 1234, photo: 'https://img/x;s=800x600' },
  );

  const r2 = olx.parseSearchHtml('<a href="/d/obyavlenie/a-IDr9sfK.html">a</a><a href="/d/obyavlenie/b-IDr9sfL.html">b</a><a href="/d/obyavlenie/a-IDr9sfK.html">a</a>');
  assert.strictEqual(r2.source, 'links');
  assert.deepStrictEqual(r2.ads.map((a) => a.id), [401214632, 401214633]);
});

test('карточка по номеру: цена из параметров, остальные параметры отдельно', () => {
  const o = olx.normalizeOffer({
    id: 401214632, title: 'HP 250 G9', description: 'Ноутбук<br/>АКБ 100%', created_time: '2026-09-24T10:00:00+05:00', status: 'active',
    category: { id: 1234 }, user: { id: 777, name: 'Ерлан' }, location: { city: { name: 'Алматы' }, region: { name: 'Алматы' } },
    params: [{ key: 'price', name: 'Цена', value: { value: 250000, currency: 'KZT', label: '250 000 ₸' } }, { key: 'state', name: 'Состояние', value: { label: 'Б/у' } }],
    photos: [{ link: 'https://img/y;s={width}x{height}' }],
  });
  assert.strictEqual(o.price, 250000);
  assert.strictEqual(o.priceLabel, '250 000 ₸');
  assert.deepStrictEqual(o.params, ['Состояние: Б/у']);
  assert.strictEqual(o.description, 'Ноутбук\nАКБ 100%');
  assert.strictEqual(o.userId, 777);
});

test('турбо-фильтр: слова, цена, выученные рубрики и город', () => {
  const url = 'https://www.olx.kz/d/elektronika/almaty/q-hp-250/?search%5Bfilter_float_price%3Ato%5D=300000';
  assert.deepStrictEqual(filtersFromUrl(url), { words: ['hp', '250'], priceFrom: null, priceTo: 300000 });
  const seen = Array.from({ length: 25 }, (_, i) => ({ categoryId: i % 2 ? 1234 : 1235, city: 'Алматы' }));
  const sub = { url, learned: learn({}, seen) };
  const ad = { title: 'Ноутбук HP 250 G9', price: 250000, categoryId: 1234, city: 'Алматы' };
  assert.ok(matches(sub, ad));
  assert.ok(!matches(sub, { ...ad, price: 350000 }), 'дороже фильтра');
  assert.ok(!matches(sub, { ...ad, title: 'Ноутбук Lenovo' }), 'нет слов запроса');
  assert.ok(!matches(sub, { ...ad, categoryId: 9999 }), 'чужая рубрика');
  assert.ok(!matches(sub, { ...ad, city: 'Астана' }), 'другой город');
  // Поиск без слов и без выученных рубрик турбо не трогает — иначе полетит весь OLX.
  assert.ok(!matches({ url: 'https://www.olx.kz/d/', learned: {} }, ad));
});

test('ссылка в уведомлении — чистая, без номера после #; название поиска — из ссылки', () => {
  assert.strictEqual(adLink({ id: 401214632, url: 'https://www.olx.kz/d/obyavlenie/hp-IDr9sfK.html#401214632' }), 'https://www.olx.kz/d/obyavlenie/hp-IDr9sfK.html');
  assert.strictEqual(adLink({ id: 401214632 }), 'https://www.olx.kz/d/obyavlenie/-IDr9sfK.html');
  assert.strictEqual(nameFromUrl('https://www.olx.kz/d/elektronika/almaty/q-hp-250/'), 'hp 250');
  const c = card({ title: 'HP <250>', price: 250000, city: 'Алматы', status: 'moderated' }, [{ name: 'Ноуты' }], 'turbo');
  assert.ok(c.includes('HP &lt;250&gt;') && c.includes('⚡ эксклюзив') && c.includes('на проверке'));
});

test('обмен и «отдам даром» проходят любой фильтр цены', () => {
  const sub = { url: 'https://www.olx.kz/d/elektronika/q-hp/?search%5Bfilter_float_price%3Afrom%5D=100000&search%5Bfilter_float_price%3Ato%5D=300000', learned: {} };
  const base = { title: 'HP 250', city: 'Алматы', categoryId: 1 };
  assert.ok(matches(sub, { ...base, price: null, priceLabel: 'Обмен' }), 'обмен');
  assert.ok(matches(sub, { ...base, price: 0, priceLabel: 'Бесплатно' }), 'даром');
  assert.ok(matches(sub, { ...base, price: 200000 }), 'в диапазоне');
  assert.ok(!matches(sub, { ...base, price: 50000 }), 'дешевле «от»');
  const c = card({ title: 'HP', price: null, priceLabel: 'Обмен' }, [{ name: 'x' }], 'search');
  assert.ok(c.includes('🔁 Обмен'));
});

test('ссылка «все объявления автора» — со страницы объявления', () => {
  const { sellerLinkIn } = require('../src/olx');
  assert.strictEqual(sellerLinkIn('<a href="/list/user/abcXYZ/" data-testid="user-profile-link">Все объявления автора</a>'), 'https://www.olx.kz/list/user/abcXYZ/');
  assert.strictEqual(sellerLinkIn('{"url":"https:\\/\\/www.olx.kz\\/d\\/list\\/user\\/Q7mRk\\/"}'), 'https://www.olx.kz/d/list/user/Q7mRk/');
  assert.strictEqual(sellerLinkIn('<a href="https://vprok.olx.kz/home/">Магазин</a>'), 'https://vprok.olx.kz/home/');
  assert.strictEqual(sellerLinkIn('<html>ничего</html>'), null);
});
