import Foundation

/// Тексты нативной ленты на языке телефона (kk/ru/en/ar) — тем же способом, что экран замка (AppLock.т).
enum FeedText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["reviews": "Отзывов: %d", "deals": "Сделок: %d", "used": "Б/у", "warranty": "Гарантия %d дн.", "description": "Описание", "specs": "Характеристики",
               "seller": "Продавец", "verified": "Проверенный продавец", "views": "Просмотров: %d",
               "contact": "Написать или купить", "contact_sub": "Чат с продавцом и безопасная сделка — на странице объявления",
               "share": "Поделиться", "detail_partial": "Не удалось загрузить всё объявление",
               "spec_cpu": "Процессор", "spec_gpu": "Видеокарта", "spec_ram": "ОЗУ", "spec_storage": "Накопитель", "spec_year": "Год",
               "close": "Закрыть", "search": "Toyota Camry, iPhone…", "all": "Все", "cabinet": "Кабинет",
               "noprice": "Цена по запросу", "neg": "Договорная", "perday": "/сут", "top": "ТОП", "new": "Новое",
               "empty": "Ничего не нашлось", "empty_sub": "Попробуйте другой запрос или раздел",
               "offline": "Нет соединения", "offline_sub": "Проверьте интернет и попробуйте снова.",
               "failed": "Лента не загрузилась", "failed_sub": "Можно открыть ленту сайта — там всё то же самое.",
               "retry": "Повторить", "site": "Открыть сайт", "stale": "Показываем сохранённую ленту"],
        "kk": ["reviews": "Пікірлер: %d", "deals": "Мәмілелер: %d", "used": "Қолданылған", "warranty": "Кепілдік %d күн", "description": "Сипаттама", "specs": "Сипаттамалар",
               "seller": "Сатушы", "verified": "Тексерілген сатушы", "views": "Қаралым: %d",
               "contact": "Жазу немесе сатып алу", "contact_sub": "Сатушымен чат және қауіпсіз мәміле — хабарландыру бетінде",
               "share": "Бөлісу", "detail_partial": "Хабарландыру толық жүктелмеді",
               "spec_cpu": "Процессор", "spec_gpu": "Бейнекарта", "spec_ram": "ЖЖҚ", "spec_storage": "Жинақтағыш", "spec_year": "Жылы",
               "close": "Жабу", "search": "Toyota Camry, iPhone…", "all": "Барлығы", "cabinet": "Кабинет",
               "noprice": "Бағасы сұрау бойынша", "neg": "Келісімді", "perday": "/тәул", "top": "ТОП", "new": "Жаңа",
               "empty": "Ештеңе табылмады", "empty_sub": "Басқа сұрау немесе бөлім таңдап көріңіз",
               "offline": "Байланыс жоқ", "offline_sub": "Интернетті тексеріп, қайталап көріңіз.",
               "failed": "Лента жүктелмеді", "failed_sub": "Сайттың лентасын ашуға болады — онда бәрі бар.",
               "retry": "Қайталау", "site": "Сайтты ашу", "stale": "Сақталған лента көрсетілуде"],
        "en": ["reviews": "Reviews: %d", "deals": "Deals: %d", "used": "Used", "warranty": "%d-day warranty", "description": "Description", "specs": "Specifications",
               "seller": "Seller", "verified": "Verified seller", "views": "Views: %d",
               "contact": "Message or buy", "contact_sub": "Chat with the seller and safe deal are on the listing page",
               "share": "Share", "detail_partial": "Couldn't load the full listing",
               "spec_cpu": "Processor", "spec_gpu": "Graphics", "spec_ram": "RAM", "spec_storage": "Storage", "spec_year": "Year",
               "close": "Close", "search": "Toyota Camry, iPhone…", "all": "All", "cabinet": "Account",
               "noprice": "Price on request", "neg": "Negotiable", "perday": "/day", "top": "TOP", "new": "New",
               "empty": "Nothing found", "empty_sub": "Try another search or category",
               "offline": "No connection", "offline_sub": "Check your internet and try again.",
               "failed": "The feed didn't load", "failed_sub": "You can open the website feed — it has the same listings.",
               "retry": "Try again", "site": "Open website", "stale": "Showing the saved feed"],
        "ar": ["reviews": "التقييمات: %d", "deals": "الصفقات: %d", "used": "مستعمل", "warranty": "ضمان %d يوم", "description": "الوصف", "specs": "المواصفات",
               "seller": "البائع", "verified": "بائع موثّق", "views": "المشاهدات: %d",
               "contact": "راسل أو اشترِ", "contact_sub": "الدردشة مع البائع والصفقة الآمنة في صفحة الإعلان",
               "share": "مشاركة", "detail_partial": "تعذّر تحميل الإعلان كاملًا",
               "spec_cpu": "المعالج", "spec_gpu": "بطاقة الرسومات", "spec_ram": "الذاكرة", "spec_storage": "التخزين", "spec_year": "السنة",
               "close": "إغلاق", "search": "Toyota Camry, iPhone…", "all": "الكل", "cabinet": "الحساب",
               "noprice": "السعر عند الطلب", "neg": "قابل للتفاوض", "perday": "/يوم", "top": "مميز", "new": "جديد",
               "empty": "لم يتم العثور على شيء", "empty_sub": "جرّب بحثًا أو قسمًا آخر",
               "offline": "لا يوجد اتصال", "offline_sub": "تحقق من الإنترنت وحاول مرة أخرى.",
               "failed": "لم يتم تحميل الإعلانات", "failed_sub": "يمكنك فتح إعلانات الموقع — فيها الإعلانات نفسها.",
               "retry": "إعادة المحاولة", "site": "فتح الموقع", "stale": "نعرض الإعلانات المحفوظة"]
    ]
}
