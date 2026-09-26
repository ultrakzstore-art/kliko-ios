#!/usr/bin/env bash
# Установка бота на VPS (Linux x64 / arm64), от root:  bash deploy/install.sh
# Всё — только в папке бота: свой Node.js 22 в .node/ (системный Node и другие программы на
# сервере не трогаем), зависимости в node_modules/, данные в data/. Ничего не удаляет.
# Служба systemd «olx-watcher»: бот работает круглосуточно и сам поднимается после сбоя или
# перезагрузки. Портов не занимает. Повторный запуск безопасен — это и есть обновление.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root: sudo bash deploy/install.sh"; exit 1; fi

# Node.js: системный, если он 22+, иначе — свой в .node/ (скачиваем с nodejs.org).
NODE="$(command -v node || true)"
if [ -z "$NODE" ] || [ "$("$NODE" -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  NODE="$DIR/.node/bin/node"
  if [ ! -x "$NODE" ]; then
    case "$(uname -m)" in
      x86_64|amd64) ARCH=x64 ;;
      aarch64|arm64) ARCH=arm64 ;;
      *) echo "Неизвестный процессор: $(uname -m)"; exit 1 ;;
    esac
    echo "== Скачиваю Node.js 22 в $DIR/.node (системный Node не меняю)"
    get() { if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"; else wget -qO- "$1"; fi; }
    FILE="$(get https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | grep -o "node-v22[^ ]*-linux-$ARCH.tar.xz" | head -1)"
    [ -n "$FILE" ] || { echo "Не удалось найти Node.js 22 на nodejs.org"; exit 1; }
    mkdir -p .node
    get "https://nodejs.org/dist/latest-v22.x/$FILE" | tar -xJ -C .node --strip-components=1
  fi
fi
export PATH="$(dirname "$NODE"):$PATH"
echo "== Node.js $("$NODE" -v)"

echo "== Ставлю зависимости бота"
# С package-lock.json — точные версии (npm ci); без него (в сборке для ПК его нет) — npm install.
if [ -f package-lock.json ]; then
  npm ci --omit=dev --ignore-scripts --no-audit --no-fund
else
  npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-package-lock
fi

# Настройки: .env рядом с ботом. Первый раз — из примера, и просим вписать токен.
if [ ! -f .env ]; then
  cp .env.example .env
  echo
  echo "Создан $DIR/.env — впишите BOT_TOKEN (и ADMIN_ID), затем запустите скрипт ещё раз:"
  echo "  nano $DIR/.env"
  exit 1
fi
if ! grep -q '^BOT_TOKEN=.\+' .env; then
  echo "В $DIR/.env не заполнен BOT_TOKEN. Впишите его и запустите скрипт ещё раз."
  exit 1
fi

# Отдельный пользователь без входа в систему — бот не работает от root.
id olxbot >/dev/null 2>&1 || useradd --system --home-dir "$DIR" --shell /usr/sbin/nologin olxbot
mkdir -p data
chown -R olxbot:olxbot "$DIR"
chmod 600 .env

sed -e "s|__DIR__|$DIR|g" -e "s|__NODE__|$NODE|g" deploy/olx-watcher.service > /etc/systemd/system/olx-watcher.service
systemctl daemon-reload
systemctl enable olx-watcher >/dev/null 2>&1
systemctl restart olx-watcher
sleep 4
if systemctl is-active --quiet olx-watcher; then
  echo "== БОТ ЗАПУЩЕН"
else
  echo "== Бот не запустился. Последние строки журнала:"
fi
journalctl -u olx-watcher -n 15 --no-pager || true
echo
echo "Журнал: journalctl -u olx-watcher -f    Перезапуск: systemctl restart olx-watcher"
