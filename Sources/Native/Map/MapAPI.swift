import Foundation

/**
 КАРТА ОБЪЯВЛЕНИЙ — ЗАПРОСЫ К САЙТУ (этап 39, владелец 25.09.2026: «почти 100% похоже на сайт»).

 Карта сайта (mkMapOpen, _mkMapFetchCities, _mkMapFetchPins, _mkMapFetchCityList в js/marketplace.min.js) ходит за
 данными тремя запросами к той же api/listings.php, что лента, — только чтение, без csrf, с куками веб-сессии:
   · пузыри городов: GET /api/listings.php?map=1&<фильтры _mkApiQS> → {ok, cities[{city, count, lat, lon}], total};
   · ценники ближе зума 12 (MK_APPROX_MAXZOOM): GET /api/listings.php?map=1&pins=1&n=&s=&e=&w=&<фильтры> — края видимой
     области пятью знаками после точки (_mkBBoxQS: toFixed(5)) → {ok, pins[{id, lat, lon, price, …}]};
   · объявления города: GET /api/listings.php?per=60&<фильтры без city>&city=<город> → {ok, items, total} — city= из
     фильтров убирается (_mkApiQS сайта, из которой заменой вырезано «city=…») и ставится город пузыря; регион и район
     остаются.
 Нет ok или ответ не JSON — сайт считает запрос неудачным (_mkSrvFail); у нас — Ошибка.ответ.

 🔴 РАЗБОР ТЕРПИМЫЙ, как у Listing: PHP отдаёт числа то числом, то строкой, а пина без номера или места, города без
 названия или координат на карте не поставить — такие пропускаем, а не роняем весь ответ. Пин разбирается тем же
 Listing(from:), что строка ленты: в ответе сайта у пина те же поля (title, price, thumb, city, is_top…), что сайт рисует
 карточкой .mk-mcard под картой. Повторы номеров и городов отбрасываем: два одинаковых id в ForEach ломают список.

 Отмена: задачу запроса отменяет МодельКарты, когда карта сдвинулась или сменились фильтры, — URLSession обрывает
 запрос, и сюда приходит CancellationError, а не «нет связи».
 */

/// Что отбирает карта — то же, что лента на экране: раздел, отправленный поиск, место (этап 32) и фильтры (этап 33).
struct УсловияКарты: Equatable, Sendable {
    var раздел = ""
    var поиск = ""
    var где = ГдеИскать()
    var фильтры = ФильтрыЛенты()

    /**
     Параметры — _mkApiQS сайта: cat, city или region, district, cond, verified, photo, pmin, pmax, sort, q, ymin, ymax,
     rooms. Пустое не шлём, как и сайт (r() пропускает ""); sort сайт шлёт всегда — и мы.
     */
    var параметры: [URLQueryItem] {
        var поля: [URLQueryItem] = []
        if !раздел.isEmpty { поля.append(URLQueryItem(name: "cat", value: раздел)) }
        поля.append(contentsOf: где.параметры)
        поля.append(contentsOf: фильтры.параметры)
        поля.append(URLQueryItem(name: "sort", value: фильтры.сортировка.rawValue))
        let текст = поиск.trimmingCharacters(in: .whitespacesAndNewlines)
        if !текст.isEmpty { поля.append(URLQueryItem(name: "q", value: текст)) }
        return поля
    }
}

enum КартаAPI {
    enum Ошибка: Error {
        /// Нет связи или сервер не ответил.
        case сеть
        /// Ответил не тем: не 2xx, не JSON или без ok.
        case ответ
    }

    /// Пузырь города: cities[] ответа map=1.
    struct Город: Identifiable, Equatable, Sendable {
        /// Название, как в объявлениях («Алматы»), — им же уходит city= в список города.
        let город: String
        /// count — сколько объявлений в городе по фильтрам.
        let число: Int
        let широта: Double
        let долгота: Double

        var id: String { город }
    }

    /// Ответ map=1: города и total — сколько всего объявлений по фильтрам.
    struct Города: Sendable {
        let города: [Город]
        let всего: Int?
    }

    /// Ценник: pins[] ответа map=1&pins=1 — объявление и его точка.
    struct Пин: Identifiable, Equatable {
        let товар: Listing
        let широта: Double
        let долгота: Double

        var id: String { товар.id }
    }

