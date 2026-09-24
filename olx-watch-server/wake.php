<?php
// Будильник для iPhone: cron раз в несколько минут, например
//   */5 * * * * php /полный/путь/olx-watch/wake.php
// Шлёт тихий пуш каждому телефону, подключившему будильник. К OLX не ходит — поэтому
// работает и там, где OLX не пускает запросы с хостинга.

declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__ . '/lib.php';

$r = send_wake();
echo json_encode($r, JSON_UNESCAPED_UNICODE), "\n";
