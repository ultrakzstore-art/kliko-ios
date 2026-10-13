import Foundation

/**
 Тексты блока «Свой ИИ в других местах» (OwnAIPlaces.swift, за Config.свойИИНовыеМеста). Подписи мест сервер пришлёт
 сам (own_ai.places[].label); здесь — запасные для известных id и слова блока. Ключи — oaip_*. Языки: ru, kk, en, ar;
 прочие — русский. Ни цен, ни слов об оплате.
 */
enum СвойИИМестаText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Запасная подпись места по id (assist, explain, support, tryon, studio, precheck); незнакомое — nil.
    static func подписьМеста(_ id: String) -> String? {
        let ключ = "oaip_" + id
        guard ru[ключ] != nil else { return nil }
        return т(ключ)
    }

    private static let ru: [String: String] = [
        "oaip_t": "Свой ИИ в других местах",
        "oaip_s": "Включите, где ещё отвечать вашему ИИ. Выключено — там работает Kliko AI.",
        "oaip_na": "Ваш поставщик или модель этого не умеют — здесь работает Kliko AI.",
        "oaip_on": "Включено — здесь ответит ваш ИИ",
        "oaip_off": "Выключено — здесь работает Kliko AI",
        "oaip_keep": "Модерация объявлений всегда работает на Kliko AI — свой ИИ её не заменяет.",
        "oaip_price_own": "Оценка · через ваш ИИ",
        "oaip_assist": "Ассистент в чате по вашим объявлениям",
        "oaip_explain": "Объяснения о товаре",
        "oaip_support": "Ответы ИИ-поддержки",
        "oaip_tryon": "Примерочная одежды",
        "oaip_studio": "ИИ-фоторедактор техники",
        "oaip_precheck": "Предпроверка объявления перед отправкой",
    ]

    private static let kk: [String: String] = [
        "oaip_t": "Өз ЖИ басқа жерлерде",
        "oaip_s": "Сіздің ЖИ тағы қай жерде жауап беретінін қосыңыз. Өшірулі болса — онда Kliko AI жұмыс істейді.",
        "oaip_na": "Жеткізушіңіз немесе модель мұны істей алмайды — мұнда Kliko AI жұмыс істейді.",
        "oaip_on": "Қосылды — мұнда сіздің ЖИ жауап береді",
        "oaip_off": "Өшірілді — мұнда Kliko AI жұмыс істейді",
        "oaip_keep": "Хабарландыруларды модерациялау әрқашан Kliko AI-да жұмыс істейді — өз ЖИ оны алмастырмайды.",
        "oaip_price_own": "Бағалау · сіздің ЖИ арқылы",
        "oaip_assist": "Хабарландыруларыңыз бойынша чаттағы ассистент",
        "oaip_explain": "Тауар туралы түсіндірмелер",
        "oaip_support": "ЖИ-қолдау жауаптары",
        "oaip_tryon": "Киімді киіп көру",
        "oaip_studio": "Техникаға арналған ЖИ-фоторедактор",
        "oaip_precheck": "Жібермес бұрын хабарландыруды алдын ала тексеру",
    ]

    private static let en: [String: String] = [
        "oaip_t": "Your AI in other places",
        "oaip_s": "Choose where else your AI should answer. When off, Kliko AI works there.",
        "oaip_na": "Your provider or model can't do this — Kliko AI works here.",
        "oaip_on": "On — your AI will answer here",
        "oaip_off": "Off — Kliko AI works here",
        "oaip_keep": "Listing moderation always runs on Kliko AI — your AI doesn't replace it.",
        "oaip_price_own": "Estimate · via your AI",
        "oaip_assist": "Assistant in chats on your listings",
        "oaip_explain": "Product explanations",
        "oaip_support": "AI support answers",
        "oaip_tryon": "Clothing fitting room",
        "oaip_studio": "AI photo editor for electronics",
        "oaip_precheck": "Listing pre-check before submitting",
    ]

    private static let ar: [String: String] = [
        "oaip_t": "ذكاؤك الاصطناعي في أماكن أخرى",
        "oaip_s": "اختر أين يجيب ذكاؤك الاصطناعي أيضًا. عند الإيقاف يعمل Kliko AI هناك.",
        "oaip_na": "مزوّدك أو النموذج لا يدعم ذلك — يعمل هنا Kliko AI.",
        "oaip_on": "مفعّل — سيجيب ذكاؤك الاصطناعي هنا",
        "oaip_off": "متوقف — يعمل هنا Kliko AI",
        "oaip_keep": "مراجعة الإعلانات تعمل دائمًا عبر Kliko AI — ولا يحلّ ذكاؤك الاصطناعي محلها.",
        "oaip_price_own": "تقدير · عبر ذكائك الاصطناعي",
        "oaip_assist": "المساعد في محادثات إعلاناتك",
        "oaip_explain": "شرح المنتج",
        "oaip_support": "ردود دعم الذكاء الاصطناعي",
        "oaip_tryon": "غرفة قياس الملابس",
        "oaip_studio": "محرر صور الأجهزة بالذكاء الاصطناعي",
        "oaip_precheck": "فحص الإعلان مسبقًا قبل الإرسال",
    ]
}
