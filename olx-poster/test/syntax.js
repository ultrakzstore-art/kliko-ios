// node --check для каждого .js в src/ (глобы в npm-скриптах на Windows не раскрываются).
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const files = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.js')) files.push(p);
  }
})(path.join(__dirname, '..', 'src'));

let failed = false;
for (const f of files) {
  const r = spawnSync(process.execPath, ['--check', f], { encoding: 'utf8' });
  if (r.status !== 0) { failed = true; console.error(r.stderr); }
}
console.log(`syntax: ${files.length} files${failed ? ' — FAILED' : ' ok'}`);
process.exit(failed ? 1 : 0);
