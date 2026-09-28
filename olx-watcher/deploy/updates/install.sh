#!/usr/bin/env bash
# Сервер обновлений ПК-программы OLX Watcher — вместо GitHub Releases и платных сборщиков.
# Раз в 10 минут берёт код с GitHub (по токену), собирает установщик Windows и раздаёт его:
#   http://<IP сервера>:8787/   — страница со ссылкой на установщик;
#   программа на ПК сама берёт отсюда обновления.
# Всё — в /opt/olx-watcher-updates. Бота (/opt/olx-watcher) и другие папки не трогает, ничего не удаляет.
# Запуск от root:  GH_TOKEN=<токен GitHub> bash install.sh     Повторный запуск безопасен.
set -euo pipefail
BASE=/opt/olx-watcher-updates
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-https://github.com/ultrakzstore-art/kliko-ios.git}"
BRANCH="${BRANCH:-claude/idea-czum8v}"
PORT="${PORT:-8787}"

if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root"; exit 1; fi
mkdir -p "$BASE/www" "$BASE/home" "$BASE/bin"

if [ -n "${GH_TOKEN:-}" ]; then printf %s "$GH_TOKEN" > "$BASE/.token"; fi
[ -s "$BASE/.token" ] || { echo "Нет токена GitHub: GH_TOKEN=<токен> bash $0"; exit 1; }
printf %s "$REPO" > "$BASE/repo"
printf %s "$BRANCH" > "$BASE/branch"

echo "== Пакеты: git, wine (для иконки в .exe)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y -qq --no-install-recommends git ca-certificates xz-utils >/dev/null
apt-get install -y -qq --no-install-recommends wine64 >/dev/null 2>&1 \
  || apt-get install -y -qq --no-install-recommends wine >/dev/null 2>&1 \
  || echo "   wine не поставился — установщик будет со стандартной иконкой"

# Node.js 22+: тот, что у бота, системный или свой в $BASE/.node.
NODE=""
for c in /opt/olx-watcher/.node/bin/node "$(command -v node || true)" "$BASE/.node/bin/node"; do
  if [ -n "$c" ] && [ -x "$c" ] && [ "$("$c" -p 'process.versions.node.split(".")[0]')" -ge 22 ]; then NODE="$c"; break; fi
done
if [ -z "$NODE" ]; then
  case "$(uname -m)" in x86_64|amd64) ARCH=x64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "Неизвестный процессор"; exit 1 ;; esac
  echo "== Скачиваю Node.js 22 в $BASE/.node"
  FILE="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | grep -o "node-v22[^ ]*-linux-$ARCH.tar.xz" | head -1)"
  mkdir -p "$BASE/.node"
  curl -fsSL "https://nodejs.org/dist/latest-v22.x/$FILE" | tar -xJ -C "$BASE/.node" --strip-components=1
  NODE="$BASE/.node/bin/node"
fi
dirname "$NODE" > "$BASE/node-dir"
echo "== Node.js $("$NODE" -v)"

id olxbuild >/dev/null 2>&1 || useradd --system --home-dir "$BASE/home" --shell /usr/sbin/nologin olxbuild

# Код: отдельная копия репозитория; токен в неё не записывается (передаётся при каждом fetch).
if [ ! -d "$BASE/src/.git" ]; then
  git init -q "$BASE/src"
fi

cp "$HERE/build.sh" "$HERE/serve.js" "$BASE/bin/"
chmod 755 "$BASE/bin/build.sh"
chown -R olxbuild:olxbuild "$BASE"
chmod 600 "$BASE/.token"

cat > /etc/systemd/system/olx-updates-web.service <<UNIT
[Unit]
Description=OLX Watcher — раздача обновлений ПК-программы
After=network-online.target

[Service]
User=olxbuild
Environment=PORT=$PORT WWW=$BASE/www
ExecStart=$NODE $BASE/bin/serve.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/olx-updates-build.service <<UNIT
[Unit]
Description=OLX Watcher — сборка обновления ПК-программы
After=network-online.target

[Service]
Type=oneshot
User=olxbuild
ExecStart=/bin/bash $BASE/bin/build.sh
# Бот важнее: сборка — с низким приоритетом.
Nice=15
IOSchedulingClass=idle
TimeoutStartSec=45min
UNIT

cat > /etc/systemd/system/olx-updates-build.timer <<UNIT
[Unit]
Description=OLX Watcher — проверять новый код раз в 10 минут

[Timer]
OnBootSec=3min
OnUnitInactiveSec=10min

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now olx-updates-web >/dev/null 2>&1
systemctl restart olx-updates-web
systemctl enable --now olx-updates-build.timer >/dev/null 2>&1
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then ufw allow "$PORT/tcp" >/dev/null; fi

echo "== Первая сборка запущена (10–20 минут). Ход: journalctl -u olx-updates-build -f"
systemctl start --no-block olx-updates-build
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "Готово. Установщик будет здесь: http://${IP:-<IP сервера>}:$PORT/"