    /// Ответ per=60&city=: объявления города и total.
    struct СписокГорода {
        let товары: [Listing]
        let всего: Int?
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим, как ListingsAPI
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    // MARK: - Запросы

    /// GET /api/listings.php?map=1&<фильтры> — пузыри городов.
    static func города(_ условия: УсловияКарты) async throws -> Города {
        let данные = try await получить([URLQueryItem(name: "map", value: "1")] + условия.параметры)
        let ответ: ОтветГородов
        do { ответ = try JSONDecoder().decode(ОтветГородов.self, from: данные) } catch { throw Ошибка.ответ }
        guard ответ.ok else { throw Ошибка.ответ }
        return Города(города: ответ.города, всего: ответ.всего)
    }

    /// GET /api/listings.php?map=1&pins=1&n=&s=&e=&w=&<фильтры> — ценники в видимой области.
    static func пины(_ условия: УсловияКарты, север: Double, юг: Double, восток: Double, запад: Double) async throws -> [Пин] {
        var поля = [URLQueryItem(name: "map", value: "1"), URLQueryItem(name: "pins", value: "1")]
        поля.append(URLQueryItem(name: "n", value: пятьЗнаков(север)))
        поля.append(URLQueryItem(name: "s", value: пятьЗнаков(юг)))
        поля.append(URLQueryItem(name: "e", value: пятьЗнаков(восток)))
        поля.append(URLQueryItem(name: "w", value: пятьЗнаков(запад)))
        let данные = try await получить(поля + условия.параметры)
        let ответ: ОтветПинов
        do { ответ = try JSONDecoder().decode(ОтветПинов.self, from: данные) } catch { throw Ошибка.ответ }
        guard ответ.ok else { throw Ошибка.ответ }
        return ответ.пины
    }

    /// GET /api/listings.php?per=60&<фильтры без city>&city=<город> — объявления города для списка под картой.
    static func списокГорода(_ условия: УсловияКарты, город: String) async throws -> СписокГорода {
        var поля = [URLQueryItem(name: "per", value: "60")]
        поля.append(contentsOf: условия.параметры.filter { $0.name != "city" })
        поля.append(URLQueryItem(name: "city", value: город))
        let данные = try await получить(поля)
        let признак: ПризнакОк
        do { признак = try JSONDecoder().decode(ПризнакОк.self, from: данные) } catch { throw Ошибка.ответ }
        guard признак.ok else { throw Ошибка.ответ }
        let страница: ListingsPage
        do { страница = try ListingsAPI.разобрать(данные) } catch { throw Ошибка.ответ }
        var были = Set<String>()
        let товары = страница.items.filter { были.insert($0.id).inserted }
        return СписокГорода(товары: товары, всего: страница.total)
    }

    // MARK: - Общее

    /// Края области — toFixed(5) сайта. String(format:) не зависит от языка телефона: всегда точка, не запятая.
    private static func пятьЗнаков(_ число: Double) -> String {
        String(format: "%.5f", число)
    }

    /// GET /api/listings.php с этими полями и куками веб-сессии; вернуть тело 2xx.
    private static func получить(_ поля: [URLQueryItem]) async throws -> Data {
        guard var части = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"),
                                        resolvingAgainstBaseURL: false) else { throw Ошибка.ответ }
        части.queryItems = поля
        guard let адрес = части.url else { throw Ошибка.ответ }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        let заголовки = await SiteSession.куки()
        for (имя, значение) in заголовки { запрос.setValue(значение, forHTTPHeaderField: имя) }
        try Task.checkCancellation()
        let данные: Data
        let ответ: URLResponse
        do {
            (данные, ответ) = try await сессия.data(for: запрос)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Ошибка.сеть
        }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Ошибка.ответ }
        return данные
    }
}

// MARK: - Разбор

