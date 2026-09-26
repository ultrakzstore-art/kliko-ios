import Foundation

/**
 Тексты экрана «Категории» нижней панели (ЭкранКатегорийСайта) на языке приложения (kk/ru/en/ar), тем же способом, что
 DesignText.

 Русские слова — с сайта: «Найти категорию» — placeholder #mh-cq главной, «Ничего не нашлось — попробуйте другое слово» —
 ctg_none, «Все в разделе» — ctg_all_in, «Все» — cat_all, «Назад» — aria-label #mk-catov-back. Названия разделов — не
 здесь: они приходят справочником сайта на языке приложения (cats-<язык>.js, ЗагрузкаКаталогаПоиска).
 */
enum КатегорииText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "find": "Найти категорию", "none": "Ничего не нашлось — попробуйте другое слово",
            "all_in": "Все в разделе «%@»", "all": "Все", "back": "Назад",
        ],
        "kk": [
            "find": "Санатты табу", "none": "Ештеңе табылмады — басқа сөзбен көріңіз",
            "all_in": "«%@» бөліміндегі барлығы", "all": "Барлығы", "back": "Артқа",
        ],
        "en": [
            "find": "Find a category", "none": "Nothing found — try another word",
            "all_in": "All in “%@”", "all": "All", "back": "Back",
        ],
        "ar": [
            "find": "ابحث عن فئة", "none": "لم يُعثر على شيء — جرّب كلمة أخرى",
            "all_in": "الكل في «%@»", "all": "الكل", "back": "رجوع",
        ]
    ]
}
