import Foundation

/**
 Тексты пачки 83 для «Моих объявлений»: меню капсулы «+ Добавить» в шапке («Объявление» — подписи «Резюме» и
 «Вакансия» берутся из МоиОбъявленияText) и подпись VoiceOver у этой капсулы.
 Свой словарь — чтобы не пересекаться с МоиОбъявленияText. Языки ru, kk, en, ar; прочие — русский.
 */
enum МенюДобавленияText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "mla_listing": "Объявление",
        "mla_a11y": "Добавить объявление, резюме или вакансию"
    ]

    private static let kk: [String: String] = [
        "mla_listing": "Хабарландыру",
        "mla_a11y": "Хабарландыру, түйіндеме не бос орын қосу"
    ]

    private static let en: [String: String] = [
        "mla_listing": "Listing",
        "mla_a11y": "Add a listing, résumé or vacancy"
    ]

    private static let ar: [String: String] = [
        "mla_listing": "إعلان",
        "mla_a11y": "إضافة إعلان أو سيرة ذاتية أو وظيفة"
    ]
}
