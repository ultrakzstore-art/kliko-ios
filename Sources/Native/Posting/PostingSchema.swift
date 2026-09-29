import Foundation

/**
 СХЕМА ФОРМЫ ПОДАЧИ С САЙТА (владелец 29.09.2026: «форма подачи в приложении должна идти за сайтом сама — без новой
 сборки»).

 GET /api/app_post_schema.php?lang=ru|kk|en|ar (правка 90 сервера: inc/app_post_schema.php, inc/post_specs.php) отдаёт:
   · categories — разделы с признаками: аренда, обмен, VIN, «Вещь работает?», обязательная марка, предел фото, строки
     «Дополнительно»;
   · fields — характеристики каждого раздела плоским списком (наследование сайт уже разрешил, как specsFor): слот
     (cpu · gpu · ram · storage · year — те же поля cabinet.php?action=submit), вид (select · number · year · text),
     подпись и значения на языке телефона, обязательность, единица, шаг, подсказка;
   · rules — общие правила (здесь не нужны: всё нужное уже разложено по разделам).

 Кэш: файл в Caches (по языку) + ETag в UserDefaults; при открытии подачи — сначала кэш, потом запрос с If-None-Match
 (304 — ничего не меняем). Нет сети, нет кэша, ответ битый — схемы нет, и ПодачаМодель живёт по встроенным правилам и
 справочникам страницы кабинета (E_SPECS из cab-refs.js), как раньше.

 🔴 В значениях (v) — русские строки: они уходят в объявление, по ним отбирает витрина. Подписи (l) — только показ.
 Слоты вне cpu/gpu/ram/storage/year и незнакомые виды полей отбрасываются: их форме некуда записать.
 */

/// Раздел по схеме сайта: только признаки, которые меняют форму.
struct РазделСхемыПодачи: Equatable {
    let ключ: String
    let родитель: String
    let корень: String
    let аренда: Bool
    let обмен: Bool
    let vin: Bool
    let работает: Bool
    let маркаОбязательна: Bool
    /// photo_max: 5 или 10 (ТОП — 30 — решает модель).
    let фото: Int
    /// Строки «Дополнительно»: pay · del · trust.
    let дополнительно: [String]
}

struct СхемаПодачи: Equatable {
    let версия: String
    let язык: String
    let разделы: [String: РазделСхемыПодачи]
    let поля: [String: [ПолеХарактеристики]]

    /// Слоты объявления, в которые форма умеет писать (поля submit).
    static let слоты: Set<String> = ["cpu", "gpu", "ram", "storage", "year"]
    static let виды: Set<String> = ["select", "number", "year", "text"]

    /// Характеристики раздела: раздел есть в схеме — его список (может быть пустым: у раздела их нет); нет — nil.
    func характеристики(_ раздел: String) -> [ПолеХарактеристики]? {
        guard разделы[раздел] != nil else { return nil }
        return поля[раздел] ?? []
    }

    /// Разбор ответа сервера; nil — ответ не годится (не ok, нет разделов).
    static func разобрать(_ данные: Data, язык: String) -> СхемаПодачи? {
        guard let j = try? JSONSerialization.jsonObject(with: данные) as? [String: Any],
              (j["ok"] as? Bool) == true,
              let список = j["categories"] as? [Any] else { return nil }
        var разделы: [String: РазделСхемыПодачи] = [:]
        for элемент in список {
            guard let р = элемент as? [String: Any], let ключ = р["id"] as? String, !ключ.isEmpty else { continue }
            let фото = (р["photo_max"] as? NSNumber)?.intValue ?? 5
            разделы[ключ] = РазделСхемыПодачи(ключ: ключ,
                                              родитель: (р["parent"] as? String) ?? "",
                                              корень: (р["root"] as? String) ?? ключ,
                                              аренда: логика(р["rentable"]),
                                              обмен: логика(р["exchange"]),
                                              vin: логика(р["vin"]),
                                              работает: логика(р["works"]),
                                              маркаОбязательна: логика(р["brand_req"]),
                                              фото: max(1, min(30, фото)),
                                              дополнительно: ((р["extra"] as? [Any]) ?? []).compactMap { $0 as? String })
        }
        guard !разделы.isEmpty else { return nil }
        var поля: [String: [ПолеХарактеристики]] = [:]
        if let все = j["fields"] as? [String: Any] {
            for (раздел, набор) in все {
                let записи = (набор as? [Any]) ?? []
                поля[раздел] = записи.compactMap { поле($0) }
            }
        }
        let версия = (j["v"] as? String) ?? ""
        return СхемаПодачи(версия: версия, язык: язык, разделы: разделы, поля: поля)
    }

