#!/bin/bash
# Кладёт ключ App Store Connect из ASC_KEY_P8 в $KEY_DIR/AuthKey_$ASC_KEY_ID.p8.
# Принимает любой из трёх видов вставки: весь файл .p8, он же в base64,
# или только тело ключа между строками BEGIN и END.
set -euo pipefail
mkdir -p "$KEY_DIR"
out="$KEY_DIR/AuthKey_$ASC_KEY_ID.p8"
if printf %s "$ASC_KEY_P8" | grep -q "BEGIN PRIVATE KEY"; then
  printf %s "$ASC_KEY_P8" > "$out"
else
  printf %s "$ASC_KEY_P8" | tr -d "[:space:]" | base64 -D > "$KEY_DIR/decoded" 2>/dev/null || true
  if head -c 40 "$KEY_DIR/decoded" 2>/dev/null | grep -q "BEGIN PRIVATE KEY"; then
    mv "$KEY_DIR/decoded" "$out"
  else
    body=$(printf %s "$ASC_KEY_P8" | tr -d "[:space:]" | fold -w 64)
    { echo "-----BEGIN PRIVATE KEY-----"; printf %s "$body"; echo; echo "-----END PRIVATE KEY-----"; } > "$out"
  fi
  rm -f "$KEY_DIR/decoded"
fi
chmod 600 "$out"
head -1 "$out" | grep -q 'BEGIN PRIVATE KEY' \
  || { echo "ASC_KEY_P8 не похож на ключ: нужен весь файл .p8, он же в base64 или тело ключа между BEGIN и END"; exit 1; }
echo "Ключ на месте."
