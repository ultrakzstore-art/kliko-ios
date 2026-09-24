<?php
// php tests/run.php — без сети: номера, разбор, фильтры, полный цикл поиск+турбо+пуш, подпись APNs.
declare(strict_types=1);
$tmp = sys_get_temp_dir() . '/olxw-test-' . getmypid();
@mkdir($tmp);
$key = openssl_pkey_new(['curve_name' => 'prime256v1', 'private_key_type' => OPENSSL_KEYTYPE_EC]);
openssl_pkey_export_to_file($key, "$tmp/key.p8");
file_put_contents("$tmp/config.php", "<?php return ['api_token' => str_repeat('t', 32), 'db_file' => '$tmp/w.db', 'apns_key_p8' => '$tmp/key.p8', 'apns_key_id' => 'KID', 'apns_team_id' => 'TEAM'];");
putenv("OLXW_CONFIG=$tmp/config.php");
require __DIR__ . '/../watch.php';

$fails = 0;
function check(bool $ok, string $what): void { global $fails; echo ($ok ? 'ok   ' : 'FAIL ') . $what . "\n"; if (!$ok) $fails++; }

// Номера: живой пример.
check(decode_id('r9sfK') === 401214632 && encode_id(401214633) === 'r9sfL', 'r9sfK = 401214632, следующий r9sfL');
check(id_from_url('https://www.olx.kz/d/kk/obyavlenie/hp-IDr9sfK.html#401214632') === 401214632, 'номер из ссылки');
check(ad_link(['id' => 401214632, 'url' => 'https://www.olx.kz/d/obyavlenie/hp-IDr9sfK.html']) === 'https://www.olx.kz/d/obyavlenie/hp-IDr9sfK.html#401214632', 'ссылка с #номером');
parse_str(parse_url(newest_first('https://www.olx.kz/d/elektronika/q-hp/?search%5Bfilter_float_price%3Ato%5D=300000'), PHP_URL_QUERY), $q);
check($q['search']['order'] === 'created_at:desc' && $q['search']['filter_float_price:to'] === '300000', 'поиск «сначала новые», фильтры целы');

// Разбор выдачи.
$state = ['listing' => ['listing' => ['ads' => [['id' => 401214632, 'title' => 'HP 250', 'url' => 'u', 'price' => ['regularPrice' => ['value' => 250000], 'displayValue' => '250 000 ₸'], 'location' => ['cityName' => 'Алматы'], 'category' => ['id' => 1234], 'photos' => ['https://i/x;s={width}x{height}']]]]]];
$html = '<script>window.__PRERENDERED_STATE__= ' . json_encode(json_encode($state)) . ';</script>';
$r = parse_search_html($html);
check($r['source'] === 'state' && $r['ads'][0]['price'] == 250000 && $r['ads'][0]['city'] === 'Алматы' && $r['ads'][0]['photo'] === 'https://i/x;s=800x600', 'разбор данных страницы');
$r = parse_search_html('<a href="/d/obyavlenie/a-IDr9sfK.html"></a><a href="/d/obyavlenie/b-IDr9sfL.html"></a>');
check($r['source'] === 'links' && array_column($r['ads'], 'id') === [401214632, 401214633], 'запасной разбор по ссылкам');

// Фильтры турбо.
$url = 'https://www.olx.kz/d/elektronika/almaty/q-hp-250/?search%5Bfilter_float_price%3Ato%5D=300000';
$learned = learn([], array_map(fn($i) => base_ad(['category_id' => $i % 2 ? 1234 : 1235, 'city' => 'Алматы']), range(1, 25)));
$sub = ['url' => $url, 'learned' => $learned];
$ad = base_ad(['title' => 'Ноутбук HP 250 G9', 'price' => 250000.0, 'category_id' => 1234, 'city' => 'Алматы']);
check(sub_matches($sub, $ad), 'турбо: подходит');
$roundtrip = ['url' => $url, 'learned' => json_decode(json_encode($learned), true)];
check(sub_matches($roundtrip, $ad) && count(learn($roundtrip['learned'], [$ad])['category_ids']) === 2, 'турбо: рубрики переживают сохранение в базу');
check(!sub_matches($sub, ['price' => 350000.0] + $ad), 'турбо: дороже фильтра');
check(!sub_matches($sub, ['title' => 'Lenovo'] + $ad), 'турбо: нет слов');
check(!sub_matches($sub, ['category_id' => 9] + $ad), 'турбо: чужая рубрика');
check(!sub_matches($sub, ['city' => 'Астана'] + $ad), 'турбо: другой город');

