"""Пропорции фото объявлений kliko.kz — по ним выбирается рамка галереи в окне товара (владелец 17.10.2026: «как
сделать, чтобы не резал фото, 16:9, 16:10 или какой формат лучше — универсальное решение надо»).

Берёт ленту и разделы через api/listings.php, у каждого снимка читает только начало файла (Range) и достаёт размер
из заголовка JPEG (с поворотом EXIF), PNG или WebP. Печатает, сколько снимков в какой пропорции и сколько каждая
рамка отрезает при заполнении. Ничего не пишет на сайт; запускается в CI (api-probe), из контейнера сайт закрыт.
"""
import json
import statistics
import struct
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = "https://kliko.kz"
UA = "KlikoApp/1.13 (api-probe photo-ratios)"
MAX_PHOTOS = 700


def get(url, rng=None, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    if rng:
        req.add_header("Range", "bytes=0-%d" % rng)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(rng + 1 if rng else None)


def exif_orientation(app1):
    if not app1.startswith(b"Exif\x00\x00"):
        return 1
    t = app1[6:]
    if len(t) < 8:
        return 1
    end = "<" if t[:2] == b"II" else ">"
    try:
        off = struct.unpack(end + "I", t[4:8])[0]
        n = struct.unpack(end + "H", t[off:off + 2])[0]
        for i in range(n):
            e = off + 2 + i * 12
            tag, typ, cnt = struct.unpack(end + "HHI", t[e:e + 8])
            if tag == 0x0112:
                return struct.unpack(end + "H", t[e + 8:e + 10])[0]
    except struct.error:
        pass
    return 1


def jpeg_size(b):
    i, orient = 2, 1
    while i + 9 < len(b):
        if b[i] != 0xFF:
            i += 1
            continue
        m = b[i + 1]
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        ln = struct.unpack(">H", b[i + 2:i + 4])[0]
        if m == 0xE1:
            orient = exif_orientation(b[i + 4:i + 2 + ln])
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", b[i + 5:i + 9])
            return (h, w) if orient in (5, 6, 7, 8) else (w, h)
        i += 2 + ln
    return None


def webp_size(b):
    kind = b[12:16]
    if kind == b"VP8 " and len(b) >= 30:
        w, h = struct.unpack("<HH", b[26:30])
        return w & 0x3FFF, h & 0x3FFF
    if kind == b"VP8L" and len(b) >= 25:
        v = struct.unpack("<I", b[21:25])[0]
        return (v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1
    if kind == b"VP8X" and len(b) >= 30:
        w = int.from_bytes(b[24:27], "little") + 1
        h = int.from_bytes(b[27:30], "little") + 1
        return w, h
    return None


def size_of(url):
    try:
        b = get(url, rng=196607)
    except Exception as e:  # noqa: BLE001 — пробник: любая ошибка сети — просто «не прочитали»
        return url, None, type(e).__name__
    if b[:2] == b"\xff\xd8":
        return url, jpeg_size(b), "jpeg"
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return url, struct.unpack(">II", b[16:24]), "png"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return url, webp_size(b), "webp"
    return url, None, "other:" + b[:12].hex()


def absolute(u):
    if u.startswith("//"):
        return "https:" + u
    if u.startswith("http"):
        return u
    return BASE + "/" + u.lstrip("/")


def feed(params):
    try:
        d = json.loads(get(BASE + "/api/listings.php?" + params, timeout=20))
        return d.get("items") or []
    except Exception:  # noqa: BLE001
        return []


def main():
    items, seen = [], set()
    for sort in ("reco", "new"):
        for page in range(1, 6):
            for it in feed("sort=%s&page=%d&per=48" % (sort, page)):
                if it.get("id") not in seen:
                    seen.add(it.get("id"))
                    items.append(it)
    roots = sorted({(it.get("category") or "").split("-")[0] for it in items if it.get("category")})
    for c in sorted({it.get("category") for it in items if it.get("category")})[:30]:
        for it in feed("sort=new&page=1&per=24&cat=%s" % c):
            if it.get("id") not in seen:
                seen.add(it.get("id"))
                items.append(it)
    photos, first = [], set()
    by_cat = {}
    for it in items:
        imgs = [absolute(u) for u in (it.get("images") or []) if isinstance(u, str) and u]
        if imgs:
            first.add(imgs[0])
        for u in imgs:
            photos.append(u)
            by_cat.setdefault(u, it.get("category") or "?")
    photos = list(dict.fromkeys(photos))[:MAX_PHOTOS]
    print("объявлений:", len(items), "разделов:", len({it.get('category') for it in items}), "снимков к проверке:", len(photos))
    print("корни разделов:", roots[:20])
    if photos:
        print("пример адреса:", photos[0])

    with ThreadPoolExecutor(16) as pool:
        res = list(pool.map(size_of, photos))
    ok = [(u, s) for u, s, _ in res if s and s[0] > 0 and s[1] > 0]
    kinds = {}
    for _, s, k in res:
        kinds[k if s else "fail:" + k] = kinds.get(k if s else "fail:" + k, 0) + 1
    print("форматы:", kinds)
    if not ok:
        print("размеров нет — нечего считать")
        return

    buckets = [("≤ 9:16 (0.60)", 0, 0.60), ("2:3 (0.67)", 0.60, 0.70), ("3:4 (0.75)", 0.70, 0.78),
               ("4:5 (0.80)", 0.78, 0.90), ("1:1", 0.90, 1.10), ("5:4", 1.10, 1.28), ("4:3 (1.33)", 1.28, 1.42),
               ("3:2 (1.50)", 1.42, 1.56), ("16:10 (1.60)", 1.56, 1.68), ("16:9 (1.78)", 1.68, 1.90),
               ("шире 1.9", 1.90, 99)]

    def table(name, rows):
        rs = [w / h for _, (w, h) in rows]
        print("\n== %s: %d снимков, медиана %.2f ==" % (name, len(rs), statistics.median(rs)))
        for label, lo, hi in buckets:
            n = sum(1 for r in rs if lo <= r < hi)
            print("  %-15s %5.1f%%  %s" % (label, 100.0 * n / len(rs), "#" * int(60 * n / len(rs))))
        print("  вертикальных (<0.9): %.1f%% · квадратных: %.1f%% · горизонтальных (>1.1): %.1f%%" % (
            100.0 * sum(r < 0.9 for r in rs) / len(rs), 100.0 * sum(0.9 <= r <= 1.1 for r in rs) / len(rs),
            100.0 * sum(r > 1.1 for r in rs) / len(rs)))
        longs = [max(w, h) for _, (w, h) in rows]
        print("  длинная сторона, px: медиана %d, 10%% меньше %d" % (statistics.median(longs), sorted(longs)[len(longs) // 10]))
        print("  рамка        видно в среднем  режет >15%%  режет >30%%  целиком на размытом (>15%%)  высота при 393 pt")
        for fname, f in (("16:9", 16 / 9), ("16:10", 1.6), ("3:2", 1.5), ("4:3", 4 / 3), ("1:1", 1.0), ("4:5", 0.8)):
            vis = [min(r / f, f / r) for r in rs]
            print("  %-12s %10.0f%% %11.0f%% %11.0f%% %21.0f%% %15.0f" % (
                fname, 100 * statistics.mean(vis), 100.0 * sum(v < 0.85 for v in vis) / len(vis),
                100.0 * sum(v < 0.70 for v in vis) / len(vis), 100.0 * sum(v < 0.85 for v in vis) / len(vis), 393 / f))

    table("все снимки", ok)
    table("первые снимки (обложки)", [(u, s) for u, s in ok if u in first])
    per_root = {}
    for u, s in ok:
        per_root.setdefault(by_cat.get(u, "?").split("-")[0], []).append(s[0] / s[1])
    print("\n== по корням разделов (медиана, доля вертикальных) ==")
    for root, rs in sorted(per_root.items(), key=lambda kv: -len(kv[1]))[:14]:
        print("  %-14s %4d  медиана %.2f  вертикальных %3.0f%%" % (root, len(rs), statistics.median(rs),
                                                                 100.0 * sum(r < 0.9 for r in rs) / len(rs)))


if __name__ == "__main__":
    sys.exit(main())
