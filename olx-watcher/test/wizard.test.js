// Выбор поиска кнопками — целиком, на подставных Телеграме и OLX (без сети).
const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');

const cats = require('../src/categories');
const olx = require('../src/olx');
const { Db } = require('../src/db');
const { createBot } = require('../src/bot');

test('ссылка поиска из выбранного и разбор цены', () => {
  assert.strictEqual(cats.buildSearchUrl({ path: 'elektronika/noutbuki', city: 'almaty', words: 'HP 250!', priceTo: 300000 }),
    'https://www.olx.kz/d/elektronika/noutbuki/almaty/q-hp-250/?search%5Bfilter_float_price%3Ato%5D=300000');
  assert.strictEqual(cats.buildSearchUrl({ path: 'transport' }), 'https://www.olx.kz/d/transport/');
  assert.deepStrictEqual(cats.parsePrice('до 300000'), { from: null, to: 300000 });
  assert.deepStrictEqual(cats.parsePrice('от 100 до 250 тыс'), { from: 100, to: 250000 });
  assert.deepStrictEqual(cats.parsePrice('150000-300000'), { from: 150000, to: 300000 });
  assert.deepStrictEqual(cats.parsePrice('300к'), { from: null, to: 300000 });
  assert.deepStrictEqual(cats.parsePrice('от 50000'), { from: 50000, to: null });
  assert.strictEqual(cats.parsePrice('недорого'), null);
});

test('подрубрики со страницы OLX: только на уровень ниже, без городов и служебных ссылок', () => {
  const html = `
    <a href="/d/elektronika/noutbuki-i-aksesuary/"><span>Ноутбуки и аксессуары</span> <span>12 345</span></a>
    <a href="https://www.olx.kz/d/elektronika/telefony-i-aksesuary/">Телефоны и аксессуары</a>
    <a href="/d/elektronika/almaty/">Алматы</a>
    <a href="/d/elektronika/noutbuki-i-aksesuary/noutbuki/">Ноутбуки</a>
    <a href="/d/obyavlenie/x-IDr9sfK.html">Объявление</a>
    <a href="/d/transport/">Транспорт</a>`;
  assert.deepStrictEqual(cats.parseChildren(html, 'elektronika'), [
    { name: 'Ноутбуки и аксессуары', path: 'elektronika/noutbuki-i-aksesuary' },
    { name: 'Телефоны и аксессуары', path: 'elektronika/telefony-i-aksesuary' },
  ]);
});

