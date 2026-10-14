import Foundation

/**
 Тексты экрана «Об автомобиле» мастера авто (AutoPickers.swift: лента и чипы лет, регулятор пробега, объём, коробка и
 топливо, плитки поколений) на языке телефона (ru/kk/en/ar). Ключи ap_*; нет ключа — текст мастера (МастерПодачиText:
 «Год выпуска», «Пробег», «км», «л», «Готово»), за ним — ПодачаText.
 */
enum ПараметрыАвтоText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? МастерПодачиText.т(ключ)
    }

    private static let ru: [String: String] = [
        "ap_title": "Об автомобиле", "ap_title_other": "Параметры",
        "ap_gen_years": "Годы — от поколения (%@)",
        "ap_gen_hint": "Полоса внизу — годы поколения на шкале модели: правее — новее.",
        "ap_year_tape": "Листайте ленту — год встанет по центру. Или нажмите на нужный.",
        "ap_mileage_drag": "Сдвиньте регулятор", "ap_mileage_exact": "или впишите точно",
        "ap_mileage_ph": "Пробег, км", "ap_exact_hint": "Дважды нажмите, чтобы вписать пробег цифрами",
        "ap_k": "%@ тыс", "ap_m": "%@ млн",
        "ap_engine": "Объём двигателя", "ap_engine_other": "Другой — вписать", "ap_engine_ph": "Например, 1.6",
        "ap_ev": "Электромобиль — объём двигателя не нужен",
        "ap_more": "Другой…"
    ]

    private static let kk: [String: String] = [
        "ap_title": "Автокөлік туралы", "ap_title_other": "Параметрлер",
        "ap_gen_years": "Жылдар — буыннан (%@)",
        "ap_gen_hint": "Төмендегі жолақ — буын жылдары модель шкаласында: оңырақ — жаңарақ.",
        "ap_year_tape": "Таспаны жылжытыңыз — жыл ортаға тұрады. Не керегін басыңыз.",
        "ap_mileage_drag": "Реттегішті жылжытыңыз", "ap_mileage_exact": "не дәл жазыңыз",
        "ap_mileage_ph": "Жүрісі, км", "ap_exact_hint": "Жүрісті санмен жазу үшін екі рет басыңыз",
        "ap_k": "%@ мың", "ap_m": "%@ млн",
        "ap_engine": "Қозғалтқыш көлемі", "ap_engine_other": "Басқа — жазу", "ap_engine_ph": "Мысалы, 1.6",
        "ap_ev": "Электромобиль — қозғалтқыш көлемі керек емес",
        "ap_more": "Басқа…"
    ]

    private static let en: [String: String] = [
        "ap_title": "About the car", "ap_title_other": "Details",
        "ap_gen_years": "Years — from the generation (%@)",
        "ap_gen_hint": "The bar shows the generation's years on the model's timeline: further right is newer.",
        "ap_year_tape": "Swipe the strip — the year in the middle is picked. Or tap the one you need.",
        "ap_mileage_drag": "Move the slider", "ap_mileage_exact": "or type it exactly",
        "ap_mileage_ph": "Mileage, km", "ap_exact_hint": "Double-tap to type the mileage in numbers",
        "ap_k": "%@k", "ap_m": "%@M",
        "ap_engine": "Engine size", "ap_engine_other": "Other — type it", "ap_engine_ph": "E.g. 1.6",
        "ap_ev": "Electric car — no engine size needed",
        "ap_more": "Other…"
    ]

    private static let ar: [String: String] = [
        "ap_title": "عن السيارة", "ap_title_other": "التفاصيل",
        "ap_gen_years": "السنوات — من الجيل (%@)",
        "ap_gen_hint": "الشريط يبيّن سنوات الجيل على خط زمن الطراز: كلما اتجه يمينًا كان أحدث.",
        "ap_year_tape": "اسحب الشريط — تُختار السنة التي في المنتصف. أو اضغط على السنة المطلوبة.",
        "ap_mileage_drag": "حرّك المؤشر", "ap_mileage_exact": "أو اكتبها بدقة",
        "ap_mileage_ph": "المسافة، كم", "ap_exact_hint": "اضغط مرتين لكتابة المسافة بالأرقام",
        "ap_k": "%@ ألف", "ap_m": "%@ مليون",
        "ap_engine": "سعة المحرك", "ap_engine_other": "أخرى — اكتبها", "ap_engine_ph": "مثلًا 1.6",
        "ap_ev": "سيارة كهربائية — لا حاجة لسعة المحرك",
        "ap_more": "أخرى…"
    ]
}
