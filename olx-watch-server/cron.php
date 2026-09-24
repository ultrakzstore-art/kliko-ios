<?php
// Запуск cron'ом раз в минуту:  * * * * * php /путь/к/olx-watch-server/cron.php
// Внутри крутится ~55 секунд: турбо раз в turbo_sec, поиск — когда подошла очередь.
// Замок не даёт двум запускам работать одновременно, если предыдущий задержался.

declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__ . '/watch.php';

$lock = fopen(cfg('lock_file', sys_get_temp_dir() . '/olx-watch.lock'), 'c');
if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) exit(0);

$pollSec = max(10, (int)cfg('poll_sec', 30));
$turboSec = max(2, (int)cfg('turbo_sec', 5));
$window = max(1, (int)cfg('turbo_window', 10));
$budget = (int)cfg('run_seconds', 55);
$start = time();
kv_set('last_cron', $start);

while (time() - $start < $budget) {
    $tick = microtime(true);
    try {
        turbo_tick($window);
        poll_due_subs($pollSec);
    } catch (Throwable $e) {
        kv_set('last_error', ['at' => time(), 'msg' => $e->getMessage()]);
    }
    $left = $turboSec - (microtime(true) - $tick);
    if ($left > 0 && time() - $start + $left < $budget) usleep((int)($left * 1e6));
    elseif ($left > 0) break;
}
if (random_int(1, 60) === 1) prune();
flock($lock, LOCK_UN);
