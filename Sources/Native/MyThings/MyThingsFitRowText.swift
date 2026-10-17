import Foundation

/**
 Тексты ряда «Подходит вам» в разделах «Моего» (MyThingsFitRow.swift): заголовок ряда, «Все ›», «Найти подходящее» и
 подсказки VoiceOver. Ключи mfr_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной:
 ПримерочнаяText.язык). Причины под карточками («Для кровати 160×200», «Ваш размер M») — у стандартов (fy_*,
 StandardsText.swift), «Для моего» — у сверки (mf_chip, MyThingsMatchText.swift): здесь не повторяются.
 */
enum РядМоегоText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var словарь: [String: String] {
        switch ПримерочнаяText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "mfr_title": "Подходит вам",
        "mfr_all": "Все",
        "mfr_find": "Найти подходящее",
        "mfr_feed_a11y": "Откроет ленту раздела с отбором «Для моего»",
        "mfr_feed_plain_a11y": "Откроет ленту раздела",
        "mfr_cell_a11y": "Откроет объявление"
    ]

    private static let kk: [String: String] = [
        "mfr_title": "Сізге сай",
        "mfr_all": "Барлығы",
        "mfr_find": "Сай келетінді табу",
        "mfr_feed_a11y": "Бөлім таспасын «Маған лайық» сүзгісімен ашады",
        "mfr_feed_plain_a11y": "Бөлім таспасын ашады",
        "mfr_cell_a11y": "Хабарландыруды ашады"
    ]

    private static let en: [String: String] = [
        "mfr_title": "Fits you",
        "mfr_all": "All",
        "mfr_find": "Find what fits",
        "mfr_feed_a11y": "Opens the section feed filtered by “Fits mine”",
        "mfr_feed_plain_a11y": "Opens the section feed",
        "mfr_cell_a11y": "Opens the listing"
    ]

    private static let ar: [String: String] = [
        "mfr_title": "يناسبك",
        "mfr_all": "الكل",
        "mfr_find": "ابحث عمّا يناسب",
        "mfr_feed_a11y": "يفتح إعلانات القسم مع عامل التصفية «يناسب ما لدي»",
        "mfr_feed_plain_a11y": "يفتح إعلانات القسم",
        "mfr_cell_a11y": "يفتح الإعلان"
    ]
}
