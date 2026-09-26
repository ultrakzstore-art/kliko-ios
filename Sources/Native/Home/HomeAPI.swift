import Foundation

/**
 ГЛАВНАЯ ОДНИМ ЗАПРОСОМ — ЭТАП 34 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Главная сайта (js/marketplace-home.min.js) берёт плитки, ряды «Рекомендуем» и VIP одним запросом — mkHomeLoad:
 GET api/listings.php?<_mhQS()>, где _mhQS — home=1 и место: city=<название>, без города — region=<ключ> (point и
 radius приложение не ставит). Что сайт берёт из ответа (mkHomeRender, _mhTiles, _mhRow):
   ok — без него «Не удалось загрузить подборки» (_mhFail);
   verts{<раздел>: {items, n}} — ряд раздела и его число: на плитке «N предложений», в заголовке ряда и «Смотреть все»,
     когда n больше показанного;
   jobs{items, n} — ряд вакансий: у приложения его нет (этап 26: вакансии — другой API и без нативного экрана);
   vip[] — блок «VIP-объявления» среди рядов;
   total — число на кнопке «Показать все объявления».
 До этапа 34 приложение просило по запросу на раздел (cat=<раздел>&per=10): шесть запросов вместо одного и без VIP.

 Числа разделов, у которых n не пришло (в карте API поле не отмечено, а сайт читает его как +n||0), — из
 GET api/listings.php?counts=1 (mkLoadCounts: counts{раздел: число}, total; город — city=, регион сайт туда не шлёт).
 Сайт складывает их по всем подразделам (mkUpdateCatCounts → mkCatDescendants) и только когда счёт «честный»
 (_mkCountsHonest: без региона и района). Здесь так же: по корню раздела в дереве сайта (РазделыСайта), а «goods» главной —
 набор корней MK_VSETS.goods (mkHomeGo открывает «Товары» как vs=goods, а не как один раздел).

 🔴 ТЕРПИМО. kliko.kz отсюда не проверить, поэтому ответ разбирается, как Listing: числа — числом или строкой, объявление,
 которое не разобралось, пропускаем, пустой объект PHP отдаёт как [] — это пусто, а не ошибка. Нет ok или нет verts при
 ok: true — ответ не того вида (ListingsAPI.Ошибка.разбор): главная тогда идёт запросами по разделам, как на этапе 26
 (ПодборкиГлавной).
 */
struct ОтветГлавной: Decodable, @unchecked Sendable {
    struct Раздел {
        let товары: [Listing]
        /// verts[раздел].n — сколько всего в разделе; nil — не пришло.
        let всего: Int?
    }

    /// ok: false — сайт отказал; у него это _mhFail, у нас — «не пришло».
    let ok: Bool
    /// verts: раздел главной («transport», «realty»…) → ряд и число.
    let разделы: [String: Раздел]
    /// vip[] — «VIP-объявления».
    let вип: [Listing]
    /// total — «Показать все объявления N». nil — не пришло.
    let всего: Int?
    /// Этап 49: jobs.items — ряд «Работа» (mhCardJob сайта); пусто — ряда нет.
    let вакансии: [ВакансияГлавной]
    /// Этап 49: jobs.n — число на плитке «Работа» и в заголовке её ряда («N вакансий»); nil — не пришло.
    let вакансийВсего: Int?

    private enum Ключи: String, CodingKey {
        case ok
        case verts
        case vip
        case total
        case jobs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        guard let да = (try? c.decode(ДаГлавной.self, forKey: .ok))?.значение else {
            throw DecodingError.keyNotFound(Ключи.ok, DecodingError.Context(codingPath: c.codingPath,
                                                                             debugDescription: "нет ok"))
        }
        ok = да
        всего = (try? c.decode(ЧислоГлавной.self, forKey: .total))?.значение
        вип = ((try? c.decode([ТоварГлавной].self, forKey: .vip)) ?? []).compactMap(\.товар)
        /* Этап 49: вакансии — отдельным блоком jobs{items, n}, как у _mhRow и _mhTiles сайта. Не объект — ряда нет. */
        let работа = try? c.decode(СырыеВакансии.self, forKey: .jobs)
        вакансии = работа?.вакансии ?? []
        вакансийВсего = работа?.всего
        guard да else {
            разделы = [:]
            return
        }
        if let словарь = try? c.decode([String: СыройРаздел].self, forKey: .verts) {
            var итог: [String: Раздел] = [:]
            for (ключ, сырой) in словарь {
                итог[ключ] = Раздел(товары: сырой.товары, всего: сырой.всего)
            }
            разделы = итог
        } else if let пустой = try? c.nestedUnkeyedContainer(forKey: .verts), (пустой.count ?? 0) == 0 {
            /* Разделов нет: PHP кодирует пустой массив как [], а не {}. */
            разделы = [:]
        } else {
            throw DecodingError.keyNotFound(Ключи.verts, DecodingError.Context(codingPath: c.codingPath,
                                                                                debugDescription: "нет verts"))
        }
    }
}

