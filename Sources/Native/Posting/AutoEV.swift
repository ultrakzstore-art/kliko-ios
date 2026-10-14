import Foundation

/**
 ЭЛЕКТРОМОБИЛЬ ПО МАРКЕ И МОДЕЛИ (владелец 14.10.2026: «тип двигателя тоже сайт знает — например, Тесла это электрокар;
 такие мелочи нужно упрощать для юзеров»).

 Догадка мастера авто, когда у поколения нет gens[].fuel с сайта: распознали — топливо «Электро» отмечено заранее, блок
 объёма прячется. Данные сервера всегда важнее: при gens[].fuel догадку не спрашивают. Поэтому только явные случаи:
 марки, у которых все модели электро (Tesla, Lucid, Rivian, NIO; у Polestar и Zeekr — кроме гибридов), и электро-модели
 остальных по образцам. Марки со смешанной линейкой (BYD, Li Auto, Voyah, XPeng) целиком не берём — только модели.
 Сравнение без регистра, пробелов, точек и дефисов: «ID.4», «ID 4» и «id4» — одно и то же.
 */
enum ЭлектроАвто {
    static func электро(марка: String, модель: String) -> Bool {
        let м = сжать(марка)
        let н = сжать(модель)
        guard !м.isEmpty else { return false }
        /* Чистые электро-марки; в значении — их модели-гибриды (Polestar 1, Zeekr 9X). */
        if let гибриды = Self.марки[м] { return !гибриды.contains(н) }
        guard !н.isEmpty else { return false }
        /* Гибриды с розеткой и с запасом хода — не электро, хоть в названии и есть «EV» или образец модели: «MX-30
           R-EV», «Megane E-Tech Plug-in», «Song Plus DM-i», «Li L9 EREV». «REV» и «EREV» — только отдельным словом:
           сжатое «Explorer EV» («explorerev») их тоже содержит. Ни один электро-образец ниже этих кусков не содержит. */
        let части = слова(модель)
        if Self.признакиГибрида.contains(where: { н.contains($0) }) || части.contains("rev") || части.contains("erev")
            || zip(части, части.dropFirst()).contains(where: { пара in пара.0 == "r" && пара.1 == "ev" }) {
            return false
        }
        /* Отдельное слово в названии: «Niro EV», «Kona Electric», «Han EV», «Blazer EV». */
        if части.contains(where: { $0 == "ev" || $0 == "electric" || $0 == "bev" }) { return true }
        if н.contains("pureelectric") { return true }
        return поМарке(м, н)
    }

    /// Куски сжатого названия у гибридов с розеткой («PHEV», «Plug-in», «DM-i», «DM-p»).
    private static let признакиГибрида = ["phev", "hybrid", "plugin", "dmi", "dmp"]

    /// Чистые электро-марки → их модели не на электричестве.
    private static let марки: [String: Set<String>] = [
        "tesla": [], "lucid": [], "rivian": [], "nio": [], "onvo": [],
        "polestar": ["1", "polestar1"], "zeekr": ["9x"], "aion": [], "gacaion": []
    ]

