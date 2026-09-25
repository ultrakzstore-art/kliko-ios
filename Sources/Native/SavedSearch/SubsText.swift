import Foundation

/// Тексты подписок вместе с сайтом (этап 36) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
///
/// Русские слова — сайта (js/i18n-marketplace-ru.js): «Подписаться на продавца» — follow_seller, «Вы подписаны» —
/// subscribed, «Отписаться» — unfollow, «Подписались — сообщим о новых объявлениях продавца» — sl_fol_done, «Вы
/// отписались от продавца» — sl_fol_undone, «подписчик / подписчика / подписчиков» — followers_1/2/5, «Нет соединения» —
/// no_conn, «Войдите в кабинет, чтобы подписаться» — login_to_sub, «Войдите в кабинет» — login_toast, «Не удалось
/// сохранить» — save_fail, «Не удалось отписаться» — unsub_fail, «Не удалось» — failed; «Доступно после верификации» и
/// «Ошибка защиты, перезагрузите» с переводами — словарь ошибок js/err_i18n.min.js; «Мои подписки», «Продавцы»,
/// «Продавец» и «На продавца можно подписаться в его объявлении» — блок подписок сайта (mkRenderFavSubs). Строк
/// «local_only», «footer_synced», «sellers_footer» и «open_seller» у сайта нет — они свои.
enum SubsText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    /// «12 подписчиков» — noun() сайта: 1 подписчик, 2 подписчика, 5 подписчиков.
    static func подписчики(_ n: Int) -> String {
        let форма: String
        switch язык {
        case "ru":
            let д = n % 10
            let с = n % 100
            if (11...14).contains(с) {
                форма = "_5"
            } else if д == 1 {
                форма = "_1"
            } else if (2...4).contains(д) {
                форма = "_2"
            } else {
                форма = "_5"
            }
        case "en", "ar":
            форма = n == 1 ? "_1" : "_5"
        default:
            форма = "_1"
        }
        return String(n) + " " + т("followers" + форма)
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["follow_seller": "Подписаться на продавца", "subscribed": "Вы подписаны", "unfollow": "Отписаться",
               "fol_done": "Подписались — сообщим о новых объявлениях продавца",
               "fol_undone": "Вы отписались от продавца",
               "followers_1": "подписчик", "followers_2": "подписчика", "followers_5": "подписчиков",
               "seller": "Продавец", "sellers_title": "Мои подписки · Продавцы",
               "sellers_footer": "Подписки хранятся в вашем аккаунте Kliko — такие же, как на сайте. На продавца можно подписаться в его объявлении.",
               "open_seller": "Открыть страницу продавца",
               "local_only": "только на этом телефоне",
               "footer_synced": "Поиски хранятся в вашем аккаунте Kliko — такие же, как на сайте. Kliko проверяет их в фоне — не чаще раза в час, когда позволит iOS, — и присылает одно уведомление о новых объявлениях. Поиски с пометкой «только на этом телефоне» сохранены без входа и на сайт не переносятся.",
               "err_net": "Нет соединения", "err_login_sub": "Войдите в кабинет, чтобы подписаться",
               "err_login": "Войдите в кабинет", "err_verify": "Доступно после верификации",
               "err_csrf": "Ошибка защиты, перезагрузите", "err_save": "Не удалось сохранить",
               "err_unsub": "Не удалось отписаться", "err_failed": "Не удалось"],
        "kk": ["follow_seller": "Сатушыға жазылу", "subscribed": "Сіз жазылдыңыз", "unfollow": "Жазылудан бас тарту",
               "fol_done": "Жазылдыңыз — сатушының жаңа хабарландырулары туралы хабарлаймыз",
               "fol_undone": "Сатушыдан жазылудан бас тарттыңыз",
               "followers_1": "жазылушы", "followers_2": "жазылушы", "followers_5": "жазылушы",
               "seller": "Сатушы", "sellers_title": "Менің жазылымдарым · Сатушылар",
               "sellers_footer": "Жазылымдар Kliko аккаунтыңызда сақталады — сайттағыдай. Сатушыға оның хабарландыруында жазылуға болады.",
               "open_seller": "Сатушы бетін ашу",
               "local_only": "тек осы телефонда",
               "footer_synced": "Іздеулер Kliko аккаунтыңызда сақталады — сайттағыдай. Kliko оларды фонда тексереді — сағатына бір реттен жиі емес, iOS мүмкіндік бергенде — және жаңа хабарландырулар туралы бір хабарлама жібереді. «Тек осы телефонда» белгісі бар іздеулер кірмей сақталған және сайтқа ауыспайды.",
               "err_net": "Байланыс жоқ", "err_login_sub": "Жазылу үшін кабинетке кіріңіз",
               "err_login": "Кабинетке кіріңіз", "err_verify": "Верификациядан кейін қолжетімді",
               "err_csrf": "Қорғаныс қатесі, бетті қайта жүктеңіз", "err_save": "Сақтау мүмкін болмады",
               "err_unsub": "Жазылымнан бас тарту мүмкін болмады", "err_failed": "Сәтсіз аяқталды"],
        "en": ["follow_seller": "Follow seller", "subscribed": "Following", "unfollow": "Unfollow",
               "fol_done": "Following — we'll let you know about the seller's new listings",
               "fol_undone": "You unfollowed the seller",
               "followers_1": "follower", "followers_2": "followers", "followers_5": "followers",
               "seller": "Seller", "sellers_title": "My subscriptions · Sellers",
               "sellers_footer": "Subscriptions are stored in your Kliko account — the same as on the website. You can follow a seller from their listing.",
               "open_seller": "Opens the seller's page",
               "local_only": "only on this phone",
               "footer_synced": "Searches are stored in your Kliko account — the same as on the website. Kliko checks them in the background — at most once an hour, when iOS allows — and sends one notification about new listings. Searches marked “only on this phone” were saved while signed out and aren't moved to the website.",
               "err_net": "No connection", "err_login_sub": "Sign in to your account to subscribe",
               "err_login": "Sign in to your account", "err_verify": "Available after verification",
               "err_csrf": "Security error, reload the page", "err_save": "Couldn't save",
               "err_unsub": "Couldn't unsubscribe", "err_failed": "Something went wrong"],
        "ar": ["follow_seller": "متابعة البائع", "subscribed": "أنت متابع", "unfollow": "إلغاء المتابعة",
               "fol_done": "تمت المتابعة — سنخبرك بإعلانات البائع الجديدة",
               "fol_undone": "ألغيت متابعة البائع",
               "followers_1": "متابع", "followers_2": "متابعين", "followers_5": "متابعين",
               "seller": "البائع", "sellers_title": "اشتراكاتي · البائعون",
               "sellers_footer": "تُحفظ الاشتراكات في حسابك على Kliko — كما على الموقع. يمكنك متابعة البائع من إعلانه.",
               "open_seller": "يفتح صفحة البائع",
               "local_only": "على هذا الهاتف فقط",
               "footer_synced": "تُحفظ عمليات البحث في حسابك على Kliko — كما على الموقع. يتحقق ‏Kliko منها في الخلفية — مرة في الساعة على الأكثر، عندما يسمح iOS — ويرسل إشعارًا واحدًا بالإعلانات الجديدة. عمليات البحث المعلّمة «على هذا الهاتف فقط» حُفظت دون تسجيل الدخول ولا تُنقل إلى الموقع.",
               "err_net": "لا يوجد اتصال", "err_login_sub": "سجّل الدخول إلى حسابك للاشتراك",
               "err_login": "سجّل الدخول إلى حسابك", "err_verify": "متاح بعد التوثيق",
               "err_csrf": "خطأ حماية، أعد تحميل الصفحة", "err_save": "تعذّر الحفظ",
               "err_unsub": "تعذّر إلغاء الاشتراك", "err_failed": "تعذّر ذلك"]
    ]
}
