#!/usr/bin/env bash
# Обновление бота на VPS до последней версии из репозитория (если ставили через git), от root:
#   bash deploy/update.sh
# Ставили кнопкой из приложения для ПК — обновляйте той же кнопкой, git не нужен.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
git config --global --add safe.directory "$(git rev-parse --show-toplevel)" 2>/dev/null || true
git pull --ff-only
bash deploy/install.sh
