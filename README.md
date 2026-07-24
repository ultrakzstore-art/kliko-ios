# Kliko iOS (SwiftUI) — MVP покупателя

Нативное iOS-приложение поверх нашего API (`kliko.kz`). Веб-бэкенд переиспользуется как API.
Это отдельный проект — **вне** веб-репо `ultra-site` (Swift на прод-сервер не деплоим).

## Что уже есть
**Фаза 1 — Лента**: маркет из `GET /api/listings.php` (пагинация, поиск, pull-to-refresh),
карточки (фото `_t`, цена/аренда/«Договорная», бейджи ТОП/Новое/Аренда, город), сеть
`async/await`+`URLSession` (cookie-сессия), бренд-тема, модели `Codable`.

**Фаза 2 — Карточка товара**: тап по карточке → детальный экран (`GET ?id=`): галерея фото
(свайп + точки), цена, состояние/гарантия/город, характеристики (ОЗУ/накопитель/CPU/…),
описание, продавец (+синяя галочка), нижняя панель «Написать» / «Купить безопасно» (пока
заглушка — включим с входом/сделкой).

## Дальше (по плану MVP покупателя)
Вход/регистрация (нужен мобильный токен-эндпоинт на бэкенде: write за CSRF/same-origin) →
чат → безопасная сделка (эскроу) → пуши (APNs).

## Сборка на Mac
Требуется macOS + Xcode 15+.

1. Установи генератор проекта (один раз):
   ```bash
   brew install xcodegen
   ```
2. В папке проекта сгенерируй `.xcodeproj` и открой:
   ```bash
   cd kliko-ios
   xcodegen generate
   open Kliko.xcodeproj
   ```
3. В Xcode → target **Kliko** → **Signing & Capabilities**: выбери свой Team (Apple ID),
   при необходимости поменяй Bundle ID (`kz.kliko.app`).
4. Выбери симулятор (напр. iPhone 15) и нажми **Run** (⌘R). Лента подтянется с `kliko.kz`.

> Если хочешь тестировать против локального стейджа по http — добавь `NSAppTransportSecurity`
> в Info (через `project.yml`), но прод по HTTPS исключений не требует.

## Структура
```
project.yml            — спецификация проекта для XcodeGen
Sources/
  KlikoApp.swift       — @main, входная сцена (FeedView)
  Config.swift         — apiBase (домен) + помощник URL
  Theme.swift          — бренд-палитра
  Models/MarketItem.swift  — модель товара (Codable, snake_case)
  Networking/API.swift     — клиент API (async/await, cookies)
  Feed/FeedViewModel.swift — состояние ленты (пагинация/поиск)
  Feed/FeedView.swift      — экран ленты (2-колоночная сетка)
  Feed/ItemCard.swift      — карточка товара
```

## Заметки
- Иконку приложения добавим позже (Assets.xcassets → AppIcon) — сейчас проект собирается с дефолтной.
- Домен API меняется в `Sources/Config.swift` (`apiBase`).
