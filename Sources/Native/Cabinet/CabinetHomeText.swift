import Foundation

/// Тексты главного экрана кабинета (13.10.2026): плитки главных разделов и строка «Уведомления и подписки» — на языке
/// телефона (kk/ru/en/ar), тем же способом, что CabinetText. Плитка «Отзывы» (вместо «Избранного»): название, «Отзывов
/// пока нет» (те же слова, что в листе отзывов и витрине: SellerText «none», StorefrontText «no_reviews») и начало
/// значения для VoiceOver («Рейтинг 4.9, 12 отзывов»); «12 отзывов» склоняет ListingPageText.число.
enum КабинетГлавнаяText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["tile_listings": "Объявления",
               "tile_deals": "Сделки",
               "tile_requests": "Заявки рядом",
               "tile_reviews": "Отзывы",
               "reviews_none": "Отзывов пока нет",
               "a11y_rating": "Рейтинг",
               "notif_hub": "Уведомления и подписки",
               "att_title": "Требует внимания",
               "att_all": "Все сделки",
               "att_disputed": "Открыт спор — откройте сделку",
               "att_delivered": "Товар у вас — подтвердите получение",
               "att_count": "Ждут вас: %d"],
        "kk": ["tile_listings": "Хабарландырулар",
               "tile_deals": "Мәмілелер",
               "tile_requests": "Жақын өтінімдер",
               "tile_reviews": "Пікірлер",
               "reviews_none": "Әзірге пікір жоқ",
               "a11y_rating": "Рейтинг",
               "notif_hub": "Хабарламалар мен жазылымдар",
               "att_title": "Назар аударыңыз",
               "att_all": "Барлық мәмілелер",
               "att_disputed": "Дау ашылды — мәмілені ашыңыз",
               "att_delivered": "Тауар сізде — алғаныңызды растаңыз",
               "att_count": "Сізді күтеді: %d"],
        "en": ["tile_listings": "Listings",
               "tile_deals": "Deals",
               "tile_requests": "Nearby requests",
               "tile_reviews": "Reviews",
               "reviews_none": "No reviews yet",
               "a11y_rating": "Rating",
               "notif_hub": "Notifications & subscriptions",
               "att_title": "Needs your attention",
               "att_all": "All deals",
               "att_disputed": "Dispute opened — open the deal",
               "att_delivered": "Item is with you — confirm receipt",
               "att_count": "Waiting for you: %d"],
        "ar": ["tile_listings": "إعلاناتي",
               "tile_deals": "صفقاتي",
               "tile_requests": "طلبات قريبة",
               "tile_reviews": "التقييمات",
               "reviews_none": "لا توجد تقييمات بعد",
               "a11y_rating": "التقييم",
               "notif_hub": "الإشعارات والاشتراكات",
               "att_title": "يتطلب انتباهك",
               "att_all": "كل الصفقات",
               "att_disputed": "تم فتح نزاع — افتح الصفقة",
               "att_delivered": "المنتج لديك — أكّد الاستلام",
               "att_count": "بانتظارك: %d"]
    ]
}
