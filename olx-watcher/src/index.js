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

watcher.start();
bot.start({ onStart: (me) => log(`бот @${me.username} запущен; поиск раз в ${config.pollSec} сек, турбо раз в ${config.turboSec} сек`) });

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.once(sig, () => { watcher.stop(); bot.stop(); });
}
