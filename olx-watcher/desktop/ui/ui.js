// Окно: вкладки, статус бота, настройки, проверка площадок, журнал.
const $ = (id) => document.getElementById(id);
let state = null;
let settingsDirty = false;

// ---------- вкладки ----------
document.querySelectorAll('nav button').forEach((b) => b.addEventListener('click', () => {
  document.querySelectorAll('nav button').forEach((x) => x.classList.toggle('active', x === b));
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.id === `tab-${b.dataset.tab}`));
  if (b.dataset.tab === 'log') scrollLog();
  if (b.dataset.tab === 'users') loadUsers();
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
  const sections = new Set(String(s.env.CARD_SECTIONS ?? '').split(',').map((x) => x.trim()));
  document.querySelectorAll('[data-section]').forEach((el) => { el.checked = sections.has(el.dataset.section); });
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
  $('card-sections').value = [...document.querySelectorAll('[data-section]')].filter((el) => el.checked).map((el) => el.dataset.section).join(',');
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

// ---------- подписчики ----------
const EMOJI = { olx: '🟣', kolesa: '🚗', krisha: '🏠', kaspi: '🔴' };
let users = [];
let userFilter = 'all';
const day = (ts) => new Date(ts).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
const escHtml = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

async function loadUsers() {
  const r = await window.app.users();
  $('u-error').classList.toggle('hidden', r.ok);
  if (!r.ok) { $('u-error').textContent = `Не открылась база: ${r.error}`; return; }
  users = r.users;
  renderUsers();
}

function renderUsers() {
  const q = $('u-search').value.trim().toLowerCase().replace(/^@/, '');
  const count = { all: users.length, paid: 0, trial: 0, none: 0 };
  users.forEach((u) => { count[u.status] += 1; });
  for (const k of Object.keys(count)) $(`uc-${k}`).textContent = count[k];
  const list = users.filter((u) => (userFilter === 'all' || u.status === userFilter)
    && (!q || `${u.name} ${u.username} ${u.id}`.toLowerCase().includes(q)));
  $('u-empty').classList.toggle('hidden', users.length > 0);
  $('u-rows').innerHTML = list.map((u) => {
    const badge = u.status === 'paid' ? '<span class="badge paid">💎 платный</span>'
      : u.status === 'trial' ? `<span class="badge trial">🧪 тест до ${day(u.trialUntil)}</span>`
        : '<span class="badge none">⛔ нет доступа</span>';
    const access = u.access.map((a) => `<span style="white-space:nowrap">${EMOJI[a.source] || ""} до ${day(a.until)}</span>`).join("<br>");
    const pay = u.payments.n ? `${u.payments.n} · ${Number(u.payments.sum).toLocaleString('ru-RU')}` : '—';
    return `<tr>
      <td><div class="u-name">${escHtml(u.name || 'Без имени')}</div>
        <div class="u-id">${u.username ? `@${escHtml(u.username)} · ` : ''}${u.id}</div>
        ${u.blocked ? '<div class="muted">остановил бота</div>' : ''}
        ${u.vip.map((v) => `<div class="vip-line">👑 ${escHtml(v.label)} до ${day(v.until)}<button class="secondary" data-vipend="${v.id}">снять</button></div>`).join('')}</td>
      <td>${badge}<div class="muted">${access}</div></td>
      <td>${u.subs}</td>
      <td>${pay}</td>
      <td>${day(u.createdAt)}</td>
      <td><div class="u-actions">
        <button class="secondary" data-vip="${u.id}">👑 VIP</button>
        <button class="secondary" data-grant="7" data-user="${u.id}">+7 дн</button>
        <button class="secondary" data-grant="14" data-user="${u.id}">+14</button>
        <button class="secondary" data-grant="30" data-user="${u.id}">+30</button>
        ${u.status !== 'none' ? `<button class="danger" data-revoke="${u.id}">Забрать</button>` : ''}
      </div></td>
    </tr>`;
  }).join('');
}

$('u-rows').addEventListener('click', async (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.dataset.vipend) {
    if (!confirm('Снять VIP-рубрику? Объявления из неё снова будут получать все.')) return;
    await window.app.vipEnd(Number(b.dataset.vipend));
    return loadUsers();
  }
  if (b.dataset.vip) return openVip(users.find((x) => String(x.id) === b.dataset.vip));
  const u = users.find((x) => String(x.id) === (b.dataset.user || b.dataset.revoke));
  if (!u) return;
  if (b.dataset.grant) {
    const product = $('u-product').value;
    const title = $('u-product').selectedOptions[0].textContent.trim();
    if (!confirm(`Выдать ${u.name || u.id}: ${title} на ${b.dataset.grant} дней?`)) return;
    await window.app.grant(u.id, Number(b.dataset.grant), product);
  } else if (b.dataset.revoke) {
    if (!confirm(`Забрать весь доступ у ${u.name || u.id}? Поиски встанут на паузу.`)) return;
    await window.app.revoke(u.id);
  }
  loadUsers();
});
let vipTarget = null;
let vipLoaded = false;
async function openVip(u) {
  if (!u) return;
  vipTarget = u;
  if (!vipLoaded) {
    const o = await window.app.vipOptions();
    $('vip-rubric').innerHTML = o.rubrics.map((r) => `<option value="${escHtml(r.path)}">${escHtml(r.name)}</option>`).join('');
    $('vip-city').innerHTML = o.cities.map((c) => `<option value="${escHtml(c.slug)}">${escHtml(c.name)}</option>`).join('');
    vipLoaded = true;
  }
  $('vip-who').textContent = `Кому: ${u.name || 'без имени'}${u.username ? ` (@${u.username})` : ''} · ${u.id}`;
  $('vip-error').classList.add('hidden');
  $('vip-dialog').showModal();
}
$('vip-ok').addEventListener('click', async (e) => {
  e.preventDefault();
  const r = await window.app.vipGrant(vipTarget.id, $('vip-rubric').value, $('vip-city').value, Number($('vip-days').value));
  if (!r.ok) {
    $('vip-error').textContent = r.error;
    $('vip-error').classList.remove('hidden');
    return;
  }
  $('vip-dialog').close();
  loadUsers();
});
$('u-search').addEventListener('input', renderUsers);
document.querySelectorAll('#u-filters .chip').forEach((b) => b.addEventListener('click', () => {
  userFilter = b.dataset.filter;
  document.querySelectorAll('#u-filters .chip').forEach((x) => x.classList.toggle('active', x === b));
  renderUsers();
}));
setInterval(() => { if ($('tab-users').classList.contains('active')) loadUsers(); }, 10_000);

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
