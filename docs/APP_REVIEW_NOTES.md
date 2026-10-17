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

## 3а. Примерочная и проверки на странице объявления (для Review Notes)

Владелец 13.10.2026: «нужнее охват всего». Все способы — на странице объявления, под ценой и хлебными крошками: одна
зелёная кнопка, а если способов у раздела несколько — первая большая, остальные рядом под ней (код —
`Sources/Native/TryOn/`, хаб — `TryOnHub.swift`). Ничего не продаётся: ни цен, ни покупок, лимит ИИ — своей фразой.

| Кнопка | Где найти (раздел объявления) | Где работает | Что уходит с телефона |
|---|---|---|---|
| «Примерить вживую» | Одежда › Аксессуары › Очки; Украшения и часы (серьги, колье, часы, браслеты, кольца); Шапки и головные уборы; Смарт-часы | **Телефон**: сначала шаг «Вещь» — вещь вырезается из фото объявления тем же движком Vision, что «ИИ-студия» подачи (можно «Обрезать вручную» рамкой); камера включается только по «Примерить», дальше Vision (лицо, рука) | Ничего: кадры камеры не сохраняются и не отправляются |
| «Поместится ли?» | Дом и сад › Мебель (диван, шкаф, стол, кровать…), Бытовая техника (холодильник, стиральная, плита…), Телевизоры, Мониторы, Ковры, Тренажёры, Детская мебель | **Телефон**: ARKit — коробка реальных размеров из объявления на полу комнаты; переключатель «Коробка / Линейка» — линейка AR меряет нишу или проём и сравнивает с размерами вещи (работает и без размеров). На устройстве без AR (симулятор, Mac) кнопки нет | Ничего |
| «Подойдут ли?» | Транспорт › Автозапчасти › Шины и диски | **Телефон**: сверка с машиной человека (PCD, ET, DIA, диаметр; размер шины, ошибка спидометра, клиренс) | Только марка, модель и год машины — в справочник kliko.kz (`/api/autofit.php`, без входа), чтобы узнать её штатные параметры; машина запоминается на телефоне. Справочник не ответил — параметры человек вводит сам |
| «Примерить на себя» | Одежда, обувь, сумки, аксессуары (кроме детских) | **Сервер** Kliko AI, `kind: person` | Фото человека — после согласия, удаляется сразу по «Удалить фото»/закрытию окна, не позже 24 ч. Если сервер объявил `cutout` — ещё вырезка вещи из публичного фото объявления (`item_cutout`, без личных данных; при лице на фото вещи не уходит) |
| «На свою машину» | Шины и диски (диски и колёса в сборе) | **Сервер**, `kind: car` | Фото машины сбоку (людей в кадре размывают или фото не принимают), те же 24 ч |
| «В моей комнате» | Мебель, телевизоры, ковры, шторы, декор, светильники | **Сервер**, `kind: room` | Фото комнаты (без людей), те же 24 ч |

- Способы на телефоне — за рубильниками `Config.живаяПримерка`, `Config.габаритыAR`, `Config.габаритыЛинейка`,
  `Config.автоПодбор` (все `true`).
- Подача объявления в мебели и крупной технике — обязательный блок «Габариты, см» (Ш × В × Г); «Измерить в AR» в нём —
  та же линейка в режиме замера вещи (три отрезка → поля). Всё на телефоне, на сервер уходят только три числа.
- Способы ИИ — `Config.примерочная = true`, но **кнопки видны, только когда сервер ответил `on: true`** в
  `/api/tryon.php?action=info` (docs/SERVER_TRYON.md). Если к проверке сервер не готов — кнопок ИИ нет, способы на
  телефоне работают; в Review Notes тогда ИИ-способы не упоминать.
- Перед первой отправкой фото — экран согласия: кто обработает фото (поставщик ИИ из ответа сервера), 24 часа, не для
  обучения, «Согласен, примерить» (5.1.2(i)). Гостю окно сначала предлагает войти.
- Разрешения спрашиваются только по нажатию: камера — при открытии съёмки, живой примерки или AR; «Фото» (только
  добавление) — по «Сохранить в Фото». Тексты в `project.yml` упоминают примерку и «поместится ли».
