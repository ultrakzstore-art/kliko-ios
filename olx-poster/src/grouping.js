// Куча фото разом → раскладка по товарам. Claude смотрит на уменьшенные копии всех кадров
// и говорит, какие из них — один и тот же товар (общий вид, бирка, характеристики, дефекты).

const Anthropic = require('@anthropic-ai/sdk');
const { imageForClaude } = require('./images');
const { estimateCost } = require('./describe');

const MAX_PER_ITEM = 8;   // столько фото OLX принимает в одно объявление
const MAX_PER_CALL = 80;  // больше за раз не шлём — крупную пачку режем на куски

const GROUPS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['items'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['photos', 'what'],
        properties: {
          photos: { type: 'array', items: { type: 'integer' }, description: 'Номера фото этого товара; первым — лучший общий вид (он станет обложкой).' },
          what: { type: 'string', description: 'Что за товар, 2–5 слов.' },
        },
      },
    },
  },
};

const SYSTEM = `Продавец сфотографировал подряд несколько товаров для OLX и скинул все фото одной пачкой.
Разложи фото по товарам: один товар — одно объявление. Фото одного товара — это общий вид с разных сторон, бирки, ярлыки, шильдики, экран с характеристиками, коробка, крупные планы дефектов.
Фото обычно идут подряд по товарам, но не всегда. Одинаковые на вид вещи разного размера или цвета — разные товары, если на фото это видно.
Каждое фото — ровно в одном товаре. Первым в списке ставь лучший общий вид товара.`;

async function groupPhotos({ apiKey, settings, photos, log }) {
  const out = [];
  let cost = 0;
  for (let start = 0; start < photos.length; start += MAX_PER_CALL) {
    const chunk = photos.slice(start, start + MAX_PER_CALL);
    const r = await groupChunk({ apiKey, settings, photos: chunk });
    cost += r.cost;
    out.push(...r.groups);
  }
  if (log) log(`Claude разложил ${photos.length} фото на ${out.length} товаров`);
  return { groups: out, cost };
}

async function groupChunk({ apiKey, settings, photos }) {
  if (photos.length === 1) return { groups: [{ photos, what: '' }], cost: 0 };
  const client = new Anthropic({ apiKey });
  const content = [];
  photos.forEach((p, i) => {
    content.push({ type: 'text', text: `Фото ${i + 1}:` });
    content.push(imageForClaude(p, 640));
  });
  content.push({ type: 'text', text: `Всего фото: ${photos.length}. Разложи их по товарам.` });

  const response = await client.beta.messages.create({
    model: settings.model,
    max_tokens: 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    thinking: { type: 'adaptive' },
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: GROUPS_SCHEMA } },
    system: SYSTEM,
    messages: [{ role: 'user', content }],
  });
  if (response.stop_reason === 'refusal') throw new Error('Claude отказался разбирать фото');
  if (response.stop_reason === 'max_tokens') throw new Error('Ответ Claude оборвался');
  const text = response.content.find((b) => b.type === 'text');
  if (!text) throw new Error('Claude не вернул раскладку');
  const groups = normalize(JSON.parse(text.text).items, photos);
  return { groups, cost: estimateCost(settings.model, response.usage) };
}

// Страховка от ошибок модели: номера вне диапазона и повторы выкидываем, забытые фото —
// отдельными товарами, слишком большие группы режем по 8 (лимит OLX).
function normalize(items, photos) {
  const used = new Set();
  const groups = [];
  for (const it of items || []) {
    const idx = [...new Set(it.photos || [])]
      .map((n) => n - 1)
      .filter((i) => Number.isInteger(i) && i >= 0 && i < photos.length && !used.has(i));
    idx.forEach((i) => used.add(i));
    for (let k = 0; k < idx.length; k += MAX_PER_ITEM) {
      groups.push({ photos: idx.slice(k, k + MAX_PER_ITEM).map((i) => photos[i]), what: it.what || '' });
    }
  }
  photos.forEach((p, i) => { if (!used.has(i)) groups.push({ photos: [p], what: '' }); });
  return groups;
}

module.exports = { groupPhotos, normalize, GROUPS_SCHEMA, MAX_PER_ITEM };
