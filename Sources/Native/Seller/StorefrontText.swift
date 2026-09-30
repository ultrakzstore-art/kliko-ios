import Foundation

/// Тексты витрины продавца на языке телефона (kk/ru/en/ar). Русские слова — сайта, где они у него есть:
/// «Продавец» — seller_word, «Все товары продавца» — chat_seller_goods, «Проверенный продавец» — verified_seller,
/// «Новый продавец» — new_seller, «Магазин» — shop, «Отзывов пока нет» — rev_none, «Закрыть» — close_word,
/// «Нет соединения» — err_no_conn. Своих строк у сайта нет для заголовков блоков витрины («Объявления», «Отзывы»),
/// «Загружаем витрину…», «Пока нет объявлений» и подсказок VoiceOver.
enum StorefrontText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "seller": "Продавец", "shop": "Магазин", "verified": "Проверенный продавец", "new_seller": "Новый продавец",
            "listings": "Объявления", "all_goods": "Все товары продавца", "reviews": "Отзывы", "all_reviews": "Все отзывы",
            "no_reviews": "Отзывов пока нет", "loading": "Загружаем витрину…", "fail": "Не удалось загрузить витрину",
            "no_conn": "Нет соединения", "retry": "Повторить", "empty": "Пока нет объявлений",
            "empty_sub": "Подпишитесь — сообщим, когда продавец выложит новое.", "close": "Закрыть",
            "share": "Поделиться", "since": "На Kliko с %@",
            "deals": "сделок", "rating": "оценка", "followers": "подписчиков",
            "more_goods": "Показаны последние объявления продавца",
            "nf_title": "Продавец не найден",
            "nf_sub": "Такой ссылки на витрину нет — возможно, продавец сменил её или удалил аккаунт."
        ],
        "kk": [
            "seller": "Сатушы", "shop": "Дүкен", "verified": "Тексерілген сатушы", "new_seller": "Жаңа сатушы",
            "listings": "Хабарландырулар", "all_goods": "Сатушының барлық тауары", "reviews": "Пікірлер",
            "all_reviews": "Барлық пікірлер", "no_reviews": "Әзірге пікір жоқ", "loading": "Витрина жүктелуде…",
            "fail": "Витринаны жүктеу мүмкін болмады", "no_conn": "Байланыс жоқ", "retry": "Қайталау",
            "empty": "Әзірге хабарландыру жоқ", "empty_sub": "Жазылыңыз — сатушы жаңасын қосқанда хабарлаймыз.",
            "close": "Жабу", "share": "Бөлісу", "since": "Kliko-да %@ бастап",
            "deals": "мәміле", "rating": "баға", "followers": "жазылушы",
            "more_goods": "Сатушының соңғы хабарландырулары көрсетілген",
            "nf_title": "Сатушы табылмады",
            "nf_sub": "Витринаның мұндай сілтемесі жоқ — сатушы оны өзгерткен немесе аккаунтын жойған болуы мүмкін."
        ],
        "en": [
            "seller": "Seller", "shop": "Shop", "verified": "Verified seller", "new_seller": "New seller",
            "listings": "Listings", "all_goods": "All seller's items", "reviews": "Reviews", "all_reviews": "All reviews",
            "no_reviews": "No reviews yet", "loading": "Loading the storefront…", "fail": "Couldn't load the storefront",
            "no_conn": "No connection", "retry": "Retry", "empty": "No listings yet",
            "empty_sub": "Follow — we'll let you know when the seller posts something new.", "close": "Close",
            "share": "Share", "since": "On Kliko since %@",
            "deals": "deals", "rating": "rating", "followers": "followers",
            "more_goods": "Showing the seller's latest listings",
            "nf_title": "Seller not found",
            "nf_sub": "There is no storefront at this link — the seller may have changed it or deleted the account."
        ],
        "ar": [
            "seller": "البائع", "shop": "متجر", "verified": "بائع موثّق", "new_seller": "بائع جديد",
            "listings": "الإعلانات", "all_goods": "كل منتجات البائع", "reviews": "التقييمات", "all_reviews": "كل التقييمات",
            "no_reviews": "لا توجد تقييمات بعد", "loading": "جارٍ تحميل المتجر…", "fail": "تعذّر تحميل المتجر",
            "no_conn": "لا يوجد اتصال", "retry": "إعادة المحاولة", "empty": "لا توجد إعلانات بعد",
            "empty_sub": "تابِع البائع وسنخبرك عندما ينشر جديدًا.", "close": "إغلاق",
            "share": "مشاركة", "since": "على Kliko منذ %@",
            "deals": "صفقات", "rating": "التقييم", "followers": "متابعون",
            "more_goods": "تُعرض أحدث إعلانات البائع",
            "nf_title": "لم يتم العثور على البائع",
            "nf_sub": "لا يوجد متجر بهذا الرابط — ربما غيّره البائع أو حذف حسابه."
        ]
    ]
}
