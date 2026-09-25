import Foundation

/// Подписи для VoiceOver и заготовок ленты (этап 11) на языке телефона (kk/ru/en/ar) — тем же способом, что лента
/// (FeedText). На экране их не видно: их слышит тот, кто пользуется VoiceOver.
enum AccessText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["loading": "Загружаем объявления", "top": "в топе", "new": "новое", "tenge": "тенге",
               "per_day": "в сутки", "unread": "Непрочитанных: %ld"],
        "kk": ["loading": "Хабарландырулар жүктелуде", "top": "топта", "new": "жаңа", "tenge": "теңге",
               "per_day": "тәулігіне", "unread": "Оқылмаған: %ld"],
        "en": ["loading": "Loading listings", "top": "featured", "new": "new", "tenge": "tenge",
               "per_day": "per day", "unread": "Unread: %ld"],
        "ar": ["loading": "جارٍ تحميل الإعلانات", "top": "إعلان مميز", "new": "جديد", "tenge": "تنغي",
               "per_day": "في اليوم", "unread": "غير مقروءة: %ld"]
    ]
}
