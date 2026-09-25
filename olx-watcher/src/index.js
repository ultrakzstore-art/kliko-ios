const config = require('./config');
const { Db } = require('./db');
const { Watcher } = require('./watcher');
const { createBot } = require('./bot');

function log(line) {
  console.log(`${new Date().toLocaleTimeString('ru-RU')} ${line}`);
}

if (!config.token) {
  console.error('Нет BOT_TOKEN. Скопируйте .env.example в .env и вставьте токен от @BotFather.');
  process.exit(1);
}

const db = new Db(config.dbFile);
db.trialMs = config.trialDays * 86400_000;
let watcher;
const { bot, notify, alert } = createBot({ token: config.token, db, config, getWatcher: () => watcher, log });
watcher = new Watcher({ db, config, notify, alert, log });

bot.api.setMyCommands([
  { command: 'new', description: 'Новый поиск: рубрика, город, цена' },
  { command: 'list', description: 'Мои поиски' },
  { command: 'access', description: 'Доступ и оплата' },
  { command: 'help', description: 'Справка' },
]).catch(() => {});

// Запущен из приложения для ПК — отчитываемся ему: имя бота, счётчики, фатальные ошибки.
const parent = process.parentPort || null;
function report(msg) {
  if (parent) parent.postMessage(msg);
}

watcher.start();
bot.start({
  onStart: (me) => {
    log(`бот @${me.username} запущен; поиск раз в ${config.pollSec} сек, турбо раз в ${config.turboSec} сек`);
    report({ type: 'ready', username: me.username });
  },
}).catch((e) => {
  const code = e?.error_code;
  const text = code === 401 ? 'Telegram не принял токен — проверьте BOT_TOKEN (скопируйте заново у @BotFather)'
    : code === 409 ? 'Этот бот уже запущен в другом месте (второе окно, start.bat или сервер) — остановите его'
      : `Telegram: ${e.message}`;
  log(text);
  report({ type: 'fatal', text });
  watcher.stop();
  setTimeout(() => process.exit(2), 200);
});

if (parent) {
  const snapshot = () => {
    const now = Date.now();
    const users = db.users();
    report({
      type: 'stats',
      users: users.length,
      paid: users.filter((u) => db.isPaid(u, 'any', now)).length,
      trial: users.filter((u) => db.isTrial(u, now)).length,
      subs: db.subs().length,
      frontier: watcher.frontier,
      blockedUntil: watcher.backoffUntil > now ? watcher.backoffUntil : 0,
      ...watcher.stats,
    });
  };
  setInterval(snapshot, 5000);
  setTimeout(snapshot, 1500);
  parent.on('message', (e) => {
    if (e.data?.type === 'stop') { watcher.stop(); bot.stop().finally(() => process.exit(0)); }
  });
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.once(sig, () => { watcher.stop(); bot.stop(); });
}
