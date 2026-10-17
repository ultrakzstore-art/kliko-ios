"""Что сайт отдаёт в status и is_active — проверка «Снято с продажи» в окне объявления 84 (владелец 17.10.2026:
«Почему снято с продажи?» на iPhone 15 Pro Max). Печатает типы и значения обоих полей по ленте, поиску и карточке ?id=.
Только чтение; запускается в CI (api-probe), из контейнера сайт закрыт.
"""
import collections
import json
import urllib.parse
import urllib.request

BASE = "https://kliko.kz"
UA = "KlikoApp/1.13 (api-probe status)"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def show(v):
    return "%s:%r" % (type(v).__name__, v)


def main():
    items = []
    for sort in ("reco", "new"):
        for page in (1, 2, 3):
            try:
                items += get(BASE + "/api/listings.php?sort=%s&page=%d&per=48" % (sort, page)).get("items") or []
            except Exception as e:  # noqa: BLE001
                print("лента", sort, page, type(e).__name__)
    seen, uniq = set(), []
    for it in items:
        if it.get("id") not in seen:
            seen.add(it.get("id"))
            uniq.append(it)
    print("лента: объявлений", len(uniq))
    print("  status:", collections.Counter(show(it.get("status", "<нет поля>")) for it in uniq).most_common(10))
    print("  is_active:", collections.Counter(show(it.get("is_active", "<нет поля>")) for it in uniq).most_common(10))

    for q in ("iPhone 15 Pro Max", "iPhone"):
        try:
            found = get(BASE + "/api/listings.php?sort=new&page=1&per=24&q=" + urllib.parse.quote(q)).get("items") or []
        except Exception as e:  # noqa: BLE001
            print("поиск", q, type(e).__name__)
            continue
        print("\nпоиск %r: %d" % (q, len(found)))
        for it in found[:12]:
            print("  %s | %s | status=%s | is_active=%s | seller=%s" % (
                it.get("id"), (it.get("title") or "")[:40], show(it.get("status", "<нет>")),
                show(it.get("is_active", "<нет>")), (it.get("seller_name") or it.get("seller") or "")))
        for it in found[:6]:
            try:
                d = get(BASE + "/api/listings.php?id=" + urllib.parse.quote(str(it.get("id"))))
            except Exception as e:  # noqa: BLE001
                print("  ?id=%s %s" % (it.get("id"), type(e).__name__))
                continue
            card = d.get("item") if isinstance(d.get("item"), dict) else d
            keys = sorted(k for k in card.keys() if any(w in k for w in ("status", "active", "sold", "reserv", "state", "moder", "expir")))
            print("  ?id=%s: %s" % (it.get("id"), {k: card.get(k) for k in keys}))


if __name__ == "__main__":
    main()
