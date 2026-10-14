import Foundation

/**
 СХЕМА ПОДАЧИ — НОВЫЕ ПРАВИЛА САЙТА 13–14.10.2026 (ultra-site, «Изменения сайта, важные для приложения iOS»).

 В rules ответа api/app_post_schema.php (СхемаПодачи.разобрать):
   · title_cat — раздел по названию с сервера: {url:"api/cat_guess.php", param:"q", min_len:3, auto:"high"};
     сайт: «раздел по названию ставит только api/cat_guess.php», локальный разбор больше не угадывает;
   · brand_optional_cats — разделы с поддеревьями, где марка по желанию (аксессуары, игры, мелочи электроники); у них
     и brand_req раздела уже false — список нужен на случай старой записи раздела;
   · fit — «Замеры вещи» (рубильник fit_help): {on:false} — блока нет; {on:true, field, unit, cats, keys, ask, range,
     labels, kinds, title, hint, how} — свёрнутый необязательный блок в форме, поле fit в submit и edit_item.
 Нет ключа (старый сервер) — всё как было: подбор раздела по названию свой, марка по brand_req, блока замеров нет.
 */

/// rules.title_cat: куда спрашивать раздел по названию.
struct ПравилоРазделаПоНазванию: Equatable {
    /// Путь от корня сайта без «/» в начале (api/cat_guess.php).
    let адрес: String
    let параметр: String
    let минимум: Int
    /// Уверенность, с которой раздел ставится сам (high).
    let сам: String

    /// Только свой путь api/… — чужой адрес из ответа не открываем.
    static func из(_ сырое: Any?) -> ПравилоРазделаПоНазванию? {
        guard let п = сырое as? [String: Any] else { return nil }
        var адрес = МоиОбъявленияAPI.строка(п["url"]).trimmingCharacters(in: .whitespaces)
        while адрес.hasPrefix("/") { адрес.removeFirst() }
        guard адрес.hasPrefix("api/"), !адрес.contains("://"), !адрес.contains("?") else { return nil }
        let параметр = МоиОбъявленияAPI.строка(п["param"]).trimmingCharacters(in: .whitespaces)
        let минимум = МоиОбъявленияAPI.целое(п["min_len"])
        let сам = МоиОбъявленияAPI.строка(п["auto"]).trimmingCharacters(in: .whitespaces)
        return ПравилоРазделаПоНазванию(адрес: адрес, параметр: параметр.isEmpty ? "q" : параметр,
                                        минимум: минимум > 0 ? минимум : 3, сам: сам.isEmpty ? "high" : сам)
    }
}

/// Предел одного замера, см (rules.fit.range).
struct ПределЗамераВещи: Equatable {
    let от: Double
    let до: Double
}

/// rules.fit при on:true: где показывать блок, какие замеры у вида, подписи и пояснения сайта.
struct ПравилаЗамеровВещи: Equatable {
    /// Ключ поля в submit (fit).
    var поле: String = "fit"
    /// Раздел → вид вещи или «ask» (вид выбирает продавец).
    var разделы: [String: String] = [:]
    /// Вид → ключи замеров по порядку.
    var ключи: [String: [String]] = [:]
    /// Виды на выбор, когда раздел говорит «ask».
    var выбор: [String] = []
    var пределы: [String: ПределЗамераВещи] = [:]
    /// Подписи замеров и видов с сервера (на языке схемы); нет — свои.
    var подписи: [String: String] = [:]
    var виды: [String: String] = [:]
    var заголовок: String = ""
    var подсказка: String = ""
    var как: String = ""

