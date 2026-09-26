import Foundation

/**
 Тексты поиска как на сайте — полноэкранный поиск (#mk-search-ov) и поиск по фото (mkPhotoSearch) — на языке приложения
 (kk/ru/en/ar), тем же способом, что DesignText.

 Русские слова — из словаря витрины js/i18n-marketplace-ru.js: sov_* (строки поиска), ps_* (поиск по фото),
 gate_account_title, reg_photo_search, reg_have_account, gate_go (окно регистрации mkRegGate), login_toast, err_no_conn;
 подсказка поля — placeholder #mk-sov-inp («Поиск по объявлениям»). Словарей kk/en/ar сайта в снимке нет — переведено
 тем же тоном, что прежние тексты приложения. Популярные запросы (MK_TRENDS) — запасные, если страница сайта их не дала.
 */
enum ПоискСайтаText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    /// MK_TRENDS главной сайта (снимок 26.09.2026) — если загруженная страница их не отдала.
    static var популярные: [String] { запросы[язык] ?? запросы["ru"]! }

    private static let запросы: [String: [String]] = [
        "ru": ["Ноутбуки", "Lenovo", "Легковые", "Lexus", "Квартиры", "Acer", "HP", "Toyota", "ASUS", "Телевизоры",
               "Смартфоны", "Бытовая техника"],
        "kk": ["Ноутбуктер", "Lenovo", "Жеңіл көліктер", "Lexus", "Пәтерлер", "Acer", "HP", "Toyota", "ASUS",
               "Теледидарлар", "Смартфондар", "Тұрмыстық техника"],
        "en": ["Laptops", "Lenovo", "Cars", "Lexus", "Apartments", "Acer", "HP", "Toyota", "ASUS", "TVs",
               "Smartphones", "Home appliances"],
        "ar": ["حواسيب محمولة", "Lenovo", "سيارات ركاب", "Lexus", "شقق", "Acer", "HP", "Toyota", "ASUS", "تلفزيونات",
               "هواتف ذكية", "أجهزة منزلية"]
    ]

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "placeholder": "Поиск по объявлениям", "back": "Закрыть", "clear_field": "Очистить",
            "cam": "Поиск по фото",
            "sov_recent": "Вы искали", "sov_trending": "Популярные запросы", "sov_clear": "Очистить",
            "sov_remove": "Удалить", "sov_insert": "Вставить", "sov_in_cats": "Категории", "sov_brands": "Бренды",
            "sov_in": "в разделе «%@»",
            "ps_title": "Поиск по фото",
            "ps_hint": "Сфотографируйте товар или загрузите фото — Kliko AI подберёт похожие объявления.",
            "ps_upload": "Загрузить фото", "ps_note": "Фото используется только для поиска и не сохраняется.",
            "ps_recognizing": "Распознаём фото…", "ps_recognizing_sub": "Kliko AI определяет, что на фото",
            "ps_retry": "Другое фото", "ps_retry_hint": "Попробуйте фото чётче или другой ракурс",
            "ps_fail": "Не удалось распознать фото", "ps_bad_img": "Выберите изображение", "ps_found": "Ищем: %@",
            "shoot": "Снять", "pick": "Выбрать из фото", "cancel": "Отмена", "close": "Закрыть",
            "login_toast": "Войдите в кабинет", "err_no_conn": "Нет соединения",
            "gate_account_title": "Нужен аккаунт", "reg_photo_search": "Зарегистрируйтесь, чтобы искать по фото",
            "gate_go": "Регистрация через eGov", "reg_have_account": "Уже есть аккаунт — войти", "later": "Позже"
        ],
        "kk": [
            "placeholder": "Хабарландырулар бойынша іздеу", "back": "Жабу", "clear_field": "Тазалау",
            "cam": "Фото бойынша іздеу",
            "sov_recent": "Сіз іздедіңіз", "sov_trending": "Танымал сұраулар", "sov_clear": "Тазалау",
            "sov_remove": "Жою", "sov_insert": "Қою", "sov_in_cats": "Санаттар", "sov_brands": "Брендтер",
            "sov_in": "«%@» бөлімінде",
            "ps_title": "Фото бойынша іздеу",
            "ps_hint": "Тауарды суретке түсіріңіз немесе фото жүктеңіз — Kliko AI ұқсас хабарландыруларды табады.",
            "ps_upload": "Фото жүктеу", "ps_note": "Фото тек іздеу үшін қолданылады және сақталмайды.",
            "ps_recognizing": "Фотоны танып жатырмыз…", "ps_recognizing_sub": "Kliko AI фотода не бар екенін анықтап жатыр",
            "ps_retry": "Басқа фото", "ps_retry_hint": "Анығырақ фото немесе басқа қырынан көріңіз",
            "ps_fail": "Фотоны тану мүмкін болмады", "ps_bad_img": "Суретті таңдаңыз", "ps_found": "Іздейміз: %@",
            "shoot": "Түсіру", "pick": "Фотодан таңдау", "cancel": "Бас тарту", "close": "Жабу",
            "login_toast": "Кабинетке кіріңіз", "err_no_conn": "Байланыс жоқ",
            "gate_account_title": "Аккаунт қажет", "reg_photo_search": "Фото бойынша іздеу үшін тіркеліңіз",
            "gate_go": "eGov арқылы тіркелу", "reg_have_account": "Аккаунтым бар — кіру", "later": "Кейінірек"
        ],
        "en": [
            "placeholder": "Search listings", "back": "Close", "clear_field": "Clear",
            "cam": "Search by photo",
            "sov_recent": "Recent searches", "sov_trending": "Popular searches", "sov_clear": "Clear",
            "sov_remove": "Remove", "sov_insert": "Insert", "sov_in_cats": "Categories", "sov_brands": "Brands",
            "sov_in": "in “%@”",
            "ps_title": "Search by photo",
            "ps_hint": "Take a photo of an item or upload one — Kliko AI will find similar listings.",
            "ps_upload": "Upload photo", "ps_note": "The photo is used only for the search and is not stored.",
            "ps_recognizing": "Recognizing the photo…", "ps_recognizing_sub": "Kliko AI is working out what is in the photo",
            "ps_retry": "Another photo", "ps_retry_hint": "Try a sharper photo or a different angle",
            "ps_fail": "Couldn't recognize the photo", "ps_bad_img": "Choose an image", "ps_found": "Searching: %@",
            "shoot": "Take photo", "pick": "Choose from photos", "cancel": "Cancel", "close": "Close",
            "login_toast": "Sign in to your account", "err_no_conn": "No connection",
            "gate_account_title": "Account required", "reg_photo_search": "Sign up to search by photo",
            "gate_go": "Sign up with eGov", "reg_have_account": "I already have an account — sign in", "later": "Later"
        ],
        "ar": [
            "placeholder": "ابحث في الإعلانات", "back": "إغلاق", "clear_field": "مسح",
            "cam": "البحث بالصورة",
            "sov_recent": "عمليات بحثك", "sov_trending": "عمليات بحث شائعة", "sov_clear": "مسح",
            "sov_remove": "حذف", "sov_insert": "إدراج", "sov_in_cats": "الفئات", "sov_brands": "العلامات التجارية",
            "sov_in": "في قسم «%@»",
            "ps_title": "البحث بالصورة",
            "ps_hint": "صوّر المنتج أو ارفع صورة — سيجد Kliko AI إعلانات مشابهة.",
            "ps_upload": "رفع صورة", "ps_note": "تُستخدم الصورة للبحث فقط ولا تُحفظ.",
            "ps_recognizing": "نتعرّف على الصورة…", "ps_recognizing_sub": "يحدد Kliko AI ما في الصورة",
            "ps_retry": "صورة أخرى", "ps_retry_hint": "جرّب صورة أوضح أو زاوية أخرى",
            "ps_fail": "تعذّر التعرّف على الصورة", "ps_bad_img": "اختر صورة", "ps_found": "نبحث عن: %@",
            "shoot": "التقاط صورة", "pick": "اختيار من الصور", "cancel": "إلغاء", "close": "إغلاق",
            "login_toast": "سجّل الدخول إلى حسابك", "err_no_conn": "لا يوجد اتصال",
            "gate_account_title": "يلزم حساب", "reg_photo_search": "سجّل للبحث بالصورة",
            "gate_go": "التسجيل عبر eGov", "reg_have_account": "لدي حساب — تسجيل الدخول", "later": "لاحقًا"
        ]
    ]
}
