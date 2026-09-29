import Foundation

/**
 Тексты фильтров и сортировки (этап 33) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта (js/i18n-marketplace-ru.js и разметка главной): «Фильтры» — filters, «Сначала показывать» —
 sort_title, «Рекомендуемые», «Новые», «Дешевле», «Дороже» — sort_reco, sort_new, sort_cheap, sort_expensive, «Цена, ₸» —
 f_price, «от» и «до» — from и f_to, «Год выпуска» — af_year, «Комнаты» — af_rooms, «Студия» и «5 и больше» — MK_AF_ROOMS,
 «Состояние» — af_cond, «Новое» и «Б/У» — cond_new и cond_used, у транспорта «Новая» и «С пробегом» — af_cond_new и
 af_cond_used, «Продавец» и «Проверенные» — af_seller и af_verified, «Фото» и «Только с фото» — af_photo_lbl и
 af_photo_only, чипы «Проверенные продавцы» и «С фото» — verified_sellers и af_photo, «Сбросить», «Показать», «Сбросить
 всё», «Закрыть» — f_reset, f_show, reset_all, close; «×» на чипе читается «Сбросить: …», как aria-label сайта.
 «Коробка» и «Топливо» — af_gear и af_fuel мастера авто, их значения («Автомат», «Бензин», …) — fac_auto … fac_electric
 (MKF_TR сайта). Марка и модель — af_brand, af_model, af_brand_for, af_model_for, af_any_f, af_brand_find,
 af_model_find, af_brand_none, af_model_none, af_pt_miss, af_model_first, af_model_many, af_model_load, af_pt_loading,
 af_popular, af_all_brands мастера авто сайта.
 */
