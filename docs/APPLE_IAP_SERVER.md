# Покупки App Store на сервере Kliko: спецификация `/api/apple_iap.php`

Этот документ описывает серверную часть платных услуг, которые продаются в iOS-приложении через In-App Purchase (StoreKit 2). Приложение уже готово: `Sources/Native/Purchases/StoreKitStore.swift`, окно покупки `PurchaseSheet.swift`. Покупки выключены рубильником `Config.цифровыеПокупки = false`. Включать его можно только после того, как на сервере заработают оба адреса из этого документа.

Зачем всё это: правило App Store **3.1.1** запрещает продавать цифровые услуги внутри iOS-приложения иначе как через In-App Purchase. Кошелёк и карта сайта для этого не годятся. К таким услугам относятся ТОП, поднятия, слоты, комбо, PRO, пакеты Kliko AI и ТОП резюме. На сайте всё остаётся как есть: там человек, как и раньше, платит кошельком.

---

## 1. Как проходит покупка

```
Приложение                               App Store                    kliko.kz
    │ Product.products(for: ids)  ───────────►│
    │◄───────── цены (displayPrice) ──────────│
    │ purchase(appAccountToken = T(uid)) ─────►│  (Face ID, списание)
    │◄──── Transaction + JWS (подписан Apple) ─│
    │ POST /api/apple_iap.php {csrf, jws, product, service, key, target_id, …} ──────────►│
    │                                          │   проверка подписи JWS (x5c → Apple Root CA G3)
    │                                          │   bundleId, productId, appAccountToken
    │                                          │   идемпотентность по transactionId
    │                                          │   выдача услуги, как при покупке на сайте
    │◄──────────────────────────────── {ok:true} ─────────────────────────────────────────│
    │ transaction.finish()                     │
    │                                          │── App Store Server Notifications V2 ──►│ /api/apple_iap_notify.php
    │                                          │   (продления PRO, возвраты, истечение) │
```

Ответ `ok` решает судьбу транзакции. Пока его нет, приложение **не закрывает** транзакцию: человек видит «Покупка сохранится и применится позже». Повтор случается в трёх случаях:
- при следующем запуске приложения (`Transaction.unfinished`);
- при входе в аккаунт;
- при нажатии «Восстановить покупки» (`AppStore.sync()`, затем `Transaction.currentEntitlements`).

Поэтому сервер **обязан быть идемпотентным**: один и тот же `transactionId` может прийти много раз, а услуга должна выдаться один раз.

---

## 2. Как найти владельца покупки: `appAccountToken`

Приложение передаёт в Apple `appAccountToken` — UUID, выведенный из id пользователя сайта (`KlikoUser.id`, вида `u0123456789ab`). Apple кладёт этот UUID в каждую транзакцию и каждое уведомление. По нему сервер определяет владельца покупки, даже когда уведомление пришло от Apple без сессии.

Алгоритм совпадает с приложением (`ПродуктыApple.токен(для:)`):

1. Строка: `"kliko.kz/apple-iap/" . $uid` в UTF-8.
2. `SHA-256` от неё, из результата берутся первые 16 байт.
3. `байт[6] = (байт[6] & 0x0F) | 0x50`: версия 5.
4. `байт[8] = (байт[8] & 0x3F) | 0x80`: вариант RFC 4122.
5. Результат записывается строчными буквами по схеме 8-4-4-4-12.

```php
function kliko_apple_token(string $uid): string {
    $b = array_values(unpack('C*', substr(hash('sha256', 'kliko.kz/apple-iap/' . $uid, true), 0, 16)));
    $b[6] = ($b[6] & 0x0F) | 0x50;
    $b[8] = ($b[8] & 0x3F) | 0x80;
    $h = bin2hex(pack('C*', ...$b));
    return substr($h, 0, 8) . '-' . substr($h, 8, 4) . '-' . substr($h, 12, 4) . '-'
         . substr($h, 16, 4) . '-' . substr($h, 20, 12);
}
```

- Токены сравниваются **без учёта регистра**.
- В таблицу пользователей нужно добавить столбец `apple_token CHAR(36)` с индексом. Его заполняют все существующие строки (миграцией) и каждая новая регистрация. Без него уведомлению Apple (§4) не найти пользователя по токену.
- Секрета в токене нет, и он не нужен. Зная чужой uid, можно только оплатить услугу за другого человека. Подлинность покупки проверяет подпись Apple.

