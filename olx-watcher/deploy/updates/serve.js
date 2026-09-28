// Раздаёт обновления ПК-программы из папки www: http://<IP сервера>:PORT/
// Только чтение, только файлы из www, без вложенных папок. Главная страница — ссылка на установщик.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const WWW = process.env.WWW || path.join(__dirname, '..', 'www');
const PORT = Number(process.env.PORT) || 8787;
const TYPES = { '.yml': 'text/yaml; charset=utf-8', '.exe': 'application/octet-stream', '.blockmap': 'application/octet-stream' };

function latestExe() {
  try {
    const yml = fs.readFileSync(path.join(WWW, 'latest.yml'), 'utf8');
    return { file: /^path:\s*(.+)$/m.exec(yml)?.[1].trim(), version: /^version:\s*(.+)$/m.exec(yml)?.[1].trim() };
  } catch { return {}; }
}

http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405).end(); return; }
  let name;
  try { name = decodeURIComponent(new URL(req.url, 'http://x').pathname.slice(1)); } catch { res.writeHead(400).end(); return; }
  if (name === '') {
    const { file, version } = latestExe();
    const body = file
      ? `<!doctype html><meta charset="utf-8"><title>OLX Watcher</title><body style="font:16px system-ui;padding:24px">
<h2>OLX Watcher ${version}</h2><p><a href="/${encodeURIComponent(file)}">Скачать установщик для Windows</a></p>
<p>Уже установленная программа обновляется сама.</p>`
      : '<!doctype html><meta charset="utf-8"><body style="font:16px system-ui;padding:24px">Первая сборка ещё идёт — загляните через 10–15 минут.';
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(req.method === 'HEAD' ? undefined : body);
    return;
  }
  if (name.includes('/') || name.includes('\\') || name.startsWith('.')) { res.writeHead(404).end(); return; }
  const file = path.join(WWW, name);
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404).end(); return; }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(name)] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': name === 'latest.yml' ? 'no-cache' : 'public, max-age=86400',
    });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(file).pipe(res);
  });
}).listen(PORT, () => console.log(`Обновления: http://0.0.0.0:${PORT}/ из ${WWW}`));
