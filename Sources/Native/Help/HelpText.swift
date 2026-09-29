import Foundation

/**
 Тексты справочного центра и статических страниц (этап 50) на языке телефона (kk/ru/en/ar). Сами статьи приходят со
 страниц сайта на языке сайта (/kz/<язык>/…); здесь — только рамка экрана: заголовки страниц, как их называет подвал
 сайта (f_help, f_agreement, f_offer, f_privacy, f_pay, f_tariffs), и слова состояний.
 */
enum СправкаText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "p_help": "Справочный центр",
        "p_soglashenie": "Пользовательское соглашение",
        "p_oferta": "Публичная оферта",
        "p_privacy": "Политика конфиденциальности",
        "p_oplata": "Оплата и возврат",
        "p_tarify": "Услуги и цены",
        "loading": "Загрузка…",
        "fail_t": "Не удалось открыть страницу",
        "fail_s": "Проверьте соединение и попробуйте ещё раз.",
        "empty_t": "Страница пока недоступна",
        "retry": "Повторить",
        "close": "Закрыть",
        "toc": "Содержание",
        "cached": "Нет соединения — показана сохранённая копия",
        "support": "Написать в поддержку",
        "support_s": "Не нашли ответ? Мы ответим в приложении.",
        "no_digital": "Эта возможность недоступна в приложении.",
        "a11y_faq": "Вопрос. Дважды нажмите, чтобы раскрыть ответ",
        "search": "Поиск по справке",
        "search_clear": "Очистить поиск",
        "nothing_t": "Ничего не найдено",
        "nothing_s": "Попробуйте другое слово или напишите в поддержку.",
        "all_sections": "Все разделы",
        "section_empty": "В этом разделе пока нет ответов в приложении. Попробуйте поиск или напишите в поддержку.",
    ]

    private static let kk: [String: String] = [
        "p_help": "Анықтама орталығы",
        "p_soglashenie": "Пайдаланушы келісімі",
        "p_oferta": "Жария оферта",
        "p_privacy": "Құпиялылық саясаты",
        "p_oplata": "Төлем және қайтару",
        "p_tarify": "Қызметтер мен бағалар",
        "loading": "Жүктелуде…",
        "fail_t": "Бетті ашу мүмкін болмады",
        "fail_s": "Байланысты тексеріп, қайта көріңіз.",
        "empty_t": "Бет әзірге қолжетімсіз",
        "retry": "Қайталау",
        "close": "Жабу",
        "toc": "Мазмұны",
        "cached": "Байланыс жоқ — сақталған көшірме көрсетілді",
        "support": "Қолдау қызметіне жазу",
        "support_s": "Жауап таппадыңыз ба? Қосымшада жауап береміз.",
        "no_digital": "Бұл мүмкіндік қосымшада қолжетімсіз.",
        "a11y_faq": "Сұрақ. Жауапты ашу үшін екі рет басыңыз",
        "search": "Анықтамадан іздеу",
        "search_clear": "Іздеуді тазарту",
        "nothing_t": "Ештеңе табылмады",
        "nothing_s": "Басқа сөзбен іздеп көріңіз немесе қолдау қызметіне жазыңыз.",
        "all_sections": "Барлық бөлімдер",
        "section_empty": "Бұл бөлімде қосымшада әзірге жауап жоқ. Іздеуді қолданып көріңіз немесе қолдау қызметіне жазыңыз.",
    ]

    private static let en: [String: String] = [
        "p_help": "Help center",
        "p_soglashenie": "User agreement",
        "p_oferta": "Public offer",
        "p_privacy": "Privacy policy",
        "p_oplata": "Payment and refunds",
        "p_tarify": "Services and prices",
        "loading": "Loading…",
        "fail_t": "Couldn't open the page",
        "fail_s": "Check your connection and try again.",
        "empty_t": "This page isn't available yet",
        "retry": "Retry",
        "close": "Close",
        "toc": "Contents",
        "cached": "No connection — showing a saved copy",
        "support": "Contact support",
        "support_s": "Didn't find an answer? We'll reply in the app.",
        "no_digital": "This feature isn't available in the app.",
        "a11y_faq": "Question. Double-tap to show the answer",
        "search": "Search help",
        "search_clear": "Clear search",
        "nothing_t": "Nothing found",
        "nothing_s": "Try another word or contact support.",
        "all_sections": "All sections",
        "section_empty": "This section has no answers in the app yet. Try search or contact support.",
    ]

    private static let ar: [String: String] = [
        "p_help": "مركز المساعدة",
        "p_soglashenie": "اتفاقية المستخدم",
        "p_oferta": "العرض العام",
        "p_privacy": "سياسة الخصوصية",
        "p_oplata": "الدفع والاسترداد",
        "p_tarify": "الخدمات والأسعار",
        "loading": "جارٍ التحميل…",
        "fail_t": "تعذّر فتح الصفحة",
        "fail_s": "تحقّق من الاتصال وحاول مرة أخرى.",
        "empty_t": "هذه الصفحة غير متاحة حالياً",
        "retry": "إعادة المحاولة",
        "close": "إغلاق",
        "toc": "المحتويات",
        "cached": "لا يوجد اتصال — تُعرض نسخة محفوظة",
        "support": "الكتابة إلى الدعم",
        "support_s": "لم تجد إجابة؟ سنرد عليك في التطبيق.",
        "no_digital": "هذه الميزة غير متاحة في التطبيق.",
        "a11y_faq": "سؤال. انقر مرتين لعرض الإجابة",
        "search": "البحث في المساعدة",
        "search_clear": "مسح البحث",
        "nothing_t": "لم يتم العثور على شيء",
        "nothing_s": "جرّب كلمة أخرى أو اكتب إلى الدعم.",
        "all_sections": "كل الأقسام",
        "section_empty": "لا توجد إجابات في هذا القسم في التطبيق بعد. جرّب البحث أو اكتب إلى الدعم.",
    ]
}
