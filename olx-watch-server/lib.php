<?php
// OLX Watch — серверная часть на обычном PHP-хостинге kliko.kz.
// То же, что телеграм-бот olx-watcher (Node), только для iPhone-приложения: сборщик
// запускается cron'ом раз в минуту, лента и поиски — через api.php, новые объявления —
// пушем через APNs (тот же ключ .p8, что у Kliko: один ключ на все приложения команды).
//
// Короткий код в ссылке объявления — номер в 62-ричной записи: «IDr9sfK» = 401214632.
// Номера сквозные, поэтому «турбо» проверяет следующие номера напрямую — объявление
// ловится до того, как попадёт в поиск (в том числе на проверке).

declare(strict_types=1);

const OLX_BASE = 'https://www.olx.kz';
const B62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

function cfg(string $key, $default = null) {
    static $c = null;
    if ($c === null) {
        $file = getenv('OLXW_CONFIG') ?: __DIR__ . '/config.php';
        $c = is_file($file) ? require $file : [];
    }
    return $c[$key] ?? $default;
}

// ---------- номера объявлений ----------

function decode_id(string $code): int {
    $n = 0;
    foreach (str_split($code) as $ch) {
        $v = strpos(B62, $ch);
        if ($v === false) throw new InvalidArgumentException("не код объявления: $code");
        $n = $n * 62 + $v;
    }
    return $n;
}

function encode_id(int $n): string {
    $s = '';
    do { $s = B62[$n % 62] . $s; $n = intdiv($n, 62); } while ($n > 0);
    return $s;
}

function id_from_url(string $url): ?int {
    if (preg_match('/-ID([0-9a-zA-Z]+)\.html/', $url, $m)) return decode_id($m[1]);
    if (preg_match('/#(\d{6,})$/', $url, $m)) return (int)$m[1];
    return null;
}

function ad_link(array $ad): string {
    $base = !empty($ad['url']) && preg_match('#^https?://#', $ad['url'])
        ? explode('#', $ad['url'])[0]
        : OLX_BASE . '/d/obyavlenie/-ID' . encode_id((int)$ad['id']) . '.html';
    return $base . '#' . $ad['id'];
}

// ---------- HTTP к OLX ----------

class OlxHttpError extends RuntimeException {
    public int $status;
    public function __construct(int $status, string $url) {
        parent::__construct("OLX ответил $status");
        $this->status = $status;
    }
}

// Свой список корневых сертификатов (cacert.pem рядом): на части хостингов системный
// устарел, и curl отвечает «certificate has expired» на исправные сертификаты OLX и Apple.
// Проверку сертификатов не отключаем — просто даём ей свежий список.
function ca_opts(): array {
    $ca = (string)cfg('ca_file', __DIR__ . '/cacert.pem');
    return is_readable($ca) ? [CURLOPT_CAINFO => $ca] : [];
}

// Подменяется в тестах.
$GLOBALS['OLX_FETCH'] = function (string $url, string $accept): array {
    $ch = curl_init($url);
    curl_setopt_array($ch, ca_opts() + [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_ENCODING => '',
        CURLOPT_HTTPHEADER => ["User-Agent: " . UA, "Accept: $accept", 'Accept-Language: ru-RU,ru;q=0.9,kk;q=0.8'],
    ]);
    $body = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    if ($body === false) throw new RuntimeException("нет связи с OLX: $err");
    return [$code, (string)$body];
};

function http_get(string $url, string $accept): array {
    return ($GLOBALS['OLX_FETCH'])($url, $accept);
}

function newest_first(string $url): string {
    $u = parse_url($url);
    if (!$u || !preg_match('/(^|\.)olx\.kz$/', $u['host'] ?? '')) throw new InvalidArgumentException('Нужна ссылка на поиск olx.kz');
    parse_str($u['query'] ?? '', $q);
    $q['search']['order'] = 'created_at:desc';
    return 'https://' . $u['host'] . ($u['path'] ?? '/') . '?' . http_build_query($q);
}

