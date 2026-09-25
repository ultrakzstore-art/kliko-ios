// Окно: вкладки, статус бота, настройки, проверка площадок, журнал.
const $ = (id) => document.getElementById(id);
let state = null;
let settingsDirty = false;

// ---------- вкладки ----------
document.querySelectorAll('nav button').forEach((b) => b.addEventListener('click', () => {
  document.querySelectorAll('nav button').forEach((x) => x.classList.toggle('active', x === b));
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.id === `tab-${b.dataset.tab}`));
  if (b.dataset.tab === 'log') scrollLog();
}));

document.querySelectorAll('[data-url]').forEach((a) => a.addEventListener('click', (e) => {
  e.preventDefault();
  window.app.openUrl(a.dataset.url);
}));

// ---------- статус ----------
const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('ru-RU'));

function uptime(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s} с`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} мин`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h} ч ${m % 60} мин` : `${Math.floor(h / 24)} д ${h % 24} ч`;
}

function renderStatus() {
  if (!state) return;
  const b = state.bot;
  const titles = { stopped: 'Бот остановлен', starting: 'Запускаю…', running: `Работает — @${b.username}`, error: 'Ошибка' };
  $('dot').className = `dot ${b.status}`;
  $('status-title').textContent = titles[b.status] || b.status;
  $('status-sub').textContent = b.status === 'running' && b.startedAt
    ? `без перерыва ${uptime(Date.now() - b.startedAt)} · закроете окно — продолжит работать из трея`
    : !state.hasToken ? 'Нужен токен бота — инструкция ниже' : '';
  $('status-error').textContent = b.error || '';
  $('status-error').classList.toggle('hidden', !b.error);
  const active = b.status === 'running' || b.status === 'starting';
  $('btn-start').classList.toggle('hidden', active);
  $('btn-stop').classList.toggle('hidden', !active);
  $('btn-open-tg').classList.toggle('hidden', !b.username || b.status !== 'running');
  $('setup').classList.toggle('hidden', state.hasToken);

  const st = b.stats || {};
  $('st-users').textContent = fmt(st.users);
  $('st-paid').textContent = fmt(st.paid);
  $('st-trial').textContent = fmt(st.trial);
  $('st-subs').textContent = fmt(st.subs);
  $('st-sent').textContent = fmt(st.sent);
  $('st-search').textContent = b.stats ? `${fmt(st.searchOk)} / ${fmt(st.searchErr)}` : '—';
  $('st-turbo').textContent = b.stats ? `${fmt(st.turboFound)} / ${fmt(st.turboProbes)}` : '—';
  $('st-frontier').textContent = st.frontier ? String(st.frontier) : '—';
  const blocked = st.blockedUntil && st.blockedUntil > Date.now();
  $('blocked').classList.toggle('hidden', !blocked);
  if (blocked) {
    $('blocked').textContent = `OLX ограничил запросы с этого компьютера — пауза до ${new Date(st.blockedUntil).toLocaleTimeString('ru-RU')}. Бот продолжит сам.`;
  }
}

function renderSettings() {
  if (!state || settingsDirty) return;
  const s = state.settings;
  document.querySelectorAll('[data-env]').forEach((el) => { el.value = s.env[el.dataset.env] ?? ''; });
  $('autoStart').checked = !!s.autoStart;
  $('openAtLogin').checked = !!s.openAtLogin;
  $('token-hint').textContent = state.hasToken ? `Сохранён: ${state.tokenHint}` : 'Токен ещё не задан';
}

function apply(s) {
  state = s;
  renderStatus();
  renderSettings();
}

setInterval(renderStatus, 1000);   // «без перерыва N мин» тикает

// ---------- кнопки бота ----------
$('btn-start').addEventListener('click', () => window.app.start());
$('btn-stop').addEventListener('click', () => window.app.stop());
$('btn-open-tg').addEventListener('click', () => window.app.openUrl(`https://t.me/${state.bot.username}`));

$('btn-setup-save').addEventListener('click', async () => {
  const token = $('setup-token').value.trim();
  const r = await window.app.save({ token });
  $('setup-error').textContent = r.ok ? '' : r.error;
  $('setup-error').classList.toggle('hidden', r.ok);
  if (r.ok) {
    $('setup-token').value = '';
    window.app.start();
  }
});

// ---------- настройки ----------
document.querySelectorAll('#tab-settings input').forEach((el) => el.addEventListener('input', () => {
  settingsDirty = true;
  $('save-msg').textContent = 'Есть несохранённые изменения';
}));

$('btn-save').addEventListener('click', async () => {
  const env = {};
  document.querySelectorAll('[data-env]').forEach((el) => { env[el.dataset.env] = el.value; });
  const bad = [...document.querySelectorAll('[data-env^="STARS_PRICES"],[data-env^="KASPI_PRICES"]')]
    .filter((el) => el.value.trim() && el.value.split(',').filter((x) => parseInt(x.replace(/\s/g, ''), 10) > 0).length !== 3);
  if (bad.length) {
    $('save-msg').textContent = 'Цены — три числа через запятую (7, 14 и 30 дней) или пусто';
    bad[0].focus();
    return;
  }
  const r = await window.app.save({
    token: $('token').value,
    env,
    autoStart: $('autoStart').checked,
    openAtLogin: $('openAtLogin').checked,
  });
  if (!r.ok) {
    $('save-msg').textContent = r.error;
    return;
  }
  settingsDirty = false;
  $('token').value = '';
  if (r.restartNeeded) {
    $('save-msg').textContent = 'Сохранено — перезапускаю бота с новыми настройками…';
    await window.app.restart();
  } else {
    $('save-msg').textContent = 'Сохранено';
  }
  apply(await window.app.state());
});

$('btn-forget').addEventListener('click', async () => {
  if (!confirm('Удалить токен? Бот остановится.')) return;
  await window.app.forgetToken();
});

$('btn-data').addEventListener('click', () => window.app.openData());

// ---------- проверка площадок ----------
async function probe(url) {
  if (!url) return;
  $('probe-url').value = url;
  $('btn-probe').disabled = true;
  $('probe-out').textContent = `Проверяю ${url} …`;
  const out = await window.app.probe(url);
  $('probe-out').textContent = out;
  $('btn-probe').disabled = false;
}
$('btn-probe').addEventListener('click', () => probe($('probe-url').value.trim()));
$('probe-url').addEventListener('keydown', (e) => { if (e.key === 'Enter') probe($('probe-url').value.trim()); });
document.querySelectorAll('[data-probe]').forEach((b) => b.addEventListener('click', () => probe(b.dataset.probe)));
window.app.onProbe((text) => { $('probe-out').textContent = text; });

// ---------- журнал ----------
function scrollLog() {
  const el = $('log');
  el.scrollTop = el.scrollHeight;
}
function appendLog(lines) {
  const el = $('log');
  const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  el.textContent += lines.map((l) => `${l}\n`).join('');
  if (el.textContent.length > 200_000) el.textContent = el.textContent.slice(-150_000);
  if (atBottom) scrollLog();
}

window.app.onState(apply);
window.app.onLog(appendLog);
window.app.state().then((s) => {
  apply(s);
  $('log').textContent = s.log.map((l) => `${l}\n`).join('');
  scrollLog();
});
