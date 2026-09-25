import Foundation

/// Тексты удобства чата (этап 17) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и чат (ChatText).
enum ChatComfortText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["copy": "Копировать", "copied": "Скопировано",
               "down": "К последним сообщениям", "new_below": "Новых сообщений: %d"],
        "kk": ["copy": "Көшіру", "copied": "Көшірілді",
               "down": "Соңғы хабарламаларға", "new_below": "Жаңа хабарламалар: %d"],
        "en": ["copy": "Copy", "copied": "Copied",
               "down": "Jump to latest messages", "new_below": "New messages: %d"],
        "ar": ["copy": "نسخ", "copied": "تم النسخ",
               "down": "الانتقال إلى أحدث الرسائل", "new_below": "رسائل جديدة: %d"]
    ]
}
