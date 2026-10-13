import Foundation

/**
 Тексты ровной схемы карточек списков (владелец 13.10.2026: «стили независимо от названия — схема должна быть ровной
 везде в приложении»; «высота карточек с подсказками статуса») на языке телефона (kk/ru/en/ar), как МоиОбъявленияText.

 Подсказка статуса в карточке — одна строка постоянной высоты: «Показать полностью» — подсказка VoiceOver к слоту
 статуса «Моих объявлений» (полный текст — по нажатию); «Подробнее о сделке» — слот состояния «Моих сделок», когда
 подсказки по статусу нет; «Трек появится после отправки» — строка доставки «Подарков мне» без трека, пока подарок
 не отправлен.
 */
enum РовныеКарточкиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "more_hint": "Показать полностью",
        "deal_more": "Подробнее о сделке",
        "gift_no_track": "Трек появится после отправки"
    ]

    private static let kk: [String: String] = [
        "more_hint": "Толық көрсету",
        "deal_more": "Мәміле туралы толығырақ",
        "gift_no_track": "Трек жөнелтілгеннен кейін шығады"
    ]

    private static let en: [String: String] = [
        "more_hint": "Show in full",
        "deal_more": "Deal details",
        "gift_no_track": "Tracking appears after dispatch"
    ]

    private static let ar: [String: String] = [
        "more_hint": "عرض كاملًا",
        "deal_more": "تفاصيل الصفقة",
        "gift_no_track": "سيظهر رقم التتبع بعد الإرسال"
    ]
}
