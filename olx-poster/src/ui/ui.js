const $ = (id) => document.getElementById(id);
let S = null;
const editing = new Set();

const STATUS = {
  new: 'в очереди на описание',
  describing: 'Claude описывает…',
  ready: 'ждёт подачи',
  posting: 'подаётся на OLX…',
  published: 'опубликовано',
  failed: 'ошибка',
  needs_user: 'нужны вы',
};

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function fmtTime(ts) {
  return new Date(ts).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
}

function render() {
  if (!S) return;
  const running = S.settings.running;
  $('run').textContent = running ? '■ Остановить' : '▶ Запустить';
  $('run').classList.toggle('on', running);

  const ready = S.items.filter((x) => x.status === 'ready').length;
  let status;
  if (!S.hasKey) status = 'Укажите ключ Claude API в настройках.';
  else if (S.postingId) status = 'Подаю объявление…';
  else if (!running) status = `Расписание выключено. Готово к подаче: ${ready}.`;
  else if (!S.inHours) status = `Вне рабочего окна (${S.settings.workStart}–${S.settings.workEnd}). Готово к подаче: ${ready}.`;
  else if (!ready) status = 'Жду новые товары.';
  else status = `Следующая подача ≈ ${S.nextPostAt && S.nextPostAt > Date.now() ? fmtTime(S.nextPostAt) : 'сейчас'}. В очереди: ${ready}.`;
  $('status').textContent = status;

  const today = new Date().toDateString();
  const posted = S.items.filter((x) => x.postedAt && new Date(x.postedAt).toDateString() === today).length;
  const cost = S.items.reduce((a, x) => a + (x.costUsd || 0), 0);
  $('counts').textContent = `Сегодня опубликовано: ${posted} · всего товаров: ${S.items.length} · расход Claude ≈ $${cost.toFixed(2)}`;

  // Сначала то, что требует внимания, затем очередь, внизу — опубликованные.
  const order = { needs_user: 0, failed: 1, posting: 2, describing: 3, ready: 4, new: 5, published: 6 };
  const items = [...S.items].sort((a, b) => (order[a.status] - order[b.status]) || (b.status === 'published' ? b.postedAt - a.postedAt : 0));
  // Не перерисовываем список, пока человек печатает в карточке правки.
  if (!document.activeElement.closest || !document.activeElement.closest('.item.editing')) {
    $('items').innerHTML = items.map(itemHtml).join('');
  }

  $('batches').innerHTML = S.batches.map((b) => `<div class="batch">${b.id === S.groupingId
    ? `Claude раскладывает ${b.count} фото по товарам…`
    : `Пачка из ${b.count} фото ждёт раскладки${b.attempts ? ` (попыток: ${b.attempts})` : ''}${S.hasKey ? '' : ' — нужен ключ Claude API'}`}</div>`).join('');

  $('qr').src = S.phoneQr || '';
  $('phone-url').textContent = S.phoneUrls.join('\n') || 'Нет сети';
  $('inbox').textContent = S.settings.inboxDir;
}

function itemHtml(it) {
  const L = it.listing;
  if (editing.has(it.id) && L) {
    return `<div class="item editing" data-id="${it.id}">
      <label>Заголовок <input data-f="title" maxlength="70" value="${esc(L.title)}"></label>
      <label>Цена, ₸ <input data-f="price" type="number" value="${esc(L.price)}"></label>
      <label>Описание <textarea data-f="description" rows="7">${esc(L.description)}</textarea></label>
      <div class="actions"><button data-a="save">Сохранить</button><button data-a="cancel">Отмена</button></div>
    </div>`;
  }
  const title = L ? esc(L.title) : `Товар ${esc(it.id)}`;
  const meta = [
    `<span class="pill ${it.status}">${STATUS[it.status] || it.status}</span>`,
    L ? `${L.price} ₸` : '',
    L ? esc((L.category_path || []).join(' › ')) : '',
    `${it.photos.length} фото`,
    it.note ? `«${esc(it.note)}»` : '',
  ].filter(Boolean).join(' · ');
  const actions = [];
  if (it.status === 'ready') actions.push('<button data-a="post">Подать сейчас</button>', '<button data-a="edit">Править</button>');
  if (it.status === 'posting') actions.push('<button data-a="stop">Остановить</button>');
  if (['failed', 'needs_user'].includes(it.status)) actions.push('<button data-a="retry">Повторить</button>');
  if (L && ['ready', 'failed', 'needs_user'].includes(it.status)) actions.push('<button data-a="redescribe">Описать заново</button>');
  if (it.olxUrl) actions.push('<button data-a="open">Открыть на OLX</button>');
  if (!['posting', 'describing'].includes(it.status)) actions.push('<button data-a="remove">Удалить</button>');
  return `<div class="item" data-id="${it.id}">
    <img src="${esc(it.photoUrls[0])}" alt="">
    <div>
      <div class="title">${title}</div>
      <div class="meta">${meta}</div>
      ${L && L.warning ? `<div class="warn">⚠ ${esc(L.warning)}</div>` : ''}
      ${it.error ? `<div class="err">${esc(it.error)}</div>` : ''}
      <div class="actions">${actions.join('')}</div>
    </div>
  </div>`;
}

