import Foundation

/**
 Тексты пачки 83 для строки «Чата» (упрощение подстроки): тег «Горячий» у лида hot_lead — со значком огня, вместо
 прежнего «Лид». Остальные теги и подписи — в ИнбоксText. Свой словарь — чтобы не пересекаться с ним. Языки ru, kk,
 en, ar; прочие — русский.
 */
enum ПодстрокаЧатаText {
    static func т(_ ключ: String) -> String {
        let словарь: [String: String]
        switch DesignText.язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "isub_hot": "Горячий"
    ]

    private static let kk: [String: String] = [
        "isub_hot": "Ыстық"
    ]

    private static let en: [String: String] = [
        "isub_hot": "Hot"
    ]

    private static let ar: [String: String] = [
        "isub_hot": "ساخن"
    ]
}
