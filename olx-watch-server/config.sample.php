<?php
// Скопируйте в config.php и заполните. config.php в репозиторий не попадает.
return [
    // Секрет для приложения: длинная случайная строка (от 24 символов). Её же вводите в iPhone.
    // Сгенерировать: php -r "echo bin2hex(random_bytes(24)), PHP_EOL;"
    'api_token' => '',

    // База SQLite. Лучше вне веб-корня.
    'db_file' => __DIR__ . '/data/watch.db',

    // Пуши — тот же ключ APNs .p8, что у Kliko (ключ один на все приложения команды).
    'apns_key_p8' => '/абсолютный/путь/AuthKey_XXXXXXXXXX.p8',
    'apns_key_id' => 'XXXXXXXXXX',
    'apns_team_id' => 'YYYYYYYYYY',
    'apns_bundle_id' => 'kz.kliko.olxwatch',   // bundle id приложения OLX Watch, не Kliko
    'apns_env' => 'production',                // TestFlight — production

    // Как часто: поиск раз в poll_sec, турбо раз в turbo_sec по turbo_window номеров.
    'poll_sec' => 30,
    'turbo_sec' => 5,
    'turbo_window' => 10,

    // Шаблон ссылки «все объявления автора» ({id} — номер продавца).
    'seller_url' => 'https://www.olx.kz/list/user/{id}/',
];
