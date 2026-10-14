import Foundation

/**
 Тексты «Свой ИИ», волна 14.10.2026 (ultra-site, «Свой ИИ» во всех местах): вход через OpenRouter из приложения
 (OwnAIOpenRouter.swift), коды отказа relink и day (OwnAIModel.swift). Ключи — oair_*. Языки: ru, kk, en, ar; прочие —
 русский. Бренд OpenRouter не переводится. Ни цен, ни слов об оплате и пробном периоде (покупка — только App Store).
 */
enum СвойИИВходText {
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

    private static let ru: [String: String] = [
        "oair_or": "Войти через OpenRouter",
        "oair_or_s": "Без копирования ключа: войдите в OpenRouter, и ключ подключится сам.",
        "oair_or_or": "или",
        "oair_ok": "Свой ИИ подключён через OpenRouter",
        "oair_fail": "Не удалось войти через OpenRouter. Попробуйте ещё раз или вставьте ключ.",
        "oair_old": "Вход через OpenRouter сейчас недоступен — вставьте ключ вручную.",
        "oair_relink": "Подключите свой ИИ заново: сохранённый ключ больше не читается.",
        "oair_relink_btn": "Подключить заново",
        "oair_day": "Свой ИИ на сегодня исчерпал суточный лимит запросов — попробуйте завтра.",
    ]

    private static let kk: [String: String] = [
        "oair_or": "OpenRouter арқылы кіру",
        "oair_or_s": "Кілтті көшірмей-ақ: OpenRouter-ге кіріңіз, кілт өзі қосылады.",
        "oair_or_or": "немесе",
        "oair_ok": "Өз ЖИ OpenRouter арқылы қосылды",
        "oair_fail": "OpenRouter арқылы кіру мүмкін болмады. Қайталап көріңіз немесе кілтті қойыңыз.",
        "oair_old": "OpenRouter арқылы кіру қазір қолжетімсіз — кілтті қолмен қойыңыз.",
        "oair_relink": "Өз ЖИ-ді қайта қосыңыз: сақталған кілт енді оқылмайды.",
        "oair_relink_btn": "Қайта қосу",
        "oair_day": "Өз ЖИ бүгінгі тәуліктік сұраныс шегіне жетті — ертең қайталап көріңіз.",
    ]

    private static let en: [String: String] = [
        "oair_or": "Sign in with OpenRouter",
        "oair_or_s": "No key copying: sign in to OpenRouter and the key connects automatically.",
        "oair_or_or": "or",
        "oair_ok": "Own AI connected via OpenRouter",
        "oair_fail": "Couldn't sign in with OpenRouter. Try again or paste a key.",
        "oair_old": "Sign-in with OpenRouter is unavailable right now — paste the key manually.",
        "oair_relink": "Reconnect your own AI: the saved key can no longer be read.",
        "oair_relink_btn": "Reconnect",
        "oair_day": "Your own AI has reached today's request limit — try again tomorrow.",
    ]

    private static let ar: [String: String] = [
        "oair_or": "تسجيل الدخول عبر OpenRouter",
        "oair_or_s": "دون نسخ المفتاح: سجّل الدخول إلى OpenRouter وسيُربط المفتاح تلقائيًا.",
        "oair_or_or": "أو",
        "oair_ok": "تم ربط ذكائك الاصطناعي عبر OpenRouter",
        "oair_fail": "تعذّر تسجيل الدخول عبر OpenRouter. حاول مرة أخرى أو الصق المفتاح.",
        "oair_old": "تسجيل الدخول عبر OpenRouter غير متاح الآن — الصق المفتاح يدويًا.",
        "oair_relink": "أعد ربط ذكائك الاصطناعي: لم يعد بالإمكان قراءة المفتاح المحفوظ.",
        "oair_relink_btn": "إعادة الربط",
        "oair_day": "بلغ ذكاؤك الاصطناعي حدّ الطلبات اليومي — حاول غدًا.",
    ]
}