/// Ответ api/listings.php?counts=1 — mkLoadCounts сайта: counts{раздел: число}, total.
struct СчётРазделов: Decodable, @unchecked Sendable {
    /// Раздел дерева сайта → сколько в нём объявлений; только больше нуля.
    let счёт: [String: Int]
    let всего: Int?

    private enum Ключи: String, CodingKey {
        case ok
        case counts
        case total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        /* Как у сайта: t && t.ok — иначе числа не берём. */
        guard (try? c.decode(ДаГлавной.self, forKey: .ok))?.значение == true else {
            throw DecodingError.keyNotFound(Ключи.ok, DecodingError.Context(codingPath: c.codingPath,
                                                                             debugDescription: "нет ok"))
        }
        let сырой = (try? c.decode([String: ЧислоГлавной].self, forKey: .counts)) ?? [:]
        var итог: [String: Int] = [:]
        for (раздел, сколько) in сырой {
            if let n = сколько.значение, n > 0 { итог[раздел] = n }
        }
        счёт = итог
        всего = (try? c.decode(ЧислоГлавной.self, forKey: .total))?.значение
    }

    /// MK_VSETS главной (home.html, 25.09.2026): {"goods":["clothing","home-garden","kids","sport","hobby","food-farm",
    /// "beauty"]} — из чего состоит «Товары».
    static let наборТоваров: Set<String> = ["clothing", "home-garden", "kids", "sport", "hobby", "food-farm", "beauty"]

    /// Сколько в разделе главной: сумма по всем его подразделам, как mkUpdateCatCounts (mkCatDescendants).
    func число(_ разделГлавной: String) -> Int {
        var сумма = 0
        for (раздел, n) in счёт where Self.входит(раздел, разделГлавной) {
            сумма += n
        }
        return сумма
    }

    /// Раздел ответа — любой узел дерева сайта; решает его корень (снимок MK_CATS, РазделыСайта). Неизвестный снимку раздел
    /// сам себе корень — попадёт, только если это и есть раздел главной.
    private static func входит(_ раздел: String, _ разделГлавной: String) -> Bool {
        let корень = РазделыСайта.корень(раздел)
        if разделГлавной == "goods" { return корень == "goods" || наборТоваров.contains(корень) }
        return корень == разделГлавной
    }
}

/// Да или нет в любом виде PHP: true, 1, "1"; прочее — nil.
private struct ДаГлавной: Decodable {
    let значение: Bool?

    init(from decoder: Decoder) throws {
        guard let з = try? decoder.singleValueContainer() else {
            значение = nil
            return
        }
        if let b = try? з.decode(Bool.self) {
            значение = b
        } else if let n = try? з.decode(Int.self) {
            значение = n != 0
        } else if let s = try? з.decode(String.self) {
            значение = s == "1" || s.lowercased() == "true"
        } else {
            значение = nil
        }
    }
}

/// Число в любом виде PHP: 12, "12", 12.0; прочее — nil.
private struct ЧислоГлавной: Decodable {
    let значение: Int?

    init(from decoder: Decoder) throws {
        guard let з = try? decoder.singleValueContainer() else {
            значение = nil
            return
        }
        if let n = try? з.decode(Int.self) {
            значение = n
        } else if let s = try? з.decode(String.self) {
            значение = Int(s.trimmingCharacters(in: .whitespaces))
        } else if let d = try? з.decode(Double.self), d.isFinite, abs(d) < 1e15 {
            значение = Int(d)
        } else {
            значение = nil
        }
    }
}

/// Объявление, которое не разобралось, — nil, а не падение всего ответа.
private struct ТоварГлавной: Decodable {
    let товар: Listing?

    init(from decoder: Decoder) throws {
        товар = try? Listing(from: decoder)
    }
}

/**
 Вакансия ряда «Работа» главной (этап 49) — поля, которые читает mhCardJob сайта: id, title, salary_min, salary_max,
 employment (full, part, shift, remote, internship), city, company, top. Своей карточки вакансии у приложения нет —
 нажатие открывает её на сайте (/?cat=jobs#vac=<id>: сайт сам откроет её лист, mkJobOpen).
 */
struct ВакансияГлавной: Identifiable, Hashable, Sendable {
    let id: String
    let название: String
    /// salary_min и salary_max, ₸; 0 — не указана.
    let зарплатаОт: Int
    let зарплатаДо: Int
    let занятость: String
    let город: String
    let компания: String
    /// top — метка «★ ТОП» над названием.
    let топ: Bool
}

