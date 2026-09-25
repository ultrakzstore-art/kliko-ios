// Телеграм-часть: пользователи, доступ (бесплатный и платный), оплата, карточки объявлений.
//
// Бесплатно: проверка раз в 10 минут, без турбо, до FREE_SUBS поисков.
// Платно (7/14/30 дней): раз в POLL_SEC, турбо, до PAID_SUBS поисков.
// Оплата: Telegram Stars (автоматически) или Kaspi (перевод + подтверждение владельцем).

const { Bot, InlineKeyboard, GrammyError } = require('grammy');
const { idFromUrl, newestFirst, BASE, encodeId } = require('./olx');
const { registerWizard } = require('./wizard');
const { DAY } = require('./db');

const PLANS = [7, 14, 30];

function createBot({ token, db, config, getWatcher, log }) {
  const bot = new Bot(token);
  let admin = config.adminId || db.get('owner', null);
  const isAdmin = (ctx) => ctx.from?.id === admin;

  // Все, кто пишет боту, — пользователи. Первый /start без ADMIN_ID становится владельцем.
  bot.use(async (ctx, next) => {
    const from = ctx.from;
    if (!from || from.is_bot) return;
    if (!admin && ctx.message?.text?.startsWith('/start')) {
      admin = from.id;
      db.set('owner', admin);
      log(`владелец бота: ${admin}`);
    }
    db.touchUser(from.id, [from.first_name, from.last_name].filter(Boolean).join(' '), from.username || '');
    return next();
  });

  // ---------- доступ ----------

  function planText(userId) {
    const u = db.user(userId);
    if (db.isPaid(u)) {
      return `💎 <b>Платный доступ</b> до ${fmtDate(u.paid_until)}\n` +
        `Проверка раз в ${config.pollSec} сек, ⚡ турбо — раньше поиска, до ${config.paidSubs} поисков.`;
    }
    return `🆓 <b>Бесплатный доступ</b>\nПроверка раз в ${Math.round(config.freePollSec / 60)} мин, без турбо, до ${config.freeSubs} поисков.\n` +
      `Платно: раз в ${config.pollSec} сек + ⚡ турбо (ловит объявления раньше, чем они появятся в поиске), до ${config.paidSubs} поисков.`;
  }

  function limitFor(userId) {
    return db.isPaid(userId) ? config.paidSubs : config.freeSubs;
  }

  // true — можно добавить поиск; иначе — текст, почему нельзя.
  function canAdd(userId) {
    const n = db.subs(userId).length;
    const limit = limitFor(userId);
    if (n < limit) return true;
    return db.isPaid(userId)
      ? `Достигнут предел: ${limit} поисков. Удалите ненужный в /list.`
      : `На бесплатном доступе — до ${limit} поисков. Удалите ненужный в /list или подключите платный: /access`;
  }

  const menu = () => new InlineKeyboard()
    .text('➕ Новый поиск', 'w:new').text('📋 Мои поиски', 'list').row()
    .text('💎 Доступ', 'access');

  function accessKeyboard() {
    const kb = new InlineKeyboard();
    if (config.starsPrices) {
      PLANS.forEach((d, i) => kb.text(`⭐ ${d} дн — ${config.starsPrices[i]} Stars`, `stars:${d}`).row());
    }
    if (config.kaspiPrices && config.kaspiDetails) {
      PLANS.forEach((d, i) => kb.text(`💳 Kaspi ${d} дн — ${fmt(config.kaspiPrices[i])} ₸`, `kaspi:${d}`).row());
    }
    return kb;
  }

  async function showAccess(ctx) {
    const hasPay = config.starsPrices || (config.kaspiPrices && config.kaspiDetails);
    await ctx.reply(`${planText(ctx.from.id)}\n\n${hasPay ? 'Продлить или подключить:' : 'Оплата пока не настроена — напишите владельцу бота.'}`,
      { parse_mode: 'HTML', reply_markup: accessKeyboard() });
  }

  const HELP = `Присылаю новые объявления OLX.kz по вашим поискам — через секунды после подачи.

➕ /new — новый поиск кнопками: рубрика → подрубрика → город → слова → цена.
Или пришлите ссылку на поиск с olx.kz.

/list — мои поиски · /access — доступ и оплата · /help — справка`;

  bot.command(['start', 'help'], async (ctx) => {
    await ctx.reply(`${HELP}\n\n${planText(ctx.from.id)}`, { parse_mode: 'HTML', reply_markup: menu(), link_preview_options: { is_disabled: true } });
  });

  bot.command('access', showAccess);
  bot.callbackQuery('access', async (ctx) => { await ctx.answerCallbackQuery(); await showAccess(ctx); });
  bot.command('list', (ctx) => sendList(ctx));
  bot.callbackQuery('list', async (ctx) => { await ctx.answerCallbackQuery(); await sendList(ctx); });

  // ---------- оплата: Telegram Stars ----------

  bot.callbackQuery(/^stars:(\d+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const days = Number(ctx.match[1]);
    const i = PLANS.indexOf(days);
    if (i < 0 || !config.starsPrices) return;
    await ctx.replyWithInvoice(
      `Доступ на ${days} дней`,
      `Проверка раз в ${config.pollSec} сек, ⚡ турбо, до ${config.paidSubs} поисков.`,
      `stars:${days}:${ctx.from.id}`,
      'XTR',
      [{ label: `${days} дней`, amount: config.starsPrices[i] }],
    );
  });

  bot.on('pre_checkout_query', async (ctx) => {
    const ok = /^stars:(7|14|30):\d+$/.test(ctx.preCheckoutQuery.invoice_payload);
    await ctx.answerPreCheckoutQuery(ok, ok ? undefined : { error_message: 'Счёт устарел — откройте /access заново.' });
  });

  bot.on('message:successful_payment', async (ctx) => {
    const pay = ctx.message.successful_payment;
    const days = Number(pay.invoice_payload.split(':')[1]);
    const until = db.extend(ctx.from.id, days);
    db.addPayment({ userId: ctx.from.id, method: 'stars', days, amount: pay.total_amount, status: 'paid', chargeId: pay.telegram_payment_charge_id });
    log(`оплата Stars: ${ctx.from.id} +${days} дн`);
    await ctx.reply(`Спасибо! 💎 Платный доступ до ${fmtDate(until)}. Турбо включено для всех ваших поисков.`);
    await tellAdmin(`⭐ Оплата Stars: ${who(ctx.from)} — ${days} дн, ${pay.total_amount} Stars.`);
  });

  // ---------- оплата: Kaspi (перевод + подтверждение) ----------

  bot.callbackQuery(/^kaspi:(\d+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const days = Number(ctx.match[1]);
    const i = PLANS.indexOf(days);
    if (i < 0 || !config.kaspiPrices) return;
    await ctx.reply(
      `💳 <b>Kaspi — ${days} дней, ${fmt(config.kaspiPrices[i])} ₸</b>\n\n${esc(config.kaspiDetails)}\n\n` +
      `В комментарии к переводу укажите: <code>${ctx.from.id}</code>\nПосле перевода нажмите «Я оплатил» — доступ включится после проверки.`,
      { parse_mode: 'HTML', reply_markup: new InlineKeyboard().text('✅ Я оплатил', `kpaid:${days}`) },
    );
  });

  bot.callbackQuery(/^kpaid:(\d+)$/, async (ctx) => {
    const days = Number(ctx.match[1]);
    const i = PLANS.indexOf(days);
    if (i < 0 || !config.kaspiPrices) return ctx.answerCallbackQuery();
    const p = db.addPayment({ userId: ctx.from.id, method: 'kaspi', days, amount: config.kaspiPrices[i], status: 'pending' });
    await ctx.answerCallbackQuery('Заявка отправлена');
    await ctx.editMessageReplyMarkup().catch(() => {});
    await ctx.reply('Заявка принята. Как только владелец увидит перевод, доступ включится — пришлю сообщение.');
    await tellAdmin(`💳 Kaspi: ${who(ctx.from)} — ${days} дн, ${fmt(p.amount)} ₸. Комментарий к переводу: ${ctx.from.id}`,
      new InlineKeyboard().text(`✅ Дать ${days} дн`, `approve:${p.id}`).text('✖️ Нет перевода', `reject:${p.id}`));
  });

  bot.callbackQuery(/^(approve|reject):(\d+)$/, async (ctx) => {
    if (!isAdmin(ctx)) return ctx.answerCallbackQuery('Только для владельца');
    const [, action, idStr] = ctx.match;
    const p = db.payment(Number(idStr));
    if (!p || p.status !== 'pending') return ctx.answerCallbackQuery('Заявка уже обработана');
    const text = ctx.callbackQuery.message?.text || '';
    if (action === 'approve') {
      db.setPaymentStatus(p.id, 'paid');
      const until = db.extend(p.user_id, p.days);
      await send(p.user_id, `Оплата получена ✅ 💎 Платный доступ до ${fmtDate(until)}.`);
      await ctx.answerCallbackQuery('Доступ выдан');
      await ctx.editMessageText(`${text}\n\n✅ Выдано до ${fmtDate(until)}`).catch(() => {});
    } else {
      db.setPaymentStatus(p.id, 'rejected');
      await send(p.user_id, 'Перевод не найден. Если вы оплатили — напишите владельцу бота, указав время и сумму.');
      await ctx.answerCallbackQuery('Отклонено');
      await ctx.editMessageText(`${text}\n\n✖️ Отклонено`).catch(() => {});
    }
  });

  // ---------- команды владельца ----------

  bot.command('grant', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const [uid, days] = String(ctx.match || '').trim().split(/\s+/);
    const userId = Number(uid);
    const d = Number(days);
    if (!userId || !d || !db.user(userId)) return ctx.reply('Формат: /grant <ID пользователя> <дней>. ID — в /users.');
    const until = db.extend(userId, d);
    db.addPayment({ userId, method: 'admin', days: d, status: 'paid' });
    await send(userId, `🎁 Вам открыт платный доступ до ${fmtDate(until)}.`);
    await ctx.reply(`Выдано: ${userId} до ${fmtDate(until)}.`);
  });

  bot.command('users', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const users = db.users();
    const paid = users.filter((u) => db.isPaid(u));
    const lines = users.slice(0, 30).map((u) =>
      `${db.isPaid(u) ? '💎' : '🆓'} <code>${u.id}</code> ${esc(u.name || '')}${u.username ? ` @${esc(u.username)}` : ''}` +
      `${db.isPaid(u) ? ` — до ${fmtDate(u.paid_until)}` : ''} · поисков ${db.subs(u.id).length}${u.blocked ? ' · остановил бота' : ''}`);
    await ctx.reply(`Пользователей: ${users.length}, платных: ${paid.length}\n\n${lines.join('\n')}`, { parse_mode: 'HTML' });
  });

  bot.command('stats', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const w = getWatcher();
    const money = db.paidTotals().map((r) => `${r.method}: ${r.n} шт${r.sum ? `, ${fmt(r.sum)}` : ''}`).join(' · ') || 'оплат пока нет';
    await ctx.reply([
      `Поиск: ${w.stats.searchOk} удачных, ${w.stats.searchErr} ошибок · турбо: проверено ${w.stats.turboProbes}, найдено ${w.stats.turboFound}`,
      `Отправлено объявлений: ${w.stats.sent} · последний номер ${w.frontier || '—'}`,
      w.blocked() ? `⏸ OLX ограничил запросы — ещё ${Math.ceil((w.backoffUntil - Date.now()) / 60_000)} мин` : '',
      `Оплаты: ${money}`,
    ].filter(Boolean).join('\n'));
  });

  bot.command('turbo', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const on = !db.get('turbo', true);
    db.set('turbo', on);
    await ctx.reply(on ? '⚡ Турбо включено для платных.' : 'Турбо выключено для всех.');
  });

  // ---------- поиски ----------

  const wizardText = registerWizard(bot, { db, log, canAdd });
  bot.on('message:text', wizardText);

  // Сообщение со ссылкой на поиск OLX — новая подписка.
  bot.on('message:text', async (ctx) => {
    const text = ctx.message.text.trim();
    const m = /https?:\/\/(?:www\.|m\.)?olx\.kz\/\S+/i.exec(text);
    if (!m) return ctx.reply('Нажмите «Новый поиск» — выберем рубрику кнопками. Или пришлите ссылку на поиск с olx.kz.', { reply_markup: menu() });
    const url = m[0];
    if (idFromUrl(url)) return ctx.reply('Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком объявлений.');
    try { newestFirst(url); } catch (e) { return ctx.reply(e.message); }
    const limit = canAdd(ctx.from.id);
    if (limit !== true) return ctx.reply(limit);
    const before = text.slice(0, m.index).trim();
    const sub = db.addSub(ctx.from.id, (before || nameFromUrl(url)).slice(0, 60), url);
    await ctx.reply(`Добавил поиск «${sub.name}». Первый проход — запомню, что уже есть, дальше присылаю только новые.`);
  });

  bot.callbackQuery(/^(pause|resume|del):(\d+)$/, async (ctx) => {
    const [, action, idStr] = ctx.match;
    const sub = db.sub(Number(idStr));
    if (!sub || sub.user_id !== ctx.from.id) return ctx.answerCallbackQuery('Не найдено');
    if (action === 'del') db.deleteSub(sub.id);
    else db.updateSub(sub.id, { paused: action === 'pause' ? 1 : 0 });
    await ctx.answerCallbackQuery(action === 'del' ? 'Удалено' : action === 'pause' ? 'На паузе' : 'Снова слежу');
    await sendList(ctx, true);
  });

  async function sendList(ctx, edit = false) {
    const subs = db.subs(ctx.from.id);
    const head = `${planText(ctx.from.id)}\n\nПоиски (${subs.length}/${limitFor(ctx.from.id)}):`;
    const body = subs.length
      ? subs.map((s, i) => `${i + 1}. ${s.paused ? '⏸' : '▶️'} ${esc(s.name)} — прислано ${s.sent}${s.last_error ? ` ⚠ ${esc(s.last_error)}` : ''}`).join('\n')
      : 'пока нет.';
    const kb = new InlineKeyboard().text('➕ Новый поиск', 'w:new').text('💎 Доступ', 'access').row();
    subs.forEach((s, i) => {
      kb.text(`${s.paused ? '▶️' : '⏸'} ${i + 1}`, `${s.paused ? 'resume' : 'pause'}:${s.id}`).text(`🗑 ${i + 1}`, `del:${s.id}`).row();
    });
    const opts = { parse_mode: 'HTML', reply_markup: kb, link_preview_options: { is_disabled: true } };
    if (edit) await ctx.editMessageText(`${head}\n${body}`, opts).catch(() => {});
    else await ctx.reply(`${head}\n${body}`, opts);
  }

  bot.catch((err) => log(`телеграм: ${err.message}`));

  // ---------- отправка ----------

  async function send(userId, text, extra = {}) {
    try {
      return await bot.api.sendMessage(userId, text, extra);
    } catch (e) {
      if (e instanceof GrammyError && e.error_code === 403) db.setBlocked(userId, true);
      else log(`не отправил ${userId}: ${e.message}`);
      return null;
    }
  }

  async function tellAdmin(text, kb) {
    if (admin) await send(admin, text, kb ? { reply_markup: kb } : {});
  }

  async function notify(userId, ad, subs, via, count) {
    if (via === 'ready') {
      return send(userId, `«${subs[0].name}»: слежу. Сейчас в выдаче ${count} объявлений — присылать буду только новые.`);
    }
    const caption = card(ad, subs, via);
    const kb = new InlineKeyboard().url('Открыть объявление', adLink(ad));
    if (ad.userId) kb.row().url('Все объявления автора', config.sellerUrl.replace('{id}', encodeURIComponent(ad.userId)));
    try {
      if (!ad.photo) throw new Error('без фото');
      await bot.api.sendPhoto(userId, ad.photo, { caption, parse_mode: 'HTML', reply_markup: kb });
    } catch (e) {
      if (e instanceof GrammyError && e.error_code === 403) { db.setBlocked(userId, true); return; }
      if (e instanceof GrammyError && e.error_code === 429) await sleep((e.parameters?.retry_after || 3) * 1000);
      await send(userId, caption, { parse_mode: 'HTML', reply_markup: kb, link_preview_options: { is_disabled: true } });
    }
  }

  // Напоминания: за сутки до конца платного доступа и когда он закончился — по одному разу.
  async function remindExpiring() {
    const now = Date.now();
    for (const u of db.users()) {
      if (u.blocked || !u.paid_until) continue;
      const left = u.paid_until - now;
      const key = `remind:${u.id}:${u.paid_until}`;
      if (left > 0 && left < DAY && !db.get(`${key}:soon`)) {
        db.set(`${key}:soon`, 1);
        await send(u.id, `⏳ Платный доступ заканчивается ${fmtDate(u.paid_until)}. Продлить: /access`);
      } else if (left <= 0 && left > -7 * DAY && !db.get(`${key}:over`)) {
        db.set(`${key}:over`, 1);
        await send(u.id, `Платный доступ закончился — теперь проверка раз в ${Math.round(config.freePollSec / 60)} мин и без турбо. Продлить: /access`);
      }
    }
  }
  const reminder = setInterval(() => remindExpiring().catch((e) => log(`напоминания: ${e.message}`)), 3600_000);
  reminder.unref?.();

  return { bot, notify, alert: tellAdmin, remindExpiring };
}

