# Kliko для iOS — подготовка к App Review

Решение владельца: платные цифровые услуги (ТОП и поднятия объявлений, Kliko PRO, слоты, комбо-пакеты, пакеты
Kliko AI, ТОП резюме) в iOS-приложении продаются **только через Apple In-App Purchase** (правило 3.1.1). Сайт
kliko.kz продаёт их картой, как раньше. Приложение **не показывает** ни ссылок, ни кнопок оплаты на сайте, ни слов
«дешевле на сайте», ни цен сайта в тенге (правила 3.1.1 и 3.1.3) — ни при выключенных, ни при включённых покупках.

Код: `Sources/Native/Purchases/` (StoreKit 2), рубильник `Config.цифровыеПокупки` (сейчас `false`), сервер —
`docs/APPLE_IAP_SERVER.md`. Пока рубильник выключен, StoreKit не вызывается вовсе, экраны показывают только сведения
и текст «Эта возможность недоступна в приложении.».

---

## 1. Товары App Store Connect

Product id — байт в байт из `enum ПродуктыApple` (`Sources/Native/Purchases/StoreKitStore.swift`). Reference Name —
внутреннее имя в App Store Connect (его не видят покупатели). Display Name и Description — то, что увидят человек и
проверяющий; завести на русском, казахском и английском.

| Product ID | Тип в коде | Рекомендуемый тип в ASC | Reference Name | Display Name (ru / en) | Description для проверки (en) |
|---|---|---|---|---|---|
| `kz.kliko.app.promo.top3` | consumable | Consumable | Promo TOP 3 days | ТОП 3 дня / TOP for 3 days | Pins one of the user's published listings to the top of search results for 3 days. |
| `kz.kliko.app.promo.combo7` | consumable | Consumable | Promo Combo 7 days + 2 bumps | ТОП 7 дней + 2 поднятия / TOP 7 days + 2 bumps | Listing in TOP for 7 days plus 2 bumps to the top of the feed. |
| `kz.kliko.app.promo.top14b5` | consumable | Consumable | Promo TOP 14 days + 5 bumps | ТОП 14 дней + 5 поднятий / TOP 14 days + 5 bumps | Listing in TOP for 14 days plus 5 bumps. |
| `kz.kliko.app.promo.top30b9` | consumable | Consumable | Promo TOP 30 days + 9 bumps | ТОП 30 дней + 9 поднятий / TOP 30 days + 9 bumps | Listing in TOP for 30 days plus 9 bumps. |
| `kz.kliko.app.promo.bump1` | consumable | Consumable | Promo Bump x1 | Поднятие / Bump | Moves one listing to the top of the feed once. |
| `kz.kliko.app.resume.top7` | consumable | Consumable | Resume TOP 7 days | Резюме в ТОП на 7 дней / Résumé in TOP for 7 days | Shows the user's résumé at the top of the jobs section for 7 days. |
| `kz.kliko.app.slots.20` | consumable | Non-Renewing Subscription (рекомендуется) или Consumable | Slots +20 30 days | +20 объявлений на 30 дней / +20 listing slots for 30 days | Raises the number of simultaneously active listings by 20 for 30 days. |
| `kz.kliko.app.slots.50` | consumable | то же | Slots +50 30 days | +50 объявлений на 30 дней / +50 listing slots for 30 days | Raises the active listings limit by 50 for 30 days. |
| `kz.kliko.app.slots.100` | consumable | то же | Slots +100 30 days | +100 объявлений на 30 дней / +100 listing slots for 30 days | Raises the active listings limit by 100 for 30 days. |
| `kz.kliko.app.slots.200` | consumable | то же | Slots +200 30 days | +200 объявлений на 30 дней / +200 listing slots for 30 days | Raises the active listings limit by 200 for 30 days. |
| `kz.kliko.app.combo.start` | consumable | то же | Combo Start | Комбо «Старт» / Combo Start | 20 extra listing slots and unlimited Kliko AI listing analysis for 7 days. |
| `kz.kliko.app.combo.active` | consumable | то же | Combo Active | Комбо «Актив» / Combo Active | 50 extra listing slots and unlimited Kliko AI for 14 days. |
| `kz.kliko.app.combo.max` | consumable | то же | Combo Max | Комбо «Макс» / Combo Max | 100 extra listing slots and unlimited Kliko AI for 30 days. |
| `kz.kliko.app.ai.week` | consumable | то же | Kliko AI 7 days | Kliko AI на 7 дней / Kliko AI for 7 days | Removes the Kliko AI limit (photo recognition, listing check) for 7 days. |
| `kz.kliko.app.ai.month` | consumable | то же | Kliko AI 30 days | Kliko AI на 30 дней / Kliko AI for 30 days | Removes the Kliko AI limit for 30 days. |
| `kz.kliko.app.ai.quarter` | consumable | то же | Kliko AI 90 days | Kliko AI на 90 дней / Kliko AI for 90 days | Removes the Kliko AI limit for 90 days. |
| `kz.kliko.app.ownai.month` | consumable | то же | Own AI 30 days | Свой ИИ — 30 дней / Own AI — 30 days | Lets the user connect their own AI provider key in their Kliko account for 30 days; Kliko AI features in the account then run on that key. |
| `kz.kliko.app.pro.business.month` | auto_renewable | Auto-Renewable Subscription, группа «Kliko PRO», 1 месяц | Kliko PRO Business Monthly | Kliko PRO / Kliko PRO | Monthly business subscription: storefront, higher listing limit, Kliko AI days, price list, analytics, CRM and 1C integrations. Renews automatically. |

