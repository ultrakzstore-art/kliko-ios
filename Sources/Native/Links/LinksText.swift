import Foundation

/// Тексты объявления, открытого по ссылке, на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
enum LinksText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["opening": "Открываем объявление", "failed": "Не удалось открыть объявление",
               "failed_sub": "Возможно, его уже сняли или пропала связь. Попробуйте ещё раз или откройте на сайте."],
        "kk": ["opening": "Хабарландыру ашылуда", "failed": "Хабарландыру ашылмады",
               "failed_sub": "Мүмкін, ол алынып тасталған немесе байланыс үзілген. Қайталап көріңіз немесе сайтта ашыңыз."],
        "en": ["opening": "Opening the listing", "failed": "Couldn't open the listing",
               "failed_sub": "It may have been removed, or the connection dropped. Try again or open it on the website."],
        "ar": ["opening": "جارٍ فتح الإعلان", "failed": "تعذّر فتح الإعلان",
               "failed_sub": "ربما أُزيل الإعلان أو انقطع الاتصال. حاول مرة أخرى أو افتحه في الموقع."]
    ]
}