---

## 3. `POST /api/apple_iap.php`

Адрес указывается от корня, без `/kz/<язык>/`. Приложение шлёт его через `КабинетСайта.вызвать`: это `fetch` изнутри страницы сайта, с куками сессии, настоящими `Origin` и `Referer`. Тело запроса — JSON, как у остальных `/api/*`.

### 3.1 Запрос

| Поле | Тип | Что это |
|---|---|---|
| `csrf` | string | Токен сессии, как у всех записывающих запросов кабинета. |
| `jws` | string | `VerificationResult.jwsRepresentation`: подписанная Apple транзакция (JWS Compact, ES256, x5c). **Источник правды.** |
| `product` | string | productId, например `kz.kliko.app.promo.top3`. Это подсказка; правда — в JWS. |
| `service` | string | `promo`, `pro`, `slots`, `combo`, `ai`, `resume_top`. |
| `key` | string | Ключ сайта: preset `PROMO_CFG` (`top3`…`top30b9`, `bump1`), pack (`week`/`month`/`quarter`, `start`/`active`/`max`), key тарифа PRO (`business`), число слотов. |
| `target_id` | string | id объявления (`promo`) или резюме (`resume_top`); для остальных — пусто. |
| `transaction_id` | string | `Transaction.id`, строкой. |
| `original_transaction_id` | string | `Transaction.originalID`: у подписки общий для всех продлений. |
| `app_account_token` | string | UUID из §2, строчными буквами. Может быть пустым у транзакций, купленных до этой версии. |

### 3.2 Порядок проверки

1. **Сессия и CSRF.** Проверяются так же, как у `cabinet.php?action=*`. Без сессии сервер отвечает `{ok:false, error:"auth"}`. При устаревшем токене — `{ok:false, error:"csrf"}`: приложение перечитает страницу и повторит запрос один раз.
2. **Подпись JWS** (§3.4). Сервер проверяет цепочку `x5c` до Apple Root CA - G3 и подпись ES256. Если проверка не прошла — `{ok:false, error:"jws"}`: приложение повторит позже и транзакцию не закроет.
3. **Поля полезной нагрузки** (payload JWS, `JWSTransactionDecodedPayload`):
   - `bundleId === "kz.kliko.app"`. Иначе — `{ok:false, finish:true, error:"bundle"}`.
   - `productId` есть в таблице §3.5. Если нет, сервер отвечает `{ok:false, error:"unknown_product"}` **без** `finish`: товар могли завести в App Store Connect раньше, чем обновили сервер.
   - `transactionId === transaction_id` запроса.
   - `appAccountToken` сравнивается с `kliko_apple_token(uid сессии)` без учёта регистра. При несовпадении ответ — `{ok:false, error:"wrong_user"}`: покупку сделал другой аккаунт Kliko на этом телефоне. Транзакция остаётся открытой и уйдёт, когда войдёт её владелец. Если токен пуст, покупка засчитывается пользователю сессии, а случай пишется в журнал.
   - `environment`: принимать и `Production`, и `Sandbox`. App Review проверяет покупки в песочнице **на боевой сборке и боевом сервере**. Отказ в песочнице — это отказ в проверке приложения. Покупки песочницы помечаются в БД (`env='Sandbox'`) и исключаются из выручки.
   - Если есть `revocationDate`, Apple уже вернула деньги. Услугу не выдавать; если она выдана — снять (§4.3). Ответ: `{ok:true, finish:true, revoked:true}`.
   - `type`: `Consumable` или `Auto-Renewable Subscription` должен совпадать с §3.5.
4. **Идемпотентность** (§3.3). Если транзакция уже есть со статусом `granted` или `credit`, ответ — `{ok:true, already:true}`.
5. **Выдача услуги** (§3.5) в той же транзакции БД, что и запись в `apple_iap_tx`.
6. **Ответ** `{ok:true, granted:{…}}`.

### 3.3 Таблицы

