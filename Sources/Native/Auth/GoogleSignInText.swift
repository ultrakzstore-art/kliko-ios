import Foundation

/**
 Тексты входа через Google и вставки номера на экране входа (kk/ru/en/ar) — свой словарь, чтобы не задевать ВходText.
 Общие фразы входа («Номер телефона», «Нет соединения», «Ошибка входа», «Закрыть», согласие) берутся из ВходText.
 */
enum ВходGoogleText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "g_continue": "Продолжить с Google",
        "g_soon": "Вход через Google скоро заработает — пока войдите по номеру или через Apple",
        "g_err": "Не удалось войти через Google — попробуйте ещё раз",
        "g_phone_t": "Укажите номер",
        "g_phone_s": "Остался один шаг: номер нужен для объявлений, сделок и связи с покупателями. Его можно скрыть в кабинете.",
        "g_as": "Аккаунт Google: %@",
        "g_next": "Продолжить",
        "g_code": "Код из SMS",
        "g_code_sent": "Мы отправили код на этот номер — iOS подставит его сама.",
        "g_code_need": "Введите код из SMS",
        "g_code_bad": "Код не подошёл — проверьте и введите ещё раз",
        "g_expired": "Время вышло — войдите через Google ещё раз",
        "paste_no_phone": "В буфере нет номера телефона"
    ]

    private static let kk: [String: String] = [
        "g_continue": "Google арқылы жалғастыру",
        "g_soon": "Google арқылы кіру жақында іске қосылады — әзірге нөмір арқылы немесе Apple арқылы кіріңіз",
        "g_err": "Google арқылы кіру мүмкін болмады — қайталап көріңіз",
        "g_phone_t": "Нөміріңізді көрсетіңіз",
        "g_phone_s": "Бір қадам қалды: нөмір хабарландырулар, мәмілелер және сатып алушылармен байланыс үшін қажет. Оны кабинетте жасыруға болады.",
        "g_as": "Google аккаунты: %@",
        "g_next": "Жалғастыру",
        "g_code": "SMS коды",
        "g_code_sent": "Осы нөмірге код жібердік — iOS оны өзі қояды.",
        "g_code_need": "SMS кодын енгізіңіз",
        "g_code_bad": "Код сәйкес келмеді — тексеріп, қайта енгізіңіз",
        "g_expired": "Уақыт өтіп кетті — Google арқылы қайта кіріңіз",
        "paste_no_phone": "Буферде телефон нөмірі жоқ"
    ]

    private static let en: [String: String] = [
        "g_continue": "Continue with Google",
        "g_soon": "Sign-in with Google is coming soon — for now, sign in with your number or with Apple",
        "g_err": "Couldn't sign in with Google — please try again",
        "g_phone_t": "Add your number",
        "g_phone_s": "One more step: a phone number is needed for listings, deals and contact with buyers. You can hide it in your account.",
        "g_as": "Google account: %@",
        "g_next": "Continue",
        "g_code": "SMS code",
        "g_code_sent": "We've sent a code to this number — iOS will fill it in for you.",
        "g_code_need": "Enter the SMS code",
        "g_code_bad": "The code didn't match — check it and try again",
        "g_expired": "Time ran out — sign in with Google again",
        "paste_no_phone": "There's no phone number on the clipboard"
    ]

    private static let ar: [String: String] = [
        "g_continue": "المتابعة باستخدام Google",
        "g_soon": "سيتوفر تسجيل الدخول عبر Google قريبًا — سجّل الدخول الآن برقمك أو عبر Apple",
        "g_err": "تعذّر تسجيل الدخول عبر Google — حاول مرة أخرى",
        "g_phone_t": "أدخل رقمك",
        "g_phone_s": "بقيت خطوة واحدة: الرقم مطلوب للإعلانات والصفقات والتواصل مع المشترين. يمكنك إخفاؤه في الحساب.",
        "g_as": "حساب Google: %@",
        "g_next": "متابعة",
        "g_code": "رمز SMS",
        "g_code_sent": "أرسلنا رمزًا إلى هذا الرقم — سيملؤه iOS تلقائيًا.",
        "g_code_need": "أدخل رمز SMS",
        "g_code_bad": "الرمز غير صحيح — تحقّق منه وأدخله مرة أخرى",
        "g_expired": "انتهى الوقت — سجّل الدخول عبر Google مرة أخرى",
        "paste_no_phone": "لا يوجد رقم هاتف في الحافظة"
    ]
}
