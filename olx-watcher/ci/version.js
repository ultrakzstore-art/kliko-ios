// Версия сборки Codemagic: 1.0.<100 + номер сборки>. Сотня сверху — чтобы номера шли
// дальше сборок GitHub Actions (последняя — 1.0.63): иначе приложение не увидит обновление.
const fs = require('node:fs');
const path = require('node:path');

const n = Number(process.env.BUILD_NUMBER);
if (!Number.isInteger(n) || n < 1) throw new Error('BUILD_NUMBER не задан: ' + process.env.BUILD_NUMBER);
const file = path.join(__dirname, '..', 'package.json');
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
pkg.version = '1.0.' + (100 + n);
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + '\n');
console.log('Версия', pkg.version);