```sql
CREATE TABLE apple_iap_tx (
  transaction_id           VARCHAR(32)  NOT NULL PRIMARY KEY,
  original_transaction_id  VARCHAR(32)  NOT NULL,
  user_id                  VARCHAR(32)  NOT NULL,
  product_id               VARCHAR(100) NOT NULL,
  service                  VARCHAR(16)  NOT NULL,
  svc_key                  VARCHAR(32)  NOT NULL,
  target_id                VARCHAR(64)  NOT NULL DEFAULT '',
  env                      VARCHAR(12)  NOT NULL,            -- Production | Sandbox
  purchase_date            DATETIME     NOT NULL,
  expires_date             DATETIME     NULL,                -- у подписки
  status                   VARCHAR(16)  NOT NULL,            -- granted | credit | revoked | failed
  revoked_at               DATETIME     NULL,
  grant_ref                VARCHAR(64)  NULL,                -- id записи продвижения/тарифа, чтобы снять при возврате
  payload_json             MEDIUMTEXT   NOT NULL,            -- декодированный payload, для поддержки
  created_at               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY (original_transaction_id), KEY (user_id)
);

CREATE TABLE apple_iap_subs (                                 -- PRO: одна строка на подписку
  original_transaction_id  VARCHAR(32)  NOT NULL PRIMARY KEY,
  user_id                  VARCHAR(32)  NOT NULL,
  product_id               VARCHAR(100) NOT NULL,
  expires_at               DATETIME     NOT NULL,
  auto_renew               TINYINT(1)   NOT NULL DEFAULT 1,
  grace_until              DATETIME     NULL,
  status                   VARCHAR(16)  NOT NULL,            -- active | grace | expired | revoked
  updated_at               DATETIME     NOT NULL,
  KEY (user_id)
);

CREATE TABLE apple_iap_notifications (                        -- идемпотентность вебхука
  notification_uuid        CHAR(36)     NOT NULL PRIMARY KEY,
  type                     VARCHAR(40)  NOT NULL,
  subtype                  VARCHAR(40)  NULL,
  received_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Порядок записи:
1. `BEGIN`.
2. `SELECT … FROM apple_iap_tx WHERE transaction_id=? FOR UPDATE`. Если строка есть — `already`.
3. Если строки нет: `INSERT`, выдача услуги, `UPDATE status='granted', grant_ref=…`.
4. `COMMIT`.

Первичный ключ защищает от гонки двух одновременных запросов: второй `INSERT` упадёт, и после отката запрос нужно просто перечитать.

### 3.4 Проверка JWS (цепочка `x5c`, без сети)

Корневой сертификат скачивается один раз с `https://www.apple.com/certificateauthority/AppleRootCA-G3.cer` и кладётся в `inc/AppleRootCA-G3.cer` (DER). Проверить его отпечаток: `openssl x509 -inform der -in AppleRootCA-G3.cer -noout -fingerprint -sha256`; сверить с тем, что Apple публикует на той же странице.

