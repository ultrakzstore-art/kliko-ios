import Foundation

/**
 ТЕКСТЫ ПУТИ ПОДАЧИ — ru / kk / en / ar (пачка 83: экрана «Быстро / Подробно» больше нет).

 Новая подача начинается с камеры; на ней ссылка «Подробно — выбрать раздел и заполнить по шагам» (PostingCamera.swift).
 Выбрали «Подробно» — следующая подача начнётся с «Что размещаете?», а на нём ссылка «Быстро — с камеры»
 (PostingScreens.swift). Память выбора — ПамятьРежимаПодачи (PostingQuick.swift).
 */
enum ВыборПодачиText {
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
        "ch_detailed": "Подробно — выбрать раздел и заполнить по шагам",
        "ch_quick_cam": "Быстро — с камеры"
    ]

    private static let kk: [String: String] = [
        "ch_detailed": "Толық — бөлімді таңдап, қадаммен толтыру",
        "ch_quick_cam": "Жылдам — камерадан"
    ]

    private static let en: [String: String] = [
        "ch_detailed": "Detailed — choose a category and fill in step by step",
        "ch_quick_cam": "Quick — from the camera"
    ]

    private static let ar: [String: String] = [
        "ch_detailed": "مفصّل — اختر القسم واملأ خطوة بخطوة",
        "ch_quick_cam": "سريع — من الكاميرا"
    ]
}
