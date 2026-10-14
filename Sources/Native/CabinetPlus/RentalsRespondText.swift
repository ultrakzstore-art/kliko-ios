import Foundation

/**
 Тексты «Моих аренд» про срок ответа владельца и заявки только проверенному владельцу (ultra-site 13.10.2026: «Аренда,
 вторая часть: объявление без верификации, заявка — только проверенному владельцу, ответ за 24 часа»).

 Русские — как у сайта: «Владелец ответит до ЧЧ:ММ, ДД.ММ» / «Ответьте до…», «Владелец не ответил», «Пройдите
 верификацию, чтобы принимать заявки на аренду». Где %@ — время «15:00, 14.10».
 */
enum АрендаОтветText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "respond_renter": "Владелец ответит до %@",
        "respond_owner": "Ответьте до %@",
        "noanswer": "Владелец не ответил",
        "noanswer_owner": "Без ответа",
        "noanswer_s": "Запрос закрылся сам: владелец не ответил за 24 часа. Деньги не списывались.",
        "noanswer_owner_s": "Запрос закрылся сам: на него не ответили за 24 часа.",
        "open_item": "Открыть объявление",
        "verify_t": "Пройдите верификацию, чтобы принимать заявки на аренду",
        "verify_s": "Объявления с арендой видны всем, но заявку с датами площадка примет только после проверки. Пока арендаторы пишут вам в чат.",
        "verify_go": "Пройти верификацию"
    ]

    private static let kk: [String: String] = [
        "respond_renter": "Иесі %@ дейін жауап береді",
        "respond_owner": "%@ дейін жауап беріңіз",
        "noanswer": "Иесі жауап бермеді",
        "noanswer_owner": "Жауапсыз",
        "noanswer_s": "Сұрау өзі жабылды: иесі 24 сағат ішінде жауап бермеді. Ақша алынған жоқ.",
        "noanswer_owner_s": "Сұрау өзі жабылды: оған 24 сағат ішінде жауап берілмеді.",
        "open_item": "Хабарландыруды ашу",
        "verify_t": "Жалға алу өтінімдерін қабылдау үшін верификациядан өтіңіз",
        "verify_s": "Жалға беру хабарландыруларын бәрі көреді, бірақ күндері бар өтінімді алаң тексерістен кейін ғана қабылдайды. Әзірге жалға алушылар сізге чатқа жазады.",
        "verify_go": "Верификациядан өту"
    ]

    private static let en: [String: String] = [
        "respond_renter": "The owner will reply by %@",
        "respond_owner": "Reply by %@",
        "noanswer": "The owner didn't reply",
        "noanswer_owner": "No reply",
        "noanswer_s": "The request closed by itself: the owner didn't reply within 24 hours. No money was charged.",
        "noanswer_owner_s": "The request closed by itself: it wasn't answered within 24 hours.",
        "open_item": "Open the listing",
        "verify_t": "Get verified to accept rental requests",
        "verify_s": "Everyone can see your rental listings, but dated requests are accepted only after verification. Until then, renters message you in the chat.",
        "verify_go": "Get verified"
    ]

    private static let ar: [String: String] = [
        "respond_renter": "سيرد المالك قبل %@",
        "respond_owner": "يرجى الرد قبل %@",
        "noanswer": "لم يرد المالك",
        "noanswer_owner": "دون رد",
        "noanswer_s": "أُغلق الطلب تلقائيًا: لم يرد المالك خلال 24 ساعة. لم يُخصم أي مال.",
        "noanswer_owner_s": "أُغلق الطلب تلقائيًا: لم يُرد عليه خلال 24 ساعة.",
        "open_item": "فتح الإعلان",
        "verify_t": "أكمل التحقق لتتمكن من قبول طلبات الإيجار",
        "verify_s": "يرى الجميع إعلانات الإيجار، لكن طلبات الحجز بالتواريخ تُقبل بعد التحقق فقط. حتى ذلك الحين يراسلك المستأجرون في الدردشة.",
        "verify_go": "إجراء التحقق"
    ]
}
