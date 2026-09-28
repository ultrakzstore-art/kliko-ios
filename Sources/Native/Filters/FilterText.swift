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
               "search_chip": "Поиск: %@", "price_short": "Цена", "rent": "Аренда"],
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
               "search_chip": "Іздеу: %@", "price_short": "Баға", "rent": "Жалға алу"],
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
               "search_chip": "Search: %@", "price_short": "Price", "rent": "Rent"],
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
               "search_chip": "بحث: %@", "price_short": "السعر", "rent": "إيجار"]
    ]
}
