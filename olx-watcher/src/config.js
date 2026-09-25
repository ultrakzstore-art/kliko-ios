// Настройки из окружения (.env рядом с package.json подхватывается автоматически).

const path = require('path');

function int(name, def, min) {
  const v = parseInt(process.env[name] || '', 10);
  return Number.isFinite(v) ? Math.max(min, v) : def;
}

// «100,180,350» → [100, 180, 350] (цены на 7/14/30 дней); пусто или не три числа — способ выключен.
function prices(name) {
  const list = String(process.env[name] || '').split(',').map((s) => parseInt(s.replace(/\s/g, ''), 10)).filter((n) => n > 0);
  return list.length === 3 ? list : null;
}

module.exports = {
  token: (process.env.BOT_TOKEN || '').trim(),
  adminId: parseInt(process.env.ADMIN_ID || process.env.OWNER_ID || '', 10) || null,
  pollSec: int('POLL_SEC', 2, 1),                // поиск раз в N сек (тест и платный)
  turboSec: int('TURBO_SEC', 1, 1),
  boardSec: int('BOARD_SEC', 2, 1),
  // Скидки: «📉 Цена снижена», если цена знакомого объявления упала хотя бы на MIN_DROP %.
  discounts: !/^(0|off|no|false)$/i.test(process.env.DISCOUNTS || 'on'),
  minDropPct: int('MIN_DROP', 3, 1),              // лента всей доски раз в N сек
  turboWindow: int('TURBO_WINDOW', 10, 1),
  freshMs: int('FRESH_MIN', 30, 1) * 60_000,     // «новое» — подано не раньше N минут назад
  trialDays: int('TRIAL_DAYS', 7, 0),            // тестовый доступ новичку, дней
  paidSubs: int('PAID_SUBS', 20, 1),             // поисков у пользователя (тест и платный)
  // Цены за 7/14/30 дней по тарифам: отдельная площадка или «всё сразу» (комбо).
  // STARS_PRICES / KASPI_PRICES без суффикса — старые настройки, считаются ценой за OLX.
  prices: Object.fromEntries(['olx', 'kolesa', 'krisha', 'kaspi', 'all'].map((k) => [k, {
    stars: prices(`STARS_PRICES_${k.toUpperCase()}`) || (k === 'olx' ? prices('STARS_PRICES') : null),
    kaspi: prices(`KASPI_PRICES_${k.toUpperCase()}`) || (k === 'olx' ? prices('KASPI_PRICES') : null),
  }])),
  // Разделы карточки объявления: характеристики, описание, продавец (через запятую).
  cardSections: new Set(String(process.env.CARD_SECTIONS ?? 'specs,description,seller').split(',').map((s) => s.trim()).filter(Boolean)),
  // Водяной знак на фото: auto — @имя_бота, off — без знака, любой другой текст — он.
  watermark: (process.env.WATERMARK ?? 'auto').trim(),
  kaspiDetails: (process.env.KASPI_DETAILS || '').trim(),
  dbFile: process.env.DB_FILE || path.join(__dirname, '..', 'data', 'watcher.db'),
};
