# Отзывает сертификаты разработки, выпущенные прошлыми сборками через ключ API
# («Created via API»): иначе Apple упирается в лимит сертификатов. Distribution не трогает.
import base64, json, os, subprocess, time, urllib.request

kid, iss = os.environ['KID'], os.environ['ISS']
key = os.path.join(os.environ['KEY_DIR'], 'AuthKey_%s.p8' % kid)
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=')
now = int(time.time())
msg = (b64(json.dumps({'alg': 'ES256', 'kid': kid, 'typ': 'JWT'}).encode()) + b'.'
       + b64(json.dumps({'iss': iss, 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode()))
der = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', key], input=msg, capture_output=True, check=True).stdout
# Подпись openssl — DER: SEQUENCE { INTEGER r, INTEGER s }. JWT ждёт r||s по 32 байта.
pos = 3 if der[1] & 0x80 else 2
def integer(p):
    n = der[p + 1]
    return der[p + 2:p + 2 + n], p + 2 + n
r, pos = integer(pos)
s, _ = integer(pos)
raw = r.lstrip(b'\x00').rjust(32, b'\x00') + s.lstrip(b'\x00').rjust(32, b'\x00')
jwt = (msg + b'.' + b64(raw)).decode()

def call(method, url):
    req = urllib.request.Request(url, method=method, headers={'Authorization': 'Bearer ' + jwt})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
        return json.loads(data) if data else {}

api = 'https://api.appstoreconnect.apple.com/v1/certificates'
certs = call('GET', api + '?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200').get('data', [])
print('сертификатов разработки:', len(certs))
отозвано = 0
for c in certs:
    a = c.get('attributes', {})
    имя = '%s | %s' % (a.get('name') or '', a.get('displayName') or '')
    print(' -', имя, a.get('certificateType'), a.get('expirationDate'))
    if 'Created via API' not in имя:
        continue
    call('DELETE', api + '/' + c['id'])
    отозвано += 1
print('отозвано:', отозвано)
