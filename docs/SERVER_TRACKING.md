# Отслеживание доставки в приложении — что нужно от сервера

Документ для разработчика сайта kliko.kz. Владелец хочет, чтобы статусы доставки (Яндекс Доставка, СДЭК, Казпочта
и другие) показывались **нативно внутри приложения**, без перехода на сайт и на сайты перевозчиков.

Приложение уже умеет это (папка `Sources/Native/Tracking/`) и **работает и без доработок сервера**: берёт то, что
сделка отдаёт сейчас (`clocal.delivery` для Яндекса, `ship_car_*` для СДЭК/Exline/Avis, `track_url`), а трек Казпочты
спрашивает прямо в её публичном API. Как только на сервере появится `escrow.php?action=track`, приложение начнёт
брать всё оттуда — **без обновления приложения**.

Сессия та же, что у сайта: запросы идут изнутри страницы кабинета (кука сессии, `Origin`/`Referer` kliko.kz), пути
относительные — `/kz/<язык>/escrow.php`.

---

## 0. Безопасность — главное правило

* **Ключи перевозчиков живут только на сервере**: `client_secret` СДЭК, OAuth-токен Яндекс Доставки B2B, ключ
  партнёрского API Казпочты. В приложение, в ответы API и в HTML страниц они не попадают никогда.
* Приложение напрямую ходит только в API **без ключа** (сейчас — публичный трекинг Казпочты). Всё остальное — через
  `escrow.php?action=track`.
* Трек и статусы сделки видят **только её участники** (покупатель, продавец, получатель-подарок) и модераторы.
  Для чужой сделки — `{"ok":false,"error":"access"}`.
* Ссылки, которые сервер отдаёт в `public_url`, — только `https://` и только хосты служб из белого списка (тот же,
  что в `set_track`, см. §4). Приложение повторно проверяет хост и чужие ссылки не показывает.
* Номер курьера — только подменный (voice forwarding), настоящий не отдаётся (как сейчас `clocal_courier_phone`).

---

## 1. Новый эндпоинт: `GET escrow.php?action=track&id=<deal_id>`

Только чтение, без `csrf` (как `action=deal`).

### Ответ — успех

```json
{
  "ok": true,
  "role": "buyer",
  "track": {
    "carrier": "cdek",
    "carrier_name": "СДЭК",
    "track_no": "1234567890",
    "status": "in_transit",
    "status_text": "Отправлен в г. Алматы",
    "carrier_status": "SENT_TO_RECIPIENT_CITY",
    "eta": 1790150400,
    "eta_to": 1790323200,
    "etas": [
      {"target": "pickup",  "at": 1790001200},
      {"target": "dropoff", "at": 1790003400}
    ],
    "updated_at": 1790000000,
    "next_poll": 600,
    "live": false,
    "public_url": "https://www.cdek.kz/ru/tracking?order_id=1234567890",
    "courier": {
      "name": "Ерлан",
      "car": "Hyundai Solaris",
      "car_color": "белый",
      "plate": "123ABC02",
      "phone": "",
      "ext": "",
      "call": true,
      "code": "4821",
      "code_for": "",
      "code_left": 3,
      "code_sms": false,
      "lat": 43.2389,
      "lon": 76.8897
    },
    "events": [
      {"at": 1790000000, "status": "in_transit", "text": "Отправлен в г. Алматы", "place": "Астана"},
      {"at": 1789900000, "status": "accepted",   "text": "Принят на склад отправителя", "place": "Астана"}
    ]
  }
}
```

