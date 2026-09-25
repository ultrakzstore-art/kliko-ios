import Foundation

/// Тексты избранного на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и чат (ChatText).
///
/// Этап 35: ошибки записи на сайт — словами сайта: «Ошибка сети» (net_error), «Войдите в кабинет» (login_toast) и
/// «Войти» (login_short) из js/i18n-marketplace-ru.js, «Ошибка защиты, перезагрузите», «Доступно после верификации» и
/// их переводы — из словаря ошибок js/err_i18n.min.js, «Не удалось сохранить» — save_fail, «Загружаем объявления» —
/// fl_loading. Строк «synced» и «local_merge» у сайта нет (у него избранное не подписано) — они свои.
enum FavoritesText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Избранное", "add": "Добавить в избранное", "remove": "Убрать из избранного",
               "empty": "В избранном пока пусто", "empty_sub": "Нажмите на сердечко в объявлении — оно сохранится здесь.",
               "to_feed": "Перейти в ленту",
               "local": "Избранное хранится на этом телефоне и не переносится на сайт.",
               "synced": "Избранное хранится в вашем аккаунте Kliko — такое же, как на сайте.",
               "local_merge": "Избранное хранится на этом телефоне — войдите, и оно перенесётся в ваш аккаунт на сайте.",
               "loading": "Загружаем объявления",
               "err_net": "Ошибка сети", "err_auth": "Войдите в кабинет", "err_csrf": "Ошибка защиты, перезагрузите",
               "err_verify": "Доступно после верификации", "err_save": "Не удалось сохранить", "login": "Войти"],
        "kk": ["title": "Таңдаулылар", "add": "Таңдаулыларға қосу", "remove": "Таңдаулылардан алып тастау",
               "empty": "Таңдаулылар әзірге бос", "empty_sub": "Хабарландырудағы жүрекшені басыңыз — ол осында сақталады.",
               "to_feed": "Лентаға өту",
               "local": "Таңдаулылар осы телефонда сақталады және сайтқа ауыспайды.",
               "synced": "Таңдаулылар Kliko аккаунтыңызда сақталады — сайттағыдай.",
               "local_merge": "Таңдаулылар осы телефонда сақталады — кірсеңіз, ол сайттағы аккаунтыңызға ауысады.",
               "loading": "Хабарландырулар жүктелуде",
               "err_net": "Желі қатесі", "err_auth": "Кіріңіз", "err_csrf": "Қорғаныс қатесі, бетті қайта жүктеңіз",
               "err_verify": "Верификациядан кейін қолжетімді", "err_save": "Сақтау мүмкін болмады", "login": "Кіру"],
        "en": ["title": "Favorites", "add": "Add to favorites", "remove": "Remove from favorites",
               "empty": "No favorites yet", "empty_sub": "Tap the heart on a listing to save it here.",
               "to_feed": "Browse listings",
               "local": "Favorites are stored on this phone and don't sync with the website.",
               "synced": "Favorites are saved to your Kliko account — the same as on the website.",
               "local_merge": "Favorites are stored on this phone — sign in and they'll move to your account on the website.",
               "loading": "Loading listings",
               "err_net": "Network error", "err_auth": "Please sign in", "err_csrf": "Security error, reload the page",
               "err_verify": "Available after verification", "err_save": "Couldn't save", "login": "Sign in"],
        "ar": ["title": "المفضلة", "add": "إضافة إلى المفضلة", "remove": "إزالة من المفضلة",
               "empty": "المفضلة فارغة حتى الآن", "empty_sub": "اضغط على القلب في الإعلان لحفظه هنا.",
               "to_feed": "تصفّح الإعلانات",
               "local": "تُحفظ المفضلة على هذا الهاتف ولا تتم مزامنتها مع الموقع.",
               "synced": "تُحفظ المفضلة في حسابك على Kliko — وهي نفسها على الموقع.",
               "local_merge": "تُحفظ المفضلة على هذا الهاتف — سجّل الدخول وستنتقل إلى حسابك على الموقع.",
               "loading": "جارٍ تحميل الإعلانات",
               "err_net": "خطأ في الشبكة", "err_auth": "يرجى تسجيل الدخول", "err_csrf": "خطأ حماية، أعد تحميل الصفحة",
               "err_verify": "متاح بعد التوثيق", "err_save": "تعذّر الحفظ", "login": "تسجيل الدخول"]
    ]
}
