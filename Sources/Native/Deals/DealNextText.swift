import Foundation

/**
 Тексты «чей ход» сделки и четвёртого шага товарной сделки (ultra-site 13.10.2026: «Сделки: шаги после оплаты»).

 Слова самого хода (next.lead, next.text) приходят от сервера на языке зрителя — здесь только своё: шаг «Проверка»,
 метка «Ваш ход», обратный отсчёт «осталось 2 ч 15 мин» и подпись VoiceOver у числа на вкладке ролей.
 */
enum ХодСделкиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "dstep_check": "Проверка",
        "your_move": "Ваш ход",
        "left": "осталось %@",
        "d": "дн",
        "h": "ч",
        "min": "мин",
        "a11y_open": "незавершённых: %d"
    ]

    private static let kk: [String: String] = [
        "dstep_check": "Тексеру",
        "your_move": "Сіздің кезегіңіз",
        "left": "%@ қалды",
        "d": "күн",
        "h": "сағ",
        "min": "мин",
        "a11y_open": "аяқталмағаны: %d"
    ]

    private static let en: [String: String] = [
        "dstep_check": "Inspection",
        "your_move": "Your move",
        "left": "%@ left",
        "d": "d",
        "h": "h",
        "min": "min",
        "a11y_open": "%d in progress"
    ]

    private static let ar: [String: String] = [
        "dstep_check": "الفحص",
        "your_move": "دورك",
        "left": "متبقٍ %@",
        "d": "ي",
        "h": "س",
        "min": "د",
        "a11y_open": "قيد التنفيذ: %d"
    ]
}