function fetch_search(string $url): array {
    [$code, $html] = http_get(newest_first($url), 'text/html');
    if ($code >= 400) throw new OlxHttpError($code, $url);
    return parse_search_html($html);
}

function parse_search_html(string $html): array {
    if (preg_match('/window\.__PRERENDERED_STATE__\s*=\s*("(?:[^"\\\\]|\\\\.)*")/s', $html, $m)) {
        $inner = json_decode($m[1], true);
        $state = is_string($inner) ? json_decode($inner, true) : null;
        $raw = is_array($state) ? find_ads_array($state) : null;
        if ($raw) return ['source' => 'state', 'ads' => array_values(array_filter(array_map('normalize_listing_ad', $raw), fn($a) => $a['id']))];
    }
    preg_match_all('/-ID([0-9a-zA-Z]+)\.html/', $html, $mm);
    $ids = array_values(array_unique(array_map('decode_id', $mm[1])));
    return ['source' => 'links', 'ads' => array_map(fn($id) => base_ad(['id' => $id, 'url' => OLX_BASE . '/d/obyavlenie/-ID' . encode_id($id) . '.html']), $ids)];
}

function find_ads_array($node, int $depth = 0): ?array {
    if (!is_array($node) || $depth > 6) return null;
    if (array_is_list($node)) {
        if ($node && count(array_filter($node, fn($x) => is_array($x) && isset($x['id']) && (isset($x['title']) || isset($x['url'])))) === count($node)) return $node;
        return null;
    }
    if (isset($node['ads']) && is_array($node['ads']) && ($r = find_ads_array($node['ads'], $depth + 1))) return $r;
    foreach ($node as $v) if ($r = find_ads_array($v, $depth + 1)) return $r;
    return null;
}

function base_ad(array $a): array {
    return $a + ['id' => 0, 'title' => '', 'url' => '', 'price' => null, 'price_label' => '', 'city' => '', 'region' => '',
        'category_id' => null, 'created_at' => null, 'status' => '', 'promoted' => false, 'business' => false,
        'user_id' => null, 'user_name' => '', 'params' => [], 'description' => '', 'photo' => ''];
}

function normalize_listing_ad(array $a): array {
    $p = $a['price'] ?? [];
    return base_ad([
        'id' => (int)($a['id'] ?? 0),
        'title' => (string)($a['title'] ?? ''),
        'url' => (string)($a['url'] ?? ''),
        'price' => num($p['regularPrice']['value'] ?? $p['value'] ?? null),
        'price_label' => (string)($p['displayValue'] ?? $p['label'] ?? ''),
        'city' => (string)($a['location']['cityName'] ?? $a['location']['city']['name'] ?? ''),
        'category_id' => intn($a['category']['id'] ?? $a['categoryId'] ?? null),
        'created_at' => ts($a['createdTime'] ?? $a['created_time'] ?? null),
        'promoted' => !empty($a['isPromoted']) || !empty($a['promotion']['top_ad']) || !empty($a['promotion']['highlighted']),
        'business' => !empty($a['isBusiness']) || !empty($a['business']),
        'user_id' => $a['user']['id'] ?? $a['userId'] ?? null,
        'photo' => photo_url($a['photos'][0] ?? null),
    ]);
}

// Карточка по номеру. null — на OLX.kz такого номера нет (ещё не создан, удалён, чужая страна).
function fetch_offer(int $id): ?array {
    [$code, $body] = http_get(OLX_BASE . "/api/v1/offers/$id/", 'application/json');
    if ($code === 404 || $code === 410) return null;
    if ($code >= 400) throw new OlxHttpError($code, "offer $id");
    $j = json_decode($body, true);
    if (!is_array($j)) throw new RuntimeException('OLX вернул не JSON');
    return normalize_offer($j['data'] ?? $j);
}

