// Фото товара → черновик объявления для OLX.kz (один запрос к Claude со структурированным ответом).

const Anthropic = require('@anthropic-ai/sdk');
const { imageForClaude } = require('./images');

const LISTING_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'description', 'category_path', 'category_query', 'price', 'condition', 'attributes', 'confidence', 'warning'],
  properties: {
    title: { type: 'string', description: 'Заголовок для OLX, до 70 символов: что это, бренд/модель, ключевой параметр (размер, память). Без КАПСА и эмодзи.' },
    description: { type: 'string', description: 'Описание 300–900 символов на русском: что за вещь, состояние и дефекты, что в комплекте, размеры. Без выдуманных фактов.' },
    category_path: { type: 'array', items: { type: 'string' }, description: 'Путь рубрики OLX.kz сверху вниз, как на сайте, напр. ["Мода и стиль", "Мужская обувь", "Кроссовки"].' },
    category_query: { type: 'string', description: 'Короткий запрос для поиска рубрики в форме OLX, 1–3 слова, напр. «кроссовки».' },
    price: { type: 'integer', description: 'Цена в тенге, круглое число.' },
    condition: { type: 'string', enum: ['new', 'used'] },
    attributes: {
      type: 'array',
      description: 'Параметры, которые OLX обычно спрашивает в этой рубрике: бренд, размер, цвет, модель, память, марка авто, номер детали и т.п. Только то, что видно на фото или сказано в подсказке.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'value'],
        properties: { name: { type: 'string' }, value: { type: 'string' } },
      },
    },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'], description: 'Насколько уверенно опознан товар.' },
    warning: { type: 'string', description: 'Пусто, если всё хорошо. Иначе коротко: что проверить человеку (не видно модель, возможно подделка, товар запрещён на OLX и т.п.).' },
  },
};

const SYSTEM = `Ты готовишь объявления для OLX.kz (Казахстан) по фотографиям товара продавца.
По фото определи, что это за вещь, и напиши объявление, которое продаёт: ясный заголовок с брендом и моделью, честное описание с дефектами, правильную рубрику OLX.kz.
Бренд, модель, размер читай с бирок, коробок, шильдиков и экранов на фото. Если не видно — не выдумывай, опиши по внешнему виду и отметь в warning.
Для автозапчастей укажи марку/модель авто и номер детали, если он виден. Для электроники — модель, память, состояние экрана и корпуса. Для одежды и обуви — бренд, размер, цвет, материал.
Цена — в тенге (₸).`;

async function describeItem({ apiKey, settings, item }) {
  const client = new Anthropic({ apiKey });
  const content = [];
  for (const p of item.photos.slice(0, 8)) content.push(imageForClaude(p));

  const hints = [];
  if (item.note) hints.push(`Подсказка продавца: ${item.note}`);
  if (item.price) hints.push(`Цену назначил продавец: ${item.price} ₸ — используй её.`);
  else hints.push(`Цену предложи сам. Правило продавца: ${settings.priceHint}`);
  if (settings.extraRules) hints.push(`Правила продавца для текста: ${settings.extraRules}`);
  hints.push(`Город продажи: ${settings.city}.`);
  content.push({ type: 'text', text: hints.join('\n') });

  const response = await client.beta.messages.create({
    model: settings.model,
    max_tokens: 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    thinking: { type: 'adaptive' },
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: LISTING_SCHEMA } },
    system: SYSTEM,
    messages: [{ role: 'user', content }],
  });

  if (response.stop_reason === 'refusal') throw new Error('Claude отказался описывать этот товар');
  if (response.stop_reason === 'max_tokens') throw new Error('Ответ Claude оборвался — попробуйте ещё раз');
  const text = response.content.find((b) => b.type === 'text');
  if (!text) throw new Error('Claude не вернул текст объявления');
  const listing = JSON.parse(text.text);
  if (item.price) listing.price = item.price;
  listing.title = listing.title.slice(0, 70);
  return { listing, costUsd: estimateCost(settings.model, response.usage) };
}

// Грубая оценка цены запроса — для счётчика в интерфейсе, не для бухгалтерии.
const PRICES = {
  'claude-opus-5': [5, 25],
  'claude-sonnet-5': [2, 10],
  'claude-haiku-4-5': [1, 5],
};

function estimateCost(model, usage) {
  if (!usage) return 0;
  const [inp, out] = PRICES[model] || PRICES['claude-opus-5'];
  const read = usage.cache_read_input_tokens || 0;
  const write = usage.cache_creation_input_tokens || 0;
  return ((usage.input_tokens || 0) * inp + write * inp * 1.25 + read * inp * 0.1 + (usage.output_tokens || 0) * out) / 1e6;
}

module.exports = { describeItem, estimateCost, LISTING_SCHEMA };