$('items').addEventListener('click', async (e) => {
  const a = e.target.dataset.a;
  if (!a) return;
  const card = e.target.closest('.item');
  const id = card.dataset.id;
  const it = S.items.find((x) => x.id === id);
  switch (a) {
    case 'post': api.postNow(id); break;
    case 'stop': api.stopCurrent(); break;
    case 'retry': api.retry(id); break;
    case 'redescribe': api.redescribe(id); break;
    case 'open': api.openOlx(it.olxUrl); break;
    case 'remove': if (confirm('Удалить товар из очереди?')) api.remove(id); break;
    case 'edit': editing.add(id); render(); break;
    case 'cancel': editing.delete(id); render(); break;
    case 'save': {
      const patch = {};
      card.querySelectorAll('[data-f]').forEach((el) => { patch[el.dataset.f] = el.value; });
      editing.delete(id);
      await api.edit(id, patch);
      break;
    }
  }
});

$('run').onclick = () => api.run(!S.settings.running);

document.querySelectorAll('nav button').forEach((b) => {
  b.onclick = async () => {
    document.querySelectorAll('nav button, .tab').forEach((x) => x.classList.remove('on'));
    b.classList.add('on');
    $('tab-' + b.dataset.tab).classList.add('on');
    if (b.dataset.tab === 'settings') {
      fillSettings();
      $('notes').textContent = (await api.readNotes()) || 'Пока пусто — заметки появятся после первых подач.';
    }
  };
});

// ---------- настройки ----------

function fillSettings() {
  const f = $('settings');
  for (const el of f.elements) {
    if (el.name && el.name in S.settings) el.value = S.settings[el.name];
  }
  $('key').value = '';
  $('key').placeholder = S.hasKey ? 'ключ сохранён — введите новый, чтобы заменить' : 'sk-ant-…';
}

$('settings').onsubmit = async (e) => {
  e.preventDefault();
  const patch = {};
  for (const el of e.target.elements) if (el.name) patch[el.name] = el.value;
  await api.saveSettings(patch);
  if ($('key').value.trim()) await api.setKey($('key').value.trim());
  $('saved').textContent = 'Сохранено';
  setTimeout(() => { $('saved').textContent = ''; }, 2000);
  fillSettings();
};
$('inbox-choose').onclick = () => api.chooseInbox();
$('inbox-open').onclick = () => api.openInbox();

// ---------- перетаскивание ----------

const drop = $('drop');
['dragenter', 'dragover'].forEach((t) => document.addEventListener(t, (e) => { e.preventDefault(); drop.classList.add('over'); }));
['dragleave', 'drop'].forEach((t) => document.addEventListener(t, (e) => { e.preventDefault(); if (t === 'drop' || !e.relatedTarget) drop.classList.remove('over'); }));
document.addEventListener('drop', (e) => { if (e.dataTransfer.files.length) api.addFiles(e.dataTransfer.files); });

// ---------- журнал ----------

function appendLog(line) {
  const el = $('log');
  el.textContent += line + '\n';
  if (el.textContent.length > 60000) el.textContent = el.textContent.slice(-50000);
  el.scrollTop = el.scrollHeight;
}

api.onLog(appendLog);
api.onState((s) => { S = s; render(); });
api.state().then((s) => {
  S = s;
  $('log').textContent = s.log.join('\n') + (s.log.length ? '\n' : '');
  render();
  if (!s.hasKey) document.querySelector('nav button[data-tab=settings]').click();
});
