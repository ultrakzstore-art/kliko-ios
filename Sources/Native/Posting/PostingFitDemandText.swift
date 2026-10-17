import Foundation

/**
 ТЕКСТЫ «ПОДОЙДЁТ N ЛЮДЯМ» И «СООБЩИТЬ ИМ» (пачка 83; docs/SERVER_NEW_FOR_MINE.md §16.6) — ru / kk / en / ar.

 Ключи fd_* — из договора; fd_line_kz — своя строка для ячейки, у которой в городе меньше порога, а по Казахстану —
 больше (n пусто, n_kz есть). В середине фразы подпись ячейки (label) — со строчной в ru и kk, если это обычное слово
 («Шины 205/55 R16» → «шины …»), а не размер или сокращение («M (INT)», «EU 43», «VESA …» — как есть).
 Город в ru — в предложном падеже: сервер отдаёт только областные центры и города республиканского значения (§6.2),
 их формы — ниже; незнакомый город — «в г. <город>».
 */
enum СпросПодачиText {
    /// Язык строк и поле lang запроса fit_demand: первый язык телефона; незнакомый — русский.
    static var язык: String {
        let код = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        return ["ru", "kk", "en", "ar"].contains(код) ? код : "ru"
    }

    static func т(_ ключ: String) -> String {
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// «у них машина под …», «у них размер …», «у них …» — по for ячейки (car · size · phone · laptop · std:<семья>).
    static func причина(_ чья: String, подпись: String) -> String {
        let ключ: String
        switch чья {
        case "car": ключ = "fd_why_car"
        case "size": ключ = "fd_why_size"
        default: ключ = "fd_why_std"
        }
        return т(ключ).replacingOccurrences(of: "{label}", with: вСерединеФразы(подпись))
    }

    /// «Подойдёт 40+ людям в Астане: у них машина под …».
    static func строкаГорода(_ число: String, город: String, почему: String) -> String {
        let место: String = язык == "ru" ? вПредложном(город) : город
        return т("fd_line")
            .replacingOccurrences(of: "{n}", with: число)
            .replacingOccurrences(of: "{city}", with: место)
            .replacingOccurrences(of: "{why}", with: почему)
    }

    /// «Подойдёт 350+ людям в Казахстане: …» — в городе меньше порога.
    static func строкаСтраны(_ число: String, почему: String) -> String {
        т("fd_line_kz")
            .replacingOccurrences(of: "{n}", with: число)
            .replacingOccurrences(of: "{why}", with: почему)
    }

    /// «Ищут сейчас: 3».
    static func ищут(_ число: Int) -> String {
        т("fd_wanted").replacingOccurrences(of: "{n}", with: String(число))
    }

    /// Подпись со строчной в ru и kk, если первое слово обычное: заглавная, за ней строчная буква.
    static func вСерединеФразы(_ подпись: String) -> String {
        guard язык == "ru" || язык == "kk", let первая = подпись.first, первая.isUppercase else { return подпись }
        let хвост = подпись.dropFirst()
        guard let вторая = хвост.first, вторая.isLetter, вторая.isLowercase else { return подпись }
        return String(первая).lowercased() + String(хвост)
    }

    /// Город в предложном падеже (ru): «Астана» → «Астане»; незнакомый — «г. Сатпаев».
    static func вПредложном(_ город: String) -> String {
        let чистый = город.trimmingCharacters(in: .whitespacesAndNewlines)
        if let форма = городаВПредложном[чистый] { return форма }
        return чистый.isEmpty ? чистый : "г. " + чистый
    }

    private static let городаВПредложном: [String: String] = [
        "Астана": "Астане", "Нур-Султан": "Нур-Султане", "Алматы": "Алматы", "Шымкент": "Шымкенте",
        "Актау": "Актау", "Актобе": "Актобе", "Атырау": "Атырау", "Жезказган": "Жезказгане",
        "Караганда": "Караганде", "Кокшетау": "Кокшетау", "Конаев": "Конаеве", "Костанай": "Костанае",
        "Кызылорда": "Кызылорде", "Павлодар": "Павлодаре", "Петропавловск": "Петропавловске", "Семей": "Семее",
        "Талдыкорган": "Талдыкоргане", "Тараз": "Таразе", "Туркестан": "Туркестане", "Уральск": "Уральске",
        "Усть-Каменогорск": "Усть-Каменогорске", "Экибастуз": "Экибастузе", "Темиртау": "Темиртау",
        "Рудный": "Рудном"
    ]

    private static let ru: [String: String] = [
        "fd_line": "Подойдёт {n} людям в {city}: {why}",
        "fd_line_kz": "Подойдёт {n} людям в Казахстане: {why}",
        "fd_why_car": "у них машина под {label}",
        "fd_why_size": "у них размер {label}",
        "fd_why_std": "у них {label}",
        "fd_wanted": "Ищут сейчас: {n}",
        "fd_notify": "Сообщить им",
        "fd_notify_sub": "После публикации Kliko сам сообщит тем, кто ждёт такое, — вы не узнаете, кому",
        "fd_ask": "Узнать, скольким подойдёт",
        "fd_ask_sub": "Значения вещи из «Моего» уйдут на сервер только по этой кнопке"
    ]

    private static let kk: [String: String] = [
        "fd_line": "{city}: {n} адамға сәйкес келеді — {why}",
        "fd_line_kz": "Қазақстанда {n} адамға сәйкес келеді — {why}",
        "fd_why_car": "көліктеріне {label} келеді",
        "fd_why_size": "өлшемдері — {label}",
        "fd_why_std": "оларда {label} бар",
        "fd_wanted": "Қазір іздеп жүр: {n}",
        "fd_notify": "Оларға хабарлау",
        "fd_notify_sub": "Жарияланғаннан кейін Kliko мұны күтіп жүргендерге өзі хабарлайды — кімге екенін білмейсіз",
        "fd_ask": "Қанша адамға сәйкес келетінін білу",
        "fd_ask_sub": "«Менікі» бөліміндегі заттың мәндері серверге тек осы түйме арқылы жіберіледі"
    ]

    private static let en: [String: String] = [
        "fd_line": "Fits {n} people in {city}: {why}",
        "fd_line_kz": "Fits {n} people in Kazakhstan: {why}",
        "fd_why_car": "their cars take {label}",
        "fd_why_size": "they wear {label}",
        "fd_why_std": "they have {label}",
        "fd_wanted": "Looking now: {n}",
        "fd_notify": "Notify them",
        "fd_notify_sub": "After publishing, Kliko will tell people waiting for this — you won’t know who",
        "fd_ask": "See how many people it fits",
        "fd_ask_sub": "The item’s details from My Things are sent to the server only when you tap this"
    ]

    private static let ar: [String: String] = [
        "fd_line": "يناسب {n} شخصًا في {city}: {why}",
        "fd_line_kz": "يناسب {n} شخصًا في كازاخستان: {why}",
        "fd_why_car": "سياراتهم تناسب {label}",
        "fd_why_size": "مقاسهم {label}",
        "fd_why_std": "لديهم {label}",
        "fd_wanted": "يبحث الآن: {n}",
        "fd_notify": "أبلِغهم",
        "fd_notify_sub": "بعد النشر سيُبلغ Kliko من ينتظر هذا — لن تعرف من هم",
        "fd_ask": "اعرف لكم شخصًا يناسب",
        "fd_ask_sub": "لا تُرسَل تفاصيل الغرض من «أشيائي» إلى الخادم إلا عند الضغط هنا"
    ]
}
