import Foundation

/**
 Тексты «Ищу» из «Моего» (пачка 83, MyThingsWanted.swift; docs/SERVER_NEW_FOR_MINE.md §16.3.8, §16.6). Ключи iw_*;
 языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык). Строки с %@ идут через
 String(format:). Подписи вещей (iw_tyres…) — то, что стоит после «Ищу»: по-русски в винительном («мужскую обувь»), по-
 казахски значение впереди («205/55 R16 шиналарын іздеймін»).
 */
enum ИщуМоегоText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static func ф(_ ключ: String, _ аргумент: String) -> String {
        String(format: т(ключ), аргумент)
    }

    private static var словарь: [String: String] {
        switch ПримерочнаяText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "iw_head": "Ищу %@",
        "iw_title": "Ищу",
        "iw_hint": "Сохранит поиск и сообщит о новых объявлениях",
        "iw_what": "Что ищете",
        "iw_upto": "До какой цены, ₸",
        "iw_upto_ph": "Любая",
        "iw_cond": "Состояние",
        "iw_any": "Любое",
        "iw_new": "Новое",
        "iw_used": "Б/у",
        "iw_how": "Сохраним поиск «%@» и пришлём уведомление, когда появятся новые объявления.",
        "iw_account": "Если вы вошли в аккаунт, поиск сохранится и в нём — как колокольчик в ленте. Остальное «Моё» остаётся только на этом телефоне.",
        "iw_save": "Сохранить поиск",
        "iw_saved": "Поиск сохранён — сообщим о новом",
        "iw_already": "Такой поиск уже сохранён",
        "iw_look": "Посмотреть, что есть сейчас",
        "iw_tyres": "шины %@",
        "iw_mattress": "матрас %@",
        "iw_bedding": "постельное бельё %@",
        "iw_lamps": "лампы %@",
        "iw_mount": "кронштейн VESA %@",
        "iw_shoes_m": "мужскую обувь %@",
        "iw_shoes_w": "женскую обувь %@",
        "iw_clothes_m": "мужскую одежду %@",
        "iw_clothes_w": "женскую одежду %@",
        "iw_ram": "память %@",
        "iw_ssd": "SSD %@"
    ]

    private static let kk: [String: String] = [
        "iw_head": "%@ іздеймін",
        "iw_title": "Іздеймін",
        "iw_hint": "Іздеуді сақтап, жаңа хабарландырулар туралы хабарлайды",
        "iw_what": "Не іздейсіз",
        "iw_upto": "Қандай бағаға дейін, ₸",
        "iw_upto_ph": "Кез келген",
        "iw_cond": "Күйі",
        "iw_any": "Кез келген",
        "iw_new": "Жаңа",
        "iw_used": "Қолданылған",
        "iw_how": "«%@» іздеуін сақтап, жаңа хабарландырулар шыққанда хабарлама жібереміз.",
        "iw_account": "Аккаунтқа кірген болсаңыз, іздеу онда да сақталады — лентадағы қоңырау сияқты. Қалған «Менікі» тек осы телефонда қалады.",
        "iw_save": "Іздеуді сақтау",
        "iw_saved": "Іздеу сақталды — жаңасы туралы хабарлаймыз",
        "iw_already": "Мұндай іздеу бұрыннан сақталған",
        "iw_look": "Қазір барын көру",
        "iw_tyres": "%@ шиналарын",
        "iw_mattress": "%@ матрасын",
        "iw_bedding": "%@ төсек жаймасын",
        "iw_lamps": "%@ шамдарын",
        "iw_mount": "VESA %@ кронштейнін",
        "iw_shoes_m": "%@ ерлер аяқ киімін",
        "iw_shoes_w": "%@ әйелдер аяқ киімін",
        "iw_clothes_m": "%@ ерлер киімін",
        "iw_clothes_w": "%@ әйелдер киімін",
        "iw_ram": "%@ жадын",
        "iw_ssd": "%@ SSD"
    ]

    private static let en: [String: String] = [
        "iw_head": "Looking for %@",
        "iw_title": "Looking for",
        "iw_hint": "Saves a search and tells you about new listings",
        "iw_what": "What are you looking for",
        "iw_upto": "Up to price, ₸",
        "iw_upto_ph": "Any",
        "iw_cond": "Condition",
        "iw_any": "Any",
        "iw_new": "New",
        "iw_used": "Used",
        "iw_how": "We'll save the search “%@” and notify you when new listings appear.",
        "iw_account": "If you're signed in, the search is saved to your account too — like the bell in the feed. The rest of My Things stays on this phone only.",
        "iw_save": "Save search",
        "iw_saved": "Search saved — we'll let you know",
        "iw_already": "This search is already saved",
        "iw_look": "See what's there now",
        "iw_tyres": "tires %@",
        "iw_mattress": "a mattress %@",
        "iw_bedding": "bedding %@",
        "iw_lamps": "bulbs %@",
        "iw_mount": "a VESA %@ mount",
        "iw_shoes_m": "men's shoes %@",
        "iw_shoes_w": "women's shoes %@",
        "iw_clothes_m": "men's clothing %@",
        "iw_clothes_w": "women's clothing %@",
        "iw_ram": "memory %@",
        "iw_ssd": "an SSD %@"
    ]

    private static let ar: [String: String] = [
        "iw_head": "أبحث عن %@",
        "iw_title": "أبحث عن",
        "iw_hint": "يحفظ البحث ويُعلمك بالإعلانات الجديدة",
        "iw_what": "ما الذي تبحث عنه",
        "iw_upto": "حتى سعر، ₸",
        "iw_upto_ph": "أي سعر",
        "iw_cond": "الحالة",
        "iw_any": "أي حالة",
        "iw_new": "جديد",
        "iw_used": "مستعمل",
        "iw_how": "سنحفظ البحث «%@» ونرسل إشعارًا عند ظهور إعلانات جديدة.",
        "iw_account": "إذا سجّلت الدخول، فسيُحفظ البحث في حسابك أيضًا — مثل الجرس في الخلاصة. وتبقى بقية «أشيائي» على هذا الهاتف فقط.",
        "iw_save": "حفظ البحث",
        "iw_saved": "تم حفظ البحث — سنُعلمك بالجديد",
        "iw_already": "هذا البحث محفوظ بالفعل",
        "iw_look": "عرض المتوفر الآن",
        "iw_tyres": "إطارات %@",
        "iw_mattress": "مرتبة %@",
        "iw_bedding": "مفارش سرير %@",
        "iw_lamps": "مصابيح %@",
        "iw_mount": "حامل VESA %@",
        "iw_shoes_m": "أحذية رجالية %@",
        "iw_shoes_w": "أحذية نسائية %@",
        "iw_clothes_m": "ملابس رجالية %@",
        "iw_clothes_w": "ملابس نسائية %@",
        "iw_ram": "ذاكرة %@",
        "iw_ssd": "SSD %@"
    ]
}