```php
function b64url_decode(string $s): string {
    return base64_decode(strtr($s, '-_', '+/') . str_repeat('=', (4 - strlen($s) % 4) % 4));
}

function der_to_pem(string $b64der): string {
    return "-----BEGIN CERTIFICATE-----\n" . chunk_split($b64der, 64, "\n") . "-----END CERTIFICATE-----\n";
}

/** ES256 в JWS — это 64 байта r||s; openssl_verify ждёт DER-последовательность. */
function ecdsa_raw_to_der(string $raw): string {
    $int = function (string $x): string {
        $x = ltrim($x, "\x00");
        if ($x === '' || ord($x[0]) > 0x7F) { $x = "\x00" . $x; }
        return "\x02" . chr(strlen($x)) . $x;
    };
    $seq = $int(substr($raw, 0, 32)) . $int(substr($raw, 32, 32));
    return "\x30" . chr(strlen($seq)) . $seq;
}

/** Возвращает payload или бросает исключение. */
function apple_jws_verify(string $jws): array {
    $parts = explode('.', $jws);
    if (count($parts) !== 3) throw new RuntimeException('jws_format');
    [$h64, $p64, $s64] = $parts;
    $hdr = json_decode(b64url_decode($h64), true);
    if (($hdr['alg'] ?? '') !== 'ES256' || !is_array($hdr['x5c'] ?? null) || count($hdr['x5c']) !== 3) {
        throw new RuntimeException('jws_header');
    }
    // 1) корень — ровно Apple Root CA - G3
    $root = file_get_contents(__DIR__ . '/../inc/AppleRootCA-G3.cer');
    if (base64_decode($hdr['x5c'][2]) !== $root) throw new RuntimeException('jws_root');
    [$leaf, $inter, $rootPem] = array_map('der_to_pem', $hdr['x5c']);
    // 2) подписи цепочки
    if (openssl_x509_verify($leaf, $inter) !== 1)    throw new RuntimeException('jws_leaf');
    if (openssl_x509_verify($inter, $rootPem) !== 1) throw new RuntimeException('jws_inter');
    // 3) сроки и маркеры Apple (OID): лист — 1.2.840.113635.100.6.11.1, промежуточный — 1.2.840.113635.100.6.2.1
    $L = openssl_x509_parse($leaf);
    $I = openssl_x509_parse($inter);
    $now = time();
    foreach ([$L, $I] as $c) {
        if ($now < $c['validFrom_time_t'] || $now > $c['validTo_time_t']) throw new RuntimeException('jws_dates');
    }
    if (!isset($L['extensions']['1.2.840.113635.100.6.11.1'])) throw new RuntimeException('jws_oid_leaf');
    if (!isset($I['extensions']['1.2.840.113635.100.6.2.1']))  throw new RuntimeException('jws_oid_inter');
    // 4) подпись самого JWS ключом листа
    $sig = b64url_decode($s64);
    if (strlen($sig) !== 64) throw new RuntimeException('jws_sig_len');
    $ok = openssl_verify($h64 . '.' . $p64, ecdsa_raw_to_der($sig), openssl_pkey_get_public($leaf), OPENSSL_ALGO_SHA256);
    if ($ok !== 1) throw new RuntimeException('jws_sig');
    $payload = json_decode(b64url_decode($p64), true);
    if (!is_array($payload)) throw new RuntimeException('jws_payload');
    return $payload;
}
```

Требуется PHP 7.4 или новее (`openssl_x509_verify`). Ту же функцию использует вебхук (§4): и `signedPayload`, и вложенные в него `signedTransactionInfo` и `signedRenewalInfo`.

Поля payload транзакции, которые используются: `transactionId`, `originalTransactionId`, `bundleId`, `productId`, `type`, `purchaseDate`, `expiresDate`, `revocationDate`, `revocationReason`, `appAccountToken`, `environment`, `quantity`. Даты приходят в **миллисекундах** Unix.

**Вариант Б: App Store Server API.** Его можно использовать вместо §3.4 или вдобавок к нему. Запрос: `GET https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}`. Для песочницы хост — `api.storekit-sandbox.itunes.apple.com`: пробовать его, если боевой ответил 404. Авторизация — `Authorization: Bearer <JWT>`. JWT подписывается ES256 ключом In-App Purchase из App Store Connect (Users and Access → Integrations → In-App Purchase, файл `.p8` хранить вне webroot). Его заголовок: `{alg:"ES256", kid:"<Key ID>", typ:"JWT"}`, тело: `{iss:"<Issuer ID>", iat, exp: iat+1800, aud:"appstoreconnect-v1", bid:"kz.kliko.app"}`. В ответе `{signedTransactionInfo}` лежит тот же JWS, только полученный от Apple напрямую по TLS. Через этот же API работают `GET /inApps/v1/history/{transactionId}` (история, если потерялась) и `PUT /inApps/v1/transactions/consumption/{transactionId}` (ответ на `CONSUMPTION_REQUEST`, §4.2).

### 3.5 Товары и выдача: «как при покупке на сайте»

Правило: выдача — та же функция, что у покупки за кошелёк, **только без списания**. Из каждого обработчика `cabinet.php?action=…` нужно вынести внутреннюю функцию «выдать услугу». Путь кошелька: списание, затем выдача. Путь Apple: выдача и строка в `apple_iap_tx`. В истории операций кошелька строку можно показать с суммой 0 и подписью «Покупка в App Store», но баланс она не меняет.

