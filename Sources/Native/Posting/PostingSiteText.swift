import Foundation

/// Тексты подачи по сайту 14.10.2026 (пять шагов, «Адрес и дополнительно», условия проката, недвижимость: гараж,
/// комната, новостройка; авто: ориентиры цены только по модели; «Замеры вещи»; «Исправить» после отказа) на языке
/// телефона (ru/kk/en/ar) — свой словарь, чтобы ключи не пересекались с ПодачаText и другими направлениями.
enum ПодачаСайтаText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "step_where_extra": "Адрес и дополнительно", "step_where": "Адрес", "step_terms": "Условия",
        "step_what_rent": "Что сдаёте",
        "step_about_car": "Об автомобиле", "step_about_obj": "Об объекте", "step_price_only": "Цена",
        "step_rent_pay": "Плата и залог",
        "auto_few": "Таких машин пока мало — цену ставьте сами",
        "mp_ext": "По рынку · похожих: %@",
        "realty_city_hint": "Укажите город — покажем цены похожих квартир",
        "rl_garage": "Гараж, паркинг", "rl_garage_s": "гараж или паркоместо",
        "gt_label": "Что это", "gt_garage": "Гараж", "gt_parking": "Паркоместо",
        "gt_area": "Площадь", "gt_term": "Срок аренды", "gt_long": "Длительно", "gt_daily": "Посуточно",
        "gt_owner": "Кто размещает", "gt_owner_o": "Собственник", "gt_owner_a": "Риелтор",
        "rw_room": "Комната", "rw_market": "Рынок жилья", "rw_resale": "Вторичка", "rw_newbuild": "Новостройка",
        "fit_title": "Замеры вещи", "fit_sub": "Необязательно — покупатель сверит со своими мерками",
        "fit_kind": "Что это за вещь", "fit_cm": "см",
        "fit_hint": "Меряйте вещь, разложенную ровно: ширины — от шва до шва, это половина обхвата",
        "fit_chest": "Ширина груди", "fit_waist": "Ширина талии", "fit_hips": "Ширина бёдер", "fit_length": "Длина",
        "fit_sleeve": "Длина рукава", "fit_shoulders": "Ширина плеч", "fit_inseam": "Длина по шагу",
        "fit_insole": "Длина стельки", "fit_kh": "На рост",
        "fit_k_top": "Верх", "fit_k_bottom": "Брюки, юбка", "fit_k_dress": "Платье", "fit_k_outer": "Верхняя одежда",
        "fit_k_shoes": "Обувь", "fit_k_kids": "Детское",
        "fix": "Исправить", "fix_reason": "Отклонено: %@"
    ]

    private static let kk: [String: String] = [
        "step_where_extra": "Мекенжай және қосымша", "step_where": "Мекенжай", "step_terms": "Шарттар",
        "step_what_rent": "Не жалға бересіз",
        "step_about_car": "Көлік туралы", "step_about_obj": "Нысан туралы", "step_price_only": "Баға",
        "step_rent_pay": "Төлем және кепіл",
        "auto_few": "Мұндай көліктер әзірге аз — бағаны өзіңіз қойыңыз",
        "mp_ext": "Нарық бойынша · ұқсастары: %@",
        "realty_city_hint": "Қаланы көрсетіңіз — ұқсас пәтерлердің бағасын көрсетеміз",
        "rl_garage": "Гараж, паркинг", "rl_garage_s": "гараж немесе тұрақ орны",
        "gt_label": "Бұл не", "gt_garage": "Гараж", "gt_parking": "Тұрақ орны",
        "gt_area": "Ауданы", "gt_term": "Жалға беру мерзімі", "gt_long": "Ұзақ мерзімге", "gt_daily": "Тәулікпен",
        "gt_owner": "Кім орналастырады", "gt_owner_o": "Иесі", "gt_owner_a": "Риелтор",
        "rw_room": "Бөлме", "rw_market": "Тұрғын үй нарығы", "rw_resale": "Екінші нарық", "rw_newbuild": "Жаңа үй",
        "fit_title": "Заттың өлшемдері", "fit_sub": "Міндетті емес — сатып алушы өз өлшемдерімен салыстырады",
        "fit_kind": "Бұл қандай зат", "fit_cm": "см",
        "fit_hint": "Затты тегіс жайып өлшеңіз: ені — тігістен тігіске дейін, бұл орамның жартысы",
        "fit_chest": "Кеуде ені", "fit_waist": "Бел ені", "fit_hips": "Жамбас ені", "fit_length": "Ұзындығы",
        "fit_sleeve": "Жең ұзындығы", "fit_shoulders": "Иық ені", "fit_inseam": "Ішкі тігіс ұзындығы",
        "fit_insole": "Ұлтарақ ұзындығы", "fit_kh": "Бойға",
        "fit_k_top": "Үстіңгі", "fit_k_bottom": "Шалбар, юбка", "fit_k_dress": "Көйлек", "fit_k_outer": "Сырт киім",
        "fit_k_shoes": "Аяқ киім", "fit_k_kids": "Балалар киімі",
        "fix": "Түзету", "fix_reason": "Қабылданбады: %@"
    ]

    private static let en: [String: String] = [
        "step_where_extra": "Address and extras", "step_where": "Address", "step_terms": "Terms",
        "step_what_rent": "What you're renting out",
        "step_about_car": "About the vehicle", "step_about_obj": "About the property", "step_price_only": "Price",
        "step_rent_pay": "Rent and deposit",
        "auto_few": "There are few such cars yet — set the price yourself",
        "mp_ext": "Market · similar: %@",
        "realty_city_hint": "Choose the city — we'll show prices of similar flats",
        "rl_garage": "Garage, parking", "rl_garage_s": "garage or parking space",
        "gt_label": "What it is", "gt_garage": "Garage", "gt_parking": "Parking space",
        "gt_area": "Area", "gt_term": "Rental term", "gt_long": "Long term", "gt_daily": "Daily",
        "gt_owner": "Who is posting", "gt_owner_o": "Owner", "gt_owner_a": "Agent",
        "rw_room": "Room", "rw_market": "Housing market", "rw_resale": "Resale", "rw_newbuild": "New build",
        "fit_title": "Item measurements", "fit_sub": "Optional — buyers compare them with their own measurements",
        "fit_kind": "What kind of item", "fit_cm": "cm",
        "fit_hint": "Measure the item laid flat: widths go seam to seam, that is half the circumference",
        "fit_chest": "Chest width", "fit_waist": "Waist width", "fit_hips": "Hip width", "fit_length": "Length",
        "fit_sleeve": "Sleeve length", "fit_shoulders": "Shoulder width", "fit_inseam": "Inseam",
        "fit_insole": "Insole length", "fit_kh": "For height",
        "fit_k_top": "Top", "fit_k_bottom": "Trousers, skirt", "fit_k_dress": "Dress", "fit_k_outer": "Outerwear",
        "fit_k_shoes": "Shoes", "fit_k_kids": "Kids",
        "fix": "Fix", "fix_reason": "Rejected: %@"
    ]

    private static let ar: [String: String] = [
        "step_where_extra": "العنوان والإضافات", "step_where": "العنوان", "step_terms": "الشروط",
        "step_what_rent": "ما الذي تؤجره",
        "step_about_car": "عن المركبة", "step_about_obj": "عن العقار", "step_price_only": "السعر",
        "step_rent_pay": "الإيجار والتأمين",
        "auto_few": "لا توجد سيارات كهذه بما يكفي بعد — حدّد السعر بنفسك",
        "mp_ext": "حسب السوق · مشابهة: %@",
        "realty_city_hint": "حدّد المدينة — سنعرض أسعار شقق مشابهة",
        "rl_garage": "مرآب، موقف", "rl_garage_s": "مرآب أو مكان لركن السيارة",
        "gt_label": "ما هو", "gt_garage": "مرآب", "gt_parking": "مكان لركن السيارة",
        "gt_area": "المساحة", "gt_term": "مدة الإيجار", "gt_long": "طويلة الأمد", "gt_daily": "يومي",
        "gt_owner": "من ينشر", "gt_owner_o": "المالك", "gt_owner_a": "وسيط عقاري",
        "rw_room": "غرفة", "rw_market": "سوق السكن", "rw_resale": "سوق ثانوية", "rw_newbuild": "بناء جديد",
        "fit_title": "مقاسات القطعة", "fit_sub": "اختياري — يقارنها المشتري بمقاساته",
        "fit_kind": "ما نوع القطعة", "fit_cm": "سم",
        "fit_hint": "قِس القطعة وهي مفرودة: العرض من الدرزة إلى الدرزة، أي نصف المحيط",
        "fit_chest": "عرض الصدر", "fit_waist": "عرض الخصر", "fit_hips": "عرض الوركين", "fit_length": "الطول",
        "fit_sleeve": "طول الكم", "fit_shoulders": "عرض الكتفين", "fit_inseam": "طول الساق الداخلي",
        "fit_insole": "طول النعل الداخلي", "fit_kh": "لطول",
        "fit_k_top": "علوي", "fit_k_bottom": "بنطال، تنورة", "fit_k_dress": "فستان", "fit_k_outer": "ملابس خارجية",
        "fit_k_shoes": "أحذية", "fit_k_kids": "للأطفال",
        "fix": "إصلاح", "fix_reason": "مرفوض: %@"
    ]
}
