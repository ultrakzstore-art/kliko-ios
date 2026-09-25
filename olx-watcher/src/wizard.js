// Новый поиск кнопками: рубрика → подрубрика → город → слова → цена → проверка → сохранить.
// Ссылку с сайта копировать не нужно (но и она по-прежнему принимается).

const { AsyncLocalStorage } = require('node:async_hooks');
const { InlineKeyboard } = require('grammy');
const cats = require('./categories');
const olx = require('./olx');
const sources = require('./sources');

function registerWizard(bot, { db, log, canAdd }) {
  // У каждого пользователя — своё состояние мастера. Обработчики асинхронные и идут вперемешку,
  // поэтому состояние берётся из контекста запроса, а не из общей переменной.
  const states = new Map();
  const als = new AsyncLocalStorage();
  bot.use((ctx, next) => {
    const uid = ctx.from?.id;
    return als.run({
      get w() { return states.get(uid) || null; },
      set w(v) { if (v) states.set(uid, v); else states.delete(uid); },
    }, next);
  });
  const st = () => als.getStore();

  const fresh = () => ({ step: 'source', source: 'olx', stack: [], options: cats.TOP, kcat: null, ksub: null, city: null, words: '', priceFrom: null, priceTo: null, seller: 'all', url: '' });
  const src = () => sources.get(st().w.source);
  const current = () => st().w.stack[st().w.stack.length - 1] || null;

  async function show(ctx, text, kb, edit = true) {
    const opts = { reply_markup: kb, parse_mode: 'HTML', link_preview_options: { is_disabled: true } };
    if (edit && ctx.callbackQuery) {
      try { await ctx.editMessageText(text, opts); return; } catch { /* сообщение не изменилось или старое — шлём новое */ }
    }
    await ctx.reply(text, opts);
  }

  async function stepCategory(ctx, edit = true) {
    st().w.step = 'cat';
    const cur = current();
    const kb = new InlineKeyboard();
    if (cur) kb.text(`✅ Вся «${cur.name}»`, 'w:ok').row();
    st().w.options.forEach((o, i) => { kb.text(o.name, `w:c:${i}`); if (i % 2 === 1) kb.row(); });
    kb.row();
    if (cur) kb.text('⬅️ Назад', 'w:back');
    kb.text('Без рубрики — только по словам', 'w:any').row().text('✖️ Отмена', 'w:cancel');
    const path = st().w.stack.map((s) => s.name).join(' › ');
    await show(ctx, `<b>Новый поиск</b>\n${path ? `Рубрика: ${esc(path)}\n` : ''}Выберите ${cur ? 'подрубрику или всю рубрику' : 'рубрику'}:`, kb, edit);
  }

  async function stepCity(ctx) {
    st().w.step = 'city';
    const kb = new InlineKeyboard().text('🇰🇿 Весь Казахстан', 'w:city:-').row();
    cats.CITIES.forEach((c, i) => { kb.text(c.name, `w:city:${i}`); if (i % 3 === 2) kb.row(); });
    await show(ctx, `<b>Новый поиск</b>\nРубрика: ${esc(label())}\nГород:`, kb);
  }

  async function stepWords(ctx) {
    st().w.step = 'words';
    const kb = new InlineKeyboard();
    if (current()) kb.text('Пропустить', 'w:skipwords');
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\nКлючевые слова? Напишите, например: <i>iphone 13</i>, <i>hp 250</i>, <i>зимние шины r16</i>.${current() ? '\nИли «Пропустить» — все объявления рубрики.' : ''}`, kb);
  }

  async function stepPrice(ctx) {
    st().w.step = 'price';
    const kb = new InlineKeyboard().text('Любая цена', 'w:skipprice');
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\nЦена? Напишите: <i>до 300000</i>, <i>от 100000 до 250000</i>, <i>300к</i>.`, kb);
  }

  // Продавец (только OLX): все, частные или бизнес. По умолчанию — все.
  async function stepSeller(ctx) {
    if (st().w.source !== 'olx') return stepConfirm(ctx);
    st().w.step = 'seller';
    const kb = new InlineKeyboard().text('👥 Все', 'w:seller:all').row()
      .text('👤 Только частные', 'w:seller:private').text('🏪 Только бизнес', 'w:seller:business');
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\nОт кого присылать?`, kb);
  }

  // Пробный запрос к OLX: показываем, что реально найдётся по этой ссылке, до сохранения.
  async function stepConfirm(ctx) {
    st().w.step = 'confirm';
    const w = st().w;
    w.url = w.source === 'olx'
      ? cats.buildSearchUrl({ path: current()?.path, city: w.city?.slug, words: w.words, priceFrom: w.priceFrom, priceTo: w.priceTo })
      : src().wizard.build({ path: (w.ksub || w.kcat).path, params: w.ksub?.params, city: w.city?.slug, priceFrom: w.priceFrom, priceTo: w.priceTo });
    let preview;
    try {
      const found = await src().fetchSearch(w.url);
      const ads = found.filter((a) => !a.promoted && a.title).slice(0, 3);
      preview = !found.length ? 'Сейчас по этому поиску пусто — пришлю, как только появится.'
        : ads.length ? `Сейчас по этому поиску ${found.length}+ объявлений, например:\n${ads.map((a) => `• ${esc(a.title)}${a.priceLabel ? ` — ${esc(a.priceLabel)}` : ''}`).join('\n')}`
          : `Сейчас по этому поиску ${found.length}+ объявлений.`;
    } catch (e) {
      preview = `⚠ ${esc(src().title)} не открыл такой поиск (${esc(e.message)}). Попробуйте другой город или рубрику — или сохраните всё равно.`;
    }
    const kb = new InlineKeyboard().text('✅ Сохранить', 'w:save').text('↩️ Заново', 'w:restart').row().url(`Открыть на ${src().title}`, w.url);
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\n${preview}`, kb);
  }

  function label() {
    if (st().w.source !== 'olx') return [src().title, st().w.kcat?.name, st().w.ksub?.name].filter(Boolean).join(' › ');
    return st().w.stack.map((s) => s.name).join(' › ') || 'все рубрики';
  }

  function summary() {
    const price = st().w.priceFrom && st().w.priceTo ? `${fmt(st().w.priceFrom)}–${fmt(st().w.priceTo)} ₸`
      : st().w.priceTo ? `до ${fmt(st().w.priceTo)} ₸` : st().w.priceFrom ? `от ${fmt(st().w.priceFrom)} ₸` : '';
    return [
      `Рубрика: ${esc(label())}`,
      `Город: ${st().w.city ? esc(st().w.city.name) : 'весь Казахстан'}`,
      st().w.words ? `Слова: ${esc(st().w.words)}` : '',
      price ? `Цена: ${price}` : '',
      st().w.seller !== 'all' ? `Продавец: ${SELLER[st().w.seller]}` : '',
    ].filter(Boolean).join('\n');
  }

  function subName() {
    const parts = [st().w.words || (st().w.source !== 'olx' ? `${src().title}: ${st().w.ksub?.name || st().w.kcat?.name}` : current()?.name) || 'Поиск'];
    if (st().w.city) parts.push(st().w.city.name);
    if (st().w.priceTo) parts.push(`до ${fmt(st().w.priceTo)}`);
    else if (st().w.priceFrom) parts.push(`от ${fmt(st().w.priceFrom)}`);
    return parts.join(' · ').slice(0, 60);
  }

  // ---------- вход ----------

  // Шаг 0 — площадка.
  async function stepSource(ctx, edit = true) {
    st().w.step = 'source';
    const kb = new InlineKeyboard();
    sources.ALL.forEach((x, i) => { kb.text(`${x.emoji} ${x.title}`, `w:src:${x.key}`); if (i % 2 === 1) kb.row(); });
    kb.row().text('✖️ Отмена', 'w:cancel');
    await show(ctx, '<b>Новый поиск</b>\nГде искать?', kb, edit);
  }

  // Kolesa и Krisha: рубрика из короткого списка, дальше город и цена.
  async function stepKCategory(ctx) {
    st().w.step = 'kcat';
    const kb = new InlineKeyboard();
    src().wizard.categories.forEach((c, i) => { kb.text(c.name, `w:kc:${i}`); if (i % 2 === 1) kb.row(); });
    kb.row().text('⬅️ Площадка', 'w:restart').text('✖️ Отмена', 'w:cancel');
    await show(ctx, `<b>Новый поиск · ${esc(src().title)}</b>\nРубрика (марку, модель и другие фильтры можно задать на сайте и прислать ссылку):`, kb);
  }

  // Kolesa и Krisha: подрубрика (марка, число комнат) или вся рубрика.
  async function stepKSub(ctx) {
    st().w.step = 'ksub';
    const kcat = st().w.kcat;
    const kb = new InlineKeyboard().text(`✅ Вся «${kcat.name}»`, 'w:ks:all').row();
    kcat.subs.forEach((c, i) => { kb.text(c.name, `w:ks:${i}`); if (i % 3 === 2) kb.row(); });
    kb.row().text('⬅️ Назад', 'w:kback').text('✖️ Отмена', 'w:cancel');
    await show(ctx, `<b>Новый поиск · ${esc(src().title)}</b>\nРубрика: ${esc(kcat.name)}\nПодрубрика:`, kb);
  }

  async function start(ctx) {
    st().w = fresh();
    await stepSource(ctx, false);
  }

  bot.command('new', start);
  bot.callbackQuery('w:new', async (ctx) => { await ctx.answerCallbackQuery(); await start(ctx); });

  bot.callbackQuery(/^w:/, async (ctx) => {
    const data = ctx.callbackQuery.data;
    if (!st().w) { await ctx.answerCallbackQuery('Начните заново: /new'); return; }
    await ctx.answerCallbackQuery();

    if (data === 'w:cancel') { st().w = null; await ctx.editMessageText('Отменено.').catch(() => {}); return; }
    if (data === 'w:restart') { st().w = fresh(); await stepSource(ctx); return; }

    if (data.startsWith('w:src:')) {
      const key = data.slice(6);
      st().w.source = key;
      if (key === 'olx') return stepCategory(ctx);
      if (sources.get(key).wizard) return stepKCategory(ctx);
      st().w = null;
      await ctx.editMessageText(`${sources.get(key).emoji} <b>${esc(sources.get(key).title)}</b>: настройте поиск на сайте (рубрика, город, цена) и пришлите ссылку из адресной строки сюда.`, { parse_mode: 'HTML' }).catch(() => {});
      return;
    }
    if (data.startsWith('w:kc:')) {
      st().w.kcat = src().wizard.categories[Number(data.slice(5))] || null;
      st().w.ksub = null;
      if (!st().w.kcat) return;
      return st().w.kcat.subs?.length ? stepKSub(ctx) : stepCity(ctx);
    }
    if (data.startsWith('w:ks:')) {
      const i = data.slice(5);
      st().w.ksub = i === 'all' ? null : st().w.kcat?.subs?.[Number(i)] || null;
      return stepCity(ctx);
    }
    if (data === 'w:kback') { st().w.kcat = null; st().w.ksub = null; return stepKCategory(ctx); }

    if (data.startsWith('w:c:')) {
      const pick = st().w.options[Number(data.slice(4))];
      if (!pick) return;
      st().w.stack.push(pick);
      const kids = await cats.children(pick.path);
      if (!kids.length) return stepCity(ctx); // конечная рубрика
      st().w.options = kids;
      return stepCategory(ctx);
    }
    if (data === 'w:back') {
      st().w.stack.pop();
      const cur = current();
      st().w.options = cur ? await cats.children(cur.path) : cats.TOP;
      if (cur && !st().w.options.length) { st().w.stack.pop(); st().w.options = current() ? await cats.children(current().path) : cats.TOP; }
      return stepCategory(ctx);
    }
    if (data === 'w:ok') return stepCity(ctx);
    if (data === 'w:any') { st().w.stack = []; return stepCity(ctx); }

    if (data.startsWith('w:city:')) {
      const i = data.slice(7);
      st().w.city = i === '-' ? null : cats.CITIES[Number(i)] || null;
      return st().w.source === 'olx' ? stepWords(ctx) : stepPrice(ctx);
    }
    if (data === 'w:skipwords') return stepPrice(ctx);
    if (data === 'w:skipprice') return stepSeller(ctx);
    if (data.startsWith('w:seller:')) {
      const v = data.slice(9);
      st().w.seller = SELLER[v] ? v : 'all';
      return stepConfirm(ctx);
    }

    if (data === 'w:save') {
      const uid = ctx.from.id;
      const limit = canAdd(uid, st().w.source, st().w.url);
      if (limit !== true) { await ctx.editMessageText(limit, { parse_mode: 'HTML' }).catch(() => {}); st().w = null; return; }
      const sub = db.addSub(uid, subName(), st().w.url, st().w.source, st().w.seller);
      log(`новый поиск #${sub.id}: ${st().w.url}`);
      st().w = null;
      await ctx.editMessageText(`Сохранил поиск «${esc(sub.name)}» (#${sub.id}).\nПервый проход — запомню, что уже есть, дальше присылаю только новые.`, { parse_mode: 'HTML' }).catch(() => {});
      await ctx.reply('Ещё один?', { reply_markup: new InlineKeyboard().text('➕ Новый поиск', 'w:new').text('📋 Мои поиски', 'list') });
    }
  });

  // Текст во время мастера — ответ на его вопрос (слова или цена). Иначе — дальше по цепочке.
  return async function onText(ctx, next) {
    if (!st().w || (st().w.step !== 'words' && st().w.step !== 'price')) return next();
    const text = ctx.message.text.trim();
    if (/https?:\/\//i.test(text) && sources.byUrl(text.match(/https?:\/\/\S+/)[0])) { st().w = null; return next(); } // прислали ссылку — мастер не нужен
    if (st().w.step === 'words') {
      st().w.words = text.slice(0, 60);
      return stepPrice(ctx);
    }
    const p = cats.parsePrice(text);
    if (!p) return ctx.reply('Не понял цену. Например: до 300000, от 100000 до 250000, 300к — или «Любая цена».');
    st().w.priceFrom = p.from;
    st().w.priceTo = p.to;
    return stepSeller(ctx);
  };
}

const SELLER = { all: 'все', private: 'частные', business: 'бизнес' };

function fmt(n) {
  return Number(n).toLocaleString('ru-RU');
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

module.exports = { registerWizard };