| Поле | Тип | Обяз. | Описание |
|---|---|---|---|
| `role` | string | нет | `seller` / `buyer` / `recipient` (получатель подарка: видит только доставку, без цены и данных покупателя) — роль спрашивающего (от неё подписи сроков и кода). |
| `track.carrier` | string | да | `yandex`, `indrive`, `cdek`, `kazpost`, `dhl`, `exline`, `avis`, `ups`, `fedex`, `other`. |
| `track.carrier_name` | string | нет | Имя для показа, если хотите своё («СДЭК», «Exline»). |
| `track.track_no` | string | нет | Трек-номер (показывается и копируется). |
| `track.status` | string | да | Нормализованный статус — таблица §5. |
| `track.status_text` | string | нет | Готовая подпись на языке запроса (`/kz/<язык>/`). Пусто — приложение возьмёт свою по `status`. |
| `track.carrier_status` | string | нет | Сырой код перевозчика (для Яндекса — `yandex_status`: по нему строится фаза Live Activity). |
| `track.eta`, `eta_to` | unix sec | нет | Ожидаемая доставка; `eta_to` — конец окна («12–14 окт.»). |
| `track.etas[]` | array | нет | Сроки точек курьера: `target` = `pickup` (к продавцу) / `dropoff` (к покупателю) / `return` (обратно продавцу), `at`, опц. `to`. |
| `track.updated_at` | unix sec | да | Когда сервер последний раз получил данные у перевозчика («Обновлено N мин назад»). |
| `track.next_poll` | sec | нет | Через сколько спрашивать снова (15…3600). По умолчанию: 30 с при `live`, иначе 600. |
| `track.live` | bool | нет | Курьер в пути прямо сейчас — приложение опрашивает раз в 30 с, пока карточка на экране. |
| `track.public_url` | string | нет | Публичная страница отслеживания (https, белый список). Приложение откроет её листом Safari **внутри** приложения только если статусов нет совсем. |
| `track.courier` | object | нет | Курьер. `phone` — готовый подменный номер (tel:), `ext` — добавочный; если номера нет, но `call: true`, приложение само вызовет `chat.php?action=clocal_courier_phone`. `code` — код для курьера, `code_for: "return"` — код на возврат. `lat`/`lon` — где курьер (маленькая карта). |
| `track.events[]` | array | нет | Лента, **новые сверху**: `at` (unix sec или ISO 8601), `status` (§5), `text`, `place`. До 50 штук. |

Даты: unix-секунды (предпочтительно) или ISO 8601. Наивные строки `YYYY-MM-DD HH:MM:SS` приложение читает как
время Алматы.

### Ответ — трека нет / ошибки

| Ответ | Когда |
|---|---|
| `{"ok":true,"track":null}` | Отслеживать нечего (сам, из рук в руки; отправка ещё не оформлена). |
| `{"ok":false,"error":"auth"}` | Нет сессии. |
| `{"ok":false,"error":"access"}` | Не участник сделки. |
| `{"ok":false,"error":"not_found"}` | Нет такой сделки. |
| `{"ok":false,"error":"rate"}` | Слишком часто (см. §6). |

Любой другой ответ (не JSON, незнакомая ошибка вроде `bad_action`) приложение считает «сервер пока не умеет» и до
перезапуска этот вызов не повторяет — работает по данным сделки.

### Можно проще: то же внутри `action=deal`

Если удобнее, положите тот же объект в ответ сделки как `deal.track` — приложение его прочитает оттуда (сначала
смотрит `deal.track`, потом `clocal`, `ship_car_*`, `track_url`).

---

## 2. Что приложение читает из сделки уже сейчас (не ломать)

| Поле сделки | Что это |
|---|---|
| `my_role` | seller / buyer |
| `clocal.delivery.yandex_status` | статус заявки Яндекса (коды — как в `clocalYaLabel`) |
| `clocal.delivery.yandex_failed` | курьер не найден / отмена |
| `clocal.delivery.yandex_courier`, `yandex_courier_car`, `yandex_car_color` | курьер, машина, цвет |
| `clocal.delivery.yandex_eta_a` / `_b` / `_r` | unix sec: к продавцу / к покупателю / обратно |
| `clocal.delivery.yandex_code`, `yandex_code_for`, `yandex_code_left`, `yandex_code_sms` | код для курьера |
| `clocal.delivery.yandex_call` | можно звонить (`chat.php?action=clocal_courier_phone`) |
| `clocal.delivery.yandex_pos` | `{lat, lon}` курьера |
| `clocal.delivery.yandex_share_url` | ссылка Яндекса «где курьер» |
| `clocal.delivery.picked_up_at` | когда забрал |
| `ship_mode`, `ship_carrier`, `ship_car{name,kind,days_min,days_max}` | отправка перевозчиком |
| `ship_car_number`, `ship_car_order`, `ship_car_stage`, `ship_car_cancelled`, `ship_car_at`, `ship_car_track_url` | трек, этап (`created/accepted/in_transit/arrived/delivered/returning/returned/cancelled/problem`), дата оформления |
| `carrier{intercity,name,track}` | межгород |
| `track_url` | ссылка отслеживания, вставленная вручную |

