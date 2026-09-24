// Настройки из окружения (.env рядом с package.json подхватывается автоматически).

const path = require('path');

function int(name, def, min) {
  const v = parseInt(process.env[name] || '', 10);
  return Number.isFinite(v) ? Math.max(min, v) : def;
}

module.exports = {
  token: (process.env.BOT_TOKEN || '').trim(),
  ownerId: parseInt(process.env.OWNER_ID || '', 10) || null,
  pollSec: int('POLL_SEC', 30, 10),
  turboSec: int('TURBO_SEC', 5, 2),
  turboWindow: int('TURBO_WINDOW', 10, 1),
  sellerUrl: process.env.SELLER_URL || 'https://www.olx.kz/list/user/{id}/',
  dbFile: process.env.DB_FILE || path.join(__dirname, '..', 'data', 'watcher.db'),
};