Замечания:

- **Тарифы слотов.** Экран сам строит id `kz.kliko.app.slots.<N>` по числам из `slots.tiers` ответа сервера
  (`my_items`). Заводить надо ровно те N, что отдаёт сервер (в коде по умолчанию 10, 25, 50, 100 — сверить).
- **Тип пакетов на срок.** Слоты, комбо и Kliko AI дают доступ на 7/14/30/90 дней. Apple относит «доступ на ограниченный
  срок» к Non-Renewing Subscription; такой тип надёжнее проходит проверку, чем Consumable. Код работает с обоими
  типами одинаково (сайт получает каждую транзакцию, срок считает сервер), меняется только выбор при создании товара.
  ТОП, поднятие и ТОП резюме — разовые «ускорения» конкретной записи, для них Consumable — обычная практика.
- **PRO уровней 2 и 3.** Если появятся — `kz.kliko.app.pro.<key>.month` в той же группе «Kliko PRO», уровнем выше.
- **Цены.** Ценовые точки App Store по витрине Казахстана. Комиссия — 15 % при участии в App Store Small Business
  Program, иначе 30 %. Цена в приложении — только `Product.displayPrice`; цены сайта в приложении не показываются.
- **Скриншот для проверки** (Review Screenshot, у каждого товара): снимок окна покупки этого товара на iPhone
  (6,7″ или 6,5″) из TestFlight-сборки с включённым рубильником: заголовок услуги, строка товара с ценой App Store,
  «Разовая покупка» или «Подписка · 1 мес. · продлевается автоматически», что входит, кнопка покупки. Для PRO в кадре
  должны быть условия автопродления, «Управление подпиской», «Восстановить покупки» и ссылки на условия и
  политику конфиденциальности (прокрутить до подвала — можно вторым снимком в App Review Notes).
- **Review Notes у каждого товара** (поле в самом товаре): где его найти — см. пути в разделе 3.

---

## 2. Что проверяющий увидит в приложении (правило 3.1.2 для PRO)

Окно покупки (`ЭкранПокупкиApple`, `PurchaseSheet.swift`):

- название услуги и пояснение; у каждого товара — название, **цена `Product.displayPrice`**, **срок** («Разовая
  покупка» или «Подписка · 1 мес. · продлевается автоматически»), **что входит** (список);
- кнопка «Купить за …» / «Оформить за … / 1 мес.»;
- у PRO — текст условий автопродления (продление каждый месяц, отмена не позднее 24 ч до конца периода, списание с
  Apple ID), кнопка **«Управление подпиской»** (системный лист `manageSubscriptionsSheet`), ссылка на **условия
  использования Apple (EULA)**;
- всегда — **«Восстановить покупки»** (`AppStore.sync`), ссылки **«Пользовательское соглашение»**, **«Публичная
  оферта»**, **«Политика конфиденциальности»** — страницы kliko.kz открываются своим окном приложения, без браузера;
- итог покупки: готово; ждёт одобрения («Попросить купить», SCA); отменено («Покупка отменена. Деньги не списаны.»);
  ошибка App Store; «Покупка сохранится и применится позже», если сервер Kliko не ответил.

Внизу «Платных услуг» — карточка «Покупки через App Store»: «Восстановить покупки», «Управление подпиской», условия.

Транзакции: слушатель `Transaction.updates` запускается с запуска приложения; транзакция закрывается (`finish`)
**только после подтверждения сервера** (`POST /api/apple_iap.php`), иначе повторяется при следующем запуске, при
входе в аккаунт и из «Восстановить покупки».

