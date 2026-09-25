import Foundation

/// Тексты недавнего на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и избранное.
enum RecentText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["viewed": "Вы смотрели", "clear": "Очистить", "clear_viewed": "Очистить просмотренные",
               "clear_history": "Очистить историю", "query_hint": "Искать снова"],
        "kk": ["viewed": "Сіз қарағандар", "clear": "Тазалау", "clear_viewed": "Қаралғандарды тазалау",
               "clear_history": "Іздеу тарихын тазалау", "query_hint": "Қайта іздеу"],
        "en": ["viewed": "Recently viewed", "clear": "Clear", "clear_viewed": "Clear recently viewed",
               "clear_history": "Clear search history", "query_hint": "Search again"],
        "ar": ["viewed": "شوهدت مؤخرًا", "clear": "مسح", "clear_viewed": "مسح ما شوهد مؤخرًا",
               "clear_history": "مسح سجل البحث", "query_hint": "ابحث مرة أخرى"]
    ]
}