    /// nil — правила нет, выключено или в нём нет ни одного раздела.
    static func из(_ сырое: Any?) -> ПравилаЗамеровВещи? {
        typealias A = МоиОбъявленияAPI
        guard let п = сырое as? [String: Any], A.да(п["on"]) else { return nil }
        var итог = ПравилаЗамеровВещи()
        let поле = A.строка(п["field"]).trimmingCharacters(in: .whitespaces)
        if !поле.isEmpty { итог.поле = поле }
        for (раздел, вид) in (п["cats"] as? [String: Any]) ?? [:] {
            let в = A.строка(вид).trimmingCharacters(in: .whitespaces)
            if !раздел.isEmpty && !в.isEmpty { итог.разделы[раздел] = в }
        }
        guard !итог.разделы.isEmpty else { return nil }
        for (вид, список) in (п["keys"] as? [String: Any]) ?? [:] {
            let ключи = ((список as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty && $0 != "kind" }
            if !ключи.isEmpty { итог.ключи[вид] = ключи }
        }
        итог.выбор = ((п["ask"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty }
        for (ключ, пара) in (п["range"] as? [String: Any]) ?? [:] {
            guard let два = пара as? [Any], два.count >= 2 else { continue }
            let от = A.число(два[0])
            let до = A.число(два[1])
            if до > 0 && до >= от { итог.пределы[ключ] = ПределЗамераВещи(от: от, до: до) }
        }
        итог.подписи = словарьПодписей(п["labels"])
        итог.виды = словарьПодписей(п["kinds"])
        итог.заголовок = текст(п["title"])
        итог.подсказка = текст(п["hint"])
        итог.как = текст(п["how"])
        return итог
    }

    /// {ключ: «подпись»} или [{id|key|k, label|l|name}] — оба вида.
    private static func словарьПодписей(_ сырое: Any?) -> [String: String] {
        typealias A = МоиОбъявленияAPI
        var итог: [String: String] = [:]
        if let словарь = сырое as? [String: Any] {
            for (ключ, значение) in словарь {
                if let вложенное = значение as? [String: Any] {
                    let подпись = первое(вложенное, ["label", "l", "name"])
                    if !подпись.isEmpty { итог[ключ] = подпись }
                } else {
                    let подпись = A.строка(значение)
                    if !подпись.isEmpty { итог[ключ] = подпись }
                }
            }
        } else if let список = сырое as? [Any] {
            for элемент in список {
                guard let э = элемент as? [String: Any] else { continue }
                let ключ = первое(э, ["id", "key", "k"])
                let подпись = первое(э, ["label", "l", "name"])
                if !ключ.isEmpty && !подпись.isEmpty { итог[ключ] = подпись }
            }
        }
        return итог
    }

    /// Первое непустое значение из ключей по порядку.
    private static func первое(_ объект: [String: Any], _ ключи: [String]) -> String {
        for ключ in ключи {
            let значение = МоиОбъявленияAPI.строка(объект[ключ])
            if !значение.isEmpty { return значение }
        }
        return ""
    }

    /// Строка или список строк (строки — через перевод строки).
    private static func текст(_ сырое: Any?) -> String {
        if let список = сырое as? [Any] {
            return список.map { МоиОбъявленияAPI.строка($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return МоиОбъявленияAPI.строка(сырое).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Подпись замера: сервер, иначе своя, иначе ключ.
    func подписьЗамера(_ ключ: String) -> String {
        if let своя = подписи[ключ], !своя.isEmpty { return своя }
        let запасная = ПодачаСайтаText.т("fit_" + ключ)
        return запасная == "fit_" + ключ ? ключ : запасная
    }

    /// Подпись вида: сервер, иначе своя, иначе ключ.
    func подписьВида(_ вид: String) -> String {
        if let своя = виды[вид], !своя.isEmpty { return своя }
        let запасная = ПодачаСайтаText.т("fit_k_" + вид)
        return запасная == "fit_k_" + вид ? вид : запасная
    }
}

/// Замеры в форме (fit): вид вещи (если его выбирает продавец) и значения, как их ввели. Codable — черновик; старые
/// черновики без этого поля читаются (поле необязательное).
struct ЗамерыВещиПодачи: Codable, Equatable {
    var вид: String = ""
    var значения: [String: String] = [:]

    var пусто: Bool { значения.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// fit из my_items: {kind?, chest?, …} или {kind, m:{…}}; пусто или не объект — nil.
    static func изЗаписи(_ сырое: Any?) -> ЗамерыВещиПодачи? {
        typealias A = МоиОбъявленияAPI
        guard let с = сырое as? [String: Any], !с.isEmpty else { return nil }
        var итог = ЗамерыВещиПодачи()
        итог.вид = A.строка(с["kind"])
        let замеры = (с["m"] as? [String: Any]) ?? с
        for (ключ, значение) in замеры where ключ != "kind" && ключ != "m" {
            let число = A.число(значение)
            guard число > 0, число.isFinite else { continue }
            let строка = строкаЧисла(число)
            if !строка.isEmpty { итог.значения[ключ] = строка }
        }
        return итог.значения.isEmpty && итог.вид.isEmpty ? nil : итог
    }

    /// 52 → «52», 52.5 → «52.5».
    static func строкаЧисла(_ число: Double) -> String {
        guard число.isFinite, abs(число) < 1_000_000 else { return "" }
        let округлено = (число * 10).rounded() / 10
        if округлено == округлено.rounded() { return String(Int(округлено)) }
        return String(округлено)
    }
}
