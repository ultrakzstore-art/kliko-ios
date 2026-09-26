#!/usr/bin/env bash
# Установка бота на VPS (Ubuntu / Debian), запускать от root:  bash deploy/install.sh
# Ставит Node.js 22, зависимости бота и службу systemd «olx-watcher»: бот работает круглосуточно
# и сам поднимается после сбоя или перезагрузки сервера. Повторный запуск безопасен.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root: sudo bash deploy/install.sh"; exit 1; fi

# Node.js 22 или новее (нужен встроенный SQLite).
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  echo "== Ставлю Node.js 22"
  apt-get update -y
  apt-get install -y curl ca-certificates
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
echo "== Node.js $(node -v)"

echo "== Ставлю зависимости бота (без приложения для ПК)"
npm ci --omit=dev --ignore-scripts --no-audit --no-fund

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

sed "s|__DIR__|$DIR|g" deploy/olx-watcher.service > /etc/systemd/system/olx-watcher.service
systemctl daemon-reload
systemctl enable olx-watcher >/dev/null
systemctl restart olx-watcher
sleep 3
systemctl --no-pager --lines=15 status olx-watcher || true
echo
echo "Готово. Журнал: journalctl -u olx-watcher -f    Перезапуск: systemctl restart olx-watcher"
