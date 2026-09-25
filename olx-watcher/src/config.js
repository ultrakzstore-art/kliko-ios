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
  pollSec: int('POLL_SEC', 30, 10),              // платные: поиск раз в N сек
  freePollSec: int('FREE_POLL_SEC', 600, 60),    // бесплатные: раз в 10 минут
  turboSec: int('TURBO_SEC', 5, 2),
  turboWindow: int('TURBO_WINDOW', 10, 1),
  freshMs: int('FRESH_MIN', 30, 1) * 60_000,     // «новое» — подано не раньше N минут назад
  trialDays: int('TRIAL_DAYS', 7, 0),            // тестовый доступ новичку, дней
  freeSubs: int('FREE_SUBS', 3, 1),              // поисков на тестовом доступе
  paidSubs: int('PAID_SUBS', 20, 1),
  // Цены за 7/14/30 дней по тарифам: отдельная площадка или «всё сразу» (комбо).
  // STARS_PRICES / KASPI_PRICES без суффикса — старые настройки, считаются ценой за OLX.
  prices: Object.fromEntries(['olx', 'kolesa', 'krisha', 'kaspi', 'all'].map((k) => [k, {
    stars: prices(`STARS_PRICES_${k.toUpperCase()}`) || (k === 'olx' ? prices('STARS_PRICES') : null),
    kaspi: prices(`KASPI_PRICES_${k.toUpperCase()}`) || (k === 'olx' ? prices('KASPI_PRICES') : null),
  }])),
  kaspiDetails: (process.env.KASPI_DETAILS || '').trim(),
  sellerUrl: process.env.SELLER_URL || 'https://www.olx.kz/list/user/{id}/',
  dbFile: process.env.DB_FILE || path.join(__dirname, '..', 'data', 'watcher.db'),
};
