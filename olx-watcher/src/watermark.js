// Водяной знак на фото объявления: полупрозрачная плашка в правом нижнем углу с именем бота
// (например «@olx_new_kz_bot») и бирюзовой полоской слева. Маленькая — товар не закрывает.
// Чистый JavaScript (Jimp), без нативных модулей — работает и в приложении для ПК.

const { Jimp, loadFont, measureText, measureTextHeight } = require('jimp');
const fonts = require('jimp/fonts');

const ACCENT = 0x009e94ff;   // бирюзовый, как иконка приложения
const BACK = 0x000000a0;     // чёрный, ~63% непрозрачности

const fontCache = new Map();
function font(size) {
  if (!fontCache.has(size)) fontCache.set(size, loadFont(fonts[`SANS_${size}_WHITE`]));
  return fontCache.get(size);
}

// Буфер JPEG/PNG → JPEG с водяным знаком. Ошибка — вернём исходник, фото важнее знака.
async function watermark(buffer, text) {
  if (!text) return buffer;
  try {
    const img = await Jimp.read(buffer);
    const { width: w, height: h } = img.bitmap;
    if (w < 200 || h < 120) return buffer;
    const size = w >= 900 ? 32 : 16;
    const f = await font(size);
    const tw = measureText(f, text);
    const th = measureTextHeight(f, text, tw + 10);
    const padX = Math.round(size * 0.55);
    const padY = Math.round(size * 0.3);
    const bar = Math.max(3, Math.round(size / 8));
    const bw = tw + padX * 2 + bar;
    const bh = th + padY * 2;
    const margin = Math.round(Math.min(w, h) * 0.025);
    const x = w - bw - margin;
    const y = h - bh - margin;
    if (x < 0 || y < 0) return buffer;

    const pill = new Jimp({ width: bw, height: bh, color: BACK });
    pill.composite(new Jimp({ width: bar, height: bh, color: ACCENT }), 0, 0);
    roundCorners(pill, Math.round(bh / 4));
    img.composite(pill, x, y);
    img.print({ font: f, x: x + bar + padX, y: y + padY, text });
    return await img.getBuffer('image/jpeg', { quality: 86 });
  } catch {
    return buffer;
  }
}

function roundCorners(img, r) {
  const { width: w, height: h, data } = img.bitmap;
  for (let yy = 0; yy < r; yy++) {
    for (let xx = 0; xx < r; xx++) {
      if ((r - xx - 0.5) ** 2 + (r - yy - 0.5) ** 2 <= r * r) continue;
      for (const [px, py] of [[xx, yy], [w - 1 - xx, yy], [xx, h - 1 - yy], [w - 1 - xx, h - 1 - yy]]) {
        data[(py * w + px) * 4 + 3] = 0;
      }
    }
  }
}

async function fetchImage(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`фото ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

module.exports = { watermark, fetchImage };
