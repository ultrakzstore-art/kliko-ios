// Быстрые проверки без Electron и без сети: подсказки из имени папки и схема ответа Claude.
const assert = require('assert');
const { parseHint } = require('../src/intake');
const { LISTING_SCHEMA } = require('../src/describe');
const { normalize, GROUPS_SCHEMA } = require('../src/grouping');

assert.deepStrictEqual(parseHint('кроссовки nike 42 — 15000'), { note: 'кроссовки nike 42', price: 15000 });
assert.deepStrictEqual(parseHint('iPhone 13 128gb 180 000 тг'), { note: 'iPhone 13 128gb', price: 180000 });
assert.deepStrictEqual(parseHint('фара камри 50'), { note: 'фара камри 50', price: null });

// Раскладка пачки: мусорные номера и повторы выкидываются, забытые фото — отдельными
// товарами, группа больше 8 фото режется (лимит OLX).
const P = Array.from({ length: 12 }, (_, i) => `p${i + 1}`);
const g = normalize([
  { photos: [1, 2, 2, 99, 0], what: 'кроссовки' },
  { photos: [3, 4, 5, 6, 7, 8, 9, 10, 11], what: 'куртка' },
  { photos: [1], what: 'повтор' },
], P);
assert.deepStrictEqual(g.map((x) => x.photos), [['p1', 'p2'], ['p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9', 'p10'], ['p11'], ['p12']]);
assert.strictEqual(g[1].what, 'куртка');

// Страница входа OLX или нет.
const { isLoginUrl, LOGIN_POPUP_HOSTS } = require('../src/account');
assert.ok(isLoginUrl('https://login.olx.kz/?cc=abc'));
assert.ok(isLoginUrl('https://www.olx.kz/account/?ref%5B0%5D%5Baction%5D=myaccount'));
assert.ok(!isLoginUrl('https://www.olx.kz/myaccount/'));
assert.ok(!isLoginUrl('https://www.olx.kz/d/post-new-ad/'));
assert.ok(LOGIN_POPUP_HOSTS.test('accounts.google.com') && LOGIN_POPUP_HOSTS.test('www.facebook.com'));
assert.ok(!LOGIN_POPUP_HOSTS.test('evilfacebook.com'));

// Структурированный ответ: каждый объект закрыт и перечисляет все поля в required.
function walk(node, where) {
  if (node.type === 'object') {
    assert.strictEqual(node.additionalProperties, false, `${where}: additionalProperties`);
    assert.deepStrictEqual([...node.required].sort(), Object.keys(node.properties).sort(), `${where}: required`);
    for (const [k, v] of Object.entries(node.properties)) walk(v, `${where}.${k}`);
  }
  if (node.type === 'array') walk(node.items, `${where}[]`);
}
walk(LISTING_SCHEMA, 'listing');
walk(GROUPS_SCHEMA, 'groups');


console.log('ok');