Пока нет `action=track`, у СДЭК в приложении видна только текущая стадия `ship_car_stage` (ленту событий
приложение собирает само из смен стадии). С `action=track` появится полная лента.

---

## 3. Интеграции перевозчиков (всё на сервере)

### 3.1 СДЭК — API v2

1. **Токен** (OAuth 2.0 client_credentials), живёт `expires_in` (≈3600 с) — кэшировать, обновлять заранее:
   ```
   POST https://api.cdek.ru/v2/oauth/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=client_credentials&client_id=<ACCOUNT>&client_secret=<SECURE_PASSWORD>
   ```
   Тестовый контур — `https://api.edu.cdek.ru`. `client_id`/`client_secret` — в конфиге сервера (не в git).
2. **Статусы заказа**:
   ```
   GET https://api.cdek.ru/v2/orders?cdek_number=<номер СДЭК>
   GET https://api.cdek.ru/v2/orders/<uuid>          (если храните uuid из car_order)
   Authorization: Bearer <access_token>
   ```
   В ответе `entity.statuses[]` — `{code, name, date_time, city}`; `entity.delivery_detail`, плановая дата —
   `entity.planned_delivery_date` (если есть). Сортировать по `date_time` и отдавать новые сверху.
3. **Вебхук** вместо опроса (рекомендуется):
   ```
   POST https://api.cdek.ru/v2/webhooks
   {"type": "ORDER_STATUS", "url": "https://kliko.kz/hooks/cdek.php?k=<секрет>"}
   ```
   Пришёл статус — обновить кэш сделки (§6), `ship_car_stage` и отправить пуш/Live Activity (`inc/deal_live.php`).
4. Нормализация кодов — таблица §5.

### 3.2 Яндекс Доставка (B2B, «экспресс»/cargo claims)

Токен B2B (OAuth, `Authorization: Bearer …`, `Accept-Language: ru`) — только на сервере. Основные вызовы
(проверьте по актуальной документации Яндекс Доставки для Казахстана):

| Зачем | Вызов |
|---|---|
| Статус и маршрут заявки | `POST /b2b/cargo/integration/v2/claims/info?claim_id=<id>` → `status`, `route_points[]`, `performer_info{courier_name, car_model, car_number, car_color}` |
| Лента изменений по всем заявкам | `POST /b2b/cargo/integration/v2/claims/journal` `{"cursor": "<последний>"}` — опрос раз в 10–30 с одним запросом на все заявки, вместо опроса каждой |
| Где курьер | `GET /b2b/cargo/integration/v2/claims/performer-position?claim_id=<id>` → `position{lat, lon}` |
| Сроки точек | `GET /b2b/cargo/integration/v1/claims/points-eta?claim_id=<id>` → `route_points[].visited_at.expected` |
| Подменный номер курьера | `POST /b2b/cargo/integration/v2/driver-voiceforwarding` `{"claim_id", "point_id"}` → `phone, ext, ttl_seconds` (уже используется в `clocal_courier_phone`) |

Хост: `https://b2b.taxi.yandex.net`. Сервер уже заполняет `clocal.delivery.yandex_*` — для `action=track` те же
данные переложить в формат §1: `carrier:"yandex"`, `carrier_status` = `yandex_status`, `live` = курьер назначен и
заказ не завершён, `etas[]` из `yandex_eta_a/b/r`, `courier{…}` из `yandex_courier*`, `events[]` — из журнала
(`claims/journal`) с временем каждой смены статуса.