    private static func логика(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.boolValue }
        return false
    }

    private static func текст(_ значение: Any?) -> String {
        if let s = значение as? String { return s }
        if let n = значение as? NSNumber { return n.stringValue }
        return ""
    }

    /// Поле схемы → ПолеХарактеристики; чужой слот или вид — nil.
    private static func поле(_ сырое: Any) -> ПолеХарактеристики? {
        guard let п = сырое as? [String: Any] else { return nil }
        let ключ = текст(п["key"])
        let вид = текст(п["type"])
        guard слоты.contains(ключ), виды.contains(вид) else { return nil }
        let имя = текст(п["label"])
        let единица = текст(п["unit"])
        var пары: [ВариантПоля] = []
        for вариант in (п["options"] as? [Any]) ?? [] {
            guard let в = вариант as? [String: Any] else { continue }
            let значение = текст(в["v"])
            guard !значение.isEmpty else { continue }
            let подпись = текст(в["l"])
            пары.append(ВариантПоля(ключ: значение, подпись: подпись.isEmpty ? значение : подпись))
        }
        /* Список без значений — не список: пусть будет полем ввода. */
        let итоговыйВид = (вид == "select" && пары.isEmpty) ? "text" : вид
        var подварианты: [String: [String]] = [:]
        if let sub = п["sub"] as? [String: Any] {
            for (семейство, модели) in sub {
                подварианты[семейство] = ((модели as? [Any]) ?? []).map { текст($0) }.filter { !$0.isEmpty }
            }
        }
        return ПолеХарактеристики(поле: ключ,
                                  подпись: единица.isEmpty ? имя : имя + ", " + единица,
                                  варианты: пары.map { $0.ключ },
                                  вид: итоговыйВид,
                                  подписиВариантов: пары,
                                  подсказка: текст(п["ph"]),
                                  шаг: текст(п["step"]),
                                  обязательно: логика(п["required"]),
                                  своё: п["other"] == nil ? true : логика(п["other"]),
                                  подварианты: подварианты)
    }
}

/// Загрузка схемы: память → файл в Caches → сеть (ETag). Одна на все открытия мастера.
@MainActor
enum ЗагрузкаСхемыПодачи {
    private static var вПамяти: [String: СхемаПодачи] = [:]
    private static let ключМетки = "kliko.postSchema.etag."

    /// Язык телефона, как у текстов подачи (ПодачаText): kk · en · ar, иначе ru.
    static var язык: String {
        let код = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        switch код {
        case "kk", "en", "ar": return код
        default: return "ru"
        }
    }

    private static func файл(_ язык: String) -> URL? {
        guard let папка = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return папка.appendingPathComponent("kliko_post_schema_" + язык + ".json")
    }

    /// Последняя сохранённая схема на языке телефона или nil.
    static func изКэша() async -> СхемаПодачи? {
        let я = язык
        if let есть = вПамяти[я] { return есть }
        guard let путь = файл(я) else { return nil }
        let схема = await Task.detached(priority: .userInitiated) { () -> СхемаПодачи? in
            guard let данные = try? Data(contentsOf: путь) else { return nil }
            return СхемаПодачи.разобрать(данные, язык: я)
        }.value
        if let схема { вПамяти[я] = схема }
        return схема
    }

    /// Отдельная сессия без кук: ответ публичный, ETag ведём сами.
    private static let сессия: URLSession = {
        let к = URLSessionConfiguration.ephemeral
        к.urlCache = nil
        к.requestCachePolicy = .reloadIgnoringLocalCacheData
        к.timeoutIntervalForRequest = 15
        return URLSession(configuration: к)
    }()

    /// Свежая схема с сайта. nil — не изменилась (304), нет сети или ответ не годится: остаётся прежняя.
    static func загрузить() async -> СхемаПодачи? {
        let я = язык
        guard let адрес = Config.url("/api/app_post_schema.php?lang=" + я) else { return nil }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        let хранилище = UserDefaults.standard
        let естьФайл = файл(я).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if естьФайл, let метка = хранилище.string(forKey: ключМетки + я), !метка.isEmpty {
            запрос.setValue(метка, forHTTPHeaderField: "If-None-Match")
        }
        guard let пара = try? await сессия.data(for: запрос),
              let http = пара.1 as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        let данные = пара.0
        let схема = await Task.detached(priority: .utility) { () -> СхемаПодачи? in
            СхемаПодачи.разобрать(данные, язык: я)
        }.value
        guard let схема else { return nil }
        if let путь = файл(я), (try? данные.write(to: путь, options: .atomic)) != nil,
           let метка = http.value(forHTTPHeaderField: "ETag"), !метка.isEmpty {
            хранилище.set(метка, forKey: ключМетки + я)
        } else {
            хранилище.removeObject(forKey: ключМетки + я)
        }
        вПамяти[я] = схема
        return схема
    }
}