- Что показать проверяющему: любое объявление очков или часов → «Примерить вживую»; дивана или холодильника →
  «Поместится ли?»; дисков → «Подойдут ли?»; одежды → «Примерить на себя» (если сервер включён). Демо-аккаунт — тот же,
  что для покупок (раздел 4).

## 3б. 3D-обзор (для Review Notes; задание сервера 1.13, Б4)

Договор — `docs/SERVER_3D.md` (раздел 12 — что отметить для App Store). Код — `Sources/Native/Posting/Model3D*.swift`
(съёмка в подаче) и просмотр на странице объявления. Рубильники: в приложении `Config.обзор3D = true`, на сервере
`model3d` (360° по ракурсам) и `model3d_build` (сборка модели ИИ, включится после ключа поставщика).

| Что | Где | Что уходит с телефона |
|---|---|---|
| Съёмка 5 ракурсов | Подача → «Подробно» → шаг «Фото» → карточка «3D-обзор · 5 фото» (мебель, техника, электроника, обувь, сумки, машины и похожие разделы) | Пять вырезок вещи (фон убирает Vision на телефоне) — на сервер kliko.kz, после публикации — как фото объявления; неопубликованное удаляется через 24 часа |
| 360° | Объявление со значком «360°»: поворот по ракурсам в рамке фото | Ничего |
| 3D и «В комнате» | Объявление со значком «3D»: модель USDZ, AR Quick Look | Ничего |
| Сборка 3D ИИ | Только при `model3d_build`: перед первой сборкой экран согласия с именем поставщика (`ai`), 24 часа, «не для обучения», «Согласен, собрать 3D» (5.1.2(i)) | Ракурсы — поставщику ИИ через наш сервер |

- Пока `model3d_build` выключен, поставщика ИИ нет: остаётся только 360° по своим фото, экрана согласия нет, в Review
  Notes абзац про ИИ-сборку не упоминать.
- Модели помечены «3D-модель создана ИИ по фото — детали могут отличаться» (1.1/1.2), на объявление есть жалоба.
- Ничего не продаётся; на `limit` — своя фраза приложения, без цен и ссылок (3.1.1).
- Анкета App Privacy: «Фото или видео» уже объявлены (`Privacy/Kliko/PrivacyInfo.xcprivacy`) — сверить в App Store
  Connect. Камера — то же разрешение, что для фото объявления.
- Что показать проверяющему: подать объявление в «Мебели» → «Подробно» → «Фото» → «3D-обзор · 5 фото»; на объявлении
  со значком «360°» или «3D» — повернуть, «В комнате».

## 3в. «Моё» (для Review Notes; 16.10.2026)

Код — `Sources/Native/MyThings/`, рубильник `Config.моё = true`, договор на будущее — `docs/SERVER_MY_THINGS.md`.

| Что | Где найти | Где хранится | Что уходит с телефона |
|---|---|---|---|
| «Мой гараж»: до 5 машин, PCD, ET, DIA, R, шины, фото сбоку по шаблону | Кабинет → «Моё» → «Мой гараж»; из «Подойдут ли?» — «Мой гараж» | Application Support/MyThings на телефоне, вне iCloud и резервной копии | Только марка, модель и год — в справочник kliko.kz (`/api/autofit.php`, без входа и кук), как у «Подойдут ли?» |
| «Мои устройства»: модель телефона (определяется по железу), ноутбук, мониторы, ТВ | Кабинет → «Моё» → «Мои устройства» | там же | Ничего |
| «Мой рост и мерки»: рост, размеры в своей системе, мерки, фото в полный рост | Кабинет → «Моё» → «Мой рост и мерки» | там же; точки позы — Vision на телефоне | Ничего |

- Работает **без входа**: карточка «Моё» видна и гостю. Ничего не продаётся, цен и покупок нет.
- Камера — только по нажатию «Снять по шаблону» (контур машины сбоку или человека в полный рост); текст разрешения
  в `project.yml` упоминает «Моё» и то, что снимки остаются на телефоне (5.1.1(ii)). Галерея — системный выбор фото,
  разрешение на фото не нужно. В Фото iPhone снимки не сохраняются.
- Фото перерисовываются (без EXIF и места съёмки), защищены файловой защитой iOS. Vision только находит точки позы и
  «есть ли люди в кадре» — лица не распознаются, биометрических шаблонов нет. Детских размеров и фото детей нет; на
  камере — совет «Снимайте только себя».