| productId | Тип App Store | service / key | Выдать, как… | target |
|---|---|---|---|---|
| `kz.kliko.app.promo.top3` | Consumable | promo / `top3` | `promote_item` `{top_days:3, bumps:0}` | id объявления |
| `kz.kliko.app.promo.combo7` | Consumable | promo / `combo7` | `promote_item` `{top_days:7, bumps:2}` | id объявления |
| `kz.kliko.app.promo.top14b5` | Consumable | promo / `top14b5` | `promote_item` `{top_days:14, bumps:5}` | id объявления |
| `kz.kliko.app.promo.top30b9` | Consumable | promo / `top30b9` | `promote_item` `{top_days:30, bumps:9}` | id объявления |
| `kz.kliko.app.promo.bump1` | Consumable | promo / `bump1` | `promote_item` `{top_days:0, bumps:1}` | id объявления |
| `kz.kliko.app.resume.top7` | Consumable | resume_top / `top7` | `/api/jobs.php?action=promote` (ТОП резюме на 7 дней) | id резюме |
| `kz.kliko.app.slots.<N>` | Consumable | slots / `N` | `buy_slots {slots:N}` (тариф из `slots.tiers`, 30 дней) | — |
| `kz.kliko.app.combo.start` | Consumable | combo / `start` | `buy_combo {pack:"start"}` (20 слотов + Kliko AI 7 дн) | — |
| `kz.kliko.app.combo.active` | Consumable | combo / `active` | `buy_combo {pack:"active"}` (50 + 14 дн) | — |
| `kz.kliko.app.combo.max` | Consumable | combo / `max` | `buy_combo {pack:"max"}` (100 + 30 дн) | — |
| `kz.kliko.app.ai.week` | Consumable | ai / `week` | `buy_ai_package {pack:"week"}` (7 дн) | — |
| `kz.kliko.app.ai.month` | Consumable | ai / `month` | `buy_ai_package {pack:"month"}` (30 дн) | — |
| `kz.kliko.app.ai.quarter` | Consumable | ai / `quarter` | `buy_ai_package {pack:"quarter"}` (90 дн) | — |
| `kz.kliko.app.ownai.month` | Consumable | own_ai / `month` | Premium «Свой ИИ» на 30 дней (как `own_ai_buy`); ответ `{ok:true, granted:{service:"own_ai", until}}` | — |
| `kz.kliko.app.pro.business.month` | Auto-Renewable, группа «Kliko PRO», 1 месяц | pro / `business` | `buy_pro {tier:1}`, но **до `expiresDate` из payload**, а не «+30 дней по часам сервера» | — |

Уточнения к таблице:

- **Параметры берутся из payload и конфигурации сервера** (`PROMO_CFG`, `AI_PACKS`, `COMBO_PACKS`, `slots.tiers`, `PRO_TIERS`). Поля `service`, `key` и `product` из запроса служат только подсказкой. Каждое сверяется с таблицей по `productId` из JWS.
- **Цену не сверять.** Apple берёт свою цену по витрине, и выдаётся одна и та же услуга, сколько бы человек ни заплатил. Скидки сайта (`discount_pct`, `AI_DISC`, промокоды) к покупкам через App Store не применяются.
- **target_id** проверяется так же, как у `promote_item` и `jobs promote`: объявление принадлежит пользователю и опубликовано (`approved`), резюме — его. Если цель не подходит (удалена, снята, чужая), деньги уже списаны Apple. Тогда:
  - записать покупку со статусом `credit` — это оплаченный, но не применённый пакет;
  - ответить `{ok:true, credit:true}`: транзакция закроется, деньги не пропадут;
  - при следующем продвижении на сайте кабинет предложит «У вас есть оплаченный пакет — применить к этому объявлению». Для этого нужен `promote_item` с `apple_credit:<transaction_id>` вместо списания. Пока этого нет, кредит применяет поддержка вручную.
- **Слоты:** `N` должен быть в `slots.tiers` сервера. Товары `kz.kliko.app.slots.<N>` заводятся ровно под эти числа (в приложении по умолчанию стоят 10, 25, 50, 100 — сверить с сервером).
- **PRO:** `apple_iap_subs` обновляется по `originalTransactionId`. Пользователю выставляется `pro_tier=1`, `pro_until=expiresDate`, источник `apple`. Если у человека уже есть PRO с сайта, дата берётся максимальная. PRO, купленный через Apple, сайт не продлевает сам. Отменить его можно только в настройках Apple ID, поэтому кабинет сайта для такого PRO показывает «Подписка App Store — управлять в настройках iPhone» вместо своей кнопки продления.

### 3.6 Ответы

