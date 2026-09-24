// Быстрые проверки без Electron и без сети: подсказки из имени папки и схема ответа Claude.
const assert = require('assert');
const { parseHint } = require('../src/intake');
const { LISTING_SCHEMA } = require('../src/describe');

assert.deepStrictEqual(parseHint('кроссовки nike 42 — 15000'), { note: 'кроссовки nike 42', price: 15000 });
assert.deepStrictEqual(parseHint('iPhone 13 128gb 180 000 тг'), { note: 'iPhone 13 128gb', price: 180000 });
assert.deepStrictEqual(parseHint('фара камри 50'), { note: 'фара камри 50', price: null });

// Структурированный ответ: каждый объект закрыт и перечисляет все поля в required.
(function walk(node, where) {
  if (node.type === 'object') {
    assert.strictEqual(node.additionalProperties, false, `${where}: additionalProperties`);
    assert.deepStrictEqual([...node.required].sort(), Object.keys(node.properties).sort(), `${where}: required`);
    for (const [k, v] of Object.entries(node.properties)) walk(v, `${where}.${k}`);
  }
  if (node.type === 'array') walk(node.items, `${where}[]`);
})(LISTING_SCHEMA, 'listing');

console.log('ok');