// Карточка: заголовок, цена, город, свежесть, телефон из текста, пометки, параметры, описание.
function card(ad, subs, via) {
  const flags = [];
  if (via === 'turbo') flags.push('⚡ раньше поиска');
  if (ad.status && ad.status !== 'active') flags.push(`статус: ${esc(ad.status)} (возможно, на проверке)`);
  if (ad.business) flags.push('🏪 бизнес-аккаунт');
  // Номер, который продавец написал в тексте, — Телеграм сам делает его нажимаемым (звонок).
  // Номер, который OLX прячет за входом, не достаём.
  const phone = phonesIn(`${ad.title || ''}\n${ad.description || ''}`)[0];
  const lines = [
    `<b>${esc(ad.title || 'Объявление ' + ad.id)}</b>`,
    [ad.priceLabel || (ad.price != null ? `${fmt(ad.price)} ₸` : ''), [ad.city, ad.region].filter(Boolean).join(', ')].filter(Boolean).map(esc).join(' · '),
    ad.createdAt ? `🕒 подано ${ago(ad.createdAt)} назад` : '',
    phone ? `📞 ${prettyPhone(phone)}` : '',
    flags.join(' · '),
    (ad.params || []).length ? esc(ad.params.join(' · ')) : '',
    ad.description ? `\n${esc(ad.description.slice(0, 350))}${ad.description.length > 350 ? '…' : ''}` : '',
    ad.userName ? `👤 ${esc(ad.userName)}` : '',
    `🔎 ${subs.map((s) => esc(s.name)).join(', ')}`,
  ];
  return lines.filter(Boolean).join('\n').slice(0, 1024);
}