/// Поля ответа по одному и терпимо: число числом или строкой, да — true, 1 или "1".
private enum ПоляКарты {
    static func да<Ключ: CodingKey>(_ c: KeyedDecodingContainer<Ключ>, _ ключ: Ключ) -> Bool {
        if let b = try? c.decode(Bool.self, forKey: ключ) { return b }
        if let i = try? c.decode(Int.self, forKey: ключ) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: ключ) { return s == "1" || s.lowercased() == "true" }
        return false
    }

    static func дробное<Ключ: CodingKey>(_ c: KeyedDecodingContainer<Ключ>, _ ключ: Ключ) -> Double? {
        if let d = try? c.decode(Double.self, forKey: ключ) { return d.isFinite ? d : nil }
        if let s = try? c.decode(String.self, forKey: ключ) {
            let строка = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            guard let d = Double(строка), d.isFinite else { return nil }
            return d
        }
        return nil
    }

    static func целое<Ключ: CodingKey>(_ c: KeyedDecodingContainer<Ключ>, _ ключ: Ключ) -> Int? {
        if let i = try? c.decode(Int.self, forKey: ключ) { return i }
        guard let d = дробное(c, ключ) else { return nil }
        /* Int(exactly:) не падает на огромных значениях, а даёт nil. */
        return Int(exactly: d.rounded(.towardZero))
    }

    static func строка<Ключ: CodingKey>(_ c: KeyedDecodingContainer<Ключ>, _ ключ: Ключ) -> String? {
        let сырое: String?
        if let s = try? c.decode(String.self, forKey: ключ) {
            сырое = s
        } else if let i = try? c.decode(Int.self, forKey: ключ) {
            сырое = String(i)
        } else {
            сырое = nil
        }
        guard let t = сырое?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Точка на Земле и не «ноль-ноль»: так сайт отличает настоящую точку от пустой (_mkItemLL: |lat| > .01 или |lon| > .01).
    static func место(_ широта: Double?, _ долгота: Double?) -> (Double, Double)? {
        guard let ш = широта, let д = долгота, abs(ш) <= 90, abs(д) <= 180 else { return nil }
        guard abs(ш) > 0.01 || abs(д) > 0.01 else { return nil }
        return (ш, д)
    }
}

/// {ok, …} — только признак ok.
private struct ПризнакОк: Decodable {
    let ok: Bool

    private enum Ключи: String, CodingKey {
        case ok
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        ok = ПоляКарты.да(c, .ok)
    }
}

extension КартаAPI.Город: Decodable {
    private enum Ключи: String, CodingKey {
        case city, count, lat, lon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        guard let название = ПоляКарты.строка(c, .city),
              let точка = ПоляКарты.место(ПоляКарты.дробное(c, .lat), ПоляКарты.дробное(c, .lon)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "город без места"))
        }
        город = название
        число = max(0, ПоляКарты.целое(c, .count) ?? 0)
        широта = точка.0
        долгота = точка.1
    }
}

extension КартаAPI.Пин: Decodable {
    private enum Ключи: String, CodingKey {
        case lat, lon
    }

    init(from decoder: Decoder) throws {
        let объявление = try Listing(from: decoder)
        let c = try decoder.container(keyedBy: Ключи.self)
        guard let точка = ПоляКарты.место(ПоляКарты.дробное(c, .lat), ПоляКарты.дробное(c, .lon)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "пин без места"))
        }
        товар = объявление
        широта = точка.0
        долгота = точка.1
    }
}

/// Элемент массива, который не разобрался, — nil, а не ошибка всего ответа.
private struct ЛюбойЭлемент<Значение: Decodable>: Decodable {
    let значение: Значение?

    init(from decoder: Decoder) throws {
        значение = try? Значение(from: decoder)
    }
}

/// {ok, cities[], total}.
private struct ОтветГородов: Decodable {
    let ok: Bool
    let города: [КартаAPI.Город]
    let всего: Int?

    private enum Ключи: String, CodingKey {
        case ok, cities, total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        ok = ПоляКарты.да(c, .ok)
        let элементы = (try? c.decode([ЛюбойЭлемент<КартаAPI.Город>].self, forKey: .cities)) ?? []
        var были = Set<String>()
        var итог: [КартаAPI.Город] = []
        for элемент in элементы {
            guard let город = элемент.значение, были.insert(город.id).inserted else { continue }
            итог.append(город)
        }
        города = итог
        всего = ПоляКарты.целое(c, .total).flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// {ok, pins[]}.
private struct ОтветПинов: Decodable {
    let ok: Bool
    let пины: [КартаAPI.Пин]

    private enum Ключи: String, CodingKey {
        case ok, pins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        ok = ПоляКарты.да(c, .ok)
        let элементы = (try? c.decode([ЛюбойЭлемент<КартаAPI.Пин>].self, forKey: .pins)) ?? []
        var были = Set<String>()
        var итог: [КартаAPI.Пин] = []
        for элемент in элементы {
            guard let пин = элемент.значение, были.insert(пин.id).inserted else { continue }
            итог.append(пин)
        }
        пины = итог
    }
}