enum FilterText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["filters": "Фильтры", "sort_title": "Сначала показывать",
               "sort_reco": "Рекомендуемые", "sort_new": "Новые", "sort_old": "Старые", "sort_rating": "По рейтингу", "sort_cheap": "Дешевле", "sort_expensive": "Дороже",
               "price": "Цена, ₸", "from": "от", "to": "до", "from_x": "от %@", "to_x": "до %@",
               "year": "Год выпуска", "rooms": "Комнаты", "studio": "Студия", "rooms_5": "5 и больше",
               "cond": "Состояние", "cond_new": "Новое", "cond_used": "Б/У",
               "cond_new_auto": "Новая", "cond_used_auto": "С пробегом",
               "seller": "Продавец", "verified": "Проверенные", "verified_chip": "Проверенные продавцы",
               "photo": "Фото", "photo_only": "Только с фото", "photo_chip": "С фото",
               "reset": "Сбросить", "reset_all": "Сбросить всё", "show": "Показать", "close": "Закрыть",
               "remove_a11y": "Сбросить: %@", "facet": "%@: %@",
               "search_chip": "Поиск: %@", "price_short": "Цена", "rent": "Аренда",
               "gear": "Коробка", "fuel": "Топливо",
               "fac_auto": "Автомат", "fac_manual": "Механика", "fac_robot": "Робот", "fac_cvt": "Вариатор",
               "fac_petrol": "Бензин", "fac_diesel": "Дизель", "fac_gas": "Газ", "fac_hybrid": "Гибрид",
               "fac_electric": "Электро",
               "brand": "Марка", "model": "Модель", "brand_for": "Для какой марки", "model_for": "Для какой модели",
               "any_f": "Любая", "brand_find": "Найти марку", "model_find": "Найти модель",
               "brand_none": "Марка не найдена", "model_none": "Моделей нет", "nothing_found": "Не нашли — уточните запрос",
               "model_first": "Сначала марка", "model_many": "Выберите одну марку — тогда появятся её модели",
               "model_load": "Загружаем модели…", "brand_load": "Загружаем каталог…", "popular": "Популярные",
               "all_brands": "Все марки", "brands_fail": "Не удалось загрузить марки", "retry": "Повторить",
               "done": "Готово"],
        "kk": ["filters": "Сүзгілер", "sort_title": "Алдымен көрсету",
               "sort_reco": "Ұсынылатындар", "sort_new": "Жаңалары", "sort_old": "Ескілері", "sort_rating": "Рейтинг бойынша", "sort_cheap": "Арзанырақ", "sort_expensive": "Қымбатырақ",
               "price": "Бағасы, ₸", "from": "бастап", "to": "дейін", "from_x": "%@ бастап", "to_x": "%@ дейін",
               "year": "Шығарылған жылы", "rooms": "Бөлмелер", "studio": "Студия", "rooms_5": "5 және одан көп",
               "cond": "Жағдайы", "cond_new": "Жаңа", "cond_used": "Қолданылған",
               "cond_new_auto": "Жаңа", "cond_used_auto": "Жүрген",
               "seller": "Сатушы", "verified": "Тексерілгендер", "verified_chip": "Тексерілген сатушылар",
               "photo": "Фото", "photo_only": "Тек фотосы барлар", "photo_chip": "Фотосы бар",
               "reset": "Тазалау", "reset_all": "Барлығын тазалау", "show": "Көрсету", "close": "Жабу",
               "remove_a11y": "Тазалау: %@", "facet": "%@: %@",
               "search_chip": "Іздеу: %@", "price_short": "Баға", "rent": "Жалға алу",
               "gear": "Беріліс қорабы", "fuel": "Отын",
               "fac_auto": "Автомат", "fac_manual": "Механика", "fac_robot": "Робот", "fac_cvt": "Вариатор",
               "fac_petrol": "Бензин", "fac_diesel": "Дизель", "fac_gas": "Газ", "fac_hybrid": "Гибрид",
               "fac_electric": "Электр",
               "brand": "Маркасы", "model": "Моделі", "brand_for": "Қай маркаға", "model_for": "Қай модельге",
               "any_f": "Кез келген", "brand_find": "Марканы табу", "model_find": "Модельді табу",
               "brand_none": "Марка табылмады", "model_none": "Модельдер жоқ", "nothing_found": "Табылмады — сұрауды нақтылаңыз",
               "model_first": "Алдымен марка", "model_many": "Бір марканы таңдаңыз — сонда оның модельдері шығады",
               "model_load": "Модельдерді жүктеп жатырмыз…", "brand_load": "Каталогты жүктеп жатырмыз…", "popular": "Танымал",
               "all_brands": "Барлық маркалар", "brands_fail": "Маркаларды жүктеу мүмкін болмады", "retry": "Қайталау",
               "done": "Дайын"],
        "en": ["filters": "Filters", "sort_title": "Show first",
               "sort_reco": "Recommended", "sort_new": "Newest", "sort_old": "Oldest", "sort_rating": "By rating", "sort_cheap": "Cheapest", "sort_expensive": "Most expensive",
               "price": "Price, ₸", "from": "from", "to": "to", "from_x": "from %@", "to_x": "up to %@",
               "year": "Year", "rooms": "Rooms", "studio": "Studio", "rooms_5": "5 or more",
               "cond": "Condition", "cond_new": "New", "cond_used": "Used",
               "cond_new_auto": "New", "cond_used_auto": "Used",
               "seller": "Seller", "verified": "Verified", "verified_chip": "Verified sellers",
               "photo": "Photo", "photo_only": "With photos only", "photo_chip": "With photos",
               "reset": "Reset", "reset_all": "Reset all", "show": "Show", "close": "Close",
               "remove_a11y": "Remove: %@", "facet": "%@: %@",
               "search_chip": "Search: %@", "price_short": "Price", "rent": "Rent",
               "gear": "Gearbox", "fuel": "Fuel",
               "fac_auto": "Automatic", "fac_manual": "Manual", "fac_robot": "Robotic", "fac_cvt": "CVT",
               "fac_petrol": "Petrol", "fac_diesel": "Diesel", "fac_gas": "Gas", "fac_hybrid": "Hybrid",
               "fac_electric": "Electric",
               "brand": "Make", "model": "Model", "brand_for": "For which make", "model_for": "For which model",
               "any_f": "Any", "brand_find": "Find a make", "model_find": "Find a model",
               "brand_none": "Make not found", "model_none": "No models", "nothing_found": "Nothing found — refine your search",
               "model_first": "Choose a make first", "model_many": "Choose one make to see its models",
               "model_load": "Loading models…", "brand_load": "Loading catalog…", "popular": "Popular",
               "all_brands": "All makes", "brands_fail": "Couldn't load makes", "retry": "Retry",
               "done": "Done"],
        "ar": ["filters": "عوامل التصفية", "sort_title": "اعرض أولًا",
               "sort_reco": "المقترحة", "sort_new": "الأحدث", "sort_old": "الأقدم", "sort_rating": "حسب التقييم", "sort_cheap": "الأرخص", "sort_expensive": "الأغلى",
               "price": "السعر، ₸", "from": "من", "to": "إلى", "from_x": "من %@", "to_x": "حتى %@",
               "year": "سنة الصنع", "rooms": "الغرف", "studio": "استوديو", "rooms_5": "5 أو أكثر",
               "cond": "الحالة", "cond_new": "جديد", "cond_used": "مستعمل",
               "cond_new_auto": "جديدة", "cond_used_auto": "مستعملة",
               "seller": "البائع", "verified": "الموثّقون", "verified_chip": "بائعون موثّقون",
               "photo": "الصور", "photo_only": "مع صور فقط", "photo_chip": "مع صور",
               "reset": "إعادة الضبط", "reset_all": "إعادة ضبط الكل", "show": "عرض", "close": "إغلاق",
               "remove_a11y": "إزالة: %@", "facet": "%@: %@",
               "search_chip": "بحث: %@", "price_short": "السعر", "rent": "إيجار",
               "gear": "ناقل الحركة", "fuel": "الوقود",
               "fac_auto": "أوتوماتيك", "fac_manual": "يدوي", "fac_robot": "روبوتي", "fac_cvt": "CVT",
               "fac_petrol": "بنزين", "fac_diesel": "ديزل", "fac_gas": "غاز", "fac_hybrid": "هجين",
               "fac_electric": "كهربائي",
               "brand": "الماركة", "model": "الطراز", "brand_for": "لأي ماركة", "model_for": "لأي طراز",
               "any_f": "أي", "brand_find": "ابحث عن ماركة", "model_find": "ابحث عن طراز",
               "brand_none": "لم يتم العثور على الماركة", "model_none": "لا توجد طرازات", "nothing_found": "لم نجد شيئًا — دقّق طلبك",
               "model_first": "اختر الماركة أولًا", "model_many": "اختر ماركة واحدة لتظهر طرازاتها",
               "model_load": "جارٍ تحميل الطرازات…", "brand_load": "جارٍ تحميل الدليل…", "popular": "الشائعة",
               "all_brands": "كل الماركات", "brands_fail": "تعذّر تحميل الماركات", "retry": "أعد المحاولة",
               "done": "تم"]
    ]
}
