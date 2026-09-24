// Прогон «рук» робота на локальной копии формы: electron test/smoke-page-tools.js (нужен дисплей / xvfb-run).
const path = require('path');
const assert = require('assert');
const { app, BrowserWindow, nativeImage } = require('electron');
const { PageTools } = require('../src/page-tools');

app.whenReady().then(async () => {
  try {
    const win = new BrowserWindow({ width: 1000, height: 900, show: true });
    await win.loadFile(path.join(__dirname, 'fixture-form.html'));
    const page = new PageTools(win.webContents);
    const find = (snap, re) => Number(snap.split('\n').find((l) => re.test(l)).match(/^\[(\d+)\]/)[1]);

    let snap = await page.snapshot();
    console.log(snap);
    const photo = path.join(app.getPath('temp'), 'olx-smoke.png');
    require('fs').writeFileSync(photo, nativeImage.createFromDataURL('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==').toPNG());
    await page.uploadFiles(find(snap, /input:file/), [photo, photo]);
    await page.type(find(snap, /label="Название"/), 'Кроссовки Nike Air Max 42');
    await page.type(find(snap, /label="Описание"/), 'Носил месяц.\nЕсть коробка.');
    await page.type(find(snap, /label="Цена"/), '15000');
    await page.selectOption(find(snap, /select/), 'Б/у');
    await page.click(find(snap, /role=combobox/));
    snap = await page.snapshot();
    await page.click(find(snap, /role=option "Мода и стиль"/));
    const r = await win.webContents.executeJavaScript('window.__result()');
    console.log(r);
    assert.strictEqual(r.typed.title, 'Кроссовки Nike Air Max 42');
    assert.strictEqual(r.typed.price, '15000');
    assert.ok(r.typed.desc.includes('коробка'));
    assert.strictEqual(r.cat, 'Мода и стиль');
    assert.strictEqual(r.cond, 'used');
    assert.strictEqual(r.photos, 2);
    snap = await page.snapshot();
    await page.click(find(snap, /"Опубликовать"/));
    snap = await page.snapshot();
    assert.ok(/Объявление отправлено/.test(snap));
    const shot = await page.screenshot();
    assert.ok(shot.length > 1000);
    console.log('SMOKE OK');
    app.exit(0);
  } catch (e) {
    console.error('SMOKE FAIL', e);
    app.exit(1);
  }
});
