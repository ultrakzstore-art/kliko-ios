import Foundation

/// Подписи быстрых действий с иконки на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
enum SystemText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["search": "Поиск", "messages": "Сообщения", "favorites": "Избранное"],
        "kk": ["search": "Іздеу", "messages": "Хабарламалар", "favorites": "Таңдаулылар"],
        "en": ["search": "Search", "messages": "Messages", "favorites": "Favorites"],
        "ar": ["search": "بحث", "messages": "الرسائل", "favorites": "المفضلة"]
    ]
}
