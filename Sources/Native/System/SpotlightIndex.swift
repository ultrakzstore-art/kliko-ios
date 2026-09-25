import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/**
 ПОИСК iPHONE (SPOTLIGHT) — ЭТАП 10 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Открытое объявление кладём в поиск телефона: название, цена и город, на 30 дней. Смотрел человек Camry — набрал
 «camry» в поиске iPhone и вернулся к ней одним нажатием, минуя ленту. Нажатие приходит в SceneDelegate
 активностью CSSearchableItemActionType с номером объявления и дальше идёт как ссылка сайта: адрес
 /marketplace?item=<номер> → WebBridge.открытьСнаружи → нативная карточка (этап 8) или страница сайта.

 🔴 ЭТО ИСТОРИЯ ПРОСМОТРОВ, И ЛЕЖИТ ОНА НА ТЕЛЕФОНЕ. Индексируем только то, что человек открыл сам, — ни ленту, ни
 избранное. Стираем всё разом (домен kz.kliko.listing) при выходе из аккаунта (WebContainer, bye=1) и когда
 человек очищает «Вы смотрели» (RecentStore) — иначе вычищенная история осталась бы в поиске iPhone. Сервера это не
 касается: новых адресов на сайте нет.
 */
enum ПоискТелефона {
    /// Все объявления в одном домене — чтобы стереть их одним вызовом, не зная номеров.
    static let домен = "kz.kliko.listing"
    /// Сколько держим в поиске: дальше цена и само объявление уже не те, система уберёт сама.
    static let срок: TimeInterval = 30 * 24 * 60 * 60

    /// Открыли карточку — в поиск iPhone. Тот же номер заменяет прежнюю запись: дотянулась полная карточка —
    /// обновится и цена. Заготовку по ссылке (только номер) не кладём: искать в ней нечего.
    @MainActor
    static func запомнить(_ товар: Listing) {
        guard Config.spotlight, !товар.заготовка, !товар.title.isEmpty,
              CSSearchableIndex.isIndexingAvailable() else { return }
        let атрибуты = CSSearchableItemAttributeSet(contentType: UTType.content)
        атрибуты.title = товар.title
        var описание = ListingCard.цена(товар)
        if !товар.city.isEmpty { описание += " · " + товар.city }
        атрибуты.contentDescription = описание
        атрибуты.keywords = товар.city.isEmpty ? ["Kliko"] : ["Kliko", товар.city]
        let запись = CSSearchableItem(uniqueIdentifier: товар.id, domainIdentifier: домен, attributeSet: атрибуты)
        запись.expirationDate = Date().addingTimeInterval(срок)
        /* Без ответа: не легло — откроет ещё раз, попробуем снова, а показать человеку тут нечего. */
        CSSearchableIndex.default().indexSearchableItems([запись], completionHandler: nil)
    }

    /// Выход из аккаунта, очистка «Вы смотрели» или выключенный рубильник — всё, что приложение клало в поиск.
    static func стереть() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [домен], completionHandler: nil)
    }

    /// Нажатие на результат поиска → адрес объявления на сайте. nil — активность не из Spotlight.
    static func адрес(из активность: NSUserActivity) -> URL? {
        guard активность.activityType == CSSearchableItemActionType,
              let номер = активность.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              !номер.isEmpty else { return nil }
        return Listing(номер: номер).адрес
    }
}
