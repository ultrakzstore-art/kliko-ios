// Телеграм-часть: команды владельца и карточки новых объявлений.

const { Bot, InlineKeyboard, GrammyError } = require('grammy');
const { idFromUrl, newestFirst, BASE, encodeId } = require('./olx');

const HELP = `Я присылаю новые объявления OLX.kz по вашим поискам — через секунды после подачи.

Как добавить поиск: на olx.kz выберите рубрику, город, цену, введите слова → скопируйте ссылку из адресной строки → пришлите мне (можно с названием в первой строке).

/list — мои поиски (пауза, удалить)
/turbo — вкл/выкл ловлю по номерам, раньше поиска
/status — как идут дела
/help — эта справка`;

function createBot({ token, db, config, getWatcher, log }) {
  const bot = new Bot(token);
  let owner = config.ownerId || db.get('owner', null);

  // Бот личный: отвечает только владельцу. Первый /start занимает место, если OWNER_ID не задан.
  bot.use(async (ctx, next) => {
    const uid = ctx.from?.id;
    if (!uid) return;
    if (!owner && ctx.message?.text?.startsWith('/start')) {
      owner = uid;
      db.set('owner', uid);
      log(`владелец бота: ${uid}`);
    }
    if (uid !== owner) {
      if (ctx.message) await ctx.reply('Это личный бот.');
      return;
    }
    return next();
  });

  bot.command(['start', 'help'], (ctx) => ctx.reply(HELP, { link_preview_options: { is_disabled: true } }));

  bot.command('list', (ctx) => sendList(ctx));

  bot.command('turbo', async (ctx) => {
    const on = !db.get('turbo', true);
    db.set('turbo', on);
    await ctx.reply(on
      ? '⚡ Турбо включено: проверяю следующие номера объявлений напрямую — новое ловится до того, как попадёт в поиск.'
      : 'Турбо выключено: только поиск, раз в ' + config.pollSec + ' сек.');
  });

  bot.command('status', async (ctx) => {
    const w = getWatcher();
    const subs = db.subs();
    const lines = [
      `Поисков: ${subs.length} (на паузе: ${subs.filter((s) => s.paused).length})`,
      `Поиск: раз в ${config.pollSec} сек · удачных запросов ${w.stats.searchOk}, ошибок ${w.stats.searchErr}`,
      `Турбо: ${db.get('turbo', true) ? 'вкл' : 'выкл'} · последний номер ${w.frontier || '—'} · проверено номеров ${w.stats.turboProbes}, найдено ${w.stats.turboFound}` +
        (w.stats.lastTurboHit ? ` · последняя находка ${ago(w.stats.lastTurboHit)} назад` : ''),
      w.blocked() ? `⏸ OLX ограничил запросы — отдыхаю ещё ${Math.ceil((w.backoffUntil - Date.now()) / 60_000)} мин` : '',
    ].filter(Boolean);
    for (const s of subs) if (s.last_error) lines.push(`⚠ «${s.name}»: ${s.last_error}`);
    await ctx.reply(lines.join('\n'));
  });

  // Любое сообщение со ссылкой на поиск OLX — новая подписка.
  bot.on('message:text', async (ctx) => {
    const text = ctx.message.text.trim();
    const m = /https?:\/\/(?:www\.|m\.)?olx\.kz\/\S+/i.exec(text);
    if (!m) return ctx.reply('Пришлите ссылку на поиск с olx.kz. /help — подробнее.');
    const url = m[0];
    if (idFromUrl(url)) return ctx.reply('Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком объявлений.');
    try { newestFirst(url); } catch (e) { return ctx.reply(e.message); }
    const before = text.slice(0, m.index).trim();
    const name = (before || nameFromUrl(url)).slice(0, 60);
    const sub = db.addSub(name, url);
    await ctx.reply(`Добавил поиск «${sub.name}» (#${sub.id}). Первый проход — запомню, что уже есть, дальше присылаю только новые.`);
  });

  bot.callbackQuery(/^(pause|resume|del):(\d+)$/, async (ctx) => {
    const [, action, idStr] = ctx.match;
    const id = Number(idStr);
    if (action === 'del') db.deleteSub(id);
    else db.updateSub(id, { paused: action === 'pause' ? 1 : 0 });
    await ctx.answerCallbackQuery(action === 'del' ? 'Удалено' : action === 'pause' ? 'На паузе' : 'Снова слежу');
    await sendList(ctx, true);
  });

  async function sendList(ctx, edit = false) {
    const subs = db.subs();
    const text = subs.length
      ? subs.map((s) => `#${s.id} ${s.paused ? '⏸' : '▶️'} ${s.name} — прислал ${s.sent}${s.last_error ? ` ⚠ ${s.last_error}` : ''}`).join('\n')
      : 'Поисков пока нет. Пришлите ссылку на поиск с olx.kz.';
    const kb = new InlineKeyboard();
    for (const s of subs) {
      kb.text(`${s.paused ? '▶️' : '⏸'} #${s.id}`, `${s.paused ? 'resume' : 'pause'}:${s.id}`).text(`🗑 #${s.id}`, `del:${s.id}`).row();
    }
    const opts = { reply_markup: kb, link_preview_options: { is_disabled: true } };
    if (edit) await ctx.editMessageText(text, opts).catch(() => {});
    else await ctx.reply(text, opts);
  }

  bot.catch((err) => log(`телеграм: ${err.message}`));

  // ---------- карточка объявления ----------

  async function notify(ad, subs, via) {
    if (!owner) return;
    const caption = card(ad, subs, via, config);
    const kb = new InlineKeyboard().url('Открыть объявление', adLink(ad));
    if (ad.userId) kb.row().url('Все объявления автора', config.sellerUrl.replace('{id}', encodeURIComponent(ad.userId)));
    try {
      if (ad.photo) await bot.api.sendPhoto(owner, ad.photo, { caption, parse_mode: 'HTML', reply_markup: kb });
      else throw new Error('без фото');
    } catch (e) {
      if (e instanceof GrammyError && e.error_code === 429) await sleep((e.parameters?.retry_after || 3) * 1000);
      await bot.api.sendMessage(owner, caption, { parse_mode: 'HTML', reply_markup: kb, link_preview_options: { is_disabled: true } })
        .catch((err) => log(`не отправил ${ad.id}: ${err.message}`));
    }
  }

  async function alert(text) {
    if (owner) await bot.api.sendMessage(owner, `ℹ️ ${text}`).catch(() => {});
  }

  return { bot, notify, alert };
}

