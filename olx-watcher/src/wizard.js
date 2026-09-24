// Новый поиск кнопками: рубрика → подрубрика → город → слова → цена → проверка → сохранить.
// Ссылку с сайта копировать не нужно (но и она по-прежнему принимается).

const { InlineKeyboard } = require('grammy');
const cats = require('./categories');
const olx = require('./olx');

function registerWizard(bot, { db, log }) {
  let w = null; // один владелец — одно состояние

  const fresh = () => ({ step: 'cat', stack: [], options: cats.TOP, city: null, words: '', priceFrom: null, priceTo: null, url: '' });
  const current = () => w.stack[w.stack.length - 1] || null;

  async function show(ctx, text, kb, edit = true) {
    const opts = { reply_markup: kb, parse_mode: 'HTML', link_preview_options: { is_disabled: true } };
    if (edit && ctx.callbackQuery) {
      try { await ctx.editMessageText(text, opts); return; } catch { /* сообщение не изменилось или старое — шлём новое */ }
    }
    await ctx.reply(text, opts);
  }

  async function stepCategory(ctx, edit = true) {
    w.step = 'cat';
    const cur = current();
    const kb = new InlineKeyboard();
    if (cur) kb.text(`✅ Вся «${cur.name}»`, 'w:ok').row();
    w.options.forEach((o, i) => { kb.text(o.name, `w:c:${i}`); if (i % 2 === 1) kb.row(); });
    kb.row();
    if (cur) kb.text('⬅️ Назад', 'w:back');
    kb.text('Без рубрики — только по словам', 'w:any').row().text('✖️ Отмена', 'w:cancel');
    const path = w.stack.map((s) => s.name).join(' › ');
    await show(ctx, `<b>Новый поиск</b>\n${path ? `Рубрика: ${esc(path)}\n` : ''}Выберите ${cur ? 'подрубрику или всю рубрику' : 'рубрику'}:`, kb, edit);
  }

  async function stepCity(ctx) {
    w.step = 'city';
    const kb = new InlineKeyboard().text('🇰🇿 Весь Казахстан', 'w:city:-').row();
    cats.CITIES.forEach((c, i) => { kb.text(c.name, `w:city:${i}`); if (i % 3 === 2) kb.row(); });
    await show(ctx, `<b>Новый поиск</b>\nРубрика: ${esc(label())}\nГород:`, kb);
  }

  async function stepWords(ctx) {
    w.step = 'words';
    const kb = new InlineKeyboard();
    if (current()) kb.text('Пропустить', 'w:skipwords');
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\nКлючевые слова? Напишите, например: <i>iphone 13</i>, <i>hp 250</i>, <i>зимние шины r16</i>.${current() ? '\nИли «Пропустить» — все объявления рубрики.' : ''}`, kb);
  }

  async function stepPrice(ctx) {
    w.step = 'price';
    const kb = new InlineKeyboard().text('Любая цена', 'w:skipprice');
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\nЦена? Напишите: <i>до 300000</i>, <i>от 100000 до 250000</i>, <i>300к</i>.`, kb);
  }

  // Пробный запрос к OLX: показываем, что реально найдётся по этой ссылке, до сохранения.
  async function stepConfirm(ctx) {
    w.step = 'confirm';
    w.url = cats.buildSearchUrl({ path: current()?.path, city: w.city?.slug, words: w.words, priceFrom: w.priceFrom, priceTo: w.priceTo });
    let preview;
    try {
      const r = await olx.fetchSearch(w.url);
      const ads = r.ads.filter((a) => !a.promoted).slice(0, 3);
      preview = r.ads.length
        ? `Сейчас по этому поиску ${r.ads.length}+ объявлений, например:\n${ads.map((a) => `• ${esc(a.title || '№' + a.id)}${a.priceLabel ? ` — ${esc(a.priceLabel)}` : ''}`).join('\n')}`
        : 'Сейчас по этому поиску пусто — пришлю, как только появится.';
    } catch (e) {
      preview = `⚠ OLX не открыл такой поиск (${esc(e.message)}). Попробуйте другой город или рубрику — или сохраните всё равно.`;
    }
    const kb = new InlineKeyboard().text('✅ Сохранить', 'w:save').text('↩️ Заново', 'w:restart').row().url('Открыть на OLX', w.url);
    await show(ctx, `<b>Новый поиск</b>\n${summary()}\n\n${preview}`, kb);
  }

  function label() {
    return w.stack.map((s) => s.name).join(' › ') || 'все рубрики';
  }

  function summary() {
    const price = w.priceFrom && w.priceTo ? `${fmt(w.priceFrom)}–${fmt(w.priceTo)} ₸`
      : w.priceTo ? `до ${fmt(w.priceTo)} ₸` : w.priceFrom ? `от ${fmt(w.priceFrom)} ₸` : '';
    return [
      `Рубрика: ${esc(label())}`,
      `Город: ${w.city ? esc(w.city.name) : 'весь Казахстан'}`,
      w.words ? `Слова: ${esc(w.words)}` : '',
      price ? `Цена: ${price}` : '',
    ].filter(Boolean).join('\n');
  }

  function subName() {
    const parts = [w.words || current()?.name || 'Поиск'];
    if (w.city) parts.push(w.city.name);
    if (w.priceTo) parts.push(`до ${fmt(w.priceTo)}`);
    else if (w.priceFrom) parts.push(`от ${fmt(w.priceFrom)}`);
    return parts.join(' · ').slice(0, 60);
  }

  // ---------- вход ----------

  async function start(ctx) {
    w = fresh();
    await stepCategory(ctx, false);
  }

  bot.command('new', start);
  bot.callbackQuery('w:new', async (ctx) => { await ctx.answerCallbackQuery(); await start(ctx); });

  bot.callbackQuery(/^w:/, async (ctx) => {
    const data = ctx.callbackQuery.data;
    if (!w) { await ctx.answerCallbackQuery('Начните заново: /new'); return; }
    await ctx.answerCallbackQuery();

    if (data === 'w:cancel') { w = null; await ctx.editMessageText('Отменено.').catch(() => {}); return; }
    if (data === 'w:restart') { w = fresh(); await stepCategory(ctx); return; }

    if (data.startsWith('w:c:')) {
      const pick = w.options[Number(data.slice(4))];
      if (!pick) return;
      w.stack.push(pick);
      const kids = await cats.children(pick.path);
      if (!kids.length) return stepCity(ctx); // конечная рубрика
      w.options = kids;
      return stepCategory(ctx);
    }
    if (data === 'w:back') {
      w.stack.pop();
      const cur = current();
      w.options = cur ? await cats.children(cur.path) : cats.TOP;
      if (cur && !w.options.length) { w.stack.pop(); w.options = current() ? await cats.children(current().path) : cats.TOP; }
      return stepCategory(ctx);
    }
    if (data === 'w:ok') return stepCity(ctx);
    if (data === 'w:any') { w.stack = []; return stepCity(ctx); }

    if (data.startsWith('w:city:')) {
      const i = data.slice(7);
      w.city = i === '-' ? null : cats.CITIES[Number(i)] || null;
      return stepWords(ctx);
    }
    if (data === 'w:skipwords') return stepPrice(ctx);
    if (data === 'w:skipprice') return stepConfirm(ctx);

    if (data === 'w:save') {
      const sub = db.addSub(subName(), w.url);
      log(`новый поиск #${sub.id}: ${w.url}`);
      w = null;
      await ctx.editMessageText(`Сохранил поиск «${esc(sub.name)}» (#${sub.id}).\nПервый проход — запомню, что уже есть, дальше присылаю только новые.`, { parse_mode: 'HTML' }).catch(() => {});
      await ctx.reply('Ещё один?', { reply_markup: new InlineKeyboard().text('➕ Новый поиск', 'w:new').text('📋 Мои поиски', 'list') });
    }
  });

  // Текст во время мастера — ответ на его вопрос (слова или цена). Иначе — дальше по цепочке.
  return async function onText(ctx, next) {
    if (!w || (w.step !== 'words' && w.step !== 'price')) return next();
    const text = ctx.message.text.trim();
    if (/olx\.kz\//i.test(text)) { w = null; return next(); } // прислали ссылку — мастер не нужен
    if (w.step === 'words') {
      w.words = text.slice(0, 60);
      return stepPrice(ctx);
    }
    const p = cats.parsePrice(text);
    if (!p) return ctx.reply('Не понял цену. Например: до 300000, от 100000 до 250000, 300к — или «Любая цена».');
    w.priceFrom = p.from;
    w.priceTo = p.to;
    return stepConfirm(ctx);
  };
}

function fmt(n) {
  return Number(n).toLocaleString('ru-RU');
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

module.exports = { registerWizard };
