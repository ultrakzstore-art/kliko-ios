<?php
// API для приложения OLX Watch. Личное: вход по секретному ключу из config.php
// (заголовок Authorization: Bearer <ключ>). Все ответы — JSON.
//
//   GET  ?a=feed[&before=<found_at>]      лента найденного, новые сверху, по 50
//   GET  ?a=subs                          поиски
//   POST ?a=subs      {url, name?}        добавить поиск
//   POST ?a=sub       {id, paused?|name?} изменить поиск
//   POST ?a=sub_del   {id}                удалить поиск
//   POST ?a=device    {token}             токен пушей iPhone
//   POST ?a=turbo     {on}                турбо вкл/выкл
//   GET  ?a=status                        как идут дела
//   POST ?a=test_push                     пробный пуш

declare(strict_types=1);
require_once __DIR__ . '/lib.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function out($data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(string $msg, int $code = 400): void {
    out(['error' => $msg], $code);
}

$secret = (string)cfg('api_token', '');
$auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
$given = preg_match('/^Bearer\s+(.+)$/i', $auth, $m) ? trim($m[1]) : (string)($_SERVER['HTTP_X_TOKEN'] ?? '');
// Проверка из браузера после установки: api.php?a=status&key=<api_token> — только статус, только чтение.
if ($given === '' && ($_GET['a'] ?? '') === 'status' && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET') $given = (string)($_GET['key'] ?? '');
if (strlen($secret) < 24 || !hash_equals($secret, $given)) fail('нет доступа', 401);

$action = (string)($_GET['a'] ?? '');
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$body = $method === 'POST' ? (json_decode((string)file_get_contents('php://input'), true) ?: []) : [];

function sub_out(array $s): array {
    return [
        'id' => (int)$s['id'], 'name' => $s['name'], 'url' => $s['url'], 'paused' => (bool)$s['paused'],
        'ready' => (bool)$s['initialized'], 'sent' => (int)$s['sent'], 'error' => $s['last_error'],
        'last_poll' => (int)$s['last_poll'] ?: null,
    ];
}

function ad_out(array $row): array {
    $a = json_decode($row['data'], true) ?: [];
    $a = base_ad($a);
    return [
        'id' => (int)$row['id'], 'title' => $a['title'], 'url' => ad_link($a), 'price' => $a['price'],
        'price_label' => $a['price_label'], 'city' => $a['city'], 'region' => $a['region'], 'photo' => $a['photo'],
        'created_at' => $a['created_at'], 'found_at' => (int)$row['found_at'], 'via' => $row['via'],
        'status' => $a['status'], 'business' => (bool)$a['business'], 'promoted' => (bool)$a['promoted'],
        'user_name' => $a['user_name'], 'params' => $a['params'], 'description' => $a['description'],
        'seller_url' => $a['user_id'] !== null ? str_replace('{id}', rawurlencode((string)$a['user_id']), (string)cfg('seller_url', OLX_BASE . '/list/user/{id}/')) : null,
        'sub_ids' => array_map('intval', array_filter(explode(',', $row['sub_ids']))),
    ];
}

// Без cron лента всё равно живая: пока приложение открыто, оно спрашивает ленту раз в 20 сек,
// и если cron не отмечался больше двух минут, этот запрос сам проверяет поиски (до ~10 сек).
// Турбо так не крутится — для него нужен cron.
function poll_on_demand(): void {
    if ((int)kv_get('last_cron', 0) > time() - 120) return;
    $lock = fopen(cfg('lock_file', sys_get_temp_dir() . '/olx-watch.lock'), 'c');
    if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) return;
    require_once __DIR__ . '/watch.php';
    $deadline = time() + 10;
    try {
        foreach (subs_all() as $sub) {
            if (time() >= $deadline || blocked()) break;
            if ($sub['paused'] || time() - (int)$sub['last_poll'] < max(10, (int)cfg('poll_sec', 30))) continue;
            poll_sub($sub);
        }
        kv_set('last_on_demand', time());
    } catch (Throwable $e) {
        kv_set('last_error', ['at' => time(), 'msg' => $e->getMessage()]);
    } finally {
        flock($lock, LOCK_UN);
    }
}