- Удаление (5.1.1(v)): «Удалить всё «Моё»» одним шагом — внизу хаба и в меню «…»; строка «Моё: машины, дом,
  компьютер, гардероб, мерки и фото» в Кабинет → «Данные на телефоне»; у каждой машины, фото и размера — своё «Удалить». Выход из аккаунта
  тоже стирает «Моё» — об этом сказано в окне выхода и под кнопкой «Выйти». Удаление приложения уносит всё.
- «Подходит моему»: на странице объявления шин и дисков, чехлов, сумок для ноутбука, одежды и обуви — плашка «Подходят
  ✓ / Не ваш размер / Проверьте модель» с подписью «Проверили по описанию объявления»; в ленте этих разделов — чип «Для
  моего» (отбор уже загруженных карточек). Всё считается на телефоне, профиль на сервер не уходит.
- Анкета App Privacy и `PrivacyInfo.xcprivacy` не меняются: обработка только на устройстве — не «сбор данных»;
  UserDefaults (CA92.1) и даты файлов (C617.1) уже объявлены, размер «Моего» для кабинета берётся через fileSize.
- Что показать проверяющему: Кабинет → «Моё» → «Мой гараж» → «Добавить машину» → марка, модель, год → «Снять по
  шаблону»; «Мои устройства» — модель телефона определилась сама; «Мой рост и мерки» — линейка роста и «Добавить
  размер»; затем «Удалить всё «Моё»».

## 3г. «Мой дом», «Мой компьютер», «Мой гардероб», «Для вас», «Добавить из моих покупок» (для Review Notes; 16.10.2026)

Версия 1.13. Код — `Sources/Native/MyThings/` (`MyThingsHome*`, `MyThingsPC*`, `MyThingsWardrobe*`,
`MyThingsFromDeals.swift`), полка — `Sources/Native/ForYou/`, сверка по стандартам — `Sources/Native/Standards/`.
Рубильники `Config.мойДом`, `Config.мойКомпьютер`, `Config.мойГардероб`, `Config.покупкиВМоё`, `Config.дляВас`,
`Config.стандарты` — все `true` и все внутри `Config.моё`.

| Что | Где найти | Где хранится | Что уходит с телефона |
|---|---|---|---|
| «Мой дом»: комнаты (размеры, фото, цвета), проёмы, лифт и лестница, кровати, окна, ТВ на стене, свет, техника; «Пройдёт ли в дверь и лифт?» | Кабинет → «Моё» → «Мой дом» | Application Support/MyThings на телефоне, вне iCloud и резервной копии (как в 3в) | Ничего. Цвета с фото комнаты считаются на телефоне, модель с наклейки техники («Снять наклейку») читает Vision на телефоне; снимок наклейки не сохраняется |
| «Мой компьютер»: до 4 компьютеров и ноутбуков, схема, «По снимку экрана», «Можно улучшить» | Кабинет → «Моё» → «Мой компьютер» | там же | Конфигурация компьютера — ничего. Снимок экрана читает Vision на телефоне и не сохраняет. Цена «от N ₸» у варианта — обычная лента раздела (память, накопители, видеокарты, блоки питания, процессоры): в адресе только раздел и город, как если открыть раздел самому. «Найти на Kliko» — обычный поиск, только по нажатию |
| «Мой гардероб»: вещи (фото, вид, цвет, размер), образы, «С чем носить» | Кабинет → «Моё» → «Мой гардероб» | там же; фон вещи убирается и цвет считается на телефоне | Ничего. «Подобрать» в «С чем носить» — по нажатию одна лента раздела (только с фото); цвета и размер в запрос не попадают, отбор — на телефоне |
| «Добавить из моих покупок» | Кабинет → «Моё» → карточка под разделами (нужен вход) | добавленная вещь — в «Моё» на телефоне: название, обложка, цена и месяц покупки видны только владельцу | Только чтение своих завершённых покупок в безопасной сделке (`escrow.php?action=my_deals&role=buyer`, тот же ответ, что у «Моих сделок»); обратно на сервер ничего не пишется. Сделки цифровых кодов не предлагаются |
| «Для вас» | Главная, полка после рядов объявлений; «Все» — экран целиком. Полки нет, пока «Моё» пусто | ответы разделов — 15 минут в памяти; на диске только число разделов, при котором полку скрыли («Скрыть») | Ленты разделов (раздел, город, новые подряд) запросами GET без куков. Значений «Моего» нет ни в адресе, ни в теле: подходящее отбирается на телефоне (крючок отбора на сервере `ОтборСервераДляВас.включён = false`) |