function normalize_offer(array $o): array {
    $params = is_array($o['params'] ?? null) ? $o['params'] : [];
    $price = null;
    $rest = [];
    foreach ($params as $p) {
        if (($p['key'] ?? '') === 'price' || ($p['type'] ?? '') === 'price') $price = $p;
        else $rest[] = ($p['name'] ?? '') . ': ' . ($p['value']['label'] ?? $p['value']['value'] ?? '');
    }
    $pv = $price['value'] ?? [];
    $id = (int)($o['id'] ?? 0);
    return base_ad([
        'id' => $id,
        'title' => (string)($o['title'] ?? ''),
        'url' => (string)($o['url'] ?? (OLX_BASE . '/d/obyavlenie/-ID' . encode_id($id) . '.html')),
        'description' => mb_substr(strip_html((string)($o['description'] ?? '')), 0, 600),
        'price' => num($pv['value'] ?? null),
        'price_label' => (string)($pv['label'] ?? (isset($pv['value']) ? $pv['value'] . ' ₸' : '')),
        'city' => (string)($o['location']['city']['name'] ?? ''),
        'region' => (string)($o['location']['region']['name'] ?? ''),
        'category_id' => intn($o['category']['id'] ?? null),
        'created_at' => ts($o['created_time'] ?? null),
        'status' => (string)($o['status'] ?? ''),
        'promoted' => !empty($o['promotion']['top_ad']) || !empty($o['promotion']['highlighted']),
        'business' => !empty($o['business']),
        'user_id' => $o['user']['id'] ?? null,
        'user_name' => (string)($o['user']['name'] ?? ''),
        'params' => array_slice($rest, 0, 6),
        'photo' => photo_url($o['photos'][0] ?? null),
    ]);
}

function photo_url($p): string {
    $link = is_string($p) ? $p : ($p['link'] ?? $p['url'] ?? '');
    return $link ? str_replace(['{width}', '{height}'], ['800', '600'], $link) : '';
}

function num($v): ?float {
    return is_numeric($v) ? (float)$v : null;
}

// Номера рубрик — целые: после JSON в базе 1234.0 становится 1234, и строгое сравнение
// дробного с целым молча не совпадало бы.
function intn($v): ?int {
    return is_numeric($v) ? (int)$v : null;
}

function ts($v): ?int {
    if (!$v) return null;
    $t = strtotime((string)$v);
    return $t === false ? null : $t;
}

function strip_html(string $s): string {
    $s = preg_replace('#<br\s*/?>#i', "\n", $s);
    $s = html_entity_decode(strip_tags($s), ENT_QUOTES | ENT_HTML5, 'UTF-8');
    return trim(preg_replace("/\n{3,}/", "\n\n", $s));
}

// ---------- фильтры турбо ----------

function filters_from_url(string $url): array {
    $u = parse_url($url);
    $path = urldecode($u['path'] ?? '');
    parse_str($u['query'] ?? '', $q);
    $words = preg_match('#/q-([^/]+)/?#', $path, $m) ? str_replace('-', ' ', $m[1]) : (string)($q['search']['q'] ?? '');
    $words = array_values(array_filter(preg_split('/\s+/u', mb_strtolower($words)), fn($w) => mb_strlen($w) > 1));
    $from = $q['search']['filter_float_price:from'] ?? null;
    $to = $q['search']['filter_float_price:to'] ?? null;
    return ['words' => $words, 'price_from' => is_numeric($from) ? (float)$from : null, 'price_to' => is_numeric($to) ? (float)$to : null];
}

function learn(array $learned, array $ads): array {
    $cats = array_map('intval', $learned['category_ids'] ?? []);
    $cities = $learned['cities'] ?? [];
    $total = $learned['total'] ?? 0;
    foreach ($ads as $a) {
        if ($a['category_id'] !== null && !in_array($a['category_id'], $cats, true)) $cats[] = $a['category_id'];
        if ($a['city'] !== '' && !in_array($a['city'], $cities, true)) $cities[] = $a['city'];
        $total++;
    }
    return ['category_ids' => $cats, 'cities' => array_slice($cities, 0, 50), 'total' => $total];
}

