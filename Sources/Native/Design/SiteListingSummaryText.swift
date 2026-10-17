import Foundation

/**
 Тексты «Карточки решения» окна объявления (сборка 84, владелец 17.10.2026: «Модалку товаров надо упростить, так как
 фокус сбивается»; на макет — «Собирай 84»; SiteListingSummary.swift) на языке телефона (kk/ru/en/ar) — тем же
 способом, что ListingPageText: язык запомнен за запуск (DesignText.язык).

 Здесь только новое: строка «что за вещь» (часы и наличие), строка «безопасно ли» (обещание гаранта — теми же словами,
 что подпись главной кнопки панели, ТекстыДействийОкна), строка аренды «Условия и заявка владельцу», капсула
 «Разбор» у цены, «Оплата и услуги» (бывший «Ещё») и капсула «Примерить» в строке «На столе». Счёт по-арабски — «الكمية المتوفرة: %d», «الصفقات: %d»: число после двоеточия
 не требует согласования с существительным (у арабского шесть форм множественного числа).
 */
enum ListingSummaryText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Язык, запомненный за запуск (DesignText.язык): настройки телефона не перечитываются на каждую подпись.
    static var язык: String { DesignText.язык }

    /// «14 сделок»: русский, казахский и английский — формами ListingPageText.число; арабский — «الصفقات: 14».
    static func сделок(_ n: Int) -> String {
        if язык == "ar" { return String(format: т("sum_deals"), n) }
        return ListingPageText.число(n, "deals")
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "sum_a11y": "Коротко об объявлении",
        "sum_open_till": "Открыто до %@",
        "sum_opens_at": "Откроется в %@",
        "sum_stock": "в наличии %d шт",
        "sum_deals": "сделок: %d",
        "esc_money": "Деньги у Kliko до получения товара",
        "esc_safe": "Безопасная сделка Kliko",
        "esc_paused": "Безопасная сделка сейчас на паузе",
        "esc_deposit": "Бронь через Безопасную сделку",
        "esc_service": "Оплата исполнителю после приёмки",
        "esc_hint": "Откроет, как работает Безопасная сделка",
        "sum_rent": "Условия и заявка владельцу",
        "sum_rent_hint": "Покажет условия аренды ниже",
        "brief_short": "Разбор",
        "pay_more": "Оплата и услуги",
        "try_short": "Примерить",
        "try_pick": "Как примерить?",
        "cancel": "Отмена"
    ]

    private static let kk: [String: String] = [
        "sum_a11y": "Хабарландыру туралы қысқаша",
        "sum_open_till": "%@ дейін ашық",
        "sum_opens_at": "%@ ашылады",
        "sum_stock": "қолда %d дана",
        "sum_deals": "мәміле: %d",
        "esc_money": "Тауарды алғанша ақша Kliko-да",
        "esc_safe": "Kliko қауіпсіз мәмілесі",
        "esc_paused": "Қауіпсіз мәміле қазір үзілісте",
        "esc_deposit": "Қауіпсіз мәміле арқылы брондау",
        "esc_service": "Орындаушыға қабылдағаннан кейін төлем",
        "esc_hint": "Қауіпсіз мәміленің қалай жұмыс істейтінін ашады",
        "sum_rent": "Шарттар және иесіне өтінім",
        "sum_rent_hint": "Төменде жалға беру шарттарын көрсетеді",
        "brief_short": "Талдау",
        "pay_more": "Төлем және қызметтер",
        "try_short": "Киіп көру",
        "try_pick": "Қалай киіп көресіз?",
        "cancel": "Бас тарту"
    ]

    private static let en: [String: String] = [
        "sum_a11y": "Listing at a glance",
        "sum_open_till": "Open until %@",
        "sum_opens_at": "Opens at %@",
        "sum_stock": "%d in stock",
        "sum_deals": "deals: %d",
        "esc_money": "Kliko holds the money until you receive it",
        "esc_safe": "Kliko Safe deal",
        "esc_paused": "The Safe deal is paused for now",
        "esc_deposit": "Reserve through the Safe deal",
        "esc_service": "The provider is paid after acceptance",
        "esc_hint": "Opens how the Safe deal works",
        "sum_rent": "Terms and request to the owner",
        "sum_rent_hint": "Shows the rental terms below",
        "brief_short": "Breakdown",
        "pay_more": "Payment and services",
        "try_short": "Try on",
        "try_pick": "How do you want to try it?",
        "cancel": "Cancel"
    ]

    private static let ar: [String: String] = [
        "sum_a11y": "الإعلان باختصار",
        "sum_open_till": "مفتوح حتى %@",
        "sum_opens_at": "يفتح الساعة %@",
        "sum_stock": "الكمية المتوفرة: %d",
        "sum_deals": "الصفقات: %d",
        "esc_money": "يبقى المال لدى Kliko حتى تستلم السلعة",
        "esc_safe": "الصفقة الآمنة من Kliko",
        "esc_paused": "الصفقة الآمنة متوقفة مؤقتًا",
        "esc_deposit": "حجز عبر الصفقة الآمنة",
        "esc_service": "يُدفع للمنفّذ بعد الاستلام",
        "esc_hint": "يفتح شرح طريقة عمل الصفقة الآمنة",
        "sum_rent": "الشروط وطلب إلى المالك",
        "sum_rent_hint": "يعرض شروط الإيجار أدناه",
        "brief_short": "تحليل",
        "pay_more": "الدفع والخدمات",
        "try_short": "جرّب",
        "try_pick": "كيف تريد التجربة؟",
        "cancel": "إلغاء"
    ]
}