### 3.3 Казпочта

* Публичный трекинг, которым пользуется страница `track.kazpost.kz` (без ключа):
  `GET https://track.kazpost.kz/api/v2/<ШПИ>/events` и `GET https://track.kazpost.kz/api/v2/<ШПИ>`.
  Официального описания нет — форма ответа может меняться. Приложение ходит сюда напрямую только как запасной путь.
* Если у Kliko есть договор — партнёрский API Казпочты с ключом (только на сервере).
* ШПИ — формат S10: `RR123456789KZ`, `CC…KZ`, `LP…CN` (2 буквы + 9 цифр + 2 буквы).
* На сервере: кэш 30 мин, `text` события — как пришло, `status` — по словам (§5, «Вручено» → `delivered`,
  «Прибыло в отделение» → `arrived_pickup`, «Возврат» → `returned`…).

### 3.4 Прочие (Exline, Avis, DHL, UPS, FedEx)

По мере подключения — тот же формат §1. Пока API нет — отдавайте `status` по `ship_car_stage` и `public_url`, если
у перевозчика есть публичная страница.

---

## 4. Правка трека: `set_track` (есть) и `set_track_no` (новое)

* **Есть:** `POST escrow.php?action=set_track` `{csrf, deal_id, url}` — ссылка (пусто — убрать). Ошибки
  `track_host`, `track_long`. Сейчас белый список — только Яндекс Go и inDrive.
  **Просьба:** расширить белый список хостов ссылками перевозчиков: `cdek.ru`, `cdek.kz`, `cdek.shopping`,
  `post.kz`, `kazpost.kz`, `dhl.com`, `dhl.kz`, `exline.kz`, `ups.com`, `fedex.com` (поддомены — тоже) — тот же
  список у приложения (`ОпределениеПеревозчика.хосты`).
* **Новое:** `POST escrow.php?action=set_track_no` `{csrf, deal_id, track_no, carrier}` — трек-номер без ссылки
  (человек вставил «1234567890» или «RR123456789KZ»). `carrier` — код §1, определённый приложением по формату
  номера (сервер вправе перепроверить). Ответ `{ok:true, track_no, carrier}` или `{ok:false, error}`:
  `track_no_bad` (формат), `status` (не held/shipped), `access`. Кто может: те же, кто может `set_track`.
  Отдельное действие нужно, потому что `set_track` с пустым `url` **стирает** ссылку.
  После сохранения — подтянуть статусы сразу (не ждать крона), чтобы вторая сторона увидела их в течение минуты.

Пока `set_track_no` нет, приложение на незнакомую ошибку показывает «Сервер пока не принимает трек-номера —
вставьте ссылку на заказ».

---

## 5. Нормализация статусов