| Ответ | Что делает приложение |
|---|---|
| `{ok:true, granted:{service, until?, target_id?}}` | `finish()`, «Готово — услуга подключена». |
| `{ok:true, already:true}` | `finish()`: выдано раньше. |
| `{ok:true, credit:true}` | `finish()`: оплачено, применится в кабинете. |
| `{ok:true, finish:true, revoked:true}` | `finish()`: Apple уже вернула деньги. |
| `{ok:false, finish:true, error:"bundle"}` | `finish()`: чек не от этого приложения, выдавать нечего никогда. |
| `{ok:false, error:"auth" \| "csrf" \| "wrong_user" \| "jws" \| "unknown_product" \| "server"}` | **Не закрывать.** «Покупка сохранится и применится позже»; повтор при запуске, входе и восстановлении. |

HTTP 5xx и любой не-JSON ответ приложение считает временной ошибкой и не закрывает транзакцию.

---

## 4. Вебхук: App Store Server Notifications V2

Адрес: `POST https://kliko.kz/api/apple_iap_notify.php`. Его нужно указать в App Store Connect (App → App Information → App Store Server Notifications) дважды: как Production URL и как Sandbox URL, версия **2**. Сессии и CSRF у этого адреса нет. Подлинность подтверждает только подпись Apple.

### 4.1 Обработка

1. Тело запроса — `{"signedPayload":"<JWS>"}`. Его нужно проверить через `apple_jws_verify` (§3.4).
2. Из payload берутся `notificationType`, `subtype`, `notificationUUID` и `data`: `bundleId` (обязан быть `kz.kliko.app`), `environment`, `signedTransactionInfo`, `signedRenewalInfo`. Оба вложенных JWS тоже проверяются через `apple_jws_verify`.
3. Если `notificationUUID` уже есть в `apple_iap_notifications`, ответить `200` и больше ничего не делать.
4. Пользователь ищется так:
   - по `appAccountToken` транзакции через `users.apple_token`;
   - если не нашёлся — по `apple_iap_tx.original_transaction_id` или `apple_iap_subs`;
   - если и так не нашёлся — записать случай в журнал для поддержки и ответить `200`.
5. Все изменения делаются в одной транзакции БД с записью `notificationUUID`. После этого — **HTTP 200**. Любой другой код ответа Apple считает сбоем и повторяет отправку (по документации — до 5 раз за несколько дней), поэтому 200 отдаётся только после надёжной записи.

### 4.2 Типы уведомлений

| notificationType (subtype) | Действие |
|---|---|
| `SUBSCRIBED` (`INITIAL_BUY`, `RESUBSCRIBE`) | PRO: `apple_iap_subs` active, `pro_until = expiresDate`. Транзакция — в `apple_iap_tx`, идемпотентно; могла уже прийти из приложения. |
| `DID_RENEW` | Продление PRO: новая строка `apple_iap_tx` (новый `transactionId`, тот же `originalTransactionId`), `pro_until = expiresDate`. Работает, даже если человек не открывает приложение. |
| `DID_CHANGE_RENEWAL_STATUS` (`AUTO_RENEW_ENABLED` / `AUTO_RENEW_DISABLED`) | `apple_iap_subs.auto_renew`. PRO остаётся до `expires_at`. |
| `DID_FAIL_TO_RENEW` (`GRACE_PERIOD` или пусто) | Если в `signedRenewalInfo` есть `gracePeriodExpiresDate`, PRO продолжает действовать до этой даты (статус `grace`), иначе ждём `EXPIRED`. |
| `GRACE_PERIOD_EXPIRED`, `EXPIRED` (любой subtype) | PRO заканчивается: `pro_until = expires_at`, статус `expired`. Слоты сверх бесплатных уходят по правилам сайта, как при окончании PRO сейчас. |
| `REFUND` | Apple вернула деньги (§4.3). |
| `REVOKE` | То же, что `REFUND` (семейный доступ; у нас он выключен, но пусть обрабатывается). |
| `REFUND_REVERSED` | Возврат отменён: выдать услугу снова (статус `granted`). |
| `REFUND_DECLINED` | Ничего не делать, только журнал. |
| `CONSUMPTION_REQUEST` | Человек просит вернуть деньги за Consumable. В течение 12 часов желательно отправить `PUT /inApps/v1/transactions/consumption/{transactionId}` (App Store Server API): `customerConsented`, `consumptionStatus` (услуга использована: ТОП уже шёл — `3`), `deliveryStatus: 0`, `platform: 1`, `appAccountToken`, `sampleContentProvided: false`, `lifetimeDollarsPurchased` и `lifetimeDollarsRefunded` (шкалы из документации Apple), `accountTenure`, `playTime: 0`, `userStatus: 1`, `refundPreference`. Без ответа Apple решает сама. |
| `PRICE_INCREASE`, `OFFER_REDEEMED`, `RENEWAL_EXTENDED`, `RENEWAL_EXTENSION` | `RENEWAL_EXTENDED` означает перенос `expiresDate`: обновить `pro_until`. Остальные — только журнал. |
| `TEST` | Ответить `200`. Это проверочный вызов из App Store Server API: `POST /inApps/v1/notifications/test`. |