function sub_matches(array $sub, array $ad): bool {
    $f = filters_from_url($sub['url']);
    $L = $sub['learned'];
    $text = mb_strtolower($ad['title'] . ' ' . $ad['description']);
    foreach ($f['words'] as $w) if (mb_strpos($text, $w) === false) return false;
    if ($f['price_from'] !== null && $ad['price'] !== null && $ad['price'] < $f['price_from']) return false;
    if ($f['price_to'] !== null && $ad['price'] !== null && $ad['price'] > $f['price_to']) return false;
    $cats = array_map('intval', $L['category_ids'] ?? []);
    if ($cats && $ad['category_id'] !== null && !in_array($ad['category_id'], $cats, true)) return false;
    $cities = $L['cities'] ?? [];
    if (($L['total'] ?? 0) >= 20 && count($cities) === 1 && $ad['city'] !== '' && $ad['city'] !== $cities[0]) return false;
    if (!$f['words'] && !$cats) return false; // без фильтров турбо не шлёт — иначе полетит весь OLX
    return true;
}

// ---------- база ----------

function db(): PDO {
    static $pdo = null;
    if ($pdo) return $pdo;
    $file = cfg('db_file', __DIR__ . '/data/watch.db');
    if (!is_dir(dirname($file))) mkdir(dirname($file), 0700, true);
    $pdo = new PDO('sqlite:' . $file, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
    $pdo->exec('PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;');
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS subs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, url TEXT NOT NULL,
            paused INTEGER NOT NULL DEFAULT 0, initialized INTEGER NOT NULL DEFAULT 0, learned TEXT NOT NULL DEFAULT '{}',
            last_poll INTEGER NOT NULL DEFAULT 0, last_error TEXT NOT NULL DEFAULT '', sent INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS ads (id INTEGER PRIMARY KEY, found_at INTEGER NOT NULL, via TEXT NOT NULL DEFAULT '',
            sub_ids TEXT NOT NULL DEFAULT '', data TEXT NOT NULL DEFAULT '', shown INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS ads_found ON ads (found_at);
        CREATE TABLE IF NOT EXISTS devices (token TEXT PRIMARY KEY, updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
    ");
    return $pdo;
}

function kv_get(string $k, $default = null) {
    $st = db()->prepare('SELECT v FROM kv WHERE k = ?');
    $st->execute([$k]);
    $v = $st->fetchColumn();
    return $v === false ? $default : json_decode($v, true);
}

function kv_set(string $k, $v): void {
    db()->prepare('INSERT INTO kv (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v')->execute([$k, json_encode($v, JSON_UNESCAPED_UNICODE)]);
}

function subs_all(): array {
    return array_map(fn($r) => ['learned' => json_decode($r['learned'], true) ?: []] + $r, db()->query('SELECT * FROM subs ORDER BY id')->fetchAll());
}

function sub_update(int $id, array $patch): void {
    if (isset($patch['learned'])) $patch['learned'] = json_encode($patch['learned'], JSON_UNESCAPED_UNICODE);
    $allowed = ['name', 'paused', 'initialized', 'learned', 'last_poll', 'last_error', 'sent'];
    $keys = array_values(array_intersect(array_keys($patch), $allowed));
    if (!$keys) return;
    $sql = 'UPDATE subs SET ' . implode(', ', array_map(fn($k) => "$k = ?", $keys)) . ' WHERE id = ?';
    db()->prepare($sql)->execute([...array_map(fn($k) => $patch[$k], $keys), $id]);
}

// «Видели» = есть строка в ads. data пустая — объявление просто запомнено (первый проход, старьё).
function ad_seen(int $id): bool {
    $st = db()->prepare('SELECT 1 FROM ads WHERE id = ?');
    $st->execute([$id]);
    return (bool)$st->fetchColumn();
}

function ad_remember(int $id): bool {
    $st = db()->prepare('INSERT OR IGNORE INTO ads (id, found_at) VALUES (?, ?)');
    $st->execute([$id, time()]);
    return $st->rowCount() > 0;
}

function ad_store(array $ad, string $via, array $subIds): void {
    db()->prepare('INSERT INTO ads (id, found_at, via, sub_ids, data, shown) VALUES (?, ?, ?, ?, ?, 1)
        ON CONFLICT(id) DO UPDATE SET via = excluded.via, sub_ids = excluded.sub_ids, data = excluded.data, shown = 1')
        ->execute([$ad['id'], time(), $via, implode(',', $subIds), json_encode($ad, JSON_UNESCAPED_UNICODE)]);
}

function prune(): void {
    db()->prepare('DELETE FROM ads WHERE found_at < ?')->execute([time() - 14 * 86400]);
}

// ---------- APNs ----------

// JWT для APNs живёт до часа; держим 50 минут. Подпись openssl — DER, APNs ждёт r||s.
function apns_jwt(): string {
    $cached = kv_get('apns_jwt');
    if ($cached && $cached['exp'] > time()) return $cached['jwt'];
    $key = openssl_pkey_get_private('file://' . cfg('apns_key_p8'));
    if (!$key) throw new RuntimeException('Не читается ключ APNs .p8 (apns_key_p8 в config.php)');
    $b64 = fn($s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    $msg = $b64(json_encode(['alg' => 'ES256', 'kid' => cfg('apns_key_id')])) . '.' . $b64(json_encode(['iss' => cfg('apns_team_id'), 'iat' => time()]));
    openssl_sign($msg, $der, $key, OPENSSL_ALGO_SHA256);
    $jwt = $msg . '.' . $b64(der_to_raw($der));
    kv_set('apns_jwt', ['jwt' => $jwt, 'exp' => time() + 3000]);
    return $jwt;
}

function der_to_raw(string $der): string {
    $pos = (ord($der[1]) & 0x80) ? 3 : 2;
    $out = '';
    for ($i = 0; $i < 2; $i++) {
        $len = ord($der[$pos + 1]);
        $int = substr($der, $pos + 2, $len);
        $out .= str_pad(ltrim($int, "\x00"), 32, "\x00", STR_PAD_LEFT);
        $pos += 2 + $len;
    }
    return $out;
}

// Подменяется в тестах.
$GLOBALS['APNS_SEND'] = function (string $token, array $payload): int {
    $host = cfg('apns_env', 'production') === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    $ch = curl_init("https://$host/3/device/$token");
    curl_setopt_array($ch, ca_opts() + [
        CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_HTTPHEADER => [
            'authorization: bearer ' . apns_jwt(),
            'apns-topic: ' . cfg('apns_bundle_id', 'kz.kliko.olxwatch'),
            'apns-push-type: alert',
            'apns-priority: 10',
        ],
    ]);
    curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    return $code;
};

// Пуш — необязательная часть: без ключа APNs или при сбое Apple объявление всё равно
// попадает в ленту, а сборщик идёт дальше.
function push_ad(array $ad, array $subs, string $via): void {
    $p8 = (string)cfg('apns_key_p8', '');
    if ($p8 === '' || !is_readable($p8)) return;
    try {
        push_ad_unsafe($ad, $subs, $via);
    } catch (Throwable $e) {
        kv_set('last_push_error', ['at' => time(), 'msg' => $e->getMessage()]);
    }
}

function push_ad_unsafe(array $ad, array $subs, string $via): void {
    $price = $ad['price_label'] ?: ($ad['price'] !== null ? number_format($ad['price'], 0, '.', ' ') . ' ₸' : '');
    $payload = [
        'aps' => [
            'alert' => [
                'title' => ($via === 'turbo' ? '⚡ ' : '') . $ad['title'],
                'subtitle' => implode(' · ', array_filter([$price, $ad['city']])),
                'body' => implode(', ', array_map(fn($s) => $s['name'], $subs)),
            ],
            'sound' => 'default',
            'thread-id' => 'sub-' . ($subs[0]['id'] ?? 0),
        ],
        'ad_id' => $ad['id'],
        'url' => ad_link($ad),
    ];
    foreach (db()->query('SELECT token FROM devices')->fetchAll(PDO::FETCH_COLUMN) as $token) {
        $code = ($GLOBALS['APNS_SEND'])($token, $payload);
        if ($code === 410) db()->prepare('DELETE FROM devices WHERE token = ?')->execute([$token]); // приложение удалено — токен умер
    }
}
