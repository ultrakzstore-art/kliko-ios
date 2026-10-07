#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# App Store Connect API для сборки в Codemagic (codemagic.yaml).
#
# 26.09.2026 GitHub отключил Actions на аккаунте («Actions has been disabled for this user»), а сборка
# в TestFlight жила там (.github/workflows/ios.yml). Codemagic собирает тем же xcodebuild, а этот файл
# делает то, что в ios.yml написано прямо в шагах:
#   revoke-dev-certs  — отозвать сертификаты разработки прошлых прогонов («Created via API»). Автоподпись
#                       на чистой машине каждый раз выпускает новый, а лимит Apple кончается (17.09.2026).
#   next-build-number — номер следующей сборки: самый большой номер, уже залитый в App Store Connect, + 1.
#                       Счётчик прогонов Codemagic начинается с 1, а в TestFlight уже 35 — Apple не примет
#                       номер меньше прежнего. И когда Actions вернутся, их номер прогона тоже надо будет сверить.
#   iap-sync [--apply] — встроенные покупки по Kliko.storekit (кнопка «App Store · Завести покупки»,
#                       .github/workflows/appstore-iap.yml). Без --apply — только GET-запросы и план. С --apply —
#                       создаёт недостающие товары, локализации ru/en-US, цену в ₸ (KAZ — базовая страна, остальные
#                       Apple выравнивает сама) и доступность во всех странах. Уже заведённое не трогает и не
#                       дублирует. На проверку НИЧЕГО не отправляет. Запускает только владелец.
#
# Ключ: ASC_KEY_ID, ASC_ISSUER_ID и путь к .p8 в ASC_KEY_PATH. Ключ не печатается.
# ─────────────────────────────────────────────────────────────────────────────
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.error
import urllib.request

BUNDLE_ID = "kz.kliko.app"
API = "https://api.appstoreconnect.apple.com/v1"