// Ссылка с номером в конце — сайт часть после # игнорирует, а номер под рукой.
function adLink(ad) {
  const base = ad.url && /^https?:/.test(ad.url) ? ad.url.split('#')[0] : `${BASE}/d/obyavlenie/-ID${encodeId(ad.id)}.html`;
  return `${base}#${ad.id}`;
}

// Казахстанские мобильные в тексте объявления: +7 777 123 45 67, 8(701)1234567 и т.п.
function phonesIn(text) {
  const out = [];
  const re = /(?<!\d)(?:\+?7|8)[\s\-()]*(7\d{2})[\s\-()]*(\d{3})[\s-]*(\d{2})[\s-]*(\d{2})(?!\d)/g;
  for (const m of String(text).matchAll(re)) {
    const n = `+7${m[1]}${m[2]}${m[3]}${m[4]}`;
    if (!out.includes(n)) out.push(n);
  }
  return out;
}

function prettyPhone(n) {
  const d = n.slice(2);
  return `+7 ${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6, 8)} ${d.slice(8, 10)}`;
}

function nameFromUrl(url) {
  const u = new URL(url);
  const parts = decodeURIComponent(u.pathname).split('/').filter((p) => p && p !== 'd' && p !== 'kk' && p !== 'list');
  const q = parts.find((p) => p.startsWith('q-'));
  return (q ? q.slice(2).replace(/-/g, ' ') : parts.slice(-2).join(' / ')) || 'Поиск';
}

function who(from) {
  const name = [from.first_name, from.last_name].filter(Boolean).join(' ');
  return `${name}${from.username ? ` @${from.username}` : ''} (${from.id})`;
}

function fmtDate(ts) {
  return new Date(ts).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Almaty' });
}

function ago(ts) {
  const s = Math.max(0, Math.round((Date.now() - ts) / 1000));
  if (s < 60) return `${s} сек`;
  if (s < 3600) return `${Math.round(s / 60)} мин`;
  return `${Math.round(s / 3600)} ч`;
}

function fmt(n) {
  return Number(n).toLocaleString('ru-RU');
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

module.exports = { createBot, card, adLink, nameFromUrl, phonesIn, PLANS };
