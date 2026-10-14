import Foundation

/// Тексты блока «Размер как на бирке» (ClothingSizes*.swift) на языке телефона (ru/kk/en/ar) — свой словарь, чтобы
/// ключи не пересекались с ПодачаText и другими направлениями. Коды систем (EU, US, UK, MEX, INT) не переводятся — они
/// такие же на любой бирке.
enum РазмерыОдеждыText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    /// Русский (или язык без своего словаря): возраст и мерки показываются как в таблице.
    private static var русский: Bool { тексты[язык] == nil || язык == "ru" }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    // MARK: - Показ значений

    /// Кусок бирки на экране: «EU 42», «W32 L32», «27 см» (единица — на языке телефона), «7–8 лет».
    static func показ(_ ч: ЧастьБиркиРазмера) -> String {
        switch ч.код {
        case "CM": return ч.значение + " " + т("cm")
        case "Возраст": return местное(ч.значение)
        case "W": return "W" + ч.значение
        default: return ч.код + " " + ч.значение
        }
    }

    /// Подпись чипа: значение системы (возраст — на языке телефона).
    static func чип(_ значение: String, код: String) -> String {
        код == "Возраст" ? местное(значение) : значение
    }

    /// Подпись системы в переключателе: «US» у US W и US M, «EU» у EU/DE, «см», «Возраст».
    static func система(_ код: String) -> String {
        switch код {
        case "CM": return т("cm")
        case "Возраст": return т("age")
        case "US W", "US M": return "US"
        case "EU/DE": return "EU"
        default: return код
        }
    }

    /// Значение таблицы на языке телефона: «1–1.5 года» → «1–1.5 yrs», «до 160» → «up to 160»; по-русски — как есть.
    static func местное(_ значение: String) -> String {
        guard !русский else { return значение }
        var s = значение.replacingOccurrences(of: " мес", with: " " + т("mo"))
        for слово in [" года", " год", " лет"] { s = s.replacingOccurrences(of: слово, with: " " + т("yr")) }
        if s.hasPrefix("до ") { s = т("upto") + " " + String(s.dropFirst(3)) }
        return s
    }

    /// Подпись мерки тела по коду столбца («Грудь, см» → «Грудь»).
    static func мерка(_ код: String) -> String {
        let ключи: [String: String] = ["Грудь, см": "m_chest", "Талия, см": "m_waist", "Бёдра, см": "m_hips",
                                       "Ворот, см": "m_neck", "По внутреннему шву, см": "m_inseam", "Рост, см": "m_height",
                                       "Под грудью, см": "m_under", "Грудь минус под грудью, см": "m_diff",
                                       "Обхват ладони, см": "m_palm", "Длина кисти, см": "m_hand"]
        if let ключ = ключи[код] { return т(ключ) }
        return код.components(separatedBy: ",").first ?? код
    }

    // MARK: - Словари

    private static let ru: [String: String] = [
        "title": "Размер", "sub": "Как на бирке магазина: выберите в своей системе — остальные посчитаются сами",
        "t_w": "Женская", "t_m": "Мужская", "t_k": "Детская", "t_cl": "Одежда", "t_jn": "Джинсы", "t_br": "Бельё",
        "system": "Система размеров", "waist": "Талия W", "length": "Длина L", "band": "Обхват", "cup": "Чашка",
        "first_main": "Сначала выберите размер выше",
        "empty": "Выберите размер — бирка соберётся сама",
        "note": "По стандартной таблице, у брендов бывает ±½ размера",
        "in_listing": "В объявлении:", "unset": "не указан", "in_desc": "В описании", "to_desc": "В описание",
        "clear": "Сбросить размер", "cm": "см", "age": "Возраст", "mo": "мес", "yr": "лет", "upto": "до",
        "m_chest": "Грудь", "m_waist": "Талия", "m_hips": "Бёдра", "m_neck": "Ворот", "m_inseam": "По шву",
        "m_height": "Рост", "m_under": "Под грудью", "m_diff": "Разница обхватов", "m_palm": "Ладонь", "m_hand": "Кисть",
        "cap_shoes_women": "Женская обувь", "cap_shoes_men": "Мужская обувь", "cap_shoes_kids": "Детская обувь",
        "cap_clothes_women": "Женская одежда", "cap_clothes_men": "Мужская одежда", "cap_jeans": "Джинсы",
        "cap_bra": "Бюстгальтер", "cap_kids_height": "Детская одежда", "cap_ring": "Кольцо", "cap_hat": "Головной убор",
        "cap_gloves": "Перчатки", "buyer_title": "Размер по бирке"
    ]

    private static let kk: [String: String] = [
        "title": "Өлшем", "sub": "Дүкен биркасындағыдай: өз жүйеңізде таңдаңыз — қалғаны өзі есептеледі",
        "t_w": "Әйелдер", "t_m": "Ерлер", "t_k": "Балалар", "t_cl": "Киім", "t_jn": "Джинсы", "t_br": "Іш киім",
        "system": "Өлшем жүйесі", "waist": "Бел W", "length": "Ұзындық L", "band": "Көлемі", "cup": "Тостаған",
        "first_main": "Алдымен жоғарыдағы өлшемді таңдаңыз",
        "empty": "Өлшемді таңдаңыз — бирка өзі жиналады",
        "note": "Стандартты кесте бойынша, брендтерде ±½ өлшем айырмашылық болады",
        "in_listing": "Хабарландыруда:", "unset": "көрсетілмеген", "in_desc": "Сипаттамада", "to_desc": "Сипаттамаға",
        "clear": "Өлшемді тазарту", "cm": "см", "age": "Жасы", "mo": "ай", "yr": "жас", "upto": "≤",
        "m_chest": "Кеуде", "m_waist": "Бел", "m_hips": "Жамбас", "m_neck": "Жаға", "m_inseam": "Ішкі тігіс",
        "m_height": "Бой", "m_under": "Кеуде асты", "m_diff": "Көлем айырмасы", "m_palm": "Алақан", "m_hand": "Қол басы",
        "cap_shoes_women": "Әйелдер аяқ киімі", "cap_shoes_men": "Ерлер аяқ киімі", "cap_shoes_kids": "Балалар аяқ киімі",
        "cap_clothes_women": "Әйелдер киімі", "cap_clothes_men": "Ерлер киімі", "cap_jeans": "Джинсы",
        "cap_bra": "Бюстгальтер", "cap_kids_height": "Балалар киімі", "cap_ring": "Сақина", "cap_hat": "Бас киім",
        "cap_gloves": "Қолғап", "buyer_title": "Бирка бойынша өлшем"
    ]

    private static let en: [String: String] = [
        "title": "Size", "sub": "Like a store tag: pick it in your system — the rest is converted for you",
        "t_w": "Women", "t_m": "Men", "t_k": "Kids", "t_cl": "Clothing", "t_jn": "Jeans", "t_br": "Lingerie",
        "system": "Size system", "waist": "Waist W", "length": "Length L", "band": "Band", "cup": "Cup",
        "first_main": "Pick the size above first",
        "empty": "Pick a size — the tag builds itself",
        "note": "Standard chart; brands can differ by ±½ size",
        "in_listing": "In listing:", "unset": "not set", "in_desc": "In description", "to_desc": "Add to description",
        "clear": "Clear size", "cm": "cm", "age": "Age", "mo": "mo", "yr": "yrs", "upto": "up to",
        "m_chest": "Chest", "m_waist": "Waist", "m_hips": "Hips", "m_neck": "Neck", "m_inseam": "Inseam",
        "m_height": "Height", "m_under": "Underbust", "m_diff": "Bust difference", "m_palm": "Palm", "m_hand": "Hand",
        "cap_shoes_women": "Women's shoes", "cap_shoes_men": "Men's shoes", "cap_shoes_kids": "Kids' shoes",
        "cap_clothes_women": "Women's clothing", "cap_clothes_men": "Men's clothing", "cap_jeans": "Jeans",
        "cap_bra": "Bra", "cap_kids_height": "Kids' clothing", "cap_ring": "Ring", "cap_hat": "Headwear",
        "cap_gloves": "Gloves", "buyer_title": "Size on the tag"
    ]

    private static let ar: [String: String] = [
        "title": "المقاس", "sub": "كما في بطاقة المتجر: اختر بنظامك — ويُحسب الباقي تلقائيًا",
        "t_w": "نسائي", "t_m": "رجالي", "t_k": "أطفال", "t_cl": "ملابس", "t_jn": "جينز", "t_br": "ملابس داخلية",
        "system": "نظام المقاسات", "waist": "الخصر W", "length": "الطول L", "band": "المحيط", "cup": "الكأس",
        "first_main": "اختر المقاس أعلاه أولًا",
        "empty": "اختر مقاسًا — وستتكوّن البطاقة تلقائيًا",
        "note": "حسب الجدول القياسي، قد تختلف الماركات بمقدار ½ مقاس",
        "in_listing": "في الإعلان:", "unset": "غير محدد", "in_desc": "في الوصف", "to_desc": "إلى الوصف",
        "clear": "مسح المقاس", "cm": "سم", "age": "العمر", "mo": "شهر", "yr": "سنة", "upto": "حتى",
        "m_chest": "الصدر", "m_waist": "الخصر", "m_hips": "الورك", "m_neck": "الياقة", "m_inseam": "الطول الداخلي",
        "m_height": "الطول", "m_under": "تحت الصدر", "m_diff": "فرق المحيط", "m_palm": "راحة اليد", "m_hand": "طول اليد",
        "cap_shoes_women": "أحذية نسائية", "cap_shoes_men": "أحذية رجالية", "cap_shoes_kids": "أحذية أطفال",
        "cap_clothes_women": "ملابس نسائية", "cap_clothes_men": "ملابس رجالية", "cap_jeans": "جينز",
        "cap_bra": "حمالة صدر", "cap_kids_height": "ملابس أطفال", "cap_ring": "خاتم", "cap_hat": "غطاء رأس",
        "cap_gloves": "قفازات", "buyer_title": "المقاس حسب البطاقة"
    ]
}