// Полный цикл на подставном OLX.
$listing = [];
$offers = [];
$mk = fn($id, $title, $extra = []) => $extra + ['id' => $id, 'title' => $title, 'url' => "https://www.olx.kz/d/obyavlenie/x-ID" . encode_id($id) . ".html", 'price' => ['regularPrice' => ['value' => 200000]], 'location' => ['cityName' => 'Алматы'], 'category' => ['id' => 1234], 'createdTime' => date('c')];
$GLOBALS['OLX_FETCH'] = function (string $u, string $accept) use (&$listing, &$offers): array {
    if (preg_match('#/api/v1/offers/(\d+)/#', $u, $m)) {
        return isset($offers[(int)$m[1]]) ? [200, json_encode(['data' => $offers[(int)$m[1]]])] : [404, ''];
    }
    return [200, '<script>window.__PRERENDERED_STATE__= ' . json_encode(json_encode(['listing' => ['listing' => ['ads' => $listing]]])) . ';</script>'];
};
$pushes = [];
$GLOBALS['APNS_SEND'] = function (string $token, array $payload) use (&$pushes): int { $pushes[] = $payload; return 200; };
db()->exec("INSERT INTO devices (token, updated_at) VALUES ('" . str_repeat('ab', 32) . "', 0)");
db()->prepare('INSERT INTO subs (name, url, created_at) VALUES (?, ?, ?)')->execute(['Ноуты HP', 'https://www.olx.kz/d/elektronika/q-hp-250/', time()]);
$get = fn() => subs_all()[0];

$listing = [$mk(100, 'HP 250 старое'), $mk(99, 'HP 250 старее')];
poll_sub($get());
check(!$pushes && (int)kv_get('frontier') === 100, 'первый проход молчит, запомнил номер 100');

$listing = array_merge([$mk(105, 'HP 250 G9 новое')], $listing);
poll_sub($get()); poll_sub($get());
check(count($pushes) === 1 && $pushes[0]['ad_id'] === 105 && str_ends_with($pushes[0]['url'], '#105'), 'новое из поиска — один пуш');

$listing = array_merge([$mk(50, 'HP 250 из Топа', ['createdTime' => date('c', time() - 3 * 3600), 'isPromoted' => true])], $listing);
poll_sub($get());
check(count($pushes) === 1, 'старьё из «Топа» не новое');

$offers[106] = ['id' => 106, 'title' => 'iPhone 13', 'category' => ['id' => 555], 'location' => ['city' => ['name' => 'Алматы']]];
$offers[108] = ['id' => 108, 'title' => 'HP 250 G8', 'status' => 'moderated', 'category' => ['id' => 1234], 'location' => ['city' => ['name' => 'Алматы']],
    'params' => [['key' => 'price', 'value' => ['value' => 180000, 'label' => '180 000 ₸']], ['key' => 'state', 'name' => 'Состояние', 'value' => ['label' => 'Б/у']]]];
turbo_tick(5);
check(count($pushes) === 2 && $pushes[1]['ad_id'] === 108 && str_starts_with($pushes[1]['aps']['alert']['title'], '⚡'), 'турбо поймал 108 раньше поиска, 106 чужое');
check((int)kv_get('frontier') === 108, 'номер-граница сдвинулся на 108');

$listing = array_merge([$mk(108, 'HP 250 G8')], $listing);
poll_sub($get());
check(count($pushes) === 2 && (int)$get()['sent'] === 2, 'из поиска 108 второй раз не пришёл');

$feed = db()->query('SELECT id, via FROM ads WHERE shown = 1 ORDER BY id DESC')->fetchAll();
check(array_column($feed, 'id') === [108, 105] && $feed[0]['via'] === 'turbo', 'лента: 108 (турбо), 105 (поиск)');

// Подпись APNs: JWT из трёх частей, подпись 64 байта (r||s).
$jwt = apns_jwt();
$parts = explode('.', $jwt);
check(count($parts) === 3 && strlen(base64_decode(strtr($parts[2], '-_', '+/'))) === 64, 'JWT APNs подписан ES256');

// Ключ APNs указан, но файла нет — объявления всё равно идут в ленту, сборщик не падает.
file_put_contents("$tmp/config2.php", "<?php return ['db_file' => '$tmp/w.db', 'apns_key_p8' => '/нет/такого/AuthKey.p8'];");
$before = count($pushes);
$GLOBALS['APNS_SEND'] = function () { throw new RuntimeException('не должно вызываться'); };
check((function () { try { push_ad(base_ad(['id' => 1, 'title' => 't']), [['id' => 1, 'name' => 'x']], 'search'); return true; } catch (Throwable $e) { return false; } })(), 'пуш без ключа не роняет сборщик');

// 403 от OLX — пауза.
$GLOBALS['OLX_FETCH'] = fn() => [429, ''];
poll_sub($get());
check(blocked(), '429 → пауза');

array_map('unlink', glob("$tmp/*"));
@rmdir($tmp);
echo $fails ? "\n$fails FAILED\n" : "\nвсё ок\n";
exit($fails ? 1 : 0);