- Работает без входа, кроме «Добавить из моих покупок». Ничего не продаётся, покупок App Store здесь нет; «от N ₸» в
  «Можно улучшить» — цены продавцов в объявлениях физических товаров, как в ленте.
- Камера — только по нажатию: «Снять» у комнаты и у вещи гардероба, «Снять наклейку» у техники, «Измерить в AR»
  у комнаты, проёма, окна и кабины лифта (та же AR-линейка, что у «Поместится ли?»; без AR кнопки нет). Фото
  и снимки экрана — через системный выбор фото (PhotosPicker: «Из галереи», «Из Фото», «Заполнить по снимку экрана» —
  до 4 снимков): приложение получает только выбранное, разрешение на всю медиатеку не спрашивается. В Фото iPhone
  ничего не сохраняется.
- Фото перерисовываются без EXIF и места съёмки и защищены файловой защитой iOS, папка и каждый файл — «не в резервную
  копию» (`isExcludedFromBackup`). Vision на телефоне читает текст (наклейка, снимок экрана), отделяет вещь от фона и
  подсказывает вид вещи («похоже на» — человек подтверждает сам). Лица не распознаются.
- Удаление (5.1.1(v)): «Удалить всё «Моё»» стирает и дом, и компьютеры, и гардероб с образами, и добавленные покупки, и
  отметку «Скрыть» полки «Для вас» (окно подтверждения называет дом, компьютеры и гардероб). Строка «Моё: машины, дом, компьютер, гардероб,
  мерки и фото» в Кабинет → «Данные на телефоне» и выход из аккаунта стирают то же самое.
- ⚠️ Текст разрешения камеры (`NSCameraUsageDescription` в `project.yml`) из «Моего» называет только машину сбоку и
  снимок в полный рост; комнаты, наклейки техники и вещи гардероба в нём не названы. Перед отправкой стоит дописать
  пример (правило 5.1.1(ii)).
- Анкета App Privacy и `PrivacyInfo.xcprivacy` не меняются: обработка только на устройстве, запросы полки — те же
  публичные ленты разделов.
- Что показать проверяющему: Кабинет → «Моё» → «Мой дом» — кровать и лифт чипами, затем «Пройдёт ли в дверь и лифт?»;
  «Мой компьютер» — компьютер или ноутбук и «Можно улучшить»; «Мой гардероб» — вещь, «Снять» или «Из Фото», затем «С чем
  носить» → «Подобрать»; главная → полка «Для вас»; в конце «Удалить всё «Моё»».

## 3д. Цифровые товары (для Review Notes; 16.10.2026)

Код — `Sources/Native/Feed/ListingDigital.swift`, `Sources/Native/Design/ListingDigitalPanel.swift`,
`Sources/Native/Deals/DealDigital.swift`, `Sources/Native/MyListings/MyListingDigital.swift`. Показ —
`Config.цифровоеВПриложенииВСборке = false`; ключ сервера `digital_show` может только выключить показ, включить его может
лишь новая сборка после проверки.

- На сайте есть раздел цифровых кодов (игровые ключи, подарочные карты, лицензии). Приложение их **не показывает и не
  продаёт** (правило 3.1.1): цифровые объявления отбрасываются в ленте, поиске, каталоге, на главной, на карте, в
  избранном и в остальных списках; в подаче такого раздела нет.
- Объявление, открытое по ссылке или пушу, показывает только сведения о коде и строку «Эта возможность
  недоступна в приложении.»: нет «Купить», «Торг» и «Связаться», чат скрыт. Ссылок и слов о покупке на сайте нет.
- Сам код в приложение не приходит и **не открывается** в нём (`digital_reveal` не вызывается нигде). Сделка такого
  кода, купленного вне приложения, показывает в «Моих сделках» только название, сумму и статус, а вместо шагов —
  строку «Цифровой код открывается в веб-версии кабинета» без ссылки.
