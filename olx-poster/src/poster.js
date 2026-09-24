// Робот-подача: Claude смотрит на страницу OLX (список элементов, при нужде — скриншот)
// и заполняет форму подачи инструментами из page-tools. Форму OLX заранее не зашиваем в код —
// она меняется; вместо этого робот копит заметки о том, что сработало (olx-notes.txt).

const Anthropic = require('@anthropic-ai/sdk');
const { estimateCost } = require('./describe');

const START_URL = 'https://www.olx.kz/d/post-new-ad/';
const MAX_STEPS = 70;

const TOOLS = [
  {
    name: 'snapshot',
    description: 'Список видимых интерактивных элементов текущей страницы с номерами [id], плюс URL, заголовки и сообщения об ошибках. Вызывай после каждого действия, которое меняет страницу.',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'screenshot',
    description: 'Скриншот видимой части страницы. Нужен, когда по списку элементов непонятно, что на экране (всплывающие окна, выбор рубрики картинками, капча).',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'click',
    description: 'Клик мышью по элементу [id] из последнего snapshot.',
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'], additionalProperties: false },
  },
  {
    name: 'type',
    description: 'Клик в поле [id] и ввод текста с клавиатуры (старое значение стирается). enter=true — нажать Enter после ввода.',
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer' }, text: { type: 'string' }, enter: { type: 'boolean' } },
      required: ['id', 'text'],
      additionalProperties: false,
    },
  },
  {
    name: 'press',
    description: 'Нажать клавишу: Enter, Tab, Escape, Down, Up, Backspace.',
    input_schema: { type: 'object', properties: { key: { type: 'string', enum: ['Enter', 'Tab', 'Escape', 'Down', 'Up', 'Backspace'] } }, required: ['key'], additionalProperties: false },
  },
  {
    name: 'select_option',
    description: 'Выбрать вариант в обычном <select> [id] по тексту варианта. Для самодельных выпадающих списков OLX используй click.',
    input_schema: { type: 'object', properties: { id: { type: 'integer' }, option: { type: 'string' } }, required: ['id', 'option'], additionalProperties: false },
  },
  {
    name: 'upload_photos',
    description: 'Загрузить все фото товара в поле input:file [id]. Вызывай один раз.',
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'], additionalProperties: false },
  },
  {
    name: 'scroll',
    description: 'Прокрутить страницу вверх или вниз на экран.',
    input_schema: { type: 'object', properties: { direction: { type: 'string', enum: ['up', 'down'] } }, required: ['direction'], additionalProperties: false },
  },
  {
    name: 'navigate',
    description: 'Открыть адрес на olx.kz.',
    input_schema: { type: 'object', properties: { url: { type: 'string' } }, required: ['url'], additionalProperties: false },
  },
  {
    name: 'wait',
    description: 'Подождать загрузки, секунд (1–10).',
    input_schema: { type: 'object', properties: { seconds: { type: 'integer', minimum: 1, maximum: 10 } }, required: ['seconds'], additionalProperties: false },
  },
  {
    name: 'save_note',
    description: 'Сохранить короткий совет себе на будущие подачи: как устроена форма OLX, что сработало, где подвох. Одна мысль — одна заметка, до 200 символов.',
    input_schema: { type: 'object', properties: { note: { type: 'string' } }, required: ['note'], additionalProperties: false },
  },
  {
    name: 'finish',
    description: 'Закончить работу. status: published — объявление отправлено (OLX показал подтверждение); needs_user — нужен человек (вход в аккаунт, капча, SMS-код, подтверждение); failed — не получилось по другой причине.',
    input_schema: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['published', 'needs_user', 'failed'] },
        reason: { type: 'string', description: 'Для needs_user и failed — что случилось, по-русски, одной фразой.' },
        ad_url: { type: 'string', description: 'Ссылка на объявление, если видна.' },
      },
      required: ['status'],
      additionalProperties: false,
    },
  },
];

function systemPrompt(settings, notes) {
  return `Ты подаёшь объявление на OLX.kz от имени продавца в его уже открытом браузере. Продавец сам вошёл в свой аккаунт и поручил тебе подачу.

Как работать:
- Начни со snapshot. Если по адресу не форма подачи (ошибка, главная страница) — найди и нажми «Подать объявление».
- После каждого действия, которое меняет страницу, снова snapshot — номера [id] меняются.
- Заполни всё, что есть в черновике: фото, заголовок, рубрику, описание, цену, состояние, параметры рубрики, местоположение, контакты. Обязательные поля OLX, которых нет в черновике, заполни разумно по фото и описанию.
- Рубрику OLX обычно предлагает сам после ввода заголовка или ищет по слову — выбирай ближайшую к category_path.
- Если поле не заполняется — посмотри screenshot, попробуй другой способ (клик по подсказке в списке, Enter, Tab).
- Перед отправкой проверь форму на ошибки валидации (snapshot → «Сообщения/ошибки»).
- Когда всё заполнено — нажми кнопку публикации («Опубликовать», «Разместить объявление»). Продавец просил публиковать сразу, без его проверки.
- Публикация считается успешной, только когда OLX показал подтверждение (объявление отправлено/на модерации/опубликовано).

Нельзя:
- Платить и выбирать платные услуги: пакеты, «Топ», «VIP», поднятия, продвижение. Если OLX предлагает продвижение после подачи — откажись («Без продвижения», «Пропустить», закрыть). Если без оплаты подать нельзя (лимит бесплатных объявлений исчерпан) — finish со status=failed и reason, где будет слово «лимит».
- Вводить пароли и коды из SMS, решать капчи, менять настройки аккаунта, удалять или редактировать другие объявления. Если OLX просит вход, код или капчу — finish со status=needs_user.
- Уходить с olx.kz.

Данные продавца: город/район — ${settings.city}${settings.contactName ? `, имя — ${settings.contactName}` : ''}${settings.phone ? `, телефон — ${settings.phone}` : ''}.
${notes ? `\nТвои заметки с прошлых подач (могли устареть — доверяй тому, что видишь на странице):\n${notes}` : ''}
Когда заметишь что-то полезное про форму OLX, чего нет в заметках, — save_note.`;
}