### 4.3 Возврат (`REFUND` / `REVOKE`, либо `revocationDate` в чеке из приложения)

Строка `apple_iap_tx` получает `status='revoked'` и `revoked_at`. Затем услуга снимается по `grant_ref`:

| Услуга | Что снять |
|---|---|
| promo | Снять ТОП с объявления (`top_until = now`), если он от этой покупки. Неизрасходованные поднятия этого пакета убрать. |
| resume_top | Снять ТОП резюме. |
| slots / combo / ai | Укоротить тариф или пакет на неиспользованный срок этой покупки. Если сверху уже была покупка на сайте, её срок не трогать. |
| pro | `pro_until = now`, статус `revoked`. |

Кошелёк при возврате не трогается и не уходит в минус: деньги возвращала Apple, а не сайт.

---

## 5. Безопасность и эксплуатация

- **Не доверять полям запроса.** Правда — только payload подписанного JWS. `target_id` приходит от клиента, поэтому у него проверяется принадлежность пользователю.
- **Ключ `.p8`** App Store Server API хранится вне webroot, с правами только для пользователя PHP. Key ID и Issuer ID — в `admin_config.php`.
- **Журнал.** Каждый вызов пишется в журнал: uid, transactionId, productId, env, итог. Сам JWS целиком писать можно, это не секрет, но он большой.
- **Надзор.** Нужно оповещение, если за сутки больше N ответов `jws` или `server`. Каждая такая транзакция — оплаченная, но не выданная услуга.
- **Параллельные запросы.** Приложение может прислать одну транзакцию одновременно из покупки и из «Восстановить покупки». От двойной выдачи защищает первичный ключ `transaction_id` (§3.3).
- **Песочница.** Покупки Sandbox выдают услугу так же, иначе App Review не пройдёт. Они не должны попадать в отчёты о выручке и в партнёрские начисления (клуб основателей).
- **`klkAppNoDigital`** на страницах сайта внутри приложения остаётся включённым. Приложение продаёт только своим окном через App Store, а страницы сайта в нём по-прежнему не показывают кнопок оплаты кошельком.

---

## 6. Проверка перед включением `Config.цифровыеПокупки = true`

1. App Store Connect: подписано соглашение **Paid Apps**, заполнены банк и налоги. Все товары из §3.5 созданы, у каждого статус «Ready to Submit», есть скриншот для проверки и описание на ru и kk.
2. Уведомления V2 включены на оба адреса. В ответ на `POST /inApps/v1/notifications/test` приходит `TEST`, и сервер отвечает 200.
3. На устройстве с Sandbox-аккаунтом, в сборке TestFlight с `цифровыеПокупки = true`:
   - купить `promo.top3` на своё объявление: ТОП появился, транзакция закрыта, повторная отправка того же чека отвечает `already`;
   - выключить сеть сразу после оплаты: появилось «Покупка сохранится и применится позже», а после перезапуска с сетью услуга выдана;
   - купить PRO: подписка активна; в песочнице месяц длится 5 минут, `DID_RENEW` приходит и продлевает `pro_until`, после отмены приходит `EXPIRED`;
   - вернуть покупку через Sandbox (Settings → App Store → Sandbox Account → Manage → Refund): пришёл `REFUND`, услуга снята;
   - «Восстановить покупки» на втором устройстве: PRO узнаётся, двойной выдачи нет;
   - войти в приложении другим аккаунтом Kliko с незакрытой покупкой первого: ответ `wrong_user`, транзакция не закрыта; после входа первым аккаунтом она применилась.
4. Только после этого — `Config.цифровыеПокупки = true`, и сборка вместе с товарами уходит на проверку в App Review.