- Продавец видит свои цифровые объявления в «Моих объявлениях» со значком «Цифровой товар»: снять и удалить можно, править
  в приложении — нет (строка «Правка цифровых товаров — в веб-версии кабинета», без ссылки).

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

TRY-ON AND FIT CHECKS (listing page, under the price)
- "Try on live" (sunglasses, hats, earrings, necklaces, watches, bracelets, rings): runs entirely on the device
  (camera + Vision). Camera frames are neither stored nor uploaded.
- "Will it fit?" (furniture, large appliances, TVs, carpets): ARKit places a box with the item's real dimensions on
  your floor. On-device only.
- "Will they fit?" (tires and wheels): checks bolt pattern, offset, center bore, diameter and tire size against the
  user's car. The check runs on the device; only the car's make, model and year are sent to our server to look up its
  stock wheel specs (no sign-in, no personal data).
- "Try it on" (clothing), "On my car" (wheels) and "In my room" (furniture): an AI image generated on our server from a
  photo the user takes. Shown only after a consent screen that names the AI provider; photos are deleted when the user
  closes the screen or taps "Delete photos", and in any case within 24 hours; never used for training. Requires sign-in.
  These AI buttons appear only while our server has the feature enabled.
Camera and "Add to Photos" permissions are requested only when the user starts one of these features or saves a result.

3D VIEW (seller side, listing page for buyers)
Sell > Detailed > step "Photo" > card "3D view - 5 photos" (furniture, appliances, electronics, shoes, bags, cars and
similar categories). The seller walks around the item and takes 5 photos (front, 45 degrees front-left, side,
45 degrees back-left, back); each photo is cut out on the device with Apple Vision and uploaded to our server.
Buyers see a "360" badge and can spin the item through these photos on the listing page. Where a "3D" badge is shown,
the model can be viewed in the room with AR Quick Look. If an AI-built 3D model is offered, the app first shows a
consent screen naming the AI provider; unpublished photos are deleted within 24 hours and nothing is used to train AI.
AI-built models are labeled as such. Nothing is sold in this flow.

MY THINGS (Cabinet > "My Things", no sign-in needed)
Users can save their car (make, model, year, wheel specs and a side photo taken with an on-screen guide), their devices
(phone model detected on the device, laptop, monitors, TVs) and their height, clothing sizes, body measurements and a
full-length photo, so the app can show listings that fit them: a "Fits mine" note on a listing page (tires and wheels,
phone cases, laptop bags, clothing and shoes, checked against the listing text) and a "Fits mine" chip that filters the
loaded feed, both computed on the device. Everything stays on the device (Application
Support, excluded from backups); photos are re-encoded without metadata and are not saved to the Photos library. Apple
Vision on the device only finds body pose points and whether people are in a car photo; no face recognition. No My
Things data is sent to our server, except the car's make, model and year for the public wheel-spec lookup (no sign-in,
no cookies). The camera is requested only when the user taps "Shoot with guide". "Delete all My Things" removes
everything in one step (in the screen and in Cabinet > Data on this phone); signing out also deletes it, and the
sign-out dialog says so. Nothing is sold here.

MY HOME, MY COMPUTER, MY WARDROBE, "FOR YOU"
In My Things users can also save their home (rooms, doorways, elevator, beds, windows, TV, lighting, appliances; "Will
it fit through the door and lift?"), up to 4 computers ("Fill in from a screenshot": on-device Vision text recognition,
screenshots are not stored; "Upgrade options") and their wardrobe (clothes and outfits; background removal and colors
on the device; "What to wear with"). "Add from my purchases" (sign-in) reads the user's completed safe-deal purchases,
read-only. The "For you" shelf on the Home tab, the "from" prices in "Upgrade options" and "Find matches" load ordinary
public category feeds (category, city and ordinary feed filters only; the shelf without cookies) and match on the
device. When our server announces matching for a category (rules.fit_filters), only size and standard values (e.g.
clothing size, bed size, wheel fitment, phone model) go in a cookie-less POST body to the public listings feed, without
name or account, and are not stored (Cache-Control: private, no-store). My Things itself stays on the device and
"Delete all My Things" erases it. The camera
opens only on "Take photo", "Shoot the sticker" or "Measure in AR"; photos come from the system photo picker (no photo
library access requested). Nothing is sold here.