/// jobs{items, n} как пришёл. Вакансия без id пропускается — её не открыть.
private struct СырыеВакансии: Decodable {
    let вакансии: [ВакансияГлавной]
    let всего: Int?

    private enum Ключи: String, CodingKey {
        case items
        case n
    }

    private struct Одна: Decodable {
        let вакансия: ВакансияГлавной?

        private struct Ключ: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ s: String) { stringValue = s }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: Ключ.self) else {
                вакансия = nil
                return
            }
            func строка(_ k: String) -> String {
                if let s = try? c.decode(String.self, forKey: Ключ(k)) {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let n = try? c.decode(Int.self, forKey: Ключ(k)) { return String(n) }
                return ""
            }
            func число(_ k: String) -> Int {
                if let n = try? c.decode(Int.self, forKey: Ключ(k)) { return n }
                if let d = try? c.decode(Double.self, forKey: Ключ(k)), d.isFinite, abs(d) < 1e15 { return Int(d) }
                /* Строка «nan» или «1e40» — не число зарплаты: Int(Double) на них упал бы. */
                if let s = try? c.decode(String.self, forKey: Ключ(k)),
                   let d = Double(s.replacingOccurrences(of: " ", with: "")), d.isFinite, abs(d) < 1e15 {
                    return Int(d)
                }
                return 0
            }
            func да(_ k: String) -> Bool {
                if let b = try? c.decode(Bool.self, forKey: Ключ(k)) { return b }
                if let n = try? c.decode(Int.self, forKey: Ключ(k)) { return n != 0 }
                if let s = try? c.decode(String.self, forKey: Ключ(k)) { return s == "1" || s.lowercased() == "true" }
                return false
            }
            let номер = строка("id")
            guard !номер.isEmpty else {
                вакансия = nil
                return
            }
            вакансия = ВакансияГлавной(id: номер, название: строка("title"), зарплатаОт: max(0, число("salary_min")),
                                       зарплатаДо: max(0, число("salary_max")), занятость: строка("employment"),
                                       город: строка("city"), компания: строка("company"), топ: да("top"))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        вакансии = ((try? c.decode([Одна].self, forKey: .items)) ?? []).compactMap(\.вакансия)
        всего = (try? c.decode(ЧислоГлавной.self, forKey: .n))?.значение
    }
}

/// verts[раздел] как пришёл: {items, n}. Не объект (null, строка) — пустой раздел, а не ошибка всего ответа.
private struct СыройРаздел: Decodable {
    let товары: [Listing]
    let всего: Int?

    private enum Ключи: String, CodingKey {
        case items
        case n
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Ключи.self) else {
            товары = []
            всего = nil
            return
        }
        товары = ((try? c.decode([ТоварГлавной].self, forKey: .items)) ?? []).compactMap(\.товар)
        всего = (try? c.decode(ЧислоГлавной.self, forKey: .n))?.значение
    }
}

/**
 ЗАПРОСЫ ГЛАВНОЙ: GET api/listings.php?home=1 и ?counts=1 — только чтение, без csrf, с куками веб-сессии, как у ленты
 (ListingsAPI: куки берём у WebKit и кладём в заголовок сами, своё хранилище куков у запроса выключено). Ошибки — те же,
 что у ленты (ListingsAPI.Ошибка): сеть, статус, разбор.
 */
enum ГлавнаяAPI {
    /// Параметры главной — _mhQS сайта: home=1, место — city=<название>, без города — region=<ключ>. Района _mhQS не
    /// шлёт: у сайта с районом главной нет вовсе (district не в MH_NEUTRAL, mkHomeWant её прячет).
    static func параметры(_ где: ГдеИскать) -> [URLQueryItem] {
        var поля = [URLQueryItem(name: "home", value: "1")]
        if !где.город.isEmpty {
            поля.append(URLQueryItem(name: "city", value: где.город))
        } else if !где.регион.isEmpty {
            поля.append(URLQueryItem(name: "region", value: где.регион))
        }
        return поля
    }

    /// Ключ копии на диске — как qs у ulx_home_feed сайта: та же строка запроса. Копия другого места не подходит.
    static func ключ(_ где: ГдеИскать) -> String {
        var ч = URLComponents()
        ч.queryItems = параметры(где)
        return ч.percentEncodedQuery ?? "home=1"
    }

    /// Главная одним запросом: рубильник включён и район не выбран. С районом — ряды по разделам (этап 26): они несут
    /// district=, а home=1 его не знает, и ряды всего города под лентой района путали бы.
    static func годится(_ где: ГдеИскать) -> Bool {
        Config.главнаяОдинЗапрос && где.район.isEmpty
    }

    /// Счёт counts=1 «честный» (_mkCountsHonest): вся страна или город — без региона и района.
    static func счётЧестный(_ где: ГдеИскать) -> Bool {
        где.регион.isEmpty && где.район.isEmpty
    }

