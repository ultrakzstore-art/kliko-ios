import Foundation

/// Тексты ленты с карточкой рядом на iPad (этап 14) на языке телефона (kk/ru/en/ar) — тем же способом, что лента
/// (FeedText).
enum IPadText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["pick": "Выберите объявление",
               "pick_sub": "Нажмите на карточку в ленте — объявление откроется здесь, а лента останется рядом."],
        "kk": ["pick": "Хабарландыруды таңдаңыз",
               "pick_sub": "Лентадағы карточканы басыңыз — хабарландыру осында ашылады, ал лента жанында қалады."],
        "en": ["pick": "Choose a listing",
               "pick_sub": "Tap a card in the feed — the listing opens here, and the feed stays alongside."],
        "ar": ["pick": "اختر إعلانًا",
               "pick_sub": "اضغط على بطاقة في الإعلانات — سيُفتح الإعلان هنا وتبقى الإعلانات بجانبه."]
    ]
}
