import Foundation

/// Всё про OLX.kz: номера объявлений, поиск, карточка по номеру, фильтры турбо, рубрики.
/// Запросы идут прямо с телефона — как обычный просмотр сайта, без подмены и обходов.
///
/// Короткий код в ссылке — номер объявления в 62-ричной записи: «IDr9sfK» = 401214632.
enum OLX {
    static let base = "https://www.olx.kz"
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    enum Failure: LocalizedError {
        case blocked(Int)
        case http(Int)
        case badURL

        var errorDescription: String? {
            switch self {
            case .blocked(let code): return "OLX ответил \(code) — ограничил запросы"
            case .http(let code): return "OLX ответил \(code)"
            case .badURL: return "Нужна ссылка на поиск olx.kz"
            }
        }
    }

    // MARK: — номера

    static func decode(_ code: String) -> Int? {
        var n = 0
        for ch in code {
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            n = n * 62 + v
        }
        return n
    }

    static func encode(_ number: Int) -> String {
        var n = number
        var s = ""
        repeat { s = String(alphabet[n % 62]) + s; n /= 62 } while n > 0
        return s
    }

    static func adId(fromURL url: String) -> Int? {
        if let code = firstMatch(#"-ID([0-9a-zA-Z]+)\.html"#, in: url) { return decode(code) }
        if let num = firstMatch(#"#(\d{6,})$"#, in: url) { return Int(num) }
        return nil
    }

    // MARK: — сеть

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["Accept-Language": "ru-RU,ru;q=0.9,kk;q=0.8"]
        return URLSession(configuration: c)
    }()

    private static func get(_ url: URL, accept: String) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Ссылка поиска, развёрнутая «сначала новые».
    static func newestFirst(_ raw: String) throws -> URL {
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, host == "olx.kz" || host.hasSuffix(".olx.kz") else { throw Failure.badURL }
        var items = (c.queryItems ?? []).filter { $0.name != "search[order]" }
        items.append(URLQueryItem(name: "search[order]", value: "created_at:desc"))
        c.queryItems = items
        c.fragment = nil
        c.scheme = "https"
        guard let url = c.url else { throw Failure.badURL }
        return url
    }

    static func search(_ raw: String) async throws -> [Ad] {
        let (data, code) = try await get(try newestFirst(raw), accept: "text/html")
        if code == 403 || code == 429 { throw Failure.blocked(code) }
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        return parseSearch(String(decoding: data, as: UTF8.self))
    }

    /// Карточка по номеру. nil — такого номера на OLX.kz нет (не создан, удалён, другая страна).
    static func offer(_ id: Int) async throws -> Ad? {
        guard let url = URL(string: "\(base)/api/v1/offers/\(id)/") else { return nil }
        let (data, code) = try await get(url, accept: "application/json")
        if code == 404 || code == 410 { return nil }
        if code == 403 || code == 429 { throw Failure.blocked(code) }
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return normalizeOffer((json["data"] as? [String: Any]) ?? json)
    }

    // MARK: — разбор выдачи

    /// Сайт кладёт данные страницы в window.__PRERENDERED_STATE__ — JSON внутри JS-строки.
    /// Нет его — берём хотя бы номера из ссылок на объявления.
    static func parseSearch(_ html: String) -> [Ad] {
        if let literal = firstMatch(#"window\.__PRERENDERED_STATE__\s*=\s*("(?:[^"\\]|\\.)*")"#, in: html, dotAll: true),
           let inner = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String,
           let state = try? JSONSerialization.jsonObject(with: Data(inner.utf8)),
           let raw = findAds(state, depth: 0), !raw.isEmpty {
            return raw.compactMap(normalizeListing)
        }
        var seen = Set<Int>()
        var out: [Ad] = []
        for code in allMatches(#"-ID([0-9a-zA-Z]+)\.html"#, in: html) {
            guard let id = decode(code), seen.insert(id).inserted else { continue }
            out.append(Ad(id: id, url: "\(base)/d/obyavlenie/-ID\(code).html"))
        }
        return out
    }

    private static func findAds(_ node: Any, depth: Int) -> [[String: Any]]? {
        if depth > 6 { return nil }
        if let list = node as? [Any] {
            let dicts = list.compactMap { $0 as? [String: Any] }
            if !dicts.isEmpty, dicts.count == list.count,
               dicts.allSatisfy({ $0["id"] != nil && ($0["title"] != nil || $0["url"] != nil) }) { return dicts }
            return nil
        }
        guard let dict = node as? [String: Any] else { return nil }
        if let ads = dict["ads"], let r = findAds(ads, depth: depth + 1) { return r }
        for value in dict.values {
            if let r = findAds(value, depth: depth + 1) { return r }
        }
        return nil
    }

    private static func normalizeListing(_ a: [String: Any]) -> Ad? {
        guard let id = int(a["id"]) else { return nil }
        var ad = Ad(id: id)
        ad.title = a["title"] as? String ?? ""
        ad.url = a["url"] as? String ?? ""
        let price = a["price"] as? [String: Any] ?? [:]
        ad.price = double((price["regularPrice"] as? [String: Any])?["value"] ?? price["value"])
        ad.priceLabel = price["displayValue"] as? String ?? price["label"] as? String ?? ""
        let loc = a["location"] as? [String: Any] ?? [:]
        ad.city = loc["cityName"] as? String ?? (loc["city"] as? [String: Any])?["name"] as? String ?? ""
        ad.categoryId = int((a["category"] as? [String: Any])?["id"] ?? a["categoryId"])
        ad.createdAt = date(a["createdTime"] ?? a["created_time"])
        let promo = a["promotion"] as? [String: Any] ?? [:]
        ad.promoted = bool(a["isPromoted"]) || bool(promo["top_ad"]) || bool(promo["highlighted"])
        ad.business = bool(a["isBusiness"]) || bool(a["business"])
        ad.userId = string((a["user"] as? [String: Any])?["id"] ?? a["userId"])
        ad.photo = photoURL((a["photos"] as? [Any])?.first)
        return ad
    }

    private static func normalizeOffer(_ o: [String: Any]) -> Ad? {
        guard let id = int(o["id"]) else { return nil }
        var ad = Ad(id: id)
        ad.title = o["title"] as? String ?? ""
        ad.url = o["url"] as? String ?? ""
        ad.description = String(stripHTML(o["description"] as? String ?? "").prefix(600))
        for p in (o["params"] as? [[String: Any]]) ?? [] {
            let value = p["value"] as? [String: Any] ?? [:]
            if (p["key"] as? String) == "price" || (p["type"] as? String) == "price" {
                ad.price = double(value["value"])
                ad.priceLabel = value["label"] as? String ?? ""
            } else if ad.params.count < 6 {
                let label = value["label"] as? String ?? string(value["value"]) ?? ""
                ad.params.append("\(p["name"] as? String ?? ""): \(label)")
            }
        }
        let loc = o["location"] as? [String: Any] ?? [:]
        ad.city = (loc["city"] as? [String: Any])?["name"] as? String ?? ""
        ad.region = (loc["region"] as? [String: Any])?["name"] as? String ?? ""
        ad.categoryId = int((o["category"] as? [String: Any])?["id"])
        ad.createdAt = date(o["created_time"])
        ad.status = o["status"] as? String ?? ""
        let promo = o["promotion"] as? [String: Any] ?? [:]
        ad.promoted = bool(promo["top_ad"]) || bool(promo["highlighted"])
        ad.business = bool(o["business"])
        let user = o["user"] as? [String: Any] ?? [:]
        ad.userId = string(user["id"])
        ad.userName = user["name"] as? String ?? ""
        ad.photo = photoURL((o["photos"] as? [Any])?.first)
        return ad
    }

    // MARK: — фильтры турбо

    struct Filters: Equatable {
        var words: [String] = []
        var priceFrom: Double?
        var priceTo: Double?
    }

    /// Из ссылки: слова (/q-hp-250/ или search[q]) и цена от/до.
    static func filters(from raw: String) -> Filters {
        guard let c = URLComponents(string: raw) else { return Filters() }
        let path = c.path.removingPercentEncoding ?? c.path
        let q = firstMatch(#"/q-([^/]+)/?"#, in: path).map { $0.replacingOccurrences(of: "-", with: " ") }
            ?? c.queryItems?.first(where: { $0.name == "search[q]" })?.value ?? ""
        let words = q.lowercased().split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 1 }
        let from = c.queryItems?.first(where: { $0.name == "search[filter_float_price:from]" })?.value.flatMap { Double($0) }
        let to = c.queryItems?.first(where: { $0.name == "search[filter_float_price:to]" })?.value.flatMap { Double($0) }
        return Filters(words: words, priceFrom: from, priceTo: to)
    }

    static func matches(_ sub: Sub, _ ad: Ad) -> Bool {
        let f = filters(from: sub.url)
        let text = (ad.title + " " + ad.description).lowercased()
        if !f.words.allSatisfy({ text.contains($0) }) { return false }
        if let from = f.priceFrom, let p = ad.price, p < from { return false }
        if let to = f.priceTo, let p = ad.price, p > to { return false }
        if !sub.learnedCategories.isEmpty, let cat = ad.categoryId, !sub.learnedCategories.contains(cat) { return false }
        if sub.learnedTotal >= 20, sub.learnedCities.count == 1, !ad.city.isEmpty, ad.city != sub.learnedCities[0] { return false }
        // Без слов и без выученных рубрик турбо не шлёт — иначе полетит весь OLX.
        if f.words.isEmpty && sub.learnedCategories.isEmpty { return false }
        return true
    }

    // MARK: — рубрики и ссылка из выбранного

    struct Category: Hashable, Identifiable {
        var name: String
        var path: String
        var id: String { path }
    }

    static let topCategories: [Category] = [
        ("Электроника", "elektronika"), ("Транспорт", "transport"), ("Запчасти для транспорта", "zapchasti-dlya-transporta"),
        ("Недвижимость", "nedvizhimost"), ("Дом и сад", "dom-i-sad"), ("Мода и стиль", "moda-i-stil"),
        ("Детский мир", "detskiy-mir"), ("Хобби, отдых и спорт", "hobbi-otdyh-i-sport"), ("Животные", "zhivotnye"),
        ("Работа", "rabota"), ("Услуги", "uslugi"), ("Отдам даром", "otdam-darom"),
    ].map { Category(name: $0.0, path: $0.1) }

    struct City: Hashable {
        var name: String
        var slug: String
    }

    static let cities: [City] = [
        ("Алматы", "almaty"), ("Астана", "astana"), ("Шымкент", "shymkent"), ("Караганда", "karaganda"),
        ("Актобе", "aktobe"), ("Тараз", "taraz"), ("Павлодар", "pavlodar"), ("Усть-Каменогорск", "ust-kamenogorsk"),
        ("Семей", "semey"), ("Костанай", "kostanay"), ("Атырау", "atyrau"), ("Актау", "aktau"),
        ("Уральск", "uralsk"), ("Кызылорда", "kyzylorda"), ("Петропавловск", "petropavlovsk"), ("Талдыкорган", "taldykorgan"),
    ].map { City(name: $0.0, slug: $0.1) }

    /// Подрубрики на уровень ниже. Сначала — с самого OLX (ссылки и данные страницы), иначе —
    /// встроенный список. note — почему список не с OLX (показываем человеку).
    static func subcategories(of path: String) async -> (list: [Category], note: String) {
        guard let url = URL(string: "\(base)/d/\(path)/") else { return (fallbackSubcategories[path] ?? [], "") }
        var note = ""
        do {
            let (data, code) = try await get(url, accept: "text/html")
            if (200..<300).contains(code) {
                let html = String(decoding: data, as: UTF8.self)
                var found = parseSubcategories(html, parent: path)
                if found.isEmpty { found = subcategoriesFromState(html, parent: path) }
                if !found.isEmpty { return (found, "") }
                note = "OLX не показал подрубрики на странице — встроенный список"
            } else {
                note = "OLX ответил \(code) — встроенный список подрубрик"
            }
        } catch {
            note = "Нет связи с OLX — встроенный список подрубрик"
        }
        return (fallbackSubcategories[path] ?? [], note)
    }

    /// Подрубрики из данных страницы (window.__PRERENDERED_STATE__): ищем любые объекты, где
    /// есть ссылка вида /d/<рубрика>/<подрубрика>/ и название рядом с ней.
    static func subcategoriesFromState(_ html: String, parent: String) -> [Category] {
        guard let literal = firstMatch(#"window\.__PRERENDERED_STATE__\s*=\s*("(?:[^"\\]|\\.)*")"#, in: html, dotAll: true),
              let inner = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String,
              let state = try? JSONSerialization.jsonObject(with: Data(inner.utf8)) else { return [] }
        let citySlugs = Set(cities.map(\.slug))
        let depth = parent.split(separator: "/").count + 1
        var out: [Category] = []
        var seen = Set<String>()
        func walk(_ node: Any, _ level: Int) {
            if level > 12 || out.count >= 40 { return }
            if let list = node as? [Any] { list.forEach { walk($0, level + 1) }; return }
            guard let d = node as? [String: Any] else { return }
            let link = ["url", "href", "path", "link", "searchUrl", "normalizedUrl"].lazy.compactMap { d[$0] as? String }.first
            let name = ["name", "label", "title", "displayName"].lazy.compactMap { d[$0] as? String }.first
            if let link, let name, let slug = firstMatch(#"/d/(?:kk/)?([a-z0-9-]+(?:/[a-z0-9-]+)*)/?"#, in: link) {
                let parts = slug.split(separator: "/")
                if parts.count == depth, slug.hasPrefix(parent + "/"), let last = parts.last.map(String.init),
                   !citySlugs.contains(last), !last.hasPrefix("q-"), seen.insert(slug).inserted, !name.isEmpty, name.count <= 60 {
                    out.append(Category(name: name, path: slug))
                }
            }
            d.values.forEach { walk($0, level + 1) }
        }
        walk(state, 0)
        return out
    }

    /// Запасной список — основные подрубрики OLX.kz. Если какая-то ссылка устарела, поиск
    /// покажет ошибку под собой (первый проход идёт сразу при добавлении).
    static let fallbackSubcategories: [String: [Category]] = {
        let raw: [String: [(String, String)]] = [
            "elektronika": [
                ("Телефоны и аксессуары", "telefony-i-aksesuary"), ("Компьютеры и комплектующие", "kompyutery-i-komplektuyuschie"),
                ("Ноутбуки и аксессуары", "noutbuki-i-aksesuary"), ("Планшеты, эл. книги", "planshety-el-knigi-i-aksessuary"),
                ("ТВ и видеотехника", "tv-videotehnika"), ("Аудиотехника", "audiotehnika"),
                ("Игры и приставки", "igry-i-igrovye-pristavki"), ("Фото и видео", "foto-video"),
                ("Техника для дома", "tehnika-dlya-doma"), ("Техника для кухни", "tehnika-dlya-kuhni"),
                ("Климатическое оборудование", "klimaticheskoe-oborudovanie"), ("Индивидуальный уход", "individualnyy-uhod"),
                ("Прочая электроника", "prochaja-electronika"),
            ],
            "transport": [
                ("Легковые автомобили", "legkovye-avtomobili"), ("Грузовые автомобили", "gruzovye-avtomobili"),
                ("Мото", "moto"), ("Спецтехника", "spetstehnika"), ("Сельхозтехника", "selhoztehnika"),
                ("Автобусы", "avtobusy"), ("Водный транспорт", "vodnyy-transport"), ("Прицепы", "pritsepy-doma-na-kolesah"),
                ("Другой транспорт", "drugoy-transport"),
            ],
            "zapchasti-dlya-transporta": [
                ("Автозапчасти", "avtozapchasti"), ("Шины, диски и колёса", "shiny-diski-i-kolesa"),
                ("Аксессуары для авто", "aksessuary-dlya-avto"), ("Мотозапчасти", "motozapchasti"),
                ("Запчасти для спецтехники", "zapchasti-dlya-spetstehniki"),
            ],
            "nedvizhimost": [
                ("Квартиры", "kvartiry"), ("Дома", "doma"), ("Земля", "zemlya"), ("Коммерческая", "kommercheskaya-nedvizhimost"),
                ("Посуточно", "posutochno-pochasovo"), ("Гаражи и парковки", "garazhy-parkovki"),
            ],
            "dom-i-sad": [
                ("Мебель", "mebel"), ("Предметы интерьера", "predmety-interera"), ("Строительство и ремонт", "stroitelstvo-remont"),
                ("Инструменты", "instrumenty"), ("Сад и огород", "sad-ogorod"), ("Посуда", "posuda-kuhonnaya-utvar"),
                ("Хозинвентарь", "hozyaystvennyy-inventar"), ("Прочее для дома", "prochie-tovary-dlya-doma"),
            ],
            "moda-i-stil": [
                ("Женская одежда", "zhenskaya-odezhda"), ("Мужская одежда", "muzhskaya-odezhda"),
                ("Женская обувь", "zhenskaya-obuv"), ("Мужская обувь", "muzhskaya-obuv"),
                ("Аксессуары", "aksessuary"), ("Наручные часы", "naruchnye-chasy"), ("Красота и здоровье", "krasota-zdorove"),
            ],
            "detskiy-mir": [
                ("Детская одежда", "detskaya-odezhda"), ("Детская обувь", "detskaya-obuv"), ("Игрушки", "igrushki"),
                ("Коляски", "detskie-kolyaski"), ("Детская мебель", "detskaya-mebel"), ("Автокресла", "detskie-avtokresla"),
            ],
            "hobbi-otdyh-i-sport": [
                ("Спорт и отдых", "sport-otdyh"), ("Велосипеды", "velo"), ("Музыкальные инструменты", "muzykalnye-instrumenty"),
                ("Книги и журналы", "knigi-zhurnaly"), ("Антиквариат и коллекции", "antikvariat-kollektsii"),
                ("Туризм", "turizm"), ("Рыбалка и охота", "ohota-rybalka"),
            ],
            "zhivotnye": [
                ("Собаки", "sobaki"), ("Кошки", "koshki"), ("Птицы", "ptitsy"), ("Аквариумистика", "akvariumnye-rybki"),
                ("Сельхоз животные", "selskohozyaystvennye-zhivotnye"), ("Зоотовары", "zootovary"),
            ],
        ]
        var out: [String: [Category]] = [:]
        for (parent, list) in raw {
            out[parent] = list.map { Category(name: $0.0, path: "\(parent)/\($0.1)") }
        }
        return out
    }()

    static func parseSubcategories(_ html: String, parent: String) -> [Category] {
        let citySlugs = Set(cities.map(\.slug))
        let skip: Set<String> = ["obyavlenie", "kk", "list", "myaccount", "account", "post-new-ad"]
        let depth = parent.split(separator: "/").count + 1
        let pattern = #"<a\b[^>]*href="(?:https?://(?:www\.)?olx\.kz)?/d/(?:kk/)?([a-z0-9-]+(?:/[a-z0-9-]+)*)/?(?:\?[^"]*)?"[^>]*>(.*?)</a>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        var out: [Category] = []
        var seen = Set<String>()
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let p = ns.substring(with: m.range(at: 1)).lowercased()
            let parts = p.split(separator: "/")
            guard parts.count == depth, p.hasPrefix(parent + "/"), let last = parts.last.map(String.init),
                  !citySlugs.contains(last), !skip.contains(last), !last.hasPrefix("q-"), seen.insert(p).inserted else { continue }
            var name = stripHTML(ns.substring(with: m.range(at: 2)))
            name = name.replacingOccurrences(of: #"\s*\d[\d\s]*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.count <= 60 else { continue }
            out.append(Category(name: name, path: p))
        }
        return Array(out.prefix(40))
    }

    static func buildSearchURL(path: String?, city: String?, words: String, priceFrom: Int?, priceTo: Int?) -> String {
        var url = "\(base)/d/"
        if let path, !path.isEmpty { url += "\(path)/" }
        if let city, !city.isEmpty { url += "\(city)/" }
        let q = words.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: "-")
        if !q.isEmpty { url += "q-\(q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q)/" }
        var items: [URLQueryItem] = []
        if let priceFrom { items.append(URLQueryItem(name: "search[filter_float_price:from]", value: String(priceFrom))) }
        if let priceTo { items.append(URLQueryItem(name: "search[filter_float_price:to]", value: String(priceTo))) }
        guard !items.isEmpty, var c = URLComponents(string: url) else { return url }
        c.queryItems = items
        return c.url?.absoluteString ?? url
    }

    // MARK: — мелочи

    private static func firstMatch(_ pattern: String, in text: String, dotAll: Bool = false) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: dotAll ? [.dotMatchesLineSeparators] : []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func photoURL(_ p: Any?) -> String {
        let link = (p as? String) ?? (p as? [String: Any])?["link"] as? String ?? (p as? [String: Any])?["url"] as? String ?? ""
        return link.replacingOccurrences(of: "{width}", with: "800").replacingOccurrences(of: "{height}", with: "600")
    }

    private static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private static func bool(_ v: Any?) -> Bool {
        (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false)
    }

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
