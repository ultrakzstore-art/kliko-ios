import Foundation

/**
 Тексты вида «как на сайте» (этапы 24–27) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта, а не придуманные: словарь витрины js/i18n-marketplace-ru.js («По всей стране» — all_kz,
 «Рекомендуем» — mh_reco_h, «Все» — mh_row_all, «Смотреть все» — mh_see_all, «предложение/-ия/-ий» — mh_offers_*,
 «Предложения от проверенных продавцов» — feed_reco, «Поиск по фото» — ps_search, «Не удалось загрузить подборки» —
 mh_fail), подписи нижней панели и поле поиска — из разметки главной («Категории», «Избранное», «Чат», «Кабинет»,
 «Разместить», «Что искали?»), названия разделов — MK_HOME_V, баннер — .mh-bn главной.
 */
enum DesignText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// «26 предложений»: число с неразрывными пробелами тысяч и слово в нужной форме (_mhCount сайта).
    static func предложений(_ n: Int) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let форма: String
        switch язык {
        case "ru":
            let д = n % 10, с = n % 100
            if д == 1 && с != 11 { форма = "offers_1" }
            else if (2...4).contains(д) && !(12...14).contains(с) { форма = "offers_2" }
            else { форма = "offers_5" }
        case "en", "ar":
            форма = n == 1 ? "offers_1" : "offers_5"
        default:
            форма = "offers_1"                      // в казахском после числа слово не меняется
        }
        return число(n) + "\u{00A0}" + т(форма)
    }

    /// «1 234» — как fmt() сайта: разряды неразрывным пробелом.
    static func число(_ n: Int) -> String {
        формат.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static let формат: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"
        ф.maximumFractionDigits = 0
        return ф
    }()

    private static let тексты: [String: [String: String]] = [
        "ru": ["all_kz": "По всей стране", "search": "Что искали?", "photo": "Поиск по фото", "on_site": "Откроется на сайте",
               "city": "Город", "theme": "Тема оформления", "clear": "Очистить",
               "reco": "Рекомендуем", "row_all": "Все", "see_all": "Смотреть все",
               "feed": "Предложения от проверенных продавцов",
               "offers_1": "предложение", "offers_2": "предложения", "offers_5": "предложений",
               "fail": "Не удалось загрузить подборки", "retry": "Повторить",
               "v_transport": "Авто", "v_realty": "Недвижимость", "v_electronics": "Электроника",
               "v_services": "Услуги", "v_goods": "Товары", "v_animals": "Животные",
               "banner": "Баннер Kliko",
               "bn_import_t": "Перенесём ваши объявления", "bn_import_s": "Пришлите прайс или фото — Kliko AI соберёт карточки сам",
               "bn_import_b": "Перенести",
               "bn_sell_t": "Продавайте на Kliko", "bn_sell_s": "Разместить объявление — бесплатно", "bn_sell_b": "Разместить",
               "nav": "Основная навигация", "categories": "Категории", "home": "Главная", "favorites": "Избранное",
               "chat": "Чат", "cabinet": "Кабинет", "post": "Разместить", "unread": "Непрочитанных: %d"],
        "kk": ["all_kz": "Бүкіл Қазақстан", "search": "Не іздедіңіз?", "photo": "Фото бойынша іздеу", "on_site": "Сайтта ашылады",
               "city": "Қала", "theme": "Безендіру тақырыбы", "clear": "Тазалау",
               "reco": "Ұсынамыз", "row_all": "Барлығы", "see_all": "Барлығын көру",
               "feed": "Тексерілген сатушылардың ұсыныстары",
               "offers_1": "ұсыныс", "offers_2": "ұсыныс", "offers_5": "ұсыныс",
               "fail": "Топтамалар жүктелмеді", "retry": "Қайталау",
               "v_transport": "Көлік", "v_realty": "Жылжымайтын мүлік", "v_electronics": "Электроника",
               "v_services": "Қызметтер", "v_goods": "Тауарлар", "v_animals": "Жануарлар",
               "banner": "Kliko баннері",
               "bn_import_t": "Хабарландыруларыңызды көшіреміз", "bn_import_s": "Прайс немесе фото жіберіңіз — Kliko AI карточкаларды өзі жинайды",
               "bn_import_b": "Көшіру",
               "bn_sell_t": "Kliko-да сатыңыз", "bn_sell_s": "Хабарландыру беру — тегін", "bn_sell_b": "Жариялау",
               "nav": "Негізгі навигация", "categories": "Санаттар", "home": "Басты бет", "favorites": "Таңдаулылар",
               "chat": "Чат", "cabinet": "Кабинет", "post": "Жариялау", "unread": "Оқылмаған: %d"],
        "en": ["all_kz": "All of Kazakhstan", "search": "What are you looking for?", "photo": "Search by photo",
               "on_site": "Opens on the website", "city": "City", "theme": "Appearance", "clear": "Clear",
               "reco": "Recommended", "row_all": "All", "see_all": "See all",
               "feed": "Offers from verified sellers",
               "offers_1": "offer", "offers_2": "offers", "offers_5": "offers",
               "fail": "Couldn't load the collections", "retry": "Try again",
               "v_transport": "Vehicles", "v_realty": "Real estate", "v_electronics": "Electronics",
               "v_services": "Services", "v_goods": "Goods", "v_animals": "Animals",
               "banner": "Kliko banner",
               "bn_import_t": "We'll move your listings", "bn_import_s": "Send a price list or photos — Kliko AI builds the listings itself",
               "bn_import_b": "Move",
               "bn_sell_t": "Sell on Kliko", "bn_sell_s": "Posting a listing is free", "bn_sell_b": "Post",
               "nav": "Main navigation", "categories": "Categories", "home": "Home", "favorites": "Favorites",
               "chat": "Chat", "cabinet": "Account", "post": "Post a listing", "unread": "Unread: %d"],
        "ar": ["all_kz": "كل كازاخستان", "search": "عمّ تبحث؟", "photo": "البحث بالصورة", "on_site": "يُفتح في الموقع",
               "city": "المدينة", "theme": "المظهر", "clear": "مسح",
               "reco": "نوصي به", "row_all": "الكل", "see_all": "عرض الكل",
               "feed": "عروض من بائعين موثّقين",
               "offers_1": "عرض", "offers_2": "عروض", "offers_5": "عروض",
               "fail": "تعذّر تحميل المجموعات", "retry": "إعادة المحاولة",
               "v_transport": "سيارات", "v_realty": "عقارات", "v_electronics": "إلكترونيات",
               "v_services": "خدمات", "v_goods": "سلع", "v_animals": "حيوانات",
               "banner": "لافتة Kliko",
               "bn_import_t": "سننقل إعلاناتك", "bn_import_s": "أرسل قائمة أسعار أو صورًا — وسيُنشئ Kliko AI الإعلانات بنفسه",
               "bn_import_b": "انقل",
               "bn_sell_t": "بِع على Kliko", "bn_sell_s": "نشر الإعلان مجاني", "bn_sell_b": "انشر",
               "nav": "التنقل الرئيسي", "categories": "الفئات", "home": "الرئيسية", "favorites": "المفضلة",
               "chat": "الدردشة", "cabinet": "الحساب", "post": "انشر إعلانًا", "unread": "غير مقروءة: %d"]
    ]
}
