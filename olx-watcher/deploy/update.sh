#!/usr/bin/env bash
# Обновление бота на VPS до последней версии из репозитория, от root:  bash deploy/update.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
git config --global --add safe.directory "$(git rev-parse --show-toplevel)" 2>/dev/null || true
git pull --ff-only
npm ci --omit=dev --ignore-scripts --no-audit --no-fund
chown -R olxbot:olxbot "$DIR"
systemctl restart olx-watcher
sleep 3
systemctl --no-pager --lines=10 status olx-watcher || true
