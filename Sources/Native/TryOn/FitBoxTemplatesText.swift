import Foundation

/**
 Тексты «Готовых размеров» в листе «Укажите размеры» «Поместится ли?» (FitBoxTemplates.swift) и пометки «размер
 примерный» под затвором окна. Ключи fbt_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной:
 ПримерочнаяText.язык). Свой словарь — чтобы не пересекаться с ГабаритыText (fb_*): имена видов и образцов — у шаблонов
 подачи (РазмерыОбразцовText, Posting/PostingSizeText.swift), здесь — только сам блок, выбор вида и озвучка чипов.
 */
enum ГотовыеРазмерыText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Строка с подстановкой одного значения (%@).
    static func т(_ ключ: String, _ значение: String) -> String {
        String(format: т(ключ), значение)
    }

    /**
     Единица после числа для VoiceOver: основа fbt_cm (сантиметр) или fbt_in (дюйм) и форма по числу — _1 «сантиметр»,
     _2 «сантиметра», _5 «сантиметров», _x — дробное («15,6 дюйма»). У русского — три формы, у английского — одна
     и много, у казахского и арабского после числа одна форма.
     */
    static func единица(_ число: Double, _ основа: String) -> String {
        let целое = число == число.rounded()
        let н = целое ? Int(abs(число).rounded()) : 0
        let форма: String
        switch ПримерочнаяText.язык {
        case "en":
            форма = целое && н == 1 ? "_1" : "_5"
        case "ru":
            if !целое {
                форма = "_x"
            } else if н % 10 == 1 && н % 100 != 11 {
                форма = "_1"
            } else if (2...4).contains(н % 10) && !(12...14).contains(н % 100) {
                форма = "_2"
            } else {
                форма = "_5"
            }
        default:
            форма = "_1"
        }
        return т(основа + форма)
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
        "fbt_title": "Готовые размеры",
        "fbt_sub": "Выберите похожую вещь — подставим типичные размеры",
        "fbt_kind": "Похоже, это",
        "fbt_other": "Другая вещь",
        "fbt_other_hint": "Выбрать вид вещи из списка",
        "fbt_unknown": "Не поняли, что это за вещь",
        "fbt_pick": "Выберите — покажем типичные размеры",
        "fbt_note": "Типичные размеры для «%@» — у конкретной модели бывает на 1–2 см иначе",
        "fbt_chip_hint": "Подставить эти размеры в поля",
        "fbt_filled": "Подставили: %@",
        "fbt_a11y_dims": "%@ на %@ на %@ %@",
        "fbt_cm_1": "сантиметр",
        "fbt_cm_2": "сантиметра",
        "fbt_cm_5": "сантиметров",
        "fbt_cm_x": "сантиметра",
        "fbt_in_1": "дюйм",
        "fbt_in_2": "дюйма",
        "fbt_in_5": "дюймов",
        "fbt_in_x": "дюйма",
        "fbt_picker_title": "Что это за вещь?",
        "fbt_search": "Диван, ноутбук, холодильник…",
        "fbt_nothing": "Ничего не нашли — попробуйте другое слово",
        "fbt_ar_note": "Размер примерный — типичный для «%@». Оставьте запас 2–3 см.",
        "fbt_ar_note_plain": "Размер примерный — точные размеры у продавца. Оставьте запас 2–3 см.",
        "fbt_ar_approx": "примерно"
    ]

    private static let kk: [String: String] = [
        "fbt_title": "Дайын өлшемдер",
        "fbt_sub": "Ұқсас затты таңдаңыз — әдеттегі өлшемдерді қоямыз",
        "fbt_kind": "Зат түрі",
        "fbt_other": "Басқа зат",
        "fbt_other_hint": "Зат түрін тізімнен таңдау",
        "fbt_unknown": "Бұл қандай зат екенін түсінбедік",
        "fbt_pick": "Таңдаңыз — әдеттегі өлшемдерді көрсетеміз",
        "fbt_note": "«%@» үшін әдеттегі өлшемдер — нақты модельде 1–2 см өзгеше болуы мүмкін",
        "fbt_chip_hint": "Осы өлшемдерді өрістерге қою",
        "fbt_filled": "Қойдық: %@",
        "fbt_a11y_dims": "ені %@, биіктігі %@, тереңдігі %@ %@",
        "fbt_cm_1": "сантиметр",
        "fbt_cm_2": "сантиметр",
        "fbt_cm_5": "сантиметр",
        "fbt_cm_x": "сантиметр",
        "fbt_in_1": "дюйм",
        "fbt_in_2": "дюйм",
        "fbt_in_5": "дюйм",
        "fbt_in_x": "дюйм",
        "fbt_picker_title": "Бұл қандай зат?",
        "fbt_search": "Диван, ноутбук, тоңазытқыш…",
        "fbt_nothing": "Ештеңе табылмады — басқа сөзбен көріңіз",
        "fbt_ar_note": "Өлшемі шамамен — «%@» үшін әдеттегі. 2–3 см қор қалдырыңыз.",
        "fbt_ar_note_plain": "Өлшемі шамамен — нақты өлшемдер сатушыда. 2–3 см қор қалдырыңыз.",
        "fbt_ar_approx": "шамамен"
    ]

    private static let en: [String: String] = [
        "fbt_title": "Ready-made sizes",
        "fbt_sub": "Pick a similar item — we'll fill in typical dimensions",
        "fbt_kind": "Looks like",
        "fbt_other": "Another item",
        "fbt_other_hint": "Choose the type of item from the list",
        "fbt_unknown": "We couldn't tell what this item is",
        "fbt_pick": "Choose one — we'll show typical sizes",
        "fbt_note": "Typical dimensions for “%@” — a specific model may differ by 1–2 cm",
        "fbt_chip_hint": "Fill in these dimensions",
        "fbt_filled": "Filled in: %@",
        "fbt_a11y_dims": "%@ by %@ by %@ %@",
        "fbt_cm_1": "centimeter",
        "fbt_cm_2": "centimeters",
        "fbt_cm_5": "centimeters",
        "fbt_cm_x": "centimeters",
        "fbt_in_1": "inch",
        "fbt_in_2": "inches",
        "fbt_in_5": "inches",
        "fbt_in_x": "inches",
        "fbt_picker_title": "What is this item?",
        "fbt_search": "Sofa, laptop, fridge…",
        "fbt_nothing": "Nothing found — try another word",
        "fbt_ar_note": "Approximate size — typical for “%@”. Leave 2–3 cm to spare.",
        "fbt_ar_note_plain": "Approximate size — ask the seller for exact dimensions. Leave 2–3 cm to spare.",
        "fbt_ar_approx": "approximately"
    ]

    private static let ar: [String: String] = [
        "fbt_title": "مقاسات جاهزة",
        "fbt_sub": "اختر قطعة مشابهة — سنضع المقاسات الشائعة",
        "fbt_kind": "يبدو أنها",
        "fbt_other": "قطعة أخرى",
        "fbt_other_hint": "اختر نوع القطعة من القائمة",
        "fbt_unknown": "لم نتعرّف على نوع هذه القطعة",
        "fbt_pick": "اختر — وسنعرض المقاسات الشائعة",
        "fbt_note": "المقاسات الشائعة لـ «%@» — قد يختلف طراز بعينه بمقدار 1–2 سم",
        "fbt_chip_hint": "ضع هذه المقاسات في الحقول",
        "fbt_filled": "تم وضع: %@",
        "fbt_a11y_dims": "%@ في %@ في %@ %@",
        "fbt_cm_1": "سنتيمتر",
        "fbt_cm_2": "سنتيمتر",
        "fbt_cm_5": "سنتيمتر",
        "fbt_cm_x": "سنتيمتر",
        "fbt_in_1": "بوصة",
        "fbt_in_2": "بوصة",
        "fbt_in_5": "بوصة",
        "fbt_in_x": "بوصة",
        "fbt_picker_title": "ما هذه القطعة؟",
        "fbt_search": "كنبة، حاسوب محمول، ثلاجة…",
        "fbt_nothing": "لم نجد شيئًا — جرّب كلمة أخرى",
        "fbt_ar_note": "المقاس تقريبي — شائع لـ «%@». اترك هامشًا من 2 إلى 3 سم.",
        "fbt_ar_note_plain": "المقاس تقريبي — المقاسات الدقيقة لدى البائع. اترك هامشًا من 2 إلى 3 سم.",
        "fbt_ar_approx": "تقريبًا"
    ]
}
