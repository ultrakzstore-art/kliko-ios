#!/usr/bin/env bash
# Сборка обновления ПК-программы (служба olx-updates-build, раз в 10 минут, от olxbuild).
# Берёт свежий код ветки с GitHub; если он новее собранного — проверки, тесты, установщик
# Windows, и кладёт его в www (latest.yml — последним, чтобы программа не увидела половину).
set -euo pipefail
BASE=/opt/olx-watcher-updates
SRC="$BASE/src"
BRANCH="$(cat "$BASE/branch")"
REPO="$(cat "$BASE/repo")"
export PATH="$(cat "$BASE/node-dir"):$PATH"
export HOME="$BASE/home"
export ELECTRON_SKIP_BINARY_DOWNLOAD=1   # Electron для Linux не нужен — для Windows его скачает сборщик

auth="Authorization: Basic $(printf 'x-access-token:%s' "$(cat "$BASE/.token")" | base64 -w0)"
cd "$SRC"
git -c http.extraHeader="$auth" fetch -q --depth 1 "$REPO" "$BRANCH"
new="$(git rev-parse FETCH_HEAD)"
if [ "$new" = "$(cat "$BASE/last-built" 2>/dev/null || true)" ]; then exit 0; fi
git checkout -q -f FETCH_HEAD

n=$(( $(cat "$BASE/build-no" 2>/dev/null || echo 0) + 1 ))
version="1.0.$(( 200 + n ))"   # выше всех версий, что выходили через GitHub (последняя — 1.0.63)
echo "== Собираю $version из $(git log -1 --format='%h %s')"

cd olx-watcher
rm -rf dist
npm ci --no-audit --no-fund
npm run check
npm test
APP_VERSION="$version" node ci/build-win.js
git checkout -q -- package.json

cp dist/*.exe dist/*.blockmap "$BASE/www/"
cp dist/latest.yml "$BASE/www/latest.yml.tmp" && mv "$BASE/www/latest.yml.tmp" "$BASE/www/latest.yml"
# Храним две последние версии.
ls -t "$BASE"/www/*.exe | tail -n +3 | while read -r f; do rm -f "$f" "$f.blockmap"; done
rm -rf dist

echo "$n" > "$BASE/build-no"
echo "$new" > "$BASE/last-built"
echo "== Готово: $version"
