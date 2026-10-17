import Foundation

/**
 Тексты частей страницы объявления сборки 84 (окно объявления v2, рубильник modal_summary — ListingWindowV2.swift;
 владелец 17.10.2026 на макет «Окно товара — упрощение»: «Собирай 84») на языке телефона (kk/ru/en/ar), тем же способом,
 что РовныеКарточкиText. Ключи с приставкой slp_: «Скрыть» под раскрытым советом «… — на что смотреть» и подсказки VoiceOver к его
 свёрнутой строке (БлокСовета, SiteListingParts.swift). Заголовок и пункты совета — прежние, из ListingPageText.
 */
enum ЧастиСтраницыText {
    static func т(_ ключ: String) -> String {
        let язык = DesignText.язык          // язык запомнен один раз за запуск, а не читается на каждую строку
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "slp_hide": "Скрыть",
        "slp_tips_open": "Показать советы",
        "slp_tips_close": "Свернуть советы"
    ]

    private static let kk: [String: String] = [
        "slp_hide": "Жасыру",
        "slp_tips_open": "Кеңестерді көрсету",
        "slp_tips_close": "Кеңестерді жию"
    ]

    private static let en: [String: String] = [
        "slp_hide": "Hide",
        "slp_tips_open": "Show tips",
        "slp_tips_close": "Collapse tips"
    ]

    private static let ar: [String: String] = [
        "slp_hide": "إخفاء",
        "slp_tips_open": "عرض النصائح",
        "slp_tips_close": "طي النصائح"
    ]
}
