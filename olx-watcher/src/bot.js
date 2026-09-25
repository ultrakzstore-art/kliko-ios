// Телеграм-часть: пользователи, доступ (бесплатный и платный), оплата, карточки объявлений.
//
// Тестовый доступ новичку (TRIAL_DAYS): проверка раз в 10 минут, без турбо, до FREE_SUBS поисков.
// Платно (7/14/30 дней): раз в POLL_SEC, турбо, до PAID_SUBS поисков. Без доступа — не проверяем.
// Оплата: Telegram Stars (автоматически) или Kaspi (перевод + подтверждение владельцем).

const { Bot, InlineKeyboard, GrammyError, InputFile } = require('grammy');
const { collage, fetchImage } = require('./watermark');
const olx = require('./olx');
const sources = require('./sources');
const { registerWizard } = require('./wizard');
const { DAY } = require('./db');

const PLANS = [7, 14, 30];

// Тарифы: отдельная площадка или «всё сразу». Комбо открывает все площадки на срок.
const PRODUCTS = [
  ...sources.ALL.map((x) => ({ key: x.key, title: `${x.emoji} ${x.title}`, sources: [x.key] })),
  { key: 'all', title: '🔥 Всё сразу', sources: sources.ALL.map((x) => x.key) },
];
const PRODUCT = Object.fromEntries(PRODUCTS.map((p) => [p.key, p]));

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
    // Владельцу — доступ без срока: его собственные поиски не должны останавливаться.
    if (from.id === admin && !db.isPaid(from.id, 'any')) db.extend(from.id, 3650, sources.ALL.map((x) => x.key));
    return next();
  });

  // ---------- доступ ----------

  function planText(userId) {
    const u = db.user(userId);
    const paidLine = `Платно: ⚡ мгновенные уведомления, до ${config.paidSubs} поисков.`;
    const paid = db.accessList(userId);
    if (paid.length) {
      const lines = paid.map((a) => `${sources.get(a.source).emoji} ${esc(sources.get(a.source).title)} — до ${fmtDate(a.until)}`);
      return `💎 <b>Платный доступ</b>\n${lines.join('\n')}\nПроверка раз в ${config.pollSec} сек, до ${config.paidSubs} поисков.`;
    }
    if (db.isTrial(u)) {
      return `🧪 <b>Тестовый доступ</b> до ${fmtDate(u.trial_until)} — все площадки\nПроверка раз в ${Math.round(config.freePollSec / 60)} мин, до ${config.freeSubs} поисков.\n${paidLine}`;
    }
    return `⛔ <b>Тестовый доступ закончился</b> — поиски на паузе, объявления не приходят.\n${paidLine}\nПодключить: /access`;
  }

  function limitFor(userId) {
    return db.isPaid(userId, 'any') ? config.paidSubs : config.freeSubs;
  }

  // true — можно добавить поиск на площадке; иначе — текст, почему нельзя.
  function canAdd(userId, source = 'olx') {
    if (!db.hasAccess(userId, source)) {
      return db.isTrial(userId) || db.isPaid(userId, 'any')
        ? `Нет доступа к ${sources.get(source).title}. Подключить: /access`
        : 'Тестовый доступ закончился. Подключите платный, чтобы добавлять поиски: /access';
    }
    const n = db.subs(userId).length;
    const limit = limitFor(userId);
    if (n < limit) return true;
    return db.isPaid(userId, 'any')
      ? `Достигнут предел: ${limit} поисков. Удалите ненужный в /list.`
      : `На тестовом доступе — до ${limit} поисков. Удалите ненужный в /list или подключите платный: /access`;
  }

  const menu = () => new InlineKeyboard()
    .text('➕ Новый поиск', 'w:new').text('📋 Мои поиски', 'list').row()
    .text('💎 Доступ', 'access');

  const priceOf = (product, method, days) => config.prices[product]?.[method]?.[PLANS.indexOf(days)] ?? null;
  const sellable = () => PRODUCTS.filter((p) => config.prices[p.key]?.stars || (config.prices[p.key]?.kaspi && config.kaspiDetails));

  async function showAccess(ctx) {
    const list = sellable();
    const kb = new InlineKeyboard();
    list.forEach((p, i) => { kb.text(p.title, `buy:${p.key}`); if (i % 2 === 1) kb.row(); });
    await ctx.reply(`${planText(ctx.from.id)}\n\n${list.length ? 'Выберите тариф:' : 'Оплата пока не настроена — напишите владельцу бота.'}`,
      { parse_mode: 'HTML', reply_markup: kb });
  }

  bot.callbackQuery(/^buy:(\w+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const p = PRODUCT[ctx.match[1]];
    if (!p) return;
    const kb = new InlineKeyboard();
    for (const d of PLANS) {
      const stars = priceOf(p.key, 'stars', d);
      const kaspi = config.kaspiDetails ? priceOf(p.key, 'kaspi', d) : null;
      if (stars) kb.text(`⭐ ${d} дн — ${stars}`, `stars:${p.key}:${d}`);
      if (kaspi) kb.text(`💳 ${d} дн — ${fmt(kaspi)} ₸`, `kaspi:${p.key}:${d}`);
      kb.row();
    }
    const what = p.key === 'all' ? 'все площадки: ' + sources.ALL.map((x) => x.title).join(', ') : sources.get(p.key).title;
    await ctx.reply(`<b>${esc(p.title)}</b> — ${esc(what)}.\n⚡ Мгновенные уведомления, до ${config.paidSubs} поисков.\n⭐ — Telegram Stars, 💳 — Kaspi.`,
      { parse_mode: 'HTML', reply_markup: kb });
  });

  const HELP = `Присылаю новые объявления по вашим поискам — сразу после подачи.

Площадки: OLX, Kolesa, Krisha, Kaspi Объявления.
➕ /new — новый поиск кнопками: площадка → рубрика → город → цена.
Или пришлите ссылку на поиск с сайта.

/list — мои поиски · /access — доступ и оплата · /help — справка`;

  bot.command(['start', 'help'], async (ctx) => {
    await ctx.reply(`${HELP}\n\n${planText(ctx.from.id)}`, { parse_mode: 'HTML', reply_markup: menu(), link_preview_options: { is_disabled: true } });
  });

  bot.command('access', showAccess);
  bot.callbackQuery('access', async (ctx) => { await ctx.answerCallbackQuery(); await showAccess(ctx); });
  bot.command('list', (ctx) => sendList(ctx));
  bot.callbackQuery('list', async (ctx) => { await ctx.answerCallbackQuery(); await sendList(ctx); });

  // ---------- оплата: Telegram Stars ----------

  bot.callbackQuery(/^stars:(\w+):(\d+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const p = PRODUCT[ctx.match[1]];
    const days = Number(ctx.match[2]);
    const amount = p && priceOf(p.key, 'stars', days);
    if (!amount) return;
    await ctx.replyWithInvoice(
      `${p.title.replace(/^\S+\s/, '')} на ${days} дней`,
      `⚡ Мгновенные уведомления, до ${config.paidSubs} поисков.`,
      `stars:${p.key}:${days}:${ctx.from.id}`,
      'XTR',
      [{ label: `${days} дней`, amount }],
    );
  });

  const PAYLOAD_RE = /^stars:(olx|kolesa|krisha|kaspi|all):(7|14|30):\d+$/;

  bot.on('pre_checkout_query', async (ctx) => {
    const ok = PAYLOAD_RE.test(ctx.preCheckoutQuery.invoice_payload);
    await ctx.answerPreCheckoutQuery(ok, ok ? undefined : { error_message: 'Счёт устарел — откройте /access заново.' });
  });

  bot.on('message:successful_payment', async (ctx) => {
    const pay = ctx.message.successful_payment;
    const m = PAYLOAD_RE.exec(pay.invoice_payload);
    if (!m) return;
    const p = PRODUCT[m[1]];
    const days = Number(m[2]);
    const until = db.extend(ctx.from.id, days, p.sources);
    db.addPayment({ userId: ctx.from.id, method: 'stars', product: p.key, days, amount: pay.total_amount, status: 'paid', chargeId: pay.telegram_payment_charge_id });
    log(`оплата Stars: ${ctx.from.id} ${p.key} +${days} дн`);
    await ctx.reply(`Спасибо! 💎 ${p.title} — до ${fmtDate(until)}.`);
    await tellAdmin(`⭐ Оплата Stars: ${who(ctx.from)} — ${p.title}, ${days} дн, ${pay.total_amount} Stars.`);
  });

  // ---------- оплата: Kaspi (перевод + подтверждение) ----------

  bot.callbackQuery(/^kaspi:(\w+):(\d+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const p = PRODUCT[ctx.match[1]];
    const days = Number(ctx.match[2]);
    const amount = p && priceOf(p.key, 'kaspi', days);
    if (!amount || !config.kaspiDetails) return;
    await ctx.reply(
      `💳 <b>Kaspi — ${esc(p.title)}, ${days} дней, ${fmt(amount)} ₸</b>\n\n${esc(config.kaspiDetails)}\n\n` +
      `В комментарии к переводу укажите: <code>${ctx.from.id}</code>\nПосле перевода нажмите «Я оплатил» — доступ включится после проверки.`,
      { parse_mode: 'HTML', reply_markup: new InlineKeyboard().text('✅ Я оплатил', `kpaid:${p.key}:${days}`) },
    );
  });

  bot.callbackQuery(/^kpaid:(\w+):(\d+)$/, async (ctx) => {
    const p = PRODUCT[ctx.match[1]];
    const days = Number(ctx.match[2]);
    const amount = p && priceOf(p.key, 'kaspi', days);
    if (!amount) return ctx.answerCallbackQuery();
    const pay = db.addPayment({ userId: ctx.from.id, method: 'kaspi', product: p.key, days, amount, status: 'pending' });
    await ctx.answerCallbackQuery('Заявка отправлена');
    await ctx.editMessageReplyMarkup().catch(() => {});
    await ctx.reply('Заявка принята. Как только владелец увидит перевод, доступ включится — пришлю сообщение.');
    await tellAdmin(`💳 Kaspi: ${who(ctx.from)} — ${p.title}, ${days} дн, ${fmt(amount)} ₸. Комментарий к переводу: ${ctx.from.id}`,
      new InlineKeyboard().text(`✅ Дать ${days} дн`, `approve:${pay.id}`).text('✖️ Нет перевода', `reject:${pay.id}`));
  });

  bot.callbackQuery(/^(approve|reject):(\d+)$/, async (ctx) => {
    if (!isAdmin(ctx)) return ctx.answerCallbackQuery('Только для владельца');
    const [, action, idStr] = ctx.match;
    const pay = db.payment(Number(idStr));
    if (!pay || pay.status !== 'pending') return ctx.answerCallbackQuery('Заявка уже обработана');
    const text = ctx.callbackQuery.message?.text || '';
    const p = PRODUCT[pay.product] || PRODUCT.olx;
    if (action === 'approve') {
      db.setPaymentStatus(pay.id, 'paid');
      const until = db.extend(pay.user_id, pay.days, p.sources);
      await send(pay.user_id, `Оплата получена ✅ 💎 ${p.title} — до ${fmtDate(until)}.`);
      await ctx.answerCallbackQuery('Доступ выдан');
      await ctx.editMessageText(`${text}\n\n✅ Выдано до ${fmtDate(until)}`).catch(() => {});
    } else {
      db.setPaymentStatus(pay.id, 'rejected');
      await send(pay.user_id, 'Перевод не найден. Если вы оплатили — напишите владельцу бота, указав время и сумму.');
      await ctx.answerCallbackQuery('Отклонено');
      await ctx.editMessageText(`${text}\n\n✖️ Отклонено`).catch(() => {});
    }
  });

  // ---------- команды владельца ----------

  bot.command('grant', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const [uid, days, productKey = 'all'] = String(ctx.match || '').trim().split(/\s+/);
    const userId = Number(uid);
    const d = Number(days);
    const p = PRODUCT[productKey];
    if (!userId || !d || !p || !db.user(userId)) {
      return ctx.reply(`Формат: /grant <ID> <дней> [${PRODUCTS.map((x) => x.key).join('|')}]. По умолчанию — all. ID — в /users.`);
    }
    const until = db.extend(userId, d, p.sources);
    db.addPayment({ userId, method: 'admin', product: p.key, days: d, status: 'paid' });
    await send(userId, `🎁 Вам открыт доступ: ${p.title} — до ${fmtDate(until)}.`);
    await ctx.reply(`Выдано: ${userId} — ${p.title} до ${fmtDate(until)}.`);
  });

  bot.command('users', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const users = db.users();
    const paid = users.filter((u) => db.isPaid(u, 'any'));
    const lines = users.slice(0, 30).map((u) =>
      `${db.isPaid(u, 'any') ? '💎' : db.isTrial(u) ? '🧪' : '⛔'} <code>${u.id}</code> ${esc(u.name || '')}${u.username ? ` @${esc(u.username)}` : ''}` +
      `${db.accessList(u.id).map((a) => ` ${sources.get(a.source).emoji}до ${fmtDate(a.until)}`).join('')} · поисков ${db.subs(u.id).length}${u.blocked ? ' · остановил бота' : ''}`);
    await ctx.reply(`Пользователей: ${users.length}, платных: ${paid.length}\n\n${lines.join('\n')}`, { parse_mode: 'HTML' });
  });

  bot.command('stats', async (ctx) => {
    if (!isAdmin(ctx)) return;
    const w = getWatcher();
    const money = db.paidTotals().map((r) => `${r.method}/${r.product}: ${r.n} шт${r.sum ? `, ${fmt(r.sum)}` : ''}`).join(' · ') || 'оплат пока нет';
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
    const m = /https?:\/\/\S+/i.exec(text);
    const src = m && sources.byUrl(m[0]);
    if (!src) {
      return ctx.reply('Нажмите «Новый поиск» — выберем площадку и рубрику кнопками. Или пришлите ссылку на поиск с olx.kz, kolesa.kz, krisha.kz или Kaspi Объявлений.', { reply_markup: menu() });
    }
    const url = m[0];
    if (src.isAdUrl(url)) return ctx.reply('Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком объявлений.');
    try { src.normalize(url); } catch (e) { return ctx.reply(e.message); }
    const limit = canAdd(ctx.from.id, src.key);
    if (limit !== true) return ctx.reply(limit);
    const before = text.slice(0, m.index).trim();
    const sub = db.addSub(ctx.from.id, (before || `${src.title}: ${nameFromUrl(url)}`).slice(0, 60), url, src.key);
    await ctx.reply(`${src.emoji} Добавил поиск «${sub.name}». Первый проход — запомню, что уже есть, дальше присылаю только новые.`);
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
      ? subs.map((s, i) => `${i + 1}. ${s.paused ? '⏸' : sources.get(s.source).emoji} ${esc(s.name)} — прислано ${s.sent}${!db.hasAccess(ctx.from.id, s.source) ? ' · нет доступа' : ''}${s.last_error ? ` ⚠ ${esc(s.last_error)}` : ''}`).join('\n')
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

  // OLX пишет продавца в ссылке коротким кодом — как номер объявления (62-ричная запись).
  function sellerLink(userId) {
    const n = Number(userId);
    const code = Number.isFinite(n) && n > 0 ? olx.encodeId(n) : String(userId);
    return config.sellerUrl.replace('{code}', encodeURIComponent(code)).replace('{id}', encodeURIComponent(userId));
  }

  // Коллаж из первых 4 фото готовим один раз на объявление: первому
  // получателю — загрузкой, остальным — по file_id, который вернул Телеграм.
  const collages = new Map();   // ключ объявления → file_id
  function watermarkText() {
    const w = config.watermark;
    if (!w || w === 'off') return '';
    return w === 'auto' ? (bot.botInfo?.username ? `@${bot.botInfo.username}` : '') : w;
  }

  // Водяной знак — только на тестовом доступе; у оплативших площадку фото чистые.
  async function collagePhoto(ad, urls, marked) {
    const mark = marked ? watermarkText() : '';
    const key = `${ad.source || 'olx'}:${ad.id}:${mark ? 'wm' : 'clean'}`;
    if (collages.has(key)) return { key, media: collages.get(key) };
    const buffers = (await Promise.all(urls.slice(0, 4).map((u) => fetchImage(u).catch(() => null)))).filter(Boolean);
    if (!buffers.length) return { key, media: urls[0] };   // скачать не вышло — пусть Телеграм возьмёт сам
    return { key, media: new InputFile(await collage(buffers, mark), 'photos.jpg') };
  }

  // Подпись к фото — до 1024 знаков: не влезает — укорачиваем описание.
  function captionFor(ad, subs, via) {
    let text = card(ad, subs, via, config.cardSections);
    for (let max = 900; text.length > 1024 && max >= 0; max -= 150) {
      text = card(ad, subs, via, config.cardSections, max);
    }
    return text.length > 1024 ? card(ad, subs, via, new Set(), 0) : text;
  }

  async function notify(userId, ad, subs, via, count) {
    if (via === 'ready') {
      return send(userId, `«${subs[0].name}»: слежу. Сейчас в выдаче ${count} объявлений — присылать буду только новые.`);
    }
    const kb = new InlineKeyboard().url(`Открыть на ${sources.get(ad.source).title}`, adLink(ad));
    if (ad.userId && (ad.source || 'olx') === 'olx') kb.row().url('Все объявления автора', sellerLink(ad.userId));
    else if (ad.sellerUrl) kb.row().url('Все объявления автора', ad.sellerUrl);
    // Одно сообщение: коллаж из до 4 фото, под ним карточка и кнопки. Остальные фото — на сайте.
    const photos = (ad.photos?.length ? ad.photos : ad.photo ? [ad.photo] : []);
    if (photos.length) {
      try {
        const { key, media } = await collagePhoto(ad, photos, !db.isPaid(userId, ad.source || 'olx'));
        const msg = await bot.api.sendPhoto(userId, media, { caption: captionFor(ad, subs, via), parse_mode: 'HTML', reply_markup: kb });
        const fileId = msg.photo?.[msg.photo.length - 1]?.file_id;
        if (fileId && !collages.has(key)) {
          collages.set(key, fileId);
          if (collages.size > 300) collages.delete(collages.keys().next().value);
        }
        return;
      } catch (e) {
        if (e instanceof GrammyError && e.error_code === 403) { db.setBlocked(userId, true); return; }
        if (e instanceof GrammyError && e.error_code === 429) await sleep((e.parameters?.retry_after || 3) * 1000);
        log(`фото ${ad.id}: ${e.message}`);
      }
    }
    // Без фото или фото не ушло — полная карточка текстом.
    const caption = card(ad, subs, via, config.cardSections);
    try {
      await bot.api.sendMessage(userId, caption, { parse_mode: 'HTML', reply_markup: kb, link_preview_options: { is_disabled: true } });
    } catch (e) {
      if (e instanceof GrammyError && e.error_code === 403) { db.setBlocked(userId, true); return; }
      await send(userId, caption, { parse_mode: 'HTML', reply_markup: kb, link_preview_options: { is_disabled: true } });
    }
  }

  // Напоминания: за сутки до конца платного доступа и когда он закончился — по одному разу.
  async function remindExpiring() {
    const now = Date.now();
    for (const u of db.users()) {
      if (u.blocked) continue;
      // Тест: за сутки до конца и когда кончился (если не оплатил).
      if (!db.isPaid(u, 'any', now) && u.trial_until) {
        const tl = u.trial_until - now;
        const tkey = `trial:${u.id}:${u.trial_until}`;
        if (tl > 0 && tl < DAY && !db.get(`${tkey}:soon`)) {
          db.set(`${tkey}:soon`, 1);
          await send(u.id, `🧪 Тестовый доступ заканчивается ${fmtDate(u.trial_until)}. Чтобы объявления продолжали приходить: /access`);
        } else if (tl <= 0 && tl > -7 * DAY && !db.get(`${tkey}:over`) && u.paid_until < now) {
          db.set(`${tkey}:over`, 1);
          await send(u.id, '⛔ Тестовый доступ закончился — поиски на паузе. Подключить платный доступ: /access');
        }
      }
      if (!u.paid_until) continue;
      const left = u.paid_until - now;
      const key = `remind:${u.id}:${u.paid_until}`;
      if (left > 0 && left < DAY && !db.get(`${key}:soon`)) {
        db.set(`${key}:soon`, 1);
        await send(u.id, `⏳ Платный доступ заканчивается ${fmtDate(u.paid_until)}. Продлить: /access`);
      } else if (left <= 0 && left > -7 * DAY && !db.get(`${key}:over`)) {
        db.set(`${key}:over`, 1);
        await send(u.id, '⛔ Платный доступ закончился — поиски на паузе, объявления не приходят. Продлить: /access');
      }
    }
  }
  const reminder = setInterval(() => remindExpiring().catch((e) => log(`напоминания: ${e.message}`)), 3600_000);
  reminder.unref?.();

  return { bot, notify, alert: tellAdmin, remindExpiring };
}

// Карточка: заголовок, цена, город, свежесть, телефон из текста, пометки, параметры, описание.
// Карточка объявления по разделам: главное, характеристики, описание, продавец, поиск.
// Шлётся текстом (до 4096 знаков), фото — превью над текстом.
function card(ad, subs, via, sections = new Set(['specs', 'description', 'seller']), descMax = 1500) {
  const src = sources.get(ad.source);
  const flags = [];
  if (via === 'turbo') flags.push('⚡ эксклюзив');
  if (ad.status && ad.status !== 'active') flags.push('⏳ на проверке');
  if (ad.promoted) flags.push('📣 продвигается');
  // Номер, который продавец написал в тексте, — Телеграм сам делает его нажимаемым (звонок).
  const phone = phonesIn(`${ad.title || ''}\n${ad.description || ''}`)[0];
  const price = ad.priceLabel || (ad.price != null ? `${fmt(ad.price)} ₸` : '');
  const place = [...new Set([ad.city, ad.region].filter(Boolean))].join(', ');

  const head = [
    `${src.emoji} <b>${esc(ad.title || 'Объявление ' + ad.id)}</b>`,
    price ? `💰 <b>${esc(price)}</b>` : '',
    place ? `📍 ${esc(place)}` : '',
    ad.createdAt ? `🕒 Подано ${ago(ad.createdAt)} назад · ${fmtTime(ad.createdAt)}` : '',
    flags.join(' · '),
    phone ? `📞 <b>${prettyPhone(phone)}</b>` : '',
  ];

  const params = (ad.params || []).filter(Boolean);
  const specs = params.length && sections.has('specs') ? ['', '<b>Характеристики</b>', ...params.map((p) => `• ${esc(p)}`)] : [];

  const desc = String(ad.description || '').trim();
  const description = desc && descMax > 20 && sections.has('description')
    ? ['', '<b>Описание</b>', `<blockquote expandable>${esc(desc.slice(0, descMax))}${desc.length > descMax ? '…' : ''}</blockquote>`]
    : [];

  const seller = [];
  if (ad.userName || ad.sellerCompany) seller.push(`👤 ${esc(ad.sellerCompany || ad.userName)} · ${ad.business ? 'бизнес' : 'частное лицо'}`);
  if (ad.sellerSince) seller.push(`📅 На ${esc(src.title)} с ${fmtMonth(ad.sellerSince)} (${since(ad.sellerSince)})`);
  if (ad.sellerAbout) seller.push(`ℹ️ ${esc(ad.sellerAbout)}`);
  const sellerBlock = seller.length && sections.has('seller') ? ['', '<b>Продавец</b>', ...seller] : [];

  const more = (ad.photos?.length || 0) - 4;
  const tail = ['', more > 0 ? `📷 Ещё ${more} фото — по кнопке «Открыть»` : '', `🔎 Поиск: ${subs.map((s) => esc(s.name)).join(', ')}`];
  return [...head, ...specs, ...description, ...sellerBlock, ...tail].filter((l) => l !== null && l !== undefined && l !== false)
    .filter((l, i, a) => l !== '' || (i > 0 && a[i - 1] !== ''))
    .join('\n')
    .slice(0, 4000);
}

function fmtTime(ts) {
  return new Date(ts).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Almaty' });
}

function fmtMonth(ts) {
  return new Date(ts).toLocaleDateString('ru-RU', { month: 'long', year: 'numeric', timeZone: 'Asia/Almaty' })
    .replace(/\s*г\.?$/, '')
    .replace(/^(\S+)ь /, '$1я ').replace(/^(\S+)й /, '$1я ').replace(/^(март|август) /, '$1а ');
}

// «3 года», «8 месяцев», «12 дней» — сколько продавец на площадке.
function since(ts) {
  const days = Math.floor((Date.now() - ts) / 86400_000);
  if (days < 31) return plural(Math.max(days, 0), 'день', 'дня', 'дней');
  const months = Math.floor(days / 30.44);
  if (months < 12) return plural(months, 'месяц', 'месяца', 'месяцев');
  return plural(Math.floor(months / 12), 'год', 'года', 'лет');
}

function plural(n, one, few, many) {
  const m10 = n % 10;
  const m100 = n % 100;
  const w = m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many;
  return `${n} ${w}`;
}

// Ссылка с номером в конце — сайт часть после # игнорирует, а номер под рукой.
function adLink(ad) {
  return sources.get(ad.source).link(ad);
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

module.exports = { createBot, card, adLink, nameFromUrl, phonesIn, PLANS, PRODUCTS };
