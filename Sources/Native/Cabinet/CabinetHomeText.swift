import Foundation

/// Тексты главного экрана кабинета (13.10.2026): плитки главных разделов и строка «Уведомления и подписки» — на языке
/// телефона (kk/ru/en/ar), тем же способом, что CabinetText.
enum КабинетГлавнаяText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["tile_listings": "Объявления",
               "tile_deals": "Сделки",
               "tile_favorites": "Избранное",
               "tile_requests": "Заявки рядом",
               "notif_hub": "Уведомления и подписки"],
        "kk": ["tile_listings": "Хабарландырулар",
               "tile_deals": "Мәмілелер",
               "tile_favorites": "Таңдаулылар",
               "tile_requests": "Жақын өтінімдер",
               "notif_hub": "Хабарламалар мен жазылымдар"],
        "en": ["tile_listings": "Listings",
               "tile_deals": "Deals",
               "tile_favorites": "Favorites",
               "tile_requests": "Nearby requests",
               "notif_hub": "Notifications & subscriptions"],
        "ar": ["tile_listings": "إعلاناتي",
               "tile_deals": "صفقاتي",
               "tile_favorites": "المفضلة",
               "tile_requests": "طلبات قريبة",
               "notif_hub": "الإشعارات والاشتراكات"]
    ]
}