// Карточка: заголовок, цена, город, свежесть, пометки, параметры, начало описания.
function card(ad, subs, via) {
  const flags = [];
  if (via === 'turbo') flags.push('⚡ раньше поиска');
  if (ad.status && ad.status !== 'active') flags.push(`статус: ${esc(ad.status)} (возможно, на проверке)`);
  if (ad.business) flags.push('🏪 бизнес-аккаунт');
  if (ad.promoted) flags.push('📣 платное продвижение');
  const lines = [
    `<b>${esc(ad.title || 'Объявление ' + ad.id)}</b>`,
    [ad.priceLabel || (ad.price != null ? `${fmt(ad.price)} ₸` : ''), [ad.city, ad.region].filter(Boolean).join(', ')].filter(Boolean).map(esc).join(' · '),
    ad.createdAt ? `🕒 подано ${ago(ad.createdAt)} назад` : '',
    flags.join(' · '),
    (ad.params || []).length ? esc(ad.params.join(' · ')) : '',
    ad.description ? `\n${esc(ad.description.slice(0, 350))}${ad.description.length > 350 ? '…' : ''}` : '',
    ad.userName ? `👤 ${esc(ad.userName)}` : '',
    `🔎 ${subs.map((s) => esc(s.name)).join(', ')}`,
  ];
  return lines.filter(Boolean).join('\n').slice(0, 1024);
}

// Ссылка с номером в конце — как у Lotify: сайт часть после # игнорирует, а номер под рукой.
function adLink(ad) {
  const base = ad.url && /^https?:/.test(ad.url) ? ad.url.split('#')[0] : `${BASE}/d/obyavlenie/-ID${encodeId(ad.id)}.html`;
  return `${base}#${ad.id}`;
}

function nameFromUrl(url) {
  const u = new URL(url);
  const parts = decodeURIComponent(u.pathname).split('/').filter((p) => p && p !== 'd' && p !== 'kk' && p !== 'list');
  const q = parts.find((p) => p.startsWith('q-'));
  return (q ? q.slice(2).replace(/-/g, ' ') : parts.slice(-2).join(' / ')) || 'Поиск';
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

module.exports = { createBot, card, adLink, nameFromUrl };
