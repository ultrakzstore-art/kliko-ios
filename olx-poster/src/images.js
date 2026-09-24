// Фото для Claude: ужимаем до 1568 px по длинной стороне (больше модель всё равно не смотрит) и в JPEG.
// Для раскладки пачки хватает и 640 px — так сотня кадров влезает в один запрос дёшево.

const { nativeImage } = require('electron');

function imageForClaude(file, maxSide = 1568) {
  let img = nativeImage.createFromPath(file);
  if (img.isEmpty()) {
    throw new Error(`Не открывается фото ${file}. Если это HEIC с iPhone — включите «Настройки → Камера → Форматы → Наиболее совместимый» или шлите фото через страницу для телефона.`);
  }
  const { width, height } = img.getSize();
  const k = maxSide / Math.max(width, height);
  if (k < 1) img = img.resize({ width: Math.round(width * k), height: Math.round(height * k), quality: 'good' });
  return {
    type: 'image',
    source: { type: 'base64', media_type: 'image/jpeg', data: img.toJPEG(85).toString('base64') },
  };
}

module.exports = { imageForClaude };