try {
    switch ("$method $action") {
        case 'GET feed':
            if (empty($_GET['before'])) poll_on_demand();
            $before = (int)($_GET['before'] ?? 0) ?: PHP_INT_MAX;
            $st = db()->prepare('SELECT * FROM ads WHERE shown = 1 AND found_at < ? ORDER BY found_at DESC, id DESC LIMIT 50');
            $st->execute([$before]);
            out(['ads' => array_map('ad_out', $st->fetchAll())]);

        case 'GET subs':
            poll_on_demand();
            out(['subs' => array_map('sub_out', subs_all())]);

        case 'POST subs':
            $url = trim((string)($body['url'] ?? ''));
            if (id_from_url($url)) fail('Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком.');
            try { newest_first($url); } catch (InvalidArgumentException $e) { fail($e->getMessage()); }
            $name = trim((string)($body['name'] ?? '')) ?: name_from_url($url);
            db()->prepare('INSERT INTO subs (name, url, created_at) VALUES (?, ?, ?)')->execute([mb_substr($name, 0, 60), $url, time()]);
            $id = (int)db()->lastInsertId();
            foreach (subs_all() as $s) if ((int)$s['id'] === $id) out(['sub' => sub_out($s)]);
            fail('не сохранилось', 500);

        case 'POST sub':
            $id = (int)($body['id'] ?? 0);
            $patch = [];
            if (isset($body['paused'])) $patch['paused'] = $body['paused'] ? 1 : 0;
            if (isset($body['name']) && trim((string)$body['name']) !== '') $patch['name'] = mb_substr(trim((string)$body['name']), 0, 60);
            sub_update($id, $patch);
            out(['ok' => true]);

        case 'POST sub_del':
            db()->prepare('DELETE FROM subs WHERE id = ?')->execute([(int)($body['id'] ?? 0)]);
            out(['ok' => true]);

        case 'POST device':
            $token = preg_replace('/[^0-9a-f]/i', '', (string)($body['token'] ?? ''));
            if (strlen($token) < 32) fail('неверный токен');
            db()->prepare('INSERT INTO devices (token, updated_at) VALUES (?, ?) ON CONFLICT(token) DO UPDATE SET updated_at = excluded.updated_at')->execute([$token, time()]);
            out(['ok' => true]);

        case 'POST turbo':
            kv_set('turbo', !empty($body['on']));
            out(['turbo' => (bool)kv_get('turbo', true)]);

        case 'GET status':
            $lastCron = (int)kv_get('last_cron', 0);
            $p8 = (string)cfg('apns_key_p8', '');
            out([
                'php' => PHP_VERSION,
                'extensions' => ['pdo_sqlite' => extension_loaded('pdo_sqlite'), 'curl' => extension_loaded('curl'), 'openssl' => extension_loaded('openssl'),
                    'curl_http2' => defined('CURL_VERSION_HTTP2') && (curl_version()['features'] & CURL_VERSION_HTTP2) !== 0],
                'subs' => (int)db()->query('SELECT COUNT(*) FROM subs')->fetchColumn(),
                'cron_ok' => $lastCron > time() - 180,
                'on_demand_at' => kv_get('last_on_demand'),
                'last_push_error' => kv_get('last_push_error'),
                'last_wake' => kv_get('last_wake'),
                'last_cron' => $lastCron ?: null,
                'turbo' => (bool)kv_get('turbo', true),
                'frontier' => (int)kv_get('frontier', 0) ?: null,
                'last_turbo_hit' => kv_get('last_turbo_hit'),
                'stats' => kv_get('stats', new stdClass()),
                'blocked_until' => ($b = (int)kv_get('backoff_until', 0)) > time() ? $b : null,
                'last_error' => kv_get('last_error'),
                'devices' => (int)db()->query('SELECT COUNT(*) FROM devices')->fetchColumn(),
                'push_ready' => $p8 !== '' && is_readable($p8) && cfg('apns_key_id') && cfg('apns_team_id'),
                'push_problem' => $p8 === '' ? 'не задан apns_key_p8' : (!is_readable($p8) ? 'файл .p8 не найден или не читается: ' . $p8 : null),
            ]);

        case 'POST test_push':
            push_ad(base_ad(['id' => 401214632, 'title' => 'Проверка: пуши работают', 'price_label' => '250 000 ₸', 'city' => 'Алматы',
                'url' => OLX_BASE . '/d/obyavlenie/-IDr9sfK.html']), [['id' => 0, 'name' => 'OLX Watch']], 'search');
            out(['ok' => true]);

        default:
            fail('неизвестное действие', 404);
    }
} catch (Throwable $e) {
    fail('ошибка сервера: ' . $e->getMessage(), 500);
}

function name_from_url(string $url): string {
    $path = urldecode((string)(parse_url($url, PHP_URL_PATH) ?? ''));
    $parts = array_values(array_filter(explode('/', $path), fn($p) => $p !== '' && !in_array($p, ['d', 'kk', 'list'], true)));
    foreach ($parts as $p) if (str_starts_with($p, 'q-')) return str_replace('-', ' ', substr($p, 2));
    return implode(' / ', array_slice($parts, -2)) ?: 'Поиск';
}
