import Foundation

/**
 Где деньги — для задатка, аренды и услуги (ultra-site 13.10.2026, «Сделки: шаги после оплаты»: «Задаток, аренда и
 услуга — по-прежнему»).

 Новые слова fz_m и dl_held_seller_c («деньги у Kliko до получения, потом срок проверки — и деньги уйдут сами») верны
 только для товарной сделки в четыре шага. У задатка, аренды и услуги срока проверки нет: деньги у Kliko до
 подтверждения сделки — эти слова здесь, нейтрально, без обещания выплаты «самой».
 */
enum ЗаморозкаСделкиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Текст с подстановкой {n} (сумма) — как ДеньгиСделкиText.т(_:n:).
    static func т(_ ключ: String, n: String) -> String {
        т(ключ).replacingOccurrences(of: "{n}", with: n)
    }

    /// Окно «Оплатить безопасно?»: товарной сделке — новые слова сайта, остальным — прежние, без срока проверки.
    static func окноОплаты(_ сделка: Сделка?, n: String) -> String {
        if сделка?.четыреШага ?? true { return ДеньгиСделкиText.т("fz_m", n: n) }
        return т("fz_m_keep", n: n)
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "fz_m_keep": "<b>{n}</b> будут у Kliko до подтверждения сделки. Вторая сторона получит деньги только после этого.",
        "held_seller_rent": "Передайте вещь — деньги у Kliko, выплата придёт после того, как арендатор подтвердит получение."
    ]

    private static let kk: [String: String] = [
        "fz_m_keep": "<b>{n}</b> мәміле расталғанша Kliko-да болады. Екінші тарап ақшаны тек содан кейін алады.",
        "held_seller_rent": "Затты тапсырыңыз — ақша Kliko-да, төлем жалға алушы алғанын растағаннан кейін келеді."
    ]

    private static let en: [String: String] = [
        "fz_m_keep": "<b>{n}</b> stays with Kliko until the deal is confirmed. The other side gets paid only after that.",
        "held_seller_rent": "Hand over the item — Kliko holds the money; the payout arrives after the renter confirms receipt."
    ]

    private static let ar: [String: String] = [
        "fz_m_keep": "يبقى <b>{n}</b> لدى Kliko حتى تأكيد الصفقة. يحصل الطرف الآخر على المال بعد ذلك فقط.",
        "held_seller_rent": "سلّم الغرض — المال لدى Kliko، ويصلك المبلغ بعد أن يؤكّد المستأجر الاستلام."
    ]
}