    /// Главная: разобранный ответ и он же как пришёл — для копии на диске.
    static func загрузить(_ где: ГдеИскать, куки: [String: String]) async throws -> (ответ: ОтветГлавной, сырое: Data) {
        let данные = try await получить(параметры(где), куки: куки)
        do {
            return (try JSONDecoder().decode(ОтветГлавной.self, from: данные), данные)
        } catch {
            throw ListingsAPI.Ошибка.разбор
        }
    }

    /// Числа разделов — mkLoadCounts: counts=1 и city=, если выбран город (регион сайт сюда не шлёт).
    static func числа(_ где: ГдеИскать, куки: [String: String]) async throws -> СчётРазделов {
        var поля = [URLQueryItem(name: "counts", value: "1")]
        if !где.город.isEmpty { поля.append(URLQueryItem(name: "city", value: где.город)) }
        let данные = try await получить(поля, куки: куки)
        do {
            return try JSONDecoder().decode(СчётРазделов.self, from: данные)
        } catch {
            throw ListingsAPI.Ошибка.разбор
        }
    }

    /// Как у ленты: куки ставим сами, тот же общий кэш, что поднимает WebContainer.
    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = .shared
        return URLSession(configuration: c)
    }()

    private static func получить(_ поля: [URLQueryItem], куки: [String: String]) async throws -> Data {
        guard var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"),
                                    resolvingAgainstBaseURL: false) else { throw ListingsAPI.Ошибка.сеть }
        ч.queryItems = поля
        guard let адрес = ч.url else { throw ListingsAPI.Ошибка.сеть }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: имя) }

        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(for: запрос) } catch { throw ListingsAPI.Ошибка.сеть }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ListingsAPI.Ошибка.статус(http.statusCode)
        }
        return данные
    }
}

/**
 ГЛАВНАЯ НА ДИСКЕ — как ulx_home_feed сайта (_mhCachePut / _mhCacheGet): последний удачный ответ home=1 вместе с его
 строкой запроса, срок — сутки (MH_CACHE_TTL). Запуск без сети показывает её с «Показано, как было в последний раз»,
 а с сетью — сразу, пока едет свежая. Копия другого места (город сменили) не подходит — как у сайта, по qs.

 Один файл в Application Support вне резервной копии, как лента на диске (ListingsCache), и не больше 2 МБ (сайт свою
 копию больше 700 000 знаков тоже не кладёт). Стирается при выходе из аккаунта (WebContainer, bye=1), а при выключенном
 рубильнике — на запуске.
 */
enum КэшГлавной {
    static let срок: TimeInterval = 24 * 3600
    private static let предел = 2 * 1024 * 1024

    private static var файл: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-home.json")
    }

    /// Запись — {"qs": <ключ>, "d": <ответ как пришёл>}: сам ответ не пересобираем, он уже разобрался.
    static func сохранить(_ сырое: Data, ключ: String) {
        guard Config.главнаяОдинЗапрос, let файл, сырое.count <= предел,
              let ключВJSON = try? JSONEncoder().encode(ключ) else { return }
        var данные = Data("{\"qs\":".utf8)
        данные.append(ключВJSON)
        данные.append(Data(",\"d\":".utf8))
        данные.append(сырое)
        данные.append(Data("}".utf8))
        do {
            try данные.write(to: файл, options: .atomic)
            var значения = URLResourceValues()
            значения.isExcludedFromBackup = true
            var изменяемый = файл
            try? изменяемый.setResourceValues(значения)
        } catch {
            // Диск полон — копия главной удобство, а не обязанность.
        }
    }

    /// Копия для этого места, не старше суток и с ok; иначе nil.
    static func прочитать(_ ключ: String) -> ОтветГлавной? {
        guard Config.главнаяОдинЗапрос, let файл,
              let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey]),
              let когда = свойства.contentModificationDate,
              Date().timeIntervalSince(когда) <= срок,
              let данные = try? Data(contentsOf: файл),
              let запись = try? JSONDecoder().decode(ЗаписьГлавной.self, from: данные),
              запись.qs == ключ, запись.d.ok else { return nil }
        return запись.d
    }

    static func стереть() {
        guard let файл else { return }
        try? FileManager.default.removeItem(at: файл)
    }

    /// То же, но не на главной очереди: до 2 МБ чтения и разбора на запуске — не повод подвешивать ленту (проверка на
    /// телефоне, сборка 33: «лента подвисает»).
    static func прочитатьВФоне(_ ключ: String) async -> ОтветГлавной? {
        прочитать(ключ)
    }

    static func сохранитьВФоне(_ сырое: Data, ключ: String) async {
        сохранить(сырое, ключ: ключ)
    }
}

private struct ЗаписьГлавной: Decodable {
    let qs: String
    let d: ОтветГлавной
}