async function postItem({ apiKey, settings, item, page, notes, onNote, log, shouldStop }) {
  const client = new Anthropic({ apiKey });
  const L = item.listing;
  const draft = {
    title: L.title,
    description: L.description,
    category_path: L.category_path,
    category_query: L.category_query,
    price_kzt: L.price,
    condition: L.condition === 'new' ? 'Новое' : 'Б/у',
    attributes: L.attributes,
    photos: item.photos.length,
  };

  await page.navigate(START_URL);
  const messages = [{
    role: 'user',
    content: `Подай это объявление. Форма подачи уже открыта (${START_URL}).\n\nЧерновик:\n${JSON.stringify(draft, null, 2)}`,
  }];

  let cost = 0;
  for (let step = 0; step < MAX_STEPS; step++) {
    if (shouldStop()) return { status: 'failed', reason: 'остановлено вручную', cost };

    const response = await client.beta.messages.create({
      model: settings.model,
      max_tokens: 16000,
      betas: ['server-side-fallback-2026-07-01', 'context-management-2025-06-27'],
      fallbacks: 'default',
      thinking: { type: 'adaptive' },
      output_config: { effort: settings.effort },
      // Старые снимки страницы и скриншоты больше не нужны — сервер вычищает их из контекста.
      context_management: {
        edits: [{ type: 'clear_tool_uses_20250919', trigger: { type: 'input_tokens', value: 40000 }, keep: { type: 'tool_uses', value: 6 } }],
      },
      cache_control: { type: 'ephemeral' },
      system: systemPrompt(settings, notes),
      tools: TOOLS,
      messages,
    });
    cost += estimateCost(settings.model, response.usage);

    if (response.stop_reason === 'refusal') return { status: 'failed', reason: 'Claude отказался продолжать', cost };
    messages.push({ role: 'assistant', content: response.content });

    const calls = response.content.filter((b) => b.type === 'tool_use');
    if (!calls.length) {
      if (response.stop_reason === 'pause_turn') continue;
      messages.push({ role: 'user', content: 'Продолжай. Когда закончишь — вызови finish.' });
      continue;
    }

    const results = [];
    let finished = null;
    for (const call of calls) {
      const input = call.input || {};
      if (call.name === 'finish') {
        finished = { status: input.status, reason: input.reason || '', adUrl: input.ad_url || '' };
        results.push({ type: 'tool_result', tool_use_id: call.id, content: 'ok' });
        continue;
      }
      try {
        const out = await runTool(call.name, input, { page, item, onNote });
        results.push({ type: 'tool_result', tool_use_id: call.id, content: out });
        if (call.name !== 'snapshot' && call.name !== 'screenshot') log(`  · ${call.name} ${short(input)}`);
      } catch (e) {
        results.push({ type: 'tool_result', tool_use_id: call.id, content: `Ошибка: ${e.message}`, is_error: true });
        log(`  · ${call.name} ${short(input)} — ошибка: ${e.message}`);
      }
    }
    messages.push({ role: 'user', content: results });

    if (finished) {
      if (finished.status === 'published' && !finished.adUrl) finished.adUrl = page.wc.getURL();
      return { ...finished, cost };
    }
  }
  return { status: 'failed', reason: `не уложился в ${MAX_STEPS} шагов`, cost };
}

async function runTool(name, input, { page, item, onNote }) {
  switch (name) {
    case 'snapshot':
      return await page.snapshot();
    case 'screenshot':
      return [{ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: await page.screenshot() } }];
    case 'click':
      await page.click(input.id);
      return 'ok';
    case 'type':
      await page.type(input.id, input.text, { enter: !!input.enter });
      return 'ok';
    case 'press':
      await page.key(input.key);
      return 'ok';
    case 'select_option':
      await page.selectOption(input.id, input.option);
      return 'ok';
    case 'upload_photos':
      await page.uploadFiles(input.id, item.photos);
      return `Загружено фото: ${item.photos.length}. Сделай snapshot и проверь, что превью появились.`;
    case 'scroll':
      await page.scroll(input.direction);
      return 'ok';
    case 'navigate':
      await page.navigate(input.url);
      return 'ok';
    case 'wait':
      await new Promise((r) => setTimeout(r, Math.min(10, Math.max(1, input.seconds || 2)) * 1000));
      return 'ok';
    case 'save_note':
      onNote(String(input.note || '').slice(0, 200));
      return 'Сохранено';
    default:
      throw new Error(`Неизвестный инструмент ${name}`);
  }
}

function short(input) {
  const s = JSON.stringify(input);
  return s.length > 90 ? s.slice(0, 87) + '…' : s;
}

module.exports = { postItem, START_URL };