DIGITAL GOODS (3.1.1)
Digital-code listings (game keys, gift cards, licenses) are not shown or sold in the app: they are filtered out of all
lists and cannot be posted. One opened from a link shows only its details and "This feature is not available in the
app." (no Buy, Offer, Contact or chat); codes are never revealed in the app.

ACCOUNT DELETION
Cabinet > Settings > Delete account (in-app, step-by-step).

DEMO ACCOUNT
Login: <DEMO_LOGIN — заполнить владельцу>
Password: <DEMO_PASSWORD — заполнить владельцу>
The demo account has published listings so "Promote" is visible. Purchases in review use the Sandbox environment.
```

Демо-аккаунт: завести отдельный тестовый аккаунт (не личный), с 2–3 опубликованными объявлениями и резюме, без
реальных денег на кошельке. Реквизиты вписать только в App Store Connect, **не в репозиторий**.

### 4.1. Short version for App Store Connect (≤4000 characters)

Сжатый текст раздела 4 для поля Notes (лимит поля — 4000 знаков; полный текст выше — для справки). Версия 1.13
(сборка 83). Длина — **3884 знака, 3884 единицы UTF-16** (с переводами строк `\r\n` — 3916): `python3 -I`, текст между
```` ``` ```` без последнего перевода строки. После замены заглушек демо-аккаунта на настоящие данные станет короче.
Строки внутри абзацев нарочно не перенесены — вставлять как есть.

Убрано по сравнению с полным текстом: 3D-обзор и 360°, ИИ-примерка («Try it on», «On my car», «In my room»),
«Объявление с ИИ» — на сервере выключены (`tryon` `on: false`, `model3d_build`, `photo_gen`). «Cabinet» заменён на
«Profile» — так вкладка называется в английском интерфейсе (`TabsText`, `CabinetText`). Добавлено по коду 1.13:
значения размеров и стандартов для подбора уходят телом POST без куков, только когда сервер объявил вид в
`rules.fit_filters` (`ForYouServer.swift`, `MyThingsFitRow.swift`; договор — `docs/SERVER_MY_THINGS.md` §8, §10:
не сохраняются, `Cache-Control: private, no-store`); «Ищу…» — обычный сохранённый поиск по нажатию
(`MyThingsWanted.swift`); «Continue with Google» — под Sign in with Apple, когда сервер готов (`SignInView.swift`); «Paid services» видны в
«For business» после «I'm a business» (`CabinetView.swift`); подписи окна покупки — как в `PurchasesText` (en).

