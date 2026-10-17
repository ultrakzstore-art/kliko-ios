"""Сколько объявлений продавца видит профиль в приложении и сколько их на самом деле (владелец 17.10.2026: «у продавца
Канат много товаров, а в профиле только 4 — где остальные?»). Сравнивает: seller.php (какие массивы JS и сколько ссылок на
объявления), api/listings.php с разными именами параметра продавца, и подсчёт по всей ленте. Только чтение; в CI.
"""
import collections
import json
import re
import urllib.parse
import urllib.request

BASE = "https://kliko.kz"
UA = "KlikoApp/1.13 (api-probe seller)"


def get(url, accept="application/json"):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with urllib.request.urlopen(req, timeout=25) as resp:
        return resp.read()


def feed(params):
    try:
        return json.loads(get(BASE + "/api/listings.php?" + params))
    except Exception as e:  # noqa: BLE001
        return {"error": type(e).__name__}


def main():
    items, seen = [], set()
    for sort in ("new", "reco"):
        for page in range(1, 8):
            d = feed("sort=%s&page=%d&per=48" % (sort, page))
            got = d.get("items") or []
            for it in got:
                if it.get("id") not in seen:
                    seen.add(it.get("id"))
                    items.append(it)
            if len(got) < 48:
                break
    по_продавцу = collections.Counter((it.get("seller_id"), it.get("seller_name") or it.get("seller") or "") for it in items)
    print("в ленте всего:", len(items), "| total ответа:", feed("sort=new&page=1&per=1").get("total"))
    print("продавцы (id, имя, объявлений в ленте):")
    for (sid, name), n in по_продавцу.most_common(8):
        print("  ", sid, name, n)
    keys = sorted({k for it in items[:5] for k in it.keys() if "sell" in k or "user" in k or "author" in k or "owner" in k})
    print("поля продавца в ленте:", keys)

    for (sid, name), n in по_продавцу.most_common(3):
        if not sid:
            continue
        print("\n=== продавец", sid, name, "— в ленте", n)
        for p in ("seller", "seller_id", "uid", "user", "author", "owner"):
            d = feed("sort=new&page=1&per=48&%s=%s" % (p, urllib.parse.quote(str(sid))))
            got = d.get("items") or []
            его = sum(1 for it in got if it.get("seller_id") == sid)
            print("  api ?%s=: items=%d, его=%d, total=%s, err=%s" % (p, len(got), его, d.get("total"), d.get("error")))
        for lang in ("ru",):
            url = BASE + "/kz/%s/seller.php?id=%s" % (lang, urllib.parse.quote(str(sid)))
            try:
                html = get(url, "text/html").decode("utf-8", "replace")
            except Exception as e:  # noqa: BLE001
                print("  seller.php:", type(e).__name__)
                continue
            arrays = re.findall(r"\b(MK_[A-Z_]+|SELLER_[A-Z_]+)\s*=\s*\[", html)
            print("  seller.php: %d байт, массивы JS: %s" % (len(html), collections.Counter(arrays).most_common(8)))
            for name_ in ("MK_SEED", "MK_SELLER_ITEMS", "SELLER_ITEMS", "MK_ITEMS"):
                m = re.search(name_ + r"\s*=\s*\[", html)
                if m:
                    print("    %s у позиции %d, ~id в нём: %d" % (name_, m.start(), html[m.end():m.end() + 200000].count('"id"')))
            ids = set(re.findall(r"item=(p[0-9a-f]{8,})", html)) | set(re.findall(r'data-id="(p[0-9a-f]{8,})"', html))
            print("  ссылок на объявления (item= / data-id): %d" % len(ids))
            cnt = re.findall(r"(\d+)\s*(?:объявлен|товар)", html)
            print("  числа «N объявлений/товаров» в тексте:", cnt[:6])
            more = re.findall(r"(page=\d+|load_more|data-page|seller_items\.php|api/[a-z_]+\.php[^\"' ]*seller[^\"' ]*)", html)
            print("  признаки подгрузки:", collections.Counter(more).most_common(6))


if __name__ == "__main__":
    main()
