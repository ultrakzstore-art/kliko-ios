import Foundation

/// Тексты избранного на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и чат (ChatText).
enum FavoritesText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Избранное", "add": "Добавить в избранное", "remove": "Убрать из избранного",
               "empty": "В избранном пока пусто", "empty_sub": "Нажмите на сердечко в объявлении — оно сохранится здесь.",
               "to_feed": "Перейти в ленту",
               "local": "Избранное хранится на этом телефоне и не переносится на сайт."],
        "kk": ["title": "Таңдаулылар", "add": "Таңдаулыларға қосу", "remove": "Таңдаулылардан алып тастау",
               "empty": "Таңдаулылар әзірге бос", "empty_sub": "Хабарландырудағы жүрекшені басыңыз — ол осында сақталады.",
               "to_feed": "Лентаға өту",
               "local": "Таңдаулылар осы телефонда сақталады және сайтқа ауыспайды."],
        "en": ["title": "Favorites", "add": "Add to favorites", "remove": "Remove from favorites",
               "empty": "No favorites yet", "empty_sub": "Tap the heart on a listing to save it here.",
               "to_feed": "Browse listings",
               "local": "Favorites are stored on this phone and don't sync with the website."],
        "ar": ["title": "المفضلة", "add": "إضافة إلى المفضلة", "remove": "إزالة من المفضلة",
               "empty": "المفضلة فارغة حتى الآن", "empty_sub": "اضغط على القلب في الإعلان لحفظه هنا.",
               "to_feed": "تصفّح الإعلانات",
               "local": "تُحفظ المفضلة على هذا الهاتف ولا تتم مزامنتها مع الموقع."]
    ]
}