test('мастер: рубрика → подрубрика → город → слова → цена → проверка → сохранить', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'olxw-wiz-'));
  const db = new Db(path.join(dir, 'w.db'));
  db.set('owner', 42);

  // Подставной OLX: у «Электроники» две подрубрики, у ноутбуков — ни одной (конечная).
  cats._setFetch(async (url) => {
    if (url.endsWith('/d/elektronika/')) return '<a href="/d/elektronika/noutbuki/">Ноутбуки</a><a href="/d/elektronika/telefony/">Телефоны</a>';
    return '';
  });
  const origSearch = olx.fetchSearch;
  let searched = '';
  olx.fetchSearch = async (url) => { searched = url; return { source: 'state', ads: [{ id: 1, title: 'HP 250 G9', priceLabel: '250 000 ₸' }] }; };

  const none = { stars: null, kaspi: null };
  const config = { pollSec: 2, paidSubs: 3, sellerUrl: '', kaspiDetails: 'Kaspi +7 700 000 00 00',
    prices: { olx: { stars: [100, 180, 300], kaspi: [1500, 2500, 4500] }, kolesa: none, krisha: none, kaspi: none,
      all: { stars: [250, 450, 800], kaspi: [4000, 7000, 12000] } } };
  const { bot } = createBot({ token: '1:x', db, config, getWatcher: () => null, log: () => {} });
  bot.botInfo = { id: 1, is_bot: true, first_name: 'bot', username: 'bot', can_join_groups: false, can_read_all_group_messages: false, supports_inline_queries: false };
  const sent = [];
  bot.api.config.use(async (prev, method, payload) => {
    sent.push({ method, payload });
    return { ok: true, result: method === 'answerCallbackQuery' ? true : { message_id: 1, date: 0, chat: { id: 42, type: 'private' }, text: '' } };
  });

  let uid = 0;
  const from = { id: 42, is_bot: false, first_name: 'Я' };
  const chat = { id: 42, type: 'private' };
  const text = (t) => bot.handleUpdate({ update_id: ++uid, message: { message_id: uid, date: 0, chat, from, text: t, ...(t.startsWith('/') ? { entities: [{ type: 'bot_command', offset: 0, length: t.length }] } : {}) } });
  const press = (data) => bot.handleUpdate({ update_id: ++uid, callback_query: { id: String(uid), from, chat_instance: 'x', data, message: { message_id: 1, date: 0, chat, from, text: '' } } });
  const lastText = () => [...sent].reverse().find((s) => s.payload.text && s.method !== 'answerCallbackQuery').payload.text;
  const buttons = () => ([...sent].reverse().find((s) => s.payload.reply_markup).payload.reply_markup.inline_keyboard.flat());

  try {
    await text('/new');
    assert.match(lastText(), /Где искать/);
    assert.ok(buttons().some((b) => /Kolesa/.test(b.text)) && buttons().some((b) => /Krisha/.test(b.text)), 'выбор площадки');
    await press('w:src:olx');
    assert.match(lastText(), /Выберите рубрику/);
    const elektro = buttons().find((b) => b.text === 'Электроника');
    await press(elektro.callback_data);
    assert.ok(buttons().some((b) => b.text === 'Ноутбуки'), 'подрубрики с OLX');
    await press(buttons().find((b) => b.text === 'Ноутбуки').callback_data);
    assert.match(lastText(), /Город/, 'конечная рубрика → сразу город');
    await press(buttons().find((b) => b.text === 'Алматы').callback_data);
    assert.match(lastText(), /Ключевые слова/);
    await text('hp 250');
    assert.match(lastText(), /Цена/);
    await text('до 300к');
    assert.match(lastText(), /От кого присылать/);
    assert.ok(buttons().some((b) => b.callback_data === 'w:seller:all'), 'по умолчанию — все');
    await press('w:seller:private');
    assert.match(lastText(), /HP 250 G9/, 'пробный поиск показан до сохранения');
    assert.strictEqual(searched, 'https://www.olx.kz/d/elektronika/noutbuki/almaty/q-hp-250/?search%5Bfilter_float_price%3Ato%5D=300000');
    await press('w:save');
    const subs = db.subs(42);
    assert.strictEqual(subs.length, 1);
    assert.strictEqual(subs[0].name.replace(/\u00a0/g, ' '), 'hp 250 · Алматы · до 300 000');
    assert.strictEqual(subs[0].url, searched);
    assert.strictEqual(subs[0].seller, 'private', 'выбор продавца сохранён');

    // Другой человек — тоже пользователь, со своими поисками и бесплатным доступом.
    const other = { id: 7, is_bot: false, first_name: 'Гость' };
    const otherChat = { id: 7, type: 'private' };
    const say = (t) => bot.handleUpdate({ update_id: ++uid, message: { message_id: uid, date: 0, chat: otherChat, from: other, text: t } });
    await say('https://www.olx.kz/d/elektronika/q-a/');
    await say('https://www.olx.kz/d/elektronika/q-b/');
    await say('https://www.olx.kz/d/elektronika/q-c/');
    await say('https://www.olx.kz/d/elektronika/q-d/');
    assert.strictEqual(db.subs(7).length, 3, 'лимит поисков (в тесте PAID_SUBS = 3)');
    assert.match(lastText(), /3 поисков/);
    assert.strictEqual(db.subs(42).length, 1, 'поиски не смешиваются');

    // Kaspi: гость жмёт «Я оплатил» → владельцу заявка → «Дать» → доступ на 14 дней.
    const pressAs = (from, data) => bot.handleUpdate({ update_id: ++uid, callback_query: { id: String(uid), from, chat_instance: 'x', data, message: { message_id: 1, date: 0, chat: { id: from.id, type: 'private' }, from, text: 'заявка' } } });
    await pressAs(other, 'buy:all');
    assert.ok(buttons().some((b) => b.callback_data === 'kaspi:all:14'), 'комбо: кнопки Kaspi по срокам');
    await pressAs(other, 'kaspi:all:14');
    assert.match(lastText(), /7\s?000 ₸/);
    await pressAs(other, 'kpaid:all:14');
    const toAdmin = [...sent].reverse().find((x) => x.method === 'sendMessage' && x.payload.chat_id === 42);
    assert.match(toAdmin.payload.text, /Kaspi/);
    const approve = toAdmin.payload.reply_markup.inline_keyboard.flat().find((b) => b.callback_data.startsWith('approve:'));
    await pressAs(other, approve.callback_data);                 // не владелец — не может
    assert.ok(!db.isPaid(7));
    await pressAs(from, approve.callback_data);                  // владелец — выдаёт
    assert.ok(db.isPaid(7, 'olx') && db.isPaid(7, 'kolesa') && db.isPaid(7, 'krisha') && db.isPaid(7, 'kaspi'), 'комбо — все площадки');

    // Stars: успешная оплата продлевает автоматически.
    await bot.handleUpdate({ update_id: ++uid, message: { message_id: uid, date: 0, chat: otherChat, from: other,
      successful_payment: { currency: 'XTR', total_amount: 100, invoice_payload: 'stars:olx:7:7', telegram_payment_charge_id: 'c1', provider_payment_charge_id: '' } } });
    assert.ok(db.paidUntil(7, 'olx') - Date.now() > 20 * 86400_000, 'OLX: 14 + 7 дней');
    assert.ok(db.paidUntil(7, 'kolesa') - Date.now() < 15 * 86400_000, 'Kolesa: только 14 из комбо');
  } finally {
    olx.fetchSearch = origSearch;
  }
});
