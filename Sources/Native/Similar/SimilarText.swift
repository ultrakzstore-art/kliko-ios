import Foundation

/// Тексты полосы похожих на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и недавнее.
enum SimilarText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Похожие объявления", "loading": "Загружаем похожие объявления"],
        "kk": ["title": "Ұқсас хабарландырулар", "loading": "Ұқсас хабарландырулар жүктелуде"],
        "en": ["title": "Similar listings", "loading": "Loading similar listings"],
        "ar": ["title": "إعلانات مشابهة", "loading": "جارٍ تحميل إعلانات مشابهة"]
    ]
}
