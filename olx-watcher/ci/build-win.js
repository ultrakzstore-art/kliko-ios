// Установщик Windows на Linux (сервер обновлений): node ci/build-win.js
// APP_VERSION — версия сборки (иначе из package.json).
// Wine нужен только чтобы вписать иконку и описание в .exe: 32-битный NSIS не запускаем —
// деинсталлятор достаём из установщика без Wine (так electron-builder делает на новых macOS).
// Нет Wine — сборка всё равно выйдет, со стандартной иконкой Electron.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
process.chdir(root);

if (process.env.APP_VERSION) {
  const file = path.join(root, 'package.json');
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
  pkg.version = process.env.APP_VERSION;
  fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
}

process.env.WINEDEBUG = '-all';
const works = () => spawnSync('wine', ['--version'], { encoding: 'utf8' }).status === 0;
let wine = works();
if (!wine && fs.existsSync('/usr/lib/wine/wine64')) {
  // Ubuntu ставит 64-битный Wine без команды «wine» — подкладываем свою.
  const shim = path.join(os.tmpdir(), `olx-wine-shim-${process.getuid()}`);
  fs.mkdirSync(shim, { recursive: true });
  for (const [name, target] of [['wine', 'wine64'], ['wineserver', 'wineserver64']]) {
    const link = path.join(shim, name);
    try { fs.unlinkSync(link); } catch { /* не было */ }
    fs.symlinkSync(path.join('/usr/lib/wine', target), link);
  }
  process.env.PATH = `${shim}:${process.env.PATH}`;
  process.env.WINELOADER = '/usr/lib/wine/wine64';
  wine = works();
}
if (!wine) console.warn('Wine не найден — .exe будет со стандартной иконкой Electron');

require('app-builder-lib/out/util/macosVersion').isMacOsCatalina = () => true;
const { build, Platform, Arch } = require('electron-builder');
build({
  targets: Platform.WINDOWS.createTarget('nsis', Arch.x64),
  publish: 'never',
  config: {
    ...(wine ? {} : { win: { signAndEditExecutable: false } }),
    // Максимальное сжатие 7z берёт под гигабайт памяти — на маленьком сервере это отнимет её у бота.
    ...(os.totalmem() < 3 * 1024 ** 3 ? { compression: 'normal' } : {}),
  },
}).then((files) => {
  console.log('Готово:', files.map((f) => path.basename(f)).join(', '));
}).catch((e) => {
  console.error('Сборка не удалась:', e.message);
  process.exit(1);
});
