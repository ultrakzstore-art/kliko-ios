# Kliko iOS

Приложение Kliko для iPhone: сайт `kliko.kz` в нативной оболочке плюс то, чего сайт не
умеет — пуши при закрытом приложении, плашка сделки на локскрине, прелоадер, экран без
связи, работа с камерой и микрофоном.

Отдельный репозиторий, **вне** веб-репо `ultra-site`: Swift не должен уезжать на
прод-сервер через `git push hoster`.

## Что это, устройство

**Оболочка, а не второй интерфейс.** В июле 2026 нативные экраны (лента, карточка,
вход, чат) были написаны и затем удалены — держать вторую реализацию витрины и чата
значит чинить каждую правку дважды. Код остался в истории (`387e7ca`), подход и
эндпоинты валидны, если решение когда-нибудь пересмотрят.

Сейчас:

| Слой | Что делает |
|---|---|
| `Sources/Web/WebContainer.swift` | WKWebView: cookie-сессия как в браузере, pull-to-refresh, свайп-назад, гранты камеры и микрофона, `tel:` / WhatsApp / Telegram наружу, оплата и eGov остаются внутри |
| `Sources/Web/SplashView.swift` | прелоадер с логотипом, минимальное время показа |
| `Sources/Web/WebBridge.swift` | мост JS ↔ Swift: токен APNs, `window.KlikoLive`, `window.KlikoNative` |
| `Sources/App/AppDelegate.swift` | регистрация в APNs, deep-link по тапу на пуш |
| `Sources/LiveActivity/` + `WidgetSources/` | Live Activity сделки: локскрин и Dynamic Island |

Веб-часть моста живёт в `ultra-site`: `inc/app_bridge.php` (отдаёт `window.KlikoUser`
и `window.KlikoCsrf`), `api/push_register.php` (приём токена APNs), `inc/apns.php`
(отправка), `js/cabinet.js` → `dealLiveActivity()` (кормит плашку сделки).

## Сборка — в облаке, Mac не нужен

Сборку делает GitHub Actions на macOS-раннере: `.github/workflows/ios.yml`. Подпись —
ключом App Store Connect API, сертификат и профили Xcode создаёт сам
(`-allowProvisioningUpdates`). Ни сертификатов, ни fastlane match, ни своего Mac.

### 1. В кабинете Apple (браузер, Windows подходит)

1. **Identifiers** → App ID `kz.kliko.app`, включить **Push Notifications**.
   Второй App ID `kz.kliko.app.widgets` — для виджета Live Activity.
2. **Keys** → новый ключ с **APNs** → скачать `AuthKey_XXXX.p8` (даётся **один раз**),
   записать **Key ID**. Это ключ для отправки пушей с сервера.
3. **Team ID** — правый верхний угол портала.
4. **App Store Connect → Users and Access → Integrations → App Store Connect API** →
   ключ с ролью **App Manager**: **Issuer ID**, **Key ID**, файл `.p8`.
   Это отдельный ключ, не тот, что для APNs: первый подписывает и заливает сборку,
   второй шлёт уведомления.
5. **App Store Connect → Apps** → создать приложение с bundle id `kz.kliko.app`.

### 2. Секреты репозитория

Settings → Secrets and variables → Actions:

| Секрет | Откуда |
|---|---|
| `APPLE_TEAM_ID` | Team ID из портала |
| `ASC_KEY_ID` | Key ID ключа App Store Connect API |
| `ASC_ISSUER_ID` | Issuer ID оттуда же |
| `ASC_KEY_P8` | тот `.p8` в base64, одной строкой |

В PowerShell на Windows:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))
```

### 3. Запуск

Вкладка **Actions** → «iOS · TestFlight» → **Run workflow**.

Первый прогон — с `upload = false`: соберёт и подпишет, но никуда не отправит, и
покажет, всё ли на месте, не расходуя номер сборки в App Store Connect. Дальше
`upload = true` либо тег `v1.0.0` — сборка уезжает в TestFlight сама.

Номер сборки — номер запуска workflow, повторов не бывает. Версия витрины берётся из
тега (`v1.0.0` → `1.0.0`) или из поля при ручном запуске.

## Пуши: что задать на сервере

В `admin_config.php` (правится руками на сервере, в репозитории его нет):

```php
define('APNS_KEY_ID',   'XXXXXXXXXX');                  // Key ID ключа APNs
define('APNS_TEAM_ID',  'YYYYYYYYYY');                  // Team ID
define('APNS_BUNDLE_ID','kz.kliko.app');
define('APNS_KEY_P8',   '/абсолютный/путь/AuthKey_XXXXXXXXXX.p8');
define('APNS_ENV',      'production');
```

⚠️ **`APNS_ENV` и `aps-environment` в `project.yml` должны совпадать.** Сейчас в
проекте стоит `production` — под TestFlight и App Store. Расхождение не ломает
сборку: APNs просто отвечает `BadDeviceToken`, и пуши молча не доходят.

Файл `.p8` положить вне веб-корня и закрыть от раздачи.

## Локально на Windows

Собрать нельзя — нужен Xcode. Проверять правки можно только прогоном workflow.
Поэтому Swift здесь пишется с расчётом на первый успешный проход: синтаксис
выверяется глазами, а не компилятором.

## Структура

```
project.yml                     — спецификация для XcodeGen (таргеты, entitlements, Info.plist)
.github/workflows/ios.yml       — сборка, подпись, заливка в TestFlight
Sources/
  KlikoApp.swift                — @main → RootWebView
  Config.swift                  — apiBase (домен)
  Theme.swift                   — бренд-палитра
  App/AppDelegate.swift         — APNs, deep-link
  Web/RootWebView.swift         — сцена: сплэш → веб
  Web/WebContainer.swift        — WKWebView и его политика
  Web/WebBridge.swift           — мост JS ↔ Swift
  Web/SplashView.swift          — прелоадер
  LiveActivity/DealActivityManager.swift
Shared/DealActivityAttributes.swift   — общие типы приложения и виджета
WidgetSources/DealLiveActivity.swift  — локскрин и Dynamic Island
```

## Заметки

- Deployment target — iOS 17.
- Домен API меняется в `Sources/Config.swift`.
- Bundle id: приложение `kz.kliko.app`, виджет `kz.kliko.app.widgets`.