---

## 3. Где в приложении покупки (для Review Notes)

- Кабинет → Для бизнеса → **Платные услуги**: Kliko PRO, Продвижение, Слоты объявлений, Комбо-пакеты, Пакеты
  Kliko AI; внизу — «Восстановить покупки» и «Управление подпиской».
- Кабинет → **Мои объявления**: у опубликованного объявления — «Продвинуть» / «Продлить ТОП»; карточка «Доступно» —
  «Расширить» (слоты) и «Пакет Kliko AI»; окно лимита — «Расширить лимит»; в блоке «Работа» у резюме — «В ТОП».
- **Подача объявления**: лист «Опубликовано» — «Продвинуть объявление»; окно лимита слотов — «Расширить лимит».
- «Поделиться» / студия роликов — автопостинг в Instagram и TikTok требует PRO (предложение PRO).
- Разделы бизнеса с замком «Доступно в тарифе PRO» (прайс-лист, аналитика, налоги, интеграции, импорт) — «Оформить PRO».

---

## 4. Текст App Review Notes (вставить в App Store Connect → App Review Information → Notes)

```
Kliko.kz is a classifieds marketplace for Kazakhstan (buy/sell goods, services, rentals, jobs).

DIGITAL SERVICES — IN-APP PURCHASE ONLY
All paid digital services inside the iOS app are sold exclusively through Apple In-App Purchase (StoreKit 2):
- Listing promotion (TOP placement, bumps) and Résumé TOP — consumables;
- Listing slots, combo packs and Kliko AI packs — time-limited packs (7/14/30/90 days);
- Kliko PRO — auto-renewable monthly subscription (group "Kliko PRO").
The app does not link to, mention or steer users to any other way of paying for these digital services. Prices in
the app come only from the App Store (Product.displayPrice). "Restore Purchases" and "Manage Subscription" are
available in the purchase sheet and at Cabinet > For business > Paid services. Terms of Use (Apple standard EULA),
our User Agreement, Public Offer and Privacy Policy are linked in the purchase sheet.

Where to find purchases: Cabinet > For business > Paid services; Cabinet > My listings > "Promote" on a published
listing; after publishing a listing > "Promote the listing".

PHYSICAL GOODS AND ESCROW DEALS — OUTSIDE IAP (3.1.3(e) / 3.1.5)
Buyers and sellers trade physical goods and real-world services between each other (electronics, cars, rentals,
repairs). Payment for these goods, the optional safe-deal (escrow) and courier delivery go through a licensed
Kazakh payment provider by bank card, because the goods are consumed outside the app. Inside the app the wallet is
used only for these deals and for payouts to sellers; the app never spends it on digital services.

IDENTITY VERIFICATION (eGov)
Sellers can verify their identity through eGov (Kazakhstan's government digital ID service) to get a "verified
seller" badge and higher limits. It opens the official eGov flow in a web view; it is optional for buyers and is not
required to review the app. Sign in with Apple is available on the sign-in screen.

ACCOUNT DELETION
Cabinet > Settings > Delete account (in-app, step-by-step).

DEMO ACCOUNT
Login: <DEMO_LOGIN — заполнить владельцу>
Password: <DEMO_PASSWORD — заполнить владельцу>
The demo account has published listings so "Promote" is visible. Purchases in review use the Sandbox environment.
```

Демо-аккаунт: завести отдельный тестовый аккаунт (не личный), с 2–3 опубликованными объявлениями и резюме, без
реальных денег на кошельке. Реквизиты вписать только в App Store Connect, **не в репозиторий**.

---

## 5. Проверка перед отправкой: частые причины отказа

