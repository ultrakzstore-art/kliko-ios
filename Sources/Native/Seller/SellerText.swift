import Foundation

/// Тексты этапа 37 — отзывы о продавце, жалоба и блокировка — на языке телефона (kk/ru/en/ar), тем же способом, что
/// лента (FeedText).
///
/// Русские слова — сайта (js/i18n-marketplace-ru.js и разметка страницы объявления), а не придуманные: «Продавец» —
/// seller_word, «Загружаем отзывы…» — rev_loading, «Не удалось загрузить отзывы» — rev_fail, «Отзывов пока нет» и
/// «Отзыв появляется после завершённой сделки…» — rev_none и rev_none_sub, «Покупатель» — buyer_word, «Закрыть» —
/// close_word, «Профиль» — profile, «Ещё» — more, «Заблокировать» / «Разблокировать» — block и
/// unblock, «Заблокировать продавца?» и «Вы перестанете получать…» — block_seller_q и block_seller_msg, «Отмена» —
/// cancel, «Продавец заблокирован» / «Продавец разблокирован» — seller_blocked и seller_unblocked, «Вы заблокировали
/// продавца — общение недоступно. История сохранена.» — chat_you_blocked, «Войдите, чтобы заблокировать» —
/// login_to_block, «Пожаловаться» — report, «Выберите причину — жалоба уйдёт модераторам.» — report_sub, причины — кнопки
/// .mk-rr окна жалобы (data-r="spam"…), «Комментарий — по желанию» — его поле, «Отправить жалобу» / «Отправляю…» —
/// report_send и report_sending, «Жалоба отправлена модераторам» — report_sent, «Вы уже жаловались на это» —
/// report_exists, «Войдите, чтобы пожаловаться» — report_login, «Не удалось отправить» — report_failed, «Выберите
/// причину» — report_pick, «Нет соединения» — no_conn, «Войдите в кабинет» — login_toast, «Не удалось» — failed;
/// «Доступно после верификации» и «Ошибка защиты, перезагрузите» — словарь ошибок js/err_i18n.min.js.
///
/// Своих строк у сайта нет для вопроса перед жалобой («Отправить жалобу?» — по образцу block_seller_q: название кнопки и
/// вопросительный знак; ««…» — жалоба уйдёт модераторам.» — хвост report_sub), для подсказок VoiceOver («Оценка 4 из
/// 5», «Откроются отзывы о продавце», «Откроется страница продавца на сайте») и «Повторить» (как у ленты).
enum SellerText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "seller": "Продавец", "loading": "Загружаем отзывы…", "fail": "Не удалось загрузить отзывы",
            "none": "Отзывов пока нет",
            "none_sub": "Отзыв появляется после завершённой сделки через гаранта — оставить его может только покупатель.",
            "buyer": "Покупатель", "close": "Закрыть", "profile": "Профиль",
            "open_profile": "Откроется страница продавца на сайте", "reviews_hint": "Откроются отзывы о продавце",
            "rating_of": "Оценка %d из 5", "retry": "Повторить",
            "more": "Ещё", "block": "Заблокировать", "unblock": "Разблокировать",
            "block_q": "Заблокировать продавца?",
            "block_msg": "Вы перестанете получать от него уведомления и не сможете переписываться. Историю можно вернуть, разблокировав его.",
            "cancel": "Отмена", "blocked": "Продавец заблокирован", "unblocked": "Продавец разблокирован",
            "you_blocked": "Вы заблокировали продавца — общение недоступно. История сохранена.",
            "login_block": "Войдите, чтобы заблокировать",
            "report": "Пожаловаться", "report_sub": "Выберите причину — жалоба уйдёт модераторам.",
            "r_spam": "Спам или реклама", "r_fraud": "Мошенничество", "r_prohibited": "Запрещённый товар",
            "r_abuse": "Оскорбления или угрозы", "r_duplicate": "Дубликат объявления", "r_other": "Другое",
            "comment": "Комментарий — по желанию", "report_send": "Отправить жалобу", "report_sending": "Отправляю…",
            "report_q": "Отправить жалобу?", "report_q_msg": "«%@» — жалоба уйдёт модераторам.",
            "report_sent": "Жалоба отправлена модераторам", "report_exists": "Вы уже жаловались на это",
            "report_login": "Войдите, чтобы пожаловаться", "report_failed": "Не удалось отправить",
            "report_pick": "Выберите причину",
            "err_net": "Нет соединения", "err_login": "Войдите в кабинет", "err_verify": "Доступно после верификации",
            "err_csrf": "Ошибка защиты, перезагрузите", "err_failed": "Не удалось"
        ],
        "kk": [
            "seller": "Сатушы", "loading": "Пікірлер жүктелуде…", "fail": "Пікірлерді жүктеу мүмкін болмады",
            "none": "Әзірге пікір жоқ",
            "none_sub": "Пікір кепілгер арқылы аяқталған мәміледен кейін пайда болады — оны тек сатып алушы қалдыра алады.",
            "buyer": "Сатып алушы", "close": "Жабу", "profile": "Профиль",
            "open_profile": "Сайтта сатушының беті ашылады", "reviews_hint": "Сатушы туралы пікірлер ашылады",
            "rating_of": "Баға: 5-тен %d", "retry": "Қайталау",
            "more": "Тағы", "block": "Бұғаттау", "unblock": "Бұғаттан шығару",
            "block_q": "Сатушыны бұғаттау керек пе?",
            "block_msg": "Одан хабарламалар келмейді және хат алмаса алмайсыз. Бұғаттан шығарып, тарихты қайтаруға болады.",
            "cancel": "Бас тарту", "blocked": "Сатушы бұғатталды", "unblocked": "Сатушы бұғаттан шығарылды",
            "you_blocked": "Сіз сатушыны бұғаттадыңыз — хат алмасу қолжетімсіз. Тарих сақталды.",
            "login_block": "Бұғаттау үшін кіріңіз",
            "report": "Шағымдану", "report_sub": "Себебін таңдаңыз — шағым модераторларға жіберіледі.",
            "r_spam": "Спам немесе жарнама", "r_fraud": "Алаяқтық", "r_prohibited": "Тыйым салынған тауар",
            "r_abuse": "Қорлау немесе қорқыту", "r_duplicate": "Хабарландырудың көшірмесі", "r_other": "Басқа",
            "comment": "Түсініктеме — қалауыңыз бойынша", "report_send": "Шағым жіберу", "report_sending": "Жіберілуде…",
            "report_q": "Шағым жіберу керек пе?", "report_q_msg": "«%@» — шағым модераторларға жіберіледі.",
            "report_sent": "Шағым модераторларға жіберілді", "report_exists": "Сіз бұған шағымданып қойғансыз",
            "report_login": "Шағымдану үшін кіріңіз", "report_failed": "Жіберу мүмкін болмады",
            "report_pick": "Себебін таңдаңыз",
            "err_net": "Байланыс жоқ", "err_login": "Кабинетке кіріңіз", "err_verify": "Верификациядан кейін қолжетімді",
            "err_csrf": "Қорғаныс қатесі, бетті қайта жүктеңіз", "err_failed": "Сәтсіз аяқталды"
        ],
        "en": [
            "seller": "Seller", "loading": "Loading reviews…", "fail": "Couldn't load reviews",
            "none": "No reviews yet",
            "none_sub": "A review appears after a deal completed through the guarantor — only the buyer can leave one.",
            "buyer": "Buyer", "close": "Close", "profile": "Profile",
            "open_profile": "Opens the seller's page on the website", "reviews_hint": "Opens reviews of the seller",
            "rating_of": "Rated %d out of 5", "retry": "Retry",
            "more": "More", "block": "Block", "unblock": "Unblock",
            "block_q": "Block the seller?",
            "block_msg": "You'll stop getting notifications from them and won't be able to message each other. You can bring the history back by unblocking them.",
            "cancel": "Cancel", "blocked": "Seller blocked", "unblocked": "Seller unblocked",
            "you_blocked": "You blocked the seller — messaging is unavailable. The history is saved.",
            "login_block": "Sign in to block",
            "report": "Report", "report_sub": "Choose a reason — the report goes to the moderators.",
            "r_spam": "Spam or advertising", "r_fraud": "Fraud", "r_prohibited": "Prohibited item",
            "r_abuse": "Insults or threats", "r_duplicate": "Duplicate listing", "r_other": "Other",
            "comment": "Comment — optional", "report_send": "Send report", "report_sending": "Sending…",
            "report_q": "Send the report?", "report_q_msg": "“%@” — the report goes to the moderators.",
            "report_sent": "Report sent to the moderators", "report_exists": "You've already reported this",
            "report_login": "Sign in to report", "report_failed": "Couldn't send",
            "report_pick": "Choose a reason",
            "err_net": "No connection", "err_login": "Sign in to your account", "err_verify": "Available after verification",
            "err_csrf": "Security error, reload the page", "err_failed": "Something went wrong"
        ],
        "ar": [
            "seller": "البائع", "loading": "جارٍ تحميل التقييمات…", "fail": "تعذّر تحميل التقييمات",
            "none": "لا توجد تقييمات بعد",
            "none_sub": "يظهر التقييم بعد إتمام صفقة عبر الضامن — ولا يمكن تركه إلا للمشتري.",
            "buyer": "المشتري", "close": "إغلاق", "profile": "الملف الشخصي",
            "open_profile": "يفتح صفحة البائع على الموقع", "reviews_hint": "يفتح تقييمات البائع",
            "rating_of": "التقييم %d من 5", "retry": "إعادة المحاولة",
            "more": "المزيد", "block": "حظر", "unblock": "إلغاء الحظر",
            "block_q": "حظر البائع؟",
            "block_msg": "لن تصلك إشعارات منه ولن تتمكنا من المراسلة. يمكنك استعادة السجل بإلغاء حظره.",
            "cancel": "إلغاء", "blocked": "تم حظر البائع", "unblocked": "تم إلغاء حظر البائع",
            "you_blocked": "لقد حظرت البائع — المراسلة غير متاحة. السجل محفوظ.",
            "login_block": "سجّل الدخول للحظر",
            "report": "إبلاغ", "report_sub": "اختر السبب — سيُرسل البلاغ إلى المشرفين.",
            "r_spam": "رسائل مزعجة أو إعلان", "r_fraud": "احتيال", "r_prohibited": "سلعة محظورة",
            "r_abuse": "إهانات أو تهديدات", "r_duplicate": "إعلان مكرر", "r_other": "أخرى",
            "comment": "تعليق — اختياري", "report_send": "إرسال البلاغ", "report_sending": "جارٍ الإرسال…",
            "report_q": "إرسال البلاغ؟", "report_q_msg": "«%@» — سيُرسل البلاغ إلى المشرفين.",
            "report_sent": "أُرسل البلاغ إلى المشرفين", "report_exists": "لقد أبلغت عن هذا من قبل",
            "report_login": "سجّل الدخول للإبلاغ", "report_failed": "تعذّر الإرسال",
            "report_pick": "اختر السبب",
            "err_net": "لا يوجد اتصال", "err_login": "سجّل الدخول إلى حسابك", "err_verify": "متاح بعد التوثيق",
            "err_csrf": "خطأ حماية، أعد تحميل الصفحة", "err_failed": "تعذّر ذلك"
        ]
    ]
}
