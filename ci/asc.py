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


if __name__ == "__main__":
    commands = {"revoke-dev-certs": revoke_dev_certs, "next-build-number": next_build_number}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit("usage: asc.py " + "|".join(commands))
    commands[sys.argv[1]]()