| `status` | Смысл | Яндекс (`yandex_status`) | СДЭК (`code`) | `ship_car_stage` | Казпочта (по тексту) |
|---|---|---|---|---|---|
| `created` | Оформлено, ещё не у перевозчика | new, estimating, ready_for_approval, accepted, performer_lookup, performer_draft | ACCEPTED, CREATED | created | «Оформлено», «Регистрация» |
| `accepted` | Принято перевозчиком / курьер едет за товаром | performer_found, pickup_arrived, ready_for_pickup_confirmation | RECEIVED_AT_SHIPMENT_WAREHOUSE, READY_TO_SHIP_AT_SENDING_OFFICE, POSTOMAT_POSTED | accepted | «Приём», «Принято» |
| `in_transit` | В пути | pickuped | TAKEN_BY_TRANSPORTER_FROM_SENDER_CITY, SENT_TO_TRANSIT_CITY, ACCEPTED_IN_TRANSIT_CITY, ACCEPTED_AT_TRANSIT_WAREHOUSE, READY_FOR_SHIPMENT_IN_TRANSIT_CITY, SENT_TO_RECIPIENT_CITY, ACCEPTED_IN_RECIPIENT_CITY | in_transit | «Отправлено», «Сортировка», «Покинуло» |
| `arrived_pickup` | В пункте выдачи / постамате | — | ACCEPTED_AT_PICK_UP_POINT (и постамат — по документации СДЭК) | arrived (ПВЗ) | «Прибыло в отделение», «Ожидает вручения» |
| `out_for_delivery` | Курьер везёт / у двери | delivery_arrived, ready_for_delivery_confirmation | TAKEN_BY_COURIER | arrived (до двери) | «Передано курьеру» |
| `delivered` | Вручено | pay_waiting, delivered, delivered_finish | DELIVERED, POSTOMAT_RECEIVED | delivered | «Вручено», «Выдано» |
| `returned` | Возврат отправителю | returning, return_arrived, ready_for_return_confirmation, returned, returned_finish | RETURNED_TO_SENDER_CITY_WAREHOUSE, RETURNED_TO_RECIPIENT_CITY_WAREHOUSE (возврат) | returning, returned | «Возврат» |
| `problem` | Задержка / не доставлено | failed, performer_not_found | NOT_DELIVERED, INVALID | problem | «Не удалось вручить», «Задержка» |
| `cancelled` | Отменено | cancelled, cancelled_by_taxi, cancelled_with_payment | REMOVED | cancelled | — |
| `unknown` | Не распознано | прочее | прочее | — | прочее |

Приложение само умеет эти же соответствия (на случай, если сервер отдаст только `text`), но надёжнее
нормализовать на сервере.

---

## 6. Кэш и лимиты

* Кэш статуса перевозчика — в БД/Redis по `(carrier, track_no)`:
  Яндекс с активным курьером — 15–30 с (лучше общий `claims/journal`), СДЭК — 10 мин (или вебхук и без опроса),
  Казпочта — 30 мин, конечные статусы (`delivered`, `returned`, `cancelled`) — не опрашивать.
* `action=track` отдаёт из кэша; если кэш старше срока — обновляет в фоне (или синхронно с таймаутом 3–5 с и
  отдачей старого при сбое). Ответ перевозчика с ошибкой — отдавать прежний кэш, `updated_at` не трогать.
* Лимит на пользователя: не чаще 1 запроса в 10 с на сделку (приложение и так не чаще 30 с) — иначе
  `{"ok":false,"error":"rate"}` + прежние данные можно не отдавать.
* СДЭК: токен кэшировать до `expires_in − 60 с`; на 401 — один перезапрос токена.
* Таймауты к перевозчикам — 5 с, повторы с backoff, логирование без секретов.

---

## 7. Вебхуки и пуши

* СДЭК `ORDER_STATUS` → обновить кэш, `ship_car_stage`, отправить пуш участникам («Посылка в пункте выдачи»),
  обновить Live Activity (`inc/deal_live.php` → `apns_send_live`).
* Яндекс: журнал `claims/journal` в кроне раз в 15–30 с → то же.
* Live Activity: в `deal.live` уже есть `statusText`, `etaText`, `phase`, `etaAt`, `courier` — заполнять их из той
  же нормализованной записи (`phase` для Яндекса: search · to_seller · at_seller · to_buyer · at_buyer · delivered ·
  returning).

---

## 8. Проверка

1. Сделка с курьером Яндекса: `action=track` → `carrier:"yandex"`, `live:true`, `courier`, `etas`. В приложении —
   карточка «Отслеживание», курьер, машина, код, «Позвонить курьеру», статус обновляется раз в 30 с.
2. Сделка со СДЭК (`ship_mode=carrier`): лента событий с городами, `eta` из плановой даты.
3. Вставить в приложении «RR123456789KZ» → `set_track_no` → через минуту лента Казпочты.
4. Чужая сделка → `access`. Без сессии → `auth`.
5. Ни в одном ответе нет `client_secret`, токенов и настоящих номеров курьеров.
