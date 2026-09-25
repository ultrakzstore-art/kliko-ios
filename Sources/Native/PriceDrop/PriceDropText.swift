import Foundation

/// Тексты снижения цены в избранном (этап 21) на языке телефона (kk/ru/en/ar) — тем же способом, что сохранённые
/// поиски (SavedSearchText). Уведомление пишется ими же: его готовит само приложение, в фоне.
enum PriceDropText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Снижение цены", "toggle": "Сообщать о снижении цены в избранном",
               "footer": "Kliko проверяет цены избранного в фоне — не чаще раза в час, когда позволит iOS, до %d объявлений за раз — и присылает одно уведомление, если цена снизилась.",
               "notif_off": "Уведомления выключены — включите их выше или в Настройках iPhone, иначе о снижении цены не узнать.",
               "refresh_off": "Обновление контента для Kliko выключено в Настройках iPhone — проверок не будет.",
               "notif_title": "Цена снизилась", "notif_item": "«%@» — %@ → %@", "notif_more": "+%d ещё",
               "untitled": "Объявление из избранного"],
        "kk": ["title": "Бағаның төмендеуі", "toggle": "Таңдаулылардағы бағаның төмендеуі туралы хабарлау",
               "footer": "Kliko таңдаулылардың бағасын фонда тексереді — сағатына бір реттен жиі емес, iOS мүмкіндік бергенде, бір жолы %d хабарландыруға дейін — және баға төмендесе, бір push-хабарландыру жібереді.",
               "notif_off": "Push-хабарландырулар өшірулі — оларды жоғарыда немесе iPhone баптауларында қосыңыз, әйтпесе бағаның төмендегенін білмейсіз.",
               "refresh_off": "iPhone баптауларында Kliko үшін контентті фондық жаңарту өшірулі — тексеру болмайды.",
               "notif_title": "Баға төмендеді", "notif_item": "«%@» — %@ → %@", "notif_more": "+%d тағы",
               "untitled": "Таңдаулылардағы хабарландыру"],
        "en": ["title": "Price drops", "toggle": "Notify me when favorites get cheaper",
               "footer": "Kliko checks the prices of your favorites in the background — at most once an hour, when iOS allows, up to %d listings at a time — and sends one notification if a price drops.",
               "notif_off": "Notifications are off — turn them on above or in iPhone Settings, or you won't hear about price drops.",
               "refresh_off": "Background App Refresh is off for Kliko in iPhone Settings, so prices won't be checked.",
               "notif_title": "Price dropped", "notif_item": "“%@” — %@ → %@", "notif_more": "+%d more",
               "untitled": "A listing in your favorites"],
        "ar": ["title": "انخفاض السعر", "toggle": "أبلغني عند انخفاض سعر المفضلة",
               "footer": "يتحقق ‏Kliko من أسعار المفضلة في الخلفية — مرة في الساعة على الأكثر، عندما يسمح iOS، حتى %d إعلانات في كل مرة — ويرسل إشعارًا واحدًا إذا انخفض السعر.",
               "notif_off": "الإشعارات متوقفة — فعّلها أعلاه أو في إعدادات iPhone، وإلا فلن تعرف بانخفاض الأسعار.",
               "refresh_off": "تحديث التطبيقات في الخلفية متوقف لـ Kliko في إعدادات iPhone، لذا لن يتم التحقق من الأسعار.",
               "notif_title": "انخفض السعر", "notif_item": "«%@» — %@ ← %@", "notif_more": "+%d أخرى",
               "untitled": "إعلان من المفضلة"]
    ]
}
