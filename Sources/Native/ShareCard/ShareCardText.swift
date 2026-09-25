import Foundation

/// Тексты «Поделиться» картинкой (этап 19) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
enum ShareCardText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["hint": "Отправит ссылку и картинку объявления", "site": "kliko.kz"],
        "kk": ["hint": "Хабарландырудың сілтемесі мен суретін жібереді", "site": "kliko.kz"],
        "en": ["hint": "Sends the link and a picture of the listing", "site": "kliko.kz"],
        "ar": ["hint": "يرسل رابط الإعلان وصورة له", "site": "kliko.kz"]
    ]
}
