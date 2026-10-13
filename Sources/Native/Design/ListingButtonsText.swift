import Foundation

/**
 Тексты кнопок страницы объявления (владелец 13.10.2026: «модалке кнопки») на языке телефона (kk/ru/en/ar), тем же
 способом, что ListingPageText. Только то, чего там нет: подпись пары стрелок ˄ ˅ над фото для VoiceOver и подсказки к
 приглушённой стрелке, когда соседа в списке нет (СтрелкиЛистанияОбъявлений, ListingFlip.swift).
 */
enum КнопкиОбъявленияText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        return тексты[язык]?[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "flip_group": "Листать объявления",
            "first_hint": "Это первое объявление в списке",
            "last_hint": "Дальше в списке пока ничего нет",
        ],
        "kk": [
            "flip_group": "Хабарландыруларды парақтау",
            "first_hint": "Бұл тізімдегі алғашқы хабарландыру",
            "last_hint": "Тізімде әзірге бұдан әрі ештеңе жоқ",
        ],
        "en": [
            "flip_group": "Browse listings",
            "first_hint": "This is the first listing in the list",
            "last_hint": "Nothing further in the list yet",
        ],
        "ar": [
            "flip_group": "تصفّح الإعلانات",
            "first_hint": "هذا أول إعلان في القائمة",
            "last_hint": "لا شيء آخر في القائمة بعد",
        ]
    ]
}