```
Kliko.kz: a classifieds marketplace for Kazakhstan (goods, services, rentals, jobs).

DEMO ACCOUNT
Login: <DEMO_LOGIN — заполнить владельцу>
Password: <DEMO_PASSWORD — заполнить владельцу>
The demo account has published listings so "Promote" is visible. Purchases in review use the Sandbox environment.
To sign in: Profile tab > Sign in (phone number and password).

NEW IN 1.13 (no sign-in needed, nothing is sold)
- Profile > My Things: My garage (car, wheel specs), My devices (phone model auto-detected), My height and measurements, My home ("Will it fit through the door and lift?"), My computer ("Fill in from a screenshot", "Upgrade options"), My wardrobe ("What to wear with" > "Find matches").
- "Fits mine" chip in the feed and a fit note on listing pages (e.g. "Your size ✓") for tires, wheels, phone cases, laptop bags, clothes, shoes; matched on the device.
- "For you" shelf on the Feed tab: listings that fit My Things (hidden while My Things is empty).
- Listing page, under the price: "Will it fit?" (furniture, appliances, TVs, carpets): a true-size AR box, plus an AR ruler; "Try on live" (glasses, hats, jewelry, watches): on-device camera + Vision, frames not stored or uploaded; "Will they fit?" (tires and wheels): bolt pattern, offset, center bore, diameter, tire size vs. the user's car.

CAMERA AND PHOTOS
The camera opens only on the user's tap (e.g. "Take photo", "Measure in AR", "Try on live"). Library photos in My Things use the system photo picker (selected photos only, no library access); My Things saves nothing to Photos. "Add to Photos" is asked only on "Save to Photos".

MY THINGS PRIVACY
Stored only on the device, excluded from backups; photos are re-encoded without metadata. Vision runs on the device; no face recognition. Only this leaves the phone: the car's make, model and year for our public wheel-spec lookup (no sign-in, no cookies); if our server supports matching, size and standard values (e.g. clothing size, bed size, wheel fitment, phone model) in a cookie-less POST body to the public listings feed, not stored or linked to the user (Cache-Control: private, no-store); and anything the user explicitly saves or posts (e.g. a "Looking for" search or a listing). "Add from my purchases" (sign-in) reads the user's completed Safe deal purchases, read-only. "Delete all My Things" erases all in one step (in My Things or Profile > Data on this phone); signing out erases it too.

PHYSICAL GOODS AND SAFE DEAL - OUTSIDE IAP (3.1.3(e), 3.1.5)
Payment for physical goods and real-world services between users, the optional Safe deal (escrow) and courier delivery go through a licensed Kazakh payment provider by bank card. The wallet is used only for these deals and seller payouts, never for digital services.

DIGITAL GOODS (3.1.1)
Digital-code listings (game keys, gift cards, licenses) are not shown or sold: filtered out of all lists, cannot be posted. One opened from a link shows only details and "This feature is not available in the app." (no Buy, Offer, Contact or chat); codes are never revealed.

DIGITAL SERVICES - IN-APP PURCHASE ONLY
Listing promotion (TOP, bumps), Résumé TOP, listing slots, combo packs, Kliko AI packages (7/14/30/90 days) and Kliko PRO (auto-renewable monthly subscription) are sold only via Apple In-App Purchase (StoreKit 2), with App Store prices only; no other way to pay is linked or mentioned. Purchase sheet: Restore purchases, Manage subscription, Terms of Use (EULA), Terms of service, Public offer, Privacy policy.
Where: Profile > For business (turn on "I'm a business") > Paid services; Profile > My listings > "Promote"; after publishing a listing > "Promote the listing".

SIGN IN
Sign-in screen: Sign in with Apple; "Continue with Google", if shown, is below it. eGov (government ID) is optional, not needed for review.
Account deletion: Profile > Settings > Delete account (in-app).
```

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
| Сторонний вход без Sign in with Apple | 4.8 | ✅ Вход через Apple — нативный лист (`ВходApple`); eGov — государственная идентификация, не соцвход | Проверить, что `apple_auth.php?action=native` работает на проде (иначе откат на страницу сайта). Когда впишут `KlikoGoogleClientID` (вход через Google, `docs/SERVER_NATIVE_AUTH.md` §3), дописать в Review Notes: «Google — нативно; Sign in with Apple равнозначен и стоит выше» |
| Строки назначения разрешений | 5.1.1 | ✅ В `project.yml`: NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSPhotoLibraryAddUsageDescription, NSLocationWhenInUseUsageDescription, NSFaceIDUsageDescription — с примерами; камера — ещё «примерить вещь на себя или посмотреть, поместится ли она в комнате», Фото — «результат примерки» | В Review Notes — раздел TRY-ON AND FIT CHECKS (раздел 3а): где каждый способ, что на телефоне, что на сервере, 24 ч. Разрешения просить только по действию человека (не при запуске) — проверить пуши: `requestPushAuthorization()` в `AppDelegate` вызывается при запуске; лучше спрашивать после входа или по действию |
| Манифест конфиденциальности (Required Reason API: UserDefaults, дата файла, время загрузки системы) | 5.1.2, ITMS-91053 | ⚠️ `PrivacyInfo.xcprivacy` в проекте нет | Добавить `PrivacyInfo.xcprivacy` в цель Kliko (UserDefaults — CA92.1) и в виджет; иначе App Store Connect пришлёт предупреждение/отказ при загрузке |
| Скрытые функции, удалённые рубильники | 2.3.1, 2.5.2 | ✅ Рубильники `Config.*` — константы времени сборки, с сервера не переключаются; код не скачивается. ⚠️ Исключение — кнопки ИИ-примерки (раздел 3а): видны, только пока сервер отвечает `on: true`; весь код уже в сборке, сервер лишь включает или выключает услугу | Первую сборку с покупками отправлять уже с `true`, не включать покупки «потом» без новой проверки. ИИ-примерку описывать в Review Notes, только если к проверке она включена на сервере; появится позже — упомянуть в следующей сборке |
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
