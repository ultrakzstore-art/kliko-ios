#!/usr/bin/env bash
# СТАРТОВЫЕ ДАННЫЕ В СБОРКЕ (Seed/*.json): справочники, без которых первый запуск после установки ждал бы сеть —
# дерево разделов на четырёх языках, справочники кабинета для подачи, марки и модели авто, типы запчастей.
# Объявлений здесь нет: они устаревают за часы, их приложение всегда берёт из сети (до ответа — серые карточки).
#
# Запуск:
#   scripts/fetch_seed.sh                        — с живого сайта (BASE=https://kliko.kz по умолчанию)
#   SEED_SITE=/путь/к/копии/сайта scripts/fetch_seed.sh — из локальной копии сайта (нужен php-cli): js/cats-*.js,
#                                                  js/cab-refs.js, api/auto_models.php, api/parts_types.php
# Итог — файлы Seed/seed-*.json; их надо закоммитить. Бюджет — до 300 КБ всего (скрипт печатает размеры).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Seed"
BASE="${BASE:-https://kliko.kz}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

get_file() {   # $1 — путь на сайте (/js/cats-ru.js), $2 — куда
  if [ -n "${SEED_SITE:-}" ]; then
    cp "$SEED_SITE$1" "$2"
  else
    curl -fsSL --retry 3 "$BASE$1" -o "$2"
  fi
}

get_api() {    # $1 — файл api (auto_models.php), $2 — строка запроса (brands=1), $3 — куда
  if [ -n "${SEED_SITE:-}" ]; then
    (cd "$SEED_SITE/api" && php -r 'parse_str($argv[2], $_GET); $_SERVER["HTTP_IF_NONE_MATCH"]=""; include $argv[1];' \
      "$1" "$2") > "$3"
  else
    curl -fsSL --retry 3 "$BASE/api/$1?$2" -o "$3"
  fi
}

for lang in ru kz en ar; do get_file "/js/cats-$lang.js" "$TMP/cats-$lang.js"; done
get_file "/js/cab-refs.js" "$TMP/cab-refs.js"
get_api auto_models.php "brands=1" "$TMP/brands.json"
get_api parts_types.php "" "$TMP/parts.json"

# Модели по марке — как их отдаёт ?brand= (имя и кузов; поколения приложение догружает из сети).
python3 - "$TMP/brands.json" > "$TMP/brand-list.txt" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for g in d.get("groups", []):
    for b in g.get("brands", []):
        print(b["brand"])
EOF
mkdir -p "$TMP/models"
n=0
while IFS= read -r brand; do
  [ -z "$brand" ] && continue
  n=$((n + 1))
  q="brand=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$brand")"
  get_api auto_models.php "$q" "$TMP/models/$n.json" || true
done < "$TMP/brand-list.txt"

python3 - "$TMP" "$OUT" <<'EOF'
import json, os, sys, glob, datetime
tmp, out = sys.argv[1], sys.argv[2]

def after(text, marker, close):
    i = text.index(marker) + len(marker)
    j = text.rindex(close) + 1
    return json.loads(text[i:j])

def dump(name, obj):
    path = os.path.join(out, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
    return os.path.getsize(path)

sizes = {}
stamp = datetime.date.today().isoformat()

# Дерево разделов: узлы один раз (ключ, номер родителя, цвет если не как у родителя, бренды), имена — по языкам.
trees = {}
for lang in ("ru", "kz", "en", "ar"):
    trees[lang] = after(open(f"{tmp}/cats-{lang}.js", encoding="utf-8").read(), "MK_CATS=", "]")
nodes, names = [], {l: [] for l in trees}
def walk(ns, parent, pcolor, per_lang):
    for idx, n in enumerate(ns):
        color = n.get("color") or ""
        row = [n["slug"], parent, "" if color == pcolor else color]
        brands = n.get("brands") or []
        if brands:
            row.append(brands)
        nodes.append(row)
        me = len(nodes) - 1
        for l, lns in per_lang.items():
            names[l].append((lns[idx].get("name") if idx < len(lns) and lns[idx].get("slug") == n["slug"] else "") or "")
        walk(n.get("children") or [], me, color or pcolor,
             {l: (lns[idx].get("children") or []) if idx < len(lns) else [] for l, lns in per_lang.items()})
walk(trees["ru"], -1, "", trees)
sizes["seed-cats.json"] = dump("seed-cats.json", {"v": stamp, "nodes": nodes, "names": names})

# Справочники кабинета — только то, что читает приложение (СправочникиПодачи.разобрать).
refs = after(open(f"{tmp}/cab-refs.js", encoding="utf-8").read(), "KLK_CAB_REFS=", "}")
keep = {k: refs[k] for k in ("E_SPECS", "BRAND_LIST", "REALTY_FIELDS", "PARTS_FIELDS", "GEO_KZ") if k in refs}
sizes["seed-cab-refs.json"] = dump("seed-cab-refs.json", keep)

# Марки группами — ответ ?brands=1 как есть; модели — имя и кузов.
brands = json.load(open(f"{tmp}/brands.json", encoding="utf-8"))
models = {}
for p in glob.glob(f"{tmp}/models/*.json"):
    try:
        d = json.load(open(p, encoding="utf-8"))
    except Exception:
        continue
    if not d.get("ok"):
        continue
    models[d["brand"]] = [[m["name"], m.get("body") or []] for m in d.get("models", []) if m.get("name")]
sizes["seed-auto.json"] = dump("seed-auto.json", {"groups": brands.get("groups", []), "models": models})

# Типы запчастей — ключ и название (синонимы нужны только поиску, их не берём).
parts = json.load(open(f"{tmp}/parts.json", encoding="utf-8"))
groups = [{"group": g.get("group", ""), "items": [{"k": i["k"], "n": i["n"]} for i in g.get("items", [])]}
          for g in parts.get("groups", [])]
sizes["seed-parts.json"] = dump("seed-parts.json", {"groups": groups})

total = 0
for k, v in sizes.items():
    total += v
    print(f"{k:22s} {v/1024:7.1f} КБ")
print(f"{'всего':22s} {total/1024:7.1f} КБ")
if total > 300 * 1024:
    print("ВНИМАНИЕ: больше 300 КБ", file=sys.stderr)
EOF
