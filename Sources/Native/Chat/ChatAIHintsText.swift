import Foundation

/// Тексты Kliko AI-подсказок в переписке (ChatAIHints.swift) на языке телефона (kk/ru/en/ar) — тем же способом, что
/// ChatText и ChatComfortText.
///
/// Слова сайта: «Kliko AI подбирает ответы…» и «Kliko AI-подсказки» — _dmTplFetchAi (js/cabinet.js), «Не удалось —
/// попробуйте ещё раз» — mkChatCallSeller, «Kliko AI временно недоступен» — ai_off_message (inc/flags.php). Образец —
/// настоящий шаблон сайта: вопрос покупателя «Здравствуйте! Ещё актуально?» (hello_q) и три ответа продавца из ACW_SUGG
/// (интент «актуальн», inc/active_chat_pin.php). Остальное — пояснения приложения о том, как работает кнопка «✨».
enum ИИПодсказкиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "btn": "Kliko AI-подсказки ответа", "loading": "Kliko AI подбирает ответы…", "head": "Kliko AI-подсказки",
            "failed": "Не удалось — попробуйте ещё раз", "hide": "Скрыть", "close": "Закрыть",
            "chip_hint": "Вставит текст в поле ввода, не отправляя",
            "intro_t": "Kliko AI подскажет ответ",
            "intro_s": "Нажмите ✨ у поля ввода — Kliko AI прочитает переписку и предложит 3 коротких ответа.",
            "how": "Как это работает",
            "t_intro": "Kliko AI-подсказки", "t_off": "Kliko AI сейчас недоступен", "t_limit": "Лимит Kliko AI исчерпан",
            "s_intro": "Kliko AI читает последние сообщения и предлагает 3 коротких ответа от вашего имени.",
            "s_empty": "Подсказки появятся, когда в переписке будут сообщения. Вот как это выглядит:",
            "s_off": "Kliko AI временно недоступен — попробуйте позже. Вот как работают подсказки:",
            "s_limit": "Подсказки на сегодня закончились — новые будут завтра. Вот как они работают:",
            "sample": "Образец", "sample_who": "Покупатель", "sample_peer": "Здравствуйте! Ещё актуально?",
            "sample_1": "Да, ещё в наличии", "sample_2": "Актуально, можно брать",
            "sample_3": "Да, продаю. Когда удобно посмотреть?",
            "how_1": "Нажмите ✨ рядом с полем ввода.",
            "how_2": "Kliko AI прочитает последние сообщения и предложит 3 варианта ответа.",
            "how_3": "Нажмите на вариант — он встанет в поле. Поправьте и отправьте сами.",
            "how_note": "Без вас ничего не отправляется.",
            "buy": "Подключить Kliko AI", "ok": "Понятно"
        ],
        "kk": [
            "btn": "Kliko AI жауап кеңестері", "loading": "Kliko AI жауаптарды іріктеуде…", "head": "Kliko AI кеңестері",
            "failed": "Болмады — қайталап көріңіз", "hide": "Жасыру", "close": "Жабу",
            "chip_hint": "Мәтінді жібермей, енгізу өрісіне қояды",
            "intro_t": "Kliko AI жауап ұсынады",
            "intro_s": "Енгізу өрісіндегі ✨ батырмасын басыңыз — Kliko AI хат алмасуды оқып, 3 қысқа жауап ұсынады.",
            "how": "Бұл қалай жұмыс істейді",
            "t_intro": "Kliko AI кеңестері", "t_off": "Kliko AI қазір қолжетімсіз", "t_limit": "Kliko AI лимиті таусылды",
            "s_intro": "Kliko AI соңғы хабарламаларды оқып, сіздің атыңыздан 3 қысқа жауап ұсынады.",
            "s_empty": "Хат алмасуда хабарламалар болғанда кеңестер шығады. Ол былай көрінеді:",
            "s_off": "Kliko AI уақытша қолжетімсіз — кейінірек көріңіз. Кеңестер былай жұмыс істейді:",
            "s_limit": "Бүгінгі кеңестер таусылды — жаңалары ертең болады. Олар былай жұмыс істейді:",
            "sample": "Үлгі", "sample_who": "Сатып алушы", "sample_peer": "Сәлеметсіз бе! Әлі өзекті ме?",
            "sample_1": "Иә, әлі бар", "sample_2": "Өзекті, алуға болады",
            "sample_3": "Иә, сатамын. Қашан көруге ыңғайлы?",
            "how_1": "Енгізу өрісінің жанындағы ✨ батырмасын басыңыз.",
            "how_2": "Kliko AI соңғы хабарламаларды оқып, 3 жауап нұсқасын ұсынады.",
            "how_3": "Нұсқаны басыңыз — ол өріске қойылады. Түзетіп, өзіңіз жіберіңіз.",
            "how_note": "Сізсіз ештеңе жіберілмейді.",
            "buy": "Kliko AI қосу", "ok": "Түсінікті"
        ],
        "en": [
            "btn": "Kliko AI reply suggestions", "loading": "Kliko AI is picking replies…", "head": "Kliko AI suggestions",
            "failed": "Didn't work — please try again", "hide": "Hide", "close": "Close",
            "chip_hint": "Puts the text into the message field without sending it",
            "intro_t": "Kliko AI can suggest a reply",
            "intro_s": "Tap ✨ in the message field — Kliko AI reads the conversation and suggests 3 short replies.",
            "how": "How it works",
            "t_intro": "Kliko AI suggestions", "t_off": "Kliko AI is unavailable right now",
            "t_limit": "Kliko AI limit reached",
            "s_intro": "Kliko AI reads the latest messages and suggests 3 short replies on your behalf.",
            "s_empty": "Suggestions appear once the conversation has messages. Here's what it looks like:",
            "s_off": "Kliko AI is temporarily unavailable — please try later. Here's how suggestions work:",
            "s_limit": "You've used today's suggestions — new ones tomorrow. Here's how they work:",
            "sample": "Example", "sample_who": "Buyer", "sample_peer": "Hello! Is this still available?",
            "sample_1": "Yes, still available", "sample_2": "Available, you can take it",
            "sample_3": "Yes, I'm selling. When can you come see it?",
            "how_1": "Tap ✨ next to the message field.",
            "how_2": "Kliko AI reads the latest messages and suggests 3 replies.",
            "how_3": "Tap a reply — it goes into the field. Edit it and send it yourself.",
            "how_note": "Nothing is sent without you.",
            "buy": "Get Kliko AI", "ok": "Got it"
        ],
        "ar": [
            "btn": "اقتراحات الرد من Kliko AI", "loading": "يختار Kliko AI الردود…", "head": "اقتراحات Kliko AI",
            "failed": "لم ينجح — حاول مرة أخرى", "hide": "إخفاء", "close": "إغلاق",
            "chip_hint": "يضع النص في حقل الرسالة دون إرساله",
            "intro_t": "يمكن لـ Kliko AI اقتراح رد",
            "intro_s": "اضغط ✨ في حقل الرسالة — يقرأ Kliko AI المحادثة ويقترح 3 ردود قصيرة.",
            "how": "كيف يعمل",
            "t_intro": "اقتراحات Kliko AI", "t_off": "Kliko AI غير متاح الآن", "t_limit": "تم استنفاد حد Kliko AI",
            "s_intro": "يقرأ Kliko AI آخر الرسائل ويقترح 3 ردود قصيرة باسمك.",
            "s_empty": "تظهر الاقتراحات عندما تحتوي المحادثة على رسائل. هكذا تبدو:",
            "s_off": "Kliko AI غير متاح مؤقتًا — حاول لاحقًا. هكذا تعمل الاقتراحات:",
            "s_limit": "انتهت اقتراحات اليوم — اقتراحات جديدة غدًا. هكذا تعمل:",
            "sample": "مثال", "sample_who": "المشتري", "sample_peer": "مرحبًا! هل ما زال متاحًا؟",
            "sample_1": "نعم، ما زال متوفرًا", "sample_2": "متاح، يمكنك أخذه",
            "sample_3": "نعم، أبيعه. متى يناسبك أن تراه؟",
            "how_1": "اضغط ✨ بجانب حقل الرسالة.",
            "how_2": "يقرأ Kliko AI آخر الرسائل ويقترح 3 ردود.",
            "how_3": "اضغط على رد — يظهر في الحقل. عدّله وأرسله بنفسك.",
            "how_note": "لا يُرسل شيء بدونك.",
            "buy": "تفعيل Kliko AI", "ok": "حسنًا"
        ]
    ]
}