    /// Модели по образцам — у каждой марки свои (у Mercedes «E 200» — не электро, у Peugeot «e-208» — электро).
    private static func поМарке(_ м: String, _ н: String) -> Bool {
        switch м {
        case "nissan":
            return начало(н, ["leaf", "ariya", "sakura"])
        case "hyundai":
            return цифраПосле(н, "ioniq") || начало(н, ["ioniqelectric", "konaelectric"])
        case "kia":
            return цифраПосле(н, "ev") || начало(н, ["niroev", "eniro", "soulev", "esoul"])
        case "volkswagen", "vw":
            return цифраПосле(н, "id") || начало(н, ["idbuzz", "egolf", "eup", "ebora", "elavida"])
        case "bmw":
            return начало(н, ["ix", "i3", "i4", "i5", "i7"])
        case "mercedesbenz", "mercedes":
            return начало(н, ["eq"])
        case "audi":
            return начало(н, ["etron", "q4etron", "q4sportbacketron", "q6etron", "q6sportbacketron", "q8etron",
                               "q8sportbacketron", "sq6etron", "sq8etron", "rsetron"])
        case "porsche":
            return начало(н, ["taycan", "macanelectric", "macanev"])
        case "chevrolet":
            return начало(н, ["bolt", "menlo"])
        case "jaguar":
            return начало(н, ["ipace"])
        case "byd":
            return н == "seal" || начало(н, ["hanev", "dolphin", "atto", "yuanplus", "yuanpro", "yuanup", "songplusev",
                                              "seagull", "e1", "e2", "e3", "e5", "e6", "tangev", "qinplusev"])
        case "lexus":
            return начало(н, ["rz", "ux300e"])
        case "toyota":
            return начало(н, ["bz"])
        case "honda":
            return н == "e" || начало(н, ["e:n", "ens1", "enp1"])
        case "mazda":
            return начало(н, ["mx30"])
        case "renault":
            return начало(н, ["zoe", "meganeetech", "scenicetech", "twizy"])
        case "peugeot":
            return начало(н, ["e208", "e2008", "e308", "e3008", "e5008", "epartner", "erifter"])
        case "fiat":
            return начало(н, ["500e", "600e"])
        case "mini":
            /* «Cooper SE Countryman ALL4» (2017–2023) — гибрид с розеткой. */
            return (начало(н, ["cooperse"]) && !н.contains("countryman")) || начало(н, ["electric", "aceman"])
        case "volvo":
            /* «XC40 Recharge T5» и «Recharge Plug-in» — гибриды; «XC40 Recharge», «Twin» и «Pure Electric» — электро. */
            return цифраПосле(н, "ex") || (начало(н, ["ec40", "c40", "xc40recharge"])
                && !начало(н, ["xc40recharget4", "xc40recharget5", "xc40rechargeplugin"]))
        case "skoda", "škoda":
            return начало(н, ["enyaq", "elroq"])
        case "cadillac":
            return начало(н, ["lyriq", "optiq", "celestiq"])
        case "ford":
            return н.contains("mache") || начало(н, ["f150lightning"])
        case "hongqi":
            return начало(н, ["ehs9", "eqm5", "eh7", "ehs7"])
        case "changan":
            return начало(н, ["lumin"])
        case "mitsubishi":
            return начало(н, ["imiev"])
        case "smart":
            return начало(н, ["#", "fortwoeq", "forfoureq"])
        case "jac":
            return начало(н, ["iev", "ejs", "ej7"])
        case "xpeng":
            return начало(н, ["p7", "p5", "g3", "g6", "g9", "mona"])
        case "opel":
            return начало(н, ["corsae", "mokkae", "amperae"])
        default:
            return false
        }
    }

    // MARK: Сравнение

    /// «Mercedes-Benz» → «mercedesbenz», «ID.4» → «id4»: без регистра, пробелов, точек, дефисов и подчёркиваний.
    private static func сжать(_ текст: String) -> String {
        String(текст.lowercased().filter { !" -._/".contains($0) })
    }

    /// Слова названия без регистра: «Niro EV» → [«niro», «ev»].
    private static func слова(_ текст: String) -> [String] {
        текст.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" || $0 == "(" || $0 == ")" })
            .map(String.init)
    }

    private static func начало(_ н: String, _ образцы: [String]) -> Bool {
        образцы.contains { н.hasPrefix($0) }
    }

    /// «ioniq5», «ev6», «id4», «ex30»: образец и сразу цифра.
    private static func цифраПосле(_ н: String, _ образец: String) -> Bool {
        guard н.hasPrefix(образец) else { return false }
        return н.dropFirst(образец.count).first?.isNumber ?? false
    }
}