| Причина отказа | Правило | Состояние в приложении | Что сделать |
|---|---|---|---|
| Цифровые услуги мимо IAP, ссылки/кнопки оплаты на сайте, «дешевле на сайте» | 3.1.1, 3.1.3 | ✅ Кнопок и ссылок оплаты на сайте нет ни в одной ветке кода; покупки — только StoreKit за `Config.цифровыеПокупки` | Не добавлять адреса оплаты. **Сервер**: страницы сайта, открытые внутри приложения (WKWebView, кабинет), обязаны прятать покупки (NOTE `klkAppNoDigital`) — проверить на живой сборке |
| Кошелёк пополняется картой в приложении и может тратиться на цифровые услуги | 3.1.1 | ⚠️ `Config.деньгиКошелька = true`: пополнение картой в приложении включено | **Сервер/владелец**: деньги кошелька, пополненные из приложения, не должны тратиться на ТОП/PRO/слоты/Kliko AI; либо пополнение только под сделку (физические товары). Иначе проверяющий сочтёт это обходом IAP |
| Промокод, меняющий цену цифровых услуг вне App Store | 3.1.1 | ✅ Поле промокода клуба выключено (`ПродуктыApple.промокодКлуба = false`) | Включать, только если сервер применяет код и к покупкам Apple (бонус после чека), а не как скидку на оплату на сайте |
| Подписка без условий, цены, срока, EULA, политики, восстановления | 3.1.2 | ✅ Всё в окне покупки PRO и в «Платных услугах» | В App Store Connect в описании приложения добавить ссылку на Terms of Use (EULA) и Privacy Policy URL |
| Товары не отправлены вместе со сборкой / товар «Missing Metadata» | 2.1 | — | Отправить товары вместе с первой сборкой с `цифровыеПокупки = true`; у каждого — скриншот и описание |
| Удаление аккаунта только на сайте | 5.1.1(v) | ✅ «Удалить аккаунт» — своим листом шагов в Настройках (`ЛистУдаленияАккаунта`) | Проверить, что удаление доходит до конца без перехода в браузер |
| Сторонний вход без Sign in with Apple | 4.8 | ✅ Вход через Apple — нативный лист (`ВходApple`); eGov — государственная идентификация, не соцвход | Проверить, что `apple_auth.php?action=native` работает на проде (иначе откат на страницу сайта) |
| Строки назначения разрешений | 5.1.1 | ✅ В `project.yml`: NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSPhotoLibraryAddUsageDescription, NSLocationWhenInUseUsageDescription, NSFaceIDUsageDescription — с примерами | Разрешения просить только по действию человека (не при запуске) — проверить пуши: `requestPushAuthorization()` в `AppDelegate` вызывается при запуске; лучше спрашивать после входа или по действию |
| Манифест конфиденциальности (Required Reason API: UserDefaults, дата файла, время загрузки системы) | 5.1.2, ITMS-91053 | ⚠️ `PrivacyInfo.xcprivacy` в проекте нет | Добавить `PrivacyInfo.xcprivacy` в цель Kliko (UserDefaults — CA92.1) и в виджет; иначе App Store Connect пришлёт предупреждение/отказ при загрузке |
| Скрытые функции, удалённые рубильники | 2.3.1, 2.5.2 | ✅ Рубильники `Config.*` — константы времени сборки, с сервера не переключаются; код не скачивается | Первую сборку с покупками отправлять уже с `true`, не включать покупки «потом» без новой проверки |
| Метки приватности (App Privacy / nutrition labels) | 5.1.2 | — | Указать: контакты (телефон, имя, e-mail), идентификаторы (id пользователя), местоположение (примерное/точное — при «Рядом»), фото и видео (объявления), сообщения (чат), покупки (история IAP), финансовая информация (платёжные данные сделок у провайдера), данные верификации (eGov). Трекинга нет — ATT не нужен, если нет рекламных SDK |
| Экспорт шифрования | — | ✅ `ITSAppUsesNonExemptEncryption: false` (только системный HTTPS) | — |
| Минимальная функциональность «сайт в обёртке» | 4.2 | ✅ Основные экраны нативные (SwiftUI); веб — только запасные страницы | Не допускать, чтобы проверяющий попадал в веб-кабинет с кнопками покупки |
| Пользовательский контент без модерации и жалоб | 1.2 | ✅ Жалоба на объявление и продавца, модерация Kliko AI, блокировка | Указать в Review Notes, что жалобы и блокировка есть (при запросе) |

---

## 6. Порядок включения покупок

1. App Store Connect → Business: соглашение **Paid Apps**, банк, налоги; заявка в **Small Business Program** (15 %).
2. Товары из таблицы раздела 1 (id байт в байт), группа подписок «Kliko PRO», скриншоты и описания; App Store
   Server Notifications V2 и ключ In-App Purchase (`docs/APPLE_IAP_SERVER.md`).
3. Сервер `/api/apple_iap.php` и уведомления Apple по `docs/APPLE_IAP_SERVER.md`; проверка в Sandbox и TestFlight:
   покупка, отмена, «Попросить купить», «Восстановить покупки», продление и возврат PRO.
4. `Sources/Config.swift`: `static let цифровыеПокупки = false` → `true`.
5. Отправить сборку на проверку вместе с товарами и текстом раздела 4 (демо-аккаунт — только в App Store Connect).