def jwt():
    kid, iss, key = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"]
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
    now = int(time.time())
    msg = (b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode()) + b"."
           + b64(json.dumps({"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode()))
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=msg, capture_output=True, check=True).stdout
    # Подпись openssl — DER: SEQUENCE { INTEGER r, INTEGER s }. JWT ждёт r||s по 32 байта.
    pos = 3 if der[1] & 0x80 else 2

    def integer(p):
        n = der[p + 1]
        return der[p + 2:p + 2 + n], p + 2 + n

    r, pos = integer(pos)
    s, _ = integer(pos)
    raw = r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")
    return (msg + b"." + b64(raw)).decode()


def call(method, url, token):
    req = urllib.request.Request(url, method=method, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
        return json.loads(data) if data else {}


def revoke_dev_certs():
    token = jwt()
    certs = call("GET", API + "/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200", token).get("data", [])
    print("сертификатов разработки:", len(certs))
    revoked = 0
    for c in certs:
        a = c.get("attributes", {})
        name = "%s | %s" % (a.get("name") or "", a.get("displayName") or "")
        print(" -", name, a.get("certificateType"), a.get("expirationDate"))
        if "Created via API" not in name:
            continue
        call("DELETE", API + "/certificates/" + c["id"], token)
        revoked += 1
    print("отозвано:", revoked)


def next_build_number():
    token = jwt()
    apps = call("GET", API + "/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID}), token).get("data", [])
    if not apps:
        sys.exit("Приложение %s не найдено этим ключом" % BUNDLE_ID)
    query = urllib.parse.urlencode({"filter[app]": apps[0]["id"], "sort": "-uploadedDate", "limit": "200",
                                    "fields[builds]": "version"})
    builds = call("GET", API + "/builds?" + query, token).get("data", [])
    numbers = [int(b["attributes"]["version"]) for b in builds
               if str(b.get("attributes", {}).get("version", "")).isdigit()]
    if not numbers:
        sys.exit("В App Store Connect не нашлось ни одной сборки — номер не угадываю")
    # Только номер — в stdout: его забирает codemagic.yaml. Пояснение — в stderr.
    print("последний номер в App Store Connect: %d" % max(numbers), file=sys.stderr)
    print(max(numbers) + 1)




# ─── iap-sync ────────────────────────────────────────────────────────────────
ROOT = "https://api.appstoreconnect.apple.com"
STOREKIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Kliko.storekit")
TERRITORY = "KAZ"
GROUP_NAME = "Kliko PRO"
REVIEW_NOTE = ("Digital service inside Kliko: promotion of the user's own listings (TOP placement, bumps), extra "
               "listing slots, Kliko AI access. To buy: sign in with the review account, open My listings "
               "(«Мои объявления») and tap «Продвинуть» (Promote) on a listing.")
PERIODS = {"P1W": "ONE_WEEK", "P1M": "ONE_MONTH", "P2M": "TWO_MONTHS", "P3M": "THREE_MONTHS",
           "P6M": "SIX_MONTHS", "P1Y": "ONE_YEAR"}
# В Kliko.storekit тексты только на русском. Английские — здесь (имя ≤ 30 знаков, описание ≤ 45).
EN = {
    "kz.kliko.app.promo.top3": ("TOP for 3 days", "Your listing in TOP for 3 days"),
    "kz.kliko.app.promo.combo7": ("Combo: TOP 7d + 2 bumps", "TOP for 7 days and 2 bumps"),
    "kz.kliko.app.promo.top14b5": ("TOP 14 days + 5 bumps", "TOP for 14 days and 5 bumps"),
    "kz.kliko.app.promo.top30b9": ("TOP 30 days + 9 bumps", "TOP for 30 days and 9 bumps"),
    "kz.kliko.app.promo.bump1": ("Bump", "Bump your listing once"),
    "kz.kliko.app.resume.top7": ("Resume in TOP for 7 days", "Resume in TOP of the Jobs section for 7 days"),
    "kz.kliko.app.slots.20": ("+20 slots for 30 days", "More active listings for 30 days"),
    "kz.kliko.app.slots.50": ("+50 slots for 30 days", "More active listings for 30 days"),
    "kz.kliko.app.slots.100": ("+100 slots for 30 days", "More active listings for 30 days"),
    "kz.kliko.app.slots.200": ("+200 slots for 30 days", "More active listings for 30 days"),
    "kz.kliko.app.combo.start": ("Start combo", "20 slots and Kliko AI for 7 days"),
    "kz.kliko.app.combo.active": ("Active combo", "50 slots and Kliko AI for 14 days"),
    "kz.kliko.app.combo.max": ("Max combo", "100 slots and Kliko AI for 30 days"),
    "kz.kliko.app.ai.week": ("Kliko AI for 7 days", "All Kliko AI features for 7 days"),
    "kz.kliko.app.ai.month": ("Kliko AI for 30 days", "All Kliko AI features for 30 days"),
    "kz.kliko.app.ai.quarter": ("Kliko AI for 90 days", "All Kliko AI features for 90 days"),
    "kz.kliko.app.pro.business.month": ("Kliko PRO", "Storefront, growth tools and Kliko AI"),
    "group": ("Kliko PRO", None),
}


class ApiError(Exception):
    pass


_tok = {"t": None, "at": 0}


def api(method, path, body=None):
    if not _tok["t"] or time.time() - _tok["at"] > 480:
        _tok["t"], _tok["at"] = jwt(), time.time()
    url = path if path.startswith("http") else ROOT + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Bearer " + _tok["t"]}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            errs = json.loads(text).get("errors", [])
            text = "; ".join("%s: %s" % (x.get("title", ""), x.get("detail", "")) for x in errs) or text
        except ValueError:
            pass
        raise ApiError("%s %s → %d %s" % (method, path.split("?")[0], e.code, " ".join(text.split())[:400]))


def get_all(path):
    out, url = [], path
    while url:
        page = api("GET", url)
        out += page.get("data", [])
        url = (page.get("links") or {}).get("next")
    return out


def ann(kind, text):
    # Аннотации видны в сводке прогона (логи через API не отдаются). В аннотации нельзя переводы строк.
    text = str(text).replace("%", "%25").replace("\r", " ").replace("\n", " ")
    print("::%s::%s" % (kind, text), flush=True)


def tenge(v):
    try:
        return "{:,.0f}".format(float(v)).replace(",", " ")
    except (TypeError, ValueError):
        return str(v)


def nearest(points, price):
    """Ближайшая к цене ценовая точка (при равенстве — меньшая)."""
    best = None
    for p in points:
        cp = float(p["attributes"]["customerPrice"])
        key = (abs(cp - price), cp)
        if best is None or key < best[0]:
            best = (key, p)
    return best[1] if best else None


def ru_loc(item):
    for l in item.get("localizations", []):
        if l.get("locale", "").lower().startswith("ru"):
            return l["displayName"], l["description"]
    l = item["localizations"][0]
    return l["displayName"], l["description"]


def load_storekit():
    with open(STOREKIT, encoding="utf-8") as f:
        sk = json.load(f)
    items = []
    for p in sk.get("products", []):
        items.append({"kind": "iap", "type": p["type"].upper().replace(" ", "_"), "id": p["productID"],
                      "ref": p.get("referenceName") or ru_loc(p)[0], "price": float(p["displayPrice"]),
                      "ru": ru_loc(p), "en": EN.get(p["productID"])})
    for g in sk.get("subscriptionGroups", []):
        for s in g.get("subscriptions", []):
            items.append({"kind": "sub", "group": g.get("name") or GROUP_NAME, "id": s["productID"],
                          "ref": s.get("referenceName") or ru_loc(s)[0], "price": float(s["displayPrice"]),
                          "period": PERIODS[s["recurringSubscriptionPeriod"]], "level": s.get("groupNumber", 1),
                          "ru": ru_loc(s), "en": EN.get(s["productID"])})
    for it in items:
        if it["type" if it["kind"] == "iap" else "kind"] not in ("CONSUMABLE", "sub"):
            sys.exit("Kliko.storekit: %s — тип %s не поддерживается" % (it["id"], it.get("type")))
        for loc in ("ru", "en"):
            if not it[loc]:
                sys.exit("%s: нет текста %s" % (it["id"], loc))
            if len(it[loc][0]) > 30 or len(it[loc][1]) > 45:
                sys.exit("%s: текст %s длиннее лимита Apple (имя ≤ 30, описание ≤ 45)" % (it["id"], loc))
    return items


def territories_all():
    return [{"type": "territories", "id": t["id"]} for t in get_all("/v1/territories?limit=200")]


def iap_existing_price(iap_id):
    """Текущая цена в KAZ у существующей покупки или None."""
    try:
        prices = api("GET", "/v1/inAppPurchasePriceSchedules/%s/manualPrices?include=inAppPurchasePricePoint,territory"
                     "&filter[territory]=%s&limit=50" % (iap_id, TERRITORY))
    except ApiError:
        return None
    for inc in prices.get("included", []):
        if inc["type"] == "inAppPurchasePricePoints":
            return inc["attributes"].get("customerPrice")
    return None


def sub_existing_price(sub_id):
    try:
        prices = api("GET", "/v1/subscriptions/%s/prices?include=subscriptionPricePoint&filter[territory]=%s&limit=50"
                     % (sub_id, TERRITORY))
    except ApiError:
        return None
    for inc in prices.get("included", []):
        if inc["type"] == "subscriptionPricePoints":
            return inc["attributes"].get("customerPrice")
    return None


def ensure_locs(existing_path, create_type, rel_name, rel_type, obj_id, it, apply):
    have = {l["attributes"]["locale"] for l in get_all(existing_path)}
    need = [("ru", it["ru"]), ("en-US", it["en"])]
    missing = [(loc, t) for loc, t in need if loc not in have]
    if apply:
        for loc, (name, desc) in missing:
            attrs = {"locale": loc, "name": name}
            if desc is not None:
                attrs["description"] = desc
            api("POST", "/v1/" + create_type, {"data": {"type": create_type, "attributes": attrs, "relationships": {
                rel_name: {"data": {"type": rel_type, "id": obj_id}}}}})
    return [loc for loc, _ in missing]


def sync_iap(app_id, it, existing, apply, ref_points):
    iap = existing.get(it["id"])
    status = "уже есть" if iap else "создан"
    if not iap:
        if not apply:
            pp = nearest(ref_points, it["price"]) if ref_points else None
            price = ("цена %s ₸ (ближайшая точка KAZ к %s ₸)" % (tenge(pp["attributes"]["customerPrice"]), tenge(it["price"]))
                     if pp else "цена %s ₸ — точка будет подобрана при создании" % tenge(it["price"]))
            ann("notice", "%s — будет создан (CONSUMABLE, ru + en-US), %s" % (it["id"], price))
            return
        iap = api("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": it["ref"][:64], "productId": it["id"], "inAppPurchaseType": "CONSUMABLE",
            "reviewNote": REVIEW_NOTE}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    iid = iap["id"]
    todo = []
    missing = ensure_locs("/v2/inAppPurchases/%s/inAppPurchaseLocalizations?limit=50" % iid, "inAppPurchaseLocalizations",
                          "inAppPurchaseV2", "inAppPurchases", iid, it, apply)
    if missing:
        todo.append("локализации " + ",".join(missing))
    cur = iap_existing_price(iid) if status == "уже есть" else None
    if cur is None:
        points = get_all("/v2/inAppPurchases/%s/pricePoints?filter[territory]=%s&limit=200" % (iid, TERRITORY))
        pp = nearest(points, it["price"])
        if not pp:
            raise ApiError("нет ценовых точек KAZ")
        cur = pp["attributes"]["customerPrice"]
        todo.append("цена %s ₸" % tenge(cur))
        if apply:
            api("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                    "baseTerritory": {"data": {"type": "territories", "id": TERRITORY}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
                "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None},
                              "relationships": {"inAppPurchasePricePoint": {"data": {
                                  "type": "inAppPurchasePricePoints", "id": pp["id"]}}}}]})
    try:
        has_avail = bool(api("GET", "/v2/inAppPurchases/%s/inAppPurchaseAvailability" % iid).get("data"))
    except ApiError:
        has_avail = False
    if not has_avail:
        todo.append("доступность во всех странах")
        if apply:
            api("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
                "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
                "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                                  "availableTerritories": {"data": territories_all()}}}})
    if apply or not todo:
        ann("notice", "%s — %s, цена %s ₸%s" % (it["id"], status, tenge(cur),
                                                 ("; дозаведено: " + ", ".join(todo)) if todo and status == "уже есть" else ""))
    else:
        ann("notice", "%s — уже есть; будет дозаведено: %s" % (it["id"], ", ".join(todo)))


def sync_sub(app_id, it, groups, apply):
    group = next((g for g in groups if g["attributes"]["referenceName"] == it["group"]), None)
    if not group and not apply:
        ann("notice", "%s — будет создана группа «%s» и подписка (%s, ru + en-US), цена %s ₸ — точка будет "
                      "подобрана при создании" % (it["id"], it["group"], it["period"], tenge(it["price"])))
        return
    if not group:
        group = api("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups",
                    "attributes": {"referenceName": it["group"]},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        groups.append(group)
    gid = group["id"]
    gl = {"ru": EN["group"], "en": EN["group"]}
    ensure_locs("/v1/subscriptionGroups/%s/subscriptionGroupLocalizations?limit=50" % gid,
                "subscriptionGroupLocalizations", "subscriptionGroup", "subscriptionGroups", gid, gl, apply)
    subs = {s["attributes"]["productId"]: s for s in get_all("/v1/subscriptionGroups/%s/subscriptions?limit=200" % gid)}
    sub = subs.get(it["id"])
    status = "уже есть" if sub else "создан"
    if not sub:
        if not apply:
            ann("notice", "%s — будет создана подписка в группе «%s» (%s, ru + en-US), цена %s ₸ — точка будет "
                          "подобрана при создании" % (it["id"], it["group"], it["period"], tenge(it["price"])))
            return
        sub = api("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
            "name": it["ref"][:64], "productId": it["id"], "subscriptionPeriod": it["period"],
            "groupLevel": it["level"], "reviewNote": REVIEW_NOTE, "familySharable": False},
            "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": gid}}}}})["data"]
    sid = sub["id"]
    todo = []
    missing = ensure_locs("/v1/subscriptions/%s/subscriptionLocalizations?limit=50" % sid, "subscriptionLocalizations",
                          "subscription", "subscriptions", sid, it, apply)
    if missing:
        todo.append("локализации " + ",".join(missing))
    cur = sub_existing_price(sid) if status == "уже есть" else None
    if cur is None:
        points = get_all("/v1/subscriptions/%s/pricePoints?filter[territory]=%s&limit=200" % (sid, TERRITORY))
        pp = nearest(points, it["price"])
        if not pp:
            raise ApiError("нет ценовых точек KAZ")
        cur = pp["attributes"]["customerPrice"]
        todo.append("цена %s ₸ и равные цены в остальных странах" % tenge(cur))
        if apply:
            def price(point_id, terr):
                api("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
                    "attributes": {"startDate": None, "preserveCurrentPrice": False}, "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sid}},
                        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point_id}},
                        "territory": {"data": {"type": "territories", "id": terr}}}}})
            price(pp["id"], TERRITORY)
            # У подписки нет «базовой страны»: цена ставится по каждой стране. Остальные — по равным точкам Apple.
            failed = []
            for eq in get_all("/v1/subscriptionPricePoints/%s/equalizations?include=territory&limit=200" % pp["id"]):
                terr = ((eq.get("relationships") or {}).get("territory") or {}).get("data") or {}
                if not terr.get("id") or terr["id"] == TERRITORY:
                    continue
                try:
                    price(eq["id"], terr["id"])
                except ApiError:
                    failed.append(terr["id"])
            if failed:
                ann("warning", "%s: цена не выставилась в %d странах (%s) — поправить в App Store Connect"
                    % (it["id"], len(failed), ",".join(failed[:20])))
    try:
        has_avail = bool(api("GET", "/v1/subscriptions/%s/subscriptionAvailability" % sid).get("data"))
    except ApiError:
        has_avail = False
    if not has_avail:
        todo.append("доступность во всех странах")
        if apply:
            api("POST", "/v1/subscriptionAvailabilities", {"data": {
                "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                  "availableTerritories": {"data": territories_all()}}}})
    if apply or not todo:
        ann("notice", "%s — %s, цена %s ₸%s" % (it["id"], status, tenge(cur),
                                                 ("; дозаведено: " + ", ".join(todo)) if todo and status == "уже есть" else ""))
    else:
        ann("notice", "%s — уже есть; будет дозаведено: %s" % (it["id"], ", ".join(todo)))


def iap_sync(apply=False):
    items = load_storekit()
    apps = api("GET", "/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID})).get("data", [])
    if not apps:
        ann("error", "Приложение %s не найдено этим ключом" % BUNDLE_ID)
        sys.exit(1)
    app_id = apps[0]["id"]
    print("режим:", "СОЗДАНИЕ" if apply else "план (ничего не создаётся)", "| app id:", app_id)
    existing = {p["attributes"]["productId"]: p for p in get_all("/v1/apps/%s/inAppPurchasesV2?limit=200" % app_id)}
    groups = get_all("/v1/apps/%s/subscriptionGroups?limit=200" % app_id)
    have_subs = set()
    for g in groups:
        for s in get_all("/v1/subscriptionGroups/%s/subscriptions?limit=200" % g["id"]):
            have_subs.add(s["attributes"]["productId"])
    # Справочник ценовых точек для плана: у ещё не созданной покупки своих точек нет. Сетка цен у покупок одна,
    # поэтому берём точки любой уже заведённой покупки; если таких нет — цену подберём при создании.
    ref_points = []
    if not apply and existing:
        try:
            ref_points = get_all("/v2/inAppPurchases/%s/pricePoints?filter[territory]=%s&limit=200"
                                 % (next(iter(existing.values()))["id"], TERRITORY))
        except ApiError:
            ref_points = []
    new = sum(1 for it in items if it["id"] not in existing and it["id"] not in have_subs)
    errors = 0
    for it in items:
        try:
            if it["kind"] == "iap":
                sync_iap(app_id, it, existing, apply, ref_points)
            else:
                sync_sub(app_id, it, groups, apply)
        except ApiError as e:
            errors += 1
            ann("error", "%s: %s" % (it["id"], e))
    verb = "создано" if apply else "будет создано"
    ann("notice", "Итого товаров в Kliko.storekit: %d; уже в App Store Connect: %d; %s: %d; ошибок: %d.%s"
        % (len(items), len(items) - new, verb, new, errors,
           "" if apply else " Это план — в Apple ничего не менялось. Создание: запуск с галочкой apply."))
    if errors:
        sys.exit(1)


def crashes():
    """Последние отчёты о падениях из TestFlight (кнопка «Отправить» в окне падения) — аннотациями прогона.
    Только чтение. Из длинного отчёта — шапка (версия, модель, iOS), тип исключения, причина и кадры упавшего потока."""
    apps = api("GET", "/v1/apps?filter[bundleId]=" + BUNDLE_ID).get("data", [])
    if not apps:
        ann("error", "Приложение " + BUNDLE_ID + " не найдено")
        return
    app_id = apps[0]["id"]
    subs = api("GET", "/v1/apps/%s/betaFeedbackCrashSubmissions?limit=5&sort=-createdDate" % app_id).get("data", [])
    if not subs:
        ann("warning", "Отчётов о падениях из TestFlight нет")
        return
    for sub in subs[:3]:
        a = sub.get("attributes", {})
        head = "%s · %s · iOS %s · %s" % (a.get("createdDate", ""), a.get("deviceModel", ""), a.get("osVersion", ""),
                                         a.get("comment") or "")
        try:
            log = api("GET", "/v1/betaFeedbackCrashSubmissions/%s/crashLog" % sub["id"]).get("data", {})
            text = (log.get("attributes") or {}).get("logText") or ""
        except ApiError as e:
            ann("error", head + " — отчёт не получить: " + str(e))
            continue
        lines = text.splitlines()
        keep = [l for l in lines if l.startswith(("Version:", "Exception Type", "Exception Reason", "Termination Reason",
                                                  "Crashed Thread", "Exception Codes", "Triggered by Thread"))]
        crashed = []
        for i, l in enumerate(lines):
            if l.startswith("Thread ") and "Crashed" in l:
                crashed = [x for x in lines[i + 1:i + 40] if x.strip()][:30]
                break
        if not crashed and text.lstrip().startswith("{"):
            crashed = [text[:4000]]
        ann("error", "ПАДЕНИЕ " + head + " | " + " | ".join(keep))
        frames = [x for x in crashed if "Kliko" in x or "libswift" in x or "SwiftUI" in x or "Foundation" in x][:18] or crashed[:18]
        ann("error", "Кадры: " + " | ".join(" ".join(x.split()) for x in frames))


if __name__ == "__main__":
    commands = {"revoke-dev-certs": revoke_dev_certs, "next-build-number": next_build_number, "crashes": crashes}
    if len(sys.argv) >= 2 and sys.argv[1] == "iap-sync" and sys.argv[2:] in ([], ["--apply"]):
        iap_sync(apply=sys.argv[2:] == ["--apply"])
    elif len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit("usage: asc.py " + "|".join(commands) + "|iap-sync [--apply]")
    else:
        commands[sys.argv[1]]()
