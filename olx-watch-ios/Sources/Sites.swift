import Foundation

/// Площадки кроме OLX: Kolesa.kz, Krisha.kz (один движок Kolesa Group) и Kaspi Объявления.
/// Как в боте: поиск «сначала новые», номера объявлений из ссылок выдачи, подробности — из
/// карточки (метки og и JSON-LD, которые сайты кладут для поисковиков). Новизна — по номеру:
/// новое для поиска — номер больше самого большого, что поиск уже видел. Турбо — только OLX.
/// Устройство этих сайтов изнутри не проверено — разбор написан по общим правилам.
enum Site: String, CaseIterable, Identifiable, Codable {
    case olx, kolesa, krisha, kaspi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .olx: return "OLX"
        case .kolesa: return "Kolesa"
        case .krisha: return "Krisha"
        case .kaspi: return "Kaspi Объявления"
        }
    }

    var emoji: String {
        switch self {
        case .olx: return "🟣"
        case .kolesa: return "🚗"
        case .krisha: return "🏠"
        case .kaspi: return "🔴"
        }
    }

    var host: String { "\(rawValue).kz" }
    var base: String { self == .kaspi ? "https://obyavleniya.kaspi.kz" : "https://\(host)" }

    /// Сдвиг номера в ленте: номера разных площадок могут совпасть, а лента общая.
    var idOffset: Int {
        switch self {
        case .olx: return 0
        case .kolesa: return 10_000_000_000
        case .krisha: return 20_000_000_000
        case .kaspi: return 30_000_000_000
        }
    }

    static func of(url: String) -> Site? {
        guard let host = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else { return nil }
        return allCases.first { host == $0.host || host.hasSuffix(".\($0.host)") }
    }

    static func of(adId: Int) -> Site {
        allCases.last { adId >= $0.idOffset } ?? .olx
    }

    /// Выбор кнопками. У Kaspi его нет — только ссылкой с сайта.
    var categories: [OLX.Category] {
        switch self {
        case .olx: return OLX.topCategories
        case .kolesa:
            let list: [(String, String)] = [("Легковые авто", "cars")] + Site.carBrands.map { ("Легковые › \($0.0)", "cars/\($0.1)") }
                + [("Мото", "moto"), ("Спецтехника", "spectehnika"), ("Запчасти", "zapchasti")]
            return list.map { OLX.Category(name: $0.0, path: $0.1) }
        case .krisha:
            let list: [(String, String)] = [("Продажа квартир", "prodazha/kvartiry"), ("Аренда квартир", "arenda/kvartiry"),
                                            ("Продажа домов", "prodazha/doma"), ("Аренда домов", "arenda/doma"), ("Участки", "prodazha/uchastkov")]
            return list.map { OLX.Category(name: $0.0, path: $0.1) }
        case .kaspi:
            // Ссылки Kaspi: obyavleniya.kaspi.kz/[город/]рубрика/…; без города — весь Казахстан.
            let list: [(String, String)] = [
                ("Электроника", "elektronika"), ("Электроника › Телефоны", "elektronika/telefony"),
                ("Электроника › Мобильные телефоны", "elektronika/telefony/mobilnye-telefony"),
                ("Электроника › Компьютеры", "elektronika/computery"), ("Электроника › Ноутбуки", "elektronika/computery/noutbuki"),
                ("Электроника › Техника для дома", "elektronika/tehnika-dlya-doma"),
                ("Apple", "apple"), ("Apple › iPhone", "apple/iphones"), ("Apple › MacBook и компьютеры", "apple/apple-computers"),
                ("Дом и дача", "dom-dacha"), ("Дом и дача › Мебель и интерьер", "dom-dacha/mebel-interer"),
                ("Животные", "zhivotnye"), ("Личные вещи", "lichnye-vezchi"), ("Прокат и аренда", "prokat-i-arenda"),
                ("Услуги", "uslugi"), ("Бизнес и оборудование", "biznes"),
            ]
            return list.map { OLX.Category(name: $0.0, path: $0.1) }
        }
    }

    /// Марки Kolesa: адрес вида /cars/toyota/. Модель — ссылкой с сайта.
    static let carBrands: [(String, String)] = [
        ("Toyota", "toyota"), ("Lexus", "lexus"), ("Hyundai", "hyundai"), ("Kia", "kia"), ("Chevrolet", "chevrolet"),
        ("Volkswagen", "volkswagen"), ("Mercedes-Benz", "mercedes-benz"), ("BMW", "bmw"), ("Audi", "audi"), ("Nissan", "nissan"),
        ("Mitsubishi", "mitsubishi"), ("Honda", "honda"), ("ВАЗ (Lada)", "vaz"), ("Subaru", "subaru"), ("Mazda", "mazda"),
        ("Skoda", "skoda"), ("Ford", "ford"), ("Renault", "renault"), ("Daewoo", "daewoo"), ("Geely", "geely"),
        ("Chery", "chery"), ("Haval", "haval"), ("Changan", "changan"), ("Land Rover", "land-rover"),
    ]

    private static let kolesaCityList: [(String, String)] = [
        ("Алматы", "almaty"), ("Астана", "astana"), ("Шымкент", "shymkent"), ("Караганда", "karaganda"),
        ("Актобе", "aktobe"), ("Тараз", "taraz"), ("Павлодар", "pavlodar"), ("Усть-Каменогорск", "ust-kamenogorsk"),
        ("Семей", "semey"), ("Костанай", "kostanay"), ("Атырау", "atyrau"), ("Актау", "aktau"),
    ]
    static let kolesaCities: [OLX.City] = kolesaCityList.map { OLX.City(name: $0.0, slug: $0.1) }

    var cities: [OLX.City] { self == .olx ? OLX.cities : Site.kolesaCities }

    func buildSearchURL(path: String?, city: String?, words: String, priceFrom: Int?, priceTo: Int?, extra: [String: String] = [:]) -> String {
        if self == .olx { return OLX.buildSearchURL(path: path, city: city, words: words, priceFrom: priceFrom, priceTo: priceTo) }
        if self == .kaspi {
            var url = base + "/"
            if let city, !city.isEmpty { url += "\(city)/" }
            url += "\(path ?? "elektronika")/"
            let q = words.trimmingCharacters(in: .whitespaces).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
            if !q.isEmpty { url += "k--\(q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q)/" }
            return url
        }
        var url = "\(base)/\(path ?? categories.first?.path ?? "")/"
        if let city, !city.isEmpty { url += "\(city)/" }
        let keys = self == .kolesa ? ("price[from]", "price[to]") : ("das[price][from]", "das[price][to]")
        var items: [URLQueryItem] = extra.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let priceFrom { items.append(URLQueryItem(name: keys.0, value: String(priceFrom))) }
        if let priceTo { items.append(URLQueryItem(name: keys.1, value: String(priceTo))) }
        guard !items.isEmpty, var c = URLComponents(string: url) else { return url }
        c.queryItems = items
        return c.url?.absoluteString ?? url
    }

    /// Ссылка поиска «сначала новые».
    func newestFirst(_ raw: String) throws -> URL {
        if self == .olx { return try OLX.newestFirst(raw) }
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), Site.of(url: raw) == self else {
            throw OLX.Failure.badURL
        }
        c.fragment = nil
        c.scheme = "https"
        if self != .kaspi {
            var items = (c.queryItems ?? []).filter { $0.name != "sort_by" }
            items.append(URLQueryItem(name: "sort_by", value: "add_date-desc"))
            c.queryItems = items
        }
        guard let url = c.url else { throw OLX.Failure.badURL }
        return url
    }

    func isAdURL(_ url: String) -> Bool {
        switch self {
        case .olx: return OLX.adId(fromURL: url) != nil
        case .kolesa, .krisha: return url.range(of: #"/a/show/\d+"#, options: .regularExpression) != nil
        case .kaspi:
            guard let path = URLComponents(string: url)?.path else { return false }
            return path.range(of: #"^/a/.+-\d{6,}/?$"#, options: .regularExpression) != nil
        }
    }

    // MARK: — сеть

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["Accept-Language": "ru-RU,ru;q=0.9,kk;q=0.8", "Accept": "text/html"]
        return URLSession(configuration: c)
    }()

    private static func html(_ url: URL) async throws -> String? {
        let (data, resp) = try await session.data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 || code == 410 { return nil }
        if code == 403 || code == 429 { throw OLX.Failure.blocked(code) }
        guard (200..<300).contains(code) else { throw OLX.Failure.http(code) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Kaspi: сортировка «сначала новые». Как она зовётся в ссылке, заранее неизвестно — ищем
    /// на первой странице выдачи (ссылка или пункт списка «Сначала новые» / «Новые» / «По дате»).
    /// nil — ещё не искали; ("", "") — искали, не нашлось.
    static var kaspiSort: (name: String, value: String)?
    private static let sortWords = #"(сначала\s+нов|нов(ые|ее|инки)|по\s+дат|свеж|недавн|newest|date)"#

    static func findSort(_ html: String) -> (name: String, value: String)? {
        let text = html.replacingOccurrences(of: "&amp;", with: "&")
        let ns = text as NSString
        let keys = #"(?:sort|order|sortBy|sort_by|orderBy)"#
        if let re = try? NSRegularExpression(pattern: #"<a\b[^>]*href=["']([^"']*[?&]"# + keys + #"=[^"']*)["'][^>]*>([\s\S]{0,120}?)</a>"#, options: [.caseInsensitive]) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                guard label.range(of: sortWords, options: [.regularExpression, .caseInsensitive]) != nil,
                      let u = URLComponents(string: ns.substring(with: m.range(at: 1))) else { continue }
                if let item = u.queryItems?.first(where: { $0.name.range(of: "^" + keys + "$", options: [.regularExpression, .caseInsensitive]) != nil }),
                   let v = item.value { return (item.name, v) }
            }
        }
        if let re = try? NSRegularExpression(pattern: #"<select\b[^>]*name=["']("# + keys + #")["'][^>]*>([\s\S]*?)</select>"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)), body = ns.substring(with: m.range(at: 2))
            let bns = body as NSString
            if let opt = try? NSRegularExpression(pattern: #"<option\b[^>]*value=["']([^"']+)["'][^>]*>([^<]*)<"#, options: [.caseInsensitive]) {
                for o in opt.matches(in: body, range: NSRange(location: 0, length: bns.length))
                where bns.substring(with: o.range(at: 2)).range(of: sortWords, options: [.regularExpression, .caseInsensitive]) != nil {
                    return (name, bns.substring(with: o.range(at: 1)))
                }
            }
        }
        return nil
    }

    private static func adding(_ sort: (name: String, value: String), to url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.queryItems = (c.queryItems ?? []).filter { $0.name != sort.name } + [URLQueryItem(name: sort.name, value: sort.value)]
        return c.url ?? url
    }

    /// Kaspi: «весь Казахстан» такой выдачи не имеет — ссылку без города обходим по городам по
    /// кругу, по 3 города за проверку. Список — крупные и средние города плюс все, на которые
    /// ссылается сама страница Kaspi; город, ответивший 404, выпадает из обхода.
    static let kaspiCitySlugs = ["almaty", "astana", "shymkent", "karaganda", "aktobe", "taraz", "pavlodar",
        "ust-kamenogorsk", "semey", "kostanay", "atyrau", "aktau", "uralsk", "kyzylorda", "petropavlovsk",
        "taldykorgan", "turkestan", "kokshetau", "ekibastuz", "temirtau", "zhezkazgan", "rudnyy", "balkhash",
        "satpaev", "kaskelen", "konaev", "zhanaozen", "aksay", "stepnogorsk", "shchuchinsk"]
    static var kaspiRounds: [String: (cities: [String], next: Int, seeded: Set<String>)] = [:]

    private static func kaspiSplit(_ url: URL) -> (city: String, path: String) {
        let parts = url.path.split(separator: "/").map(String.init)
        let known = Set(kaspiCitySlugs + kaspiRounds.values.flatMap { $0.cities })
        if parts.count > 1, known.contains(parts[0]) { return (parts[0], parts.dropFirst().joined(separator: "/")) }
        return ("", parts.joined(separator: "/"))
    }

    private func searchAllCities(_ url: URL, path: String) async throws -> [Ad] {
        let key = path + (url.query.map { "?" + $0 } ?? "")
        var r = Site.kaspiRounds[key] ?? (cities: Site.kaspiCitySlugs, next: 0, seeded: Set<String>())
        if Site.kaspiRounds[key] == nil, let page = try? await Site.html(url) {
            let esc = NSRegularExpression.escapedPattern(for: path)
            for c in Site.matches(#"(?:obyavleniya\.kaspi\.kz)?/([a-z][a-z0-9-]{2,30})/"# + esc + #"/?["'?#]"#, in: page)
            where !["a", "k", "api", "static", "img", "search"].contains(c.lowercased()) && !r.cities.contains(c.lowercased()) {
                r.cities.append(c.lowercased())
            }
        }
        var out: [Ad] = []
        for _ in 0..<3 where !r.cities.isEmpty {
            let city = r.cities[r.next % r.cities.count]
            r.next = (r.next + 1) % r.cities.count
            guard var c = URLComponents(string: "\(base)/\(city)/\(path)/") else { continue }
            c.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard let cityURL = c.url else { continue }
            do {
                let ads = try await searchOne(cityURL.absoluteString, pages: 1)
                let seed = !r.seeded.contains(city)
                r.seeded.insert(city)
                out += ads.map { var a = $0; a.anyOrder = true; if seed { a.seedOnly = true }; return a }
            } catch OLX.Failure.http(let code) where code == 404 {
                r.cities.removeAll { $0 == city }
            }
        }
        Site.kaspiRounds[key] = r
        return out
    }

    /// Выдача: номера (со сдвигом площадки) и ссылки. Подробности — отдельно, только для нового.
    func search(_ raw: String) async throws -> [Ad] {
        if self == .kaspi {
            let url = try newestFirst(raw)
            let split = Site.kaspiSplit(url)
            if split.city.isEmpty { return try await searchAllCities(url, path: split.path) }
        }
        return try await searchOne(raw)
    }

    private func searchOne(_ raw: String, pages: Int = 3) async throws -> [Ad] {
        if self == .olx { return try await OLX.search(raw) }
        var firstURL = try newestFirst(raw)
        let hasSort = firstURL.absoluteString.range(of: #"[?&](sort|order|sortBy|sort_by|orderBy)="#, options: [.regularExpression, .caseInsensitive]) != nil
        if self == .kaspi, !hasSort, let s = Site.kaspiSort, !s.name.isEmpty { firstURL = Site.adding(s, to: firstURL) }
        guard var page = try await Site.html(firstURL) else { throw OLX.Failure.http(404) }
        if self == .kaspi, Site.kaspiSort == nil {
            Site.kaspiSort = Site.findSort(page) ?? ("", "")
            if let s = Site.kaspiSort, !s.name.isEmpty, !hasSort {
                firstURL = Site.adding(s, to: firstURL)
                if let sorted = try await Site.html(firstURL) { page = sorted }
            }
        }
        // Kaspi: даже с сортировкой смотрим ещё 2 страницы — на случай продвигаемых сверху.
        if self == .kaspi, pages > 1 {
            for n in 2...pages {
                guard var c = URLComponents(url: firstURL, resolvingAgainstBaseURL: false) else { break }
                c.queryItems = (c.queryItems ?? []).filter { $0.name != "page" } + [URLQueryItem(name: "page", value: String(n))]
                guard let u = c.url, let more = try? await Site.html(u) else { break }
                page += more
            }
        }
        var out: [Ad] = []
        var seen = Set<Int>()
        func add(_ native: Int, _ url: String) {
            guard native > 0, seen.insert(native).inserted else { return }
            var ad = Ad(id: idOffset + native)
            ad.url = url
            ad.source = rawValue
            out.append(ad)
        }
        switch self {
        case .kolesa, .krisha:
            for m in Site.matches(#"/a/show/(\d{5,})"#, in: page) {
                if let n = Int(m) { add(n, "\(base)/a/show/\(n)") }
            }
        case .kaspi:
            // Объявление Kaspi: /a/<название>-<номер>/ (например /a/iphone-15-112633239/).
            for path in Site.matches(#"((?:https?://obyavleniya\.kaspi\.kz)?/a/[^"'#\s)?]*?-\d{6,}/?)(?=["'?#\s)])"#, in: page) {
                guard let u = URL(string: path, relativeTo: URL(string: base))?.absoluteURL,
                      let last = Site.matches(#"-(\d{6,})/?$"#, in: u.path).last, let n = Int(last) else { continue }
                add(n, "https://obyavleniya.kaspi.kz\(u.path)")
            }
        case .olx: break
        }
        return out
    }

    /// Карточка: заголовок, цена, город, фото, описание, дата — из меток og и JSON-LD.
    func detail(_ ad: Ad) async throws -> Ad? {
        if self == .olx { return try await OLX.offer(ad.id) }
        guard let url = URL(string: ad.url), let page = try await Site.html(url) else { return nil }
        return Site.parseDetail(page, id: ad.id, url: ad.url, source: self)
    }

    static func parseDetail(_ html: String, id: Int, url: String, source: Site) -> Ad {
        var ad = Ad(id: id)
        ad.url = url
        ad.source = source.rawValue
        let typeRe = "Product|Offer|Car|Vehicle|Apartment|House|Residence|Accommodation"
        let product: [String: Any]? = jsonLD(html).first { (x: [String: Any]) -> Bool in
            if x["offers"] != nil { return true }
            let type = x["@type"].map { String(describing: $0) } ?? ""
            return type.range(of: typeRe, options: .regularExpression) != nil
        }
        let offers = product?["offers"]
        let offer: [String: Any]? = (offers as? [[String: Any]])?.first ?? (offers as? [String: Any])
        ad.title = decode((product?["name"] as? String) ?? meta("og:title", in: html).first ?? matches(#"<title>([^<]*)</title>"#, in: html).first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ad.description = String(decode((product?["description"] as? String) ?? meta("og:description", in: html).first ?? meta("description", in: html).first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        var images: [String] = []
        if let img = product?["image"] {
            for i in (img as? [Any]) ?? [img] {
                if let s = i as? String { images.append(s) } else if let s = (i as? [String: Any])?["url"] as? String { images.append(s) }
            }
        }
        images += meta("og:image", in: html)
        var unique: [String] = []
        for i in images where !unique.contains(i) { unique.append(i) }
        ad.photo = unique.first ?? ""
        ad.photos = unique.isEmpty ? nil : Array(unique.prefix(12))
        var price = number(offer?["price"]) ?? number(offer?["lowPrice"])
        if price == nil,
           let raw = matches(#"(\d[\d\s ]{3,})\s*(?:₸|〒|тг|тенге|KZT)"#, in: "\(ad.title) \(ad.description)").first {
            price = Double(raw.filter(\.isNumber))
        }
        if let price, price > 0 {
            ad.price = price
            ad.priceLabel = "\(Int(price).formatted(.number.locale(Locale(identifier: "ru_RU")))) ₸"
        }
        let address = (product?["address"] as? [String: Any]) ?? ((offer?["availableAtOrFrom"] as? [String: Any])?["address"] as? [String: Any])
        ad.city = decode(address?["addressLocality"] as? String ?? "")
        if ad.city.isEmpty, let city = matches(#" в ([А-ЯЁ][а-яё-]+(?:\s[А-ЯЁ][а-яё-]+)?)\s*$"#, in: ad.title).first { ad.city = city }
        // Kolesa: подпись «Автосалон» / «Дилер» (с большой буквы, не «Автосалоны» из меню и не
        // «в автосалоне» из описания) или разметка AutoDealer — не хозяин; «Частное лицо» — хозяин.
        if source == .kolesa {
            if html.range(of: #""@type"\s*:\s*"(AutoDealer|AutomotiveBusiness|CarDealer)""#, options: [.regularExpression, .caseInsensitive]) != nil
                || html.range(of: #"(^|[>\s"])(Автосалон|Автодилер|Официальный дилер|Проверенный дилер|Дилл?ер)(?![а-яё])"#, options: .regularExpression) != nil {
                ad.owner = false
            } else if html.range(of: #"Частное\s+лицо|Собственник|Хозяин"#, options: [.regularExpression, .caseInsensitive]) != nil {
                ad.owner = true
            }
        // Krisha подписывает продавца: «Хозяин недвижимости» или «Агент» / «Специалист».
        } else if html.range(of: #"Хозяин\s+недвижимости"#, options: [.regularExpression, .caseInsensitive]) != nil {
            ad.owner = true
        } else if html.range(of: #"(^|[>\s])(Агент|Специалист|Агентство недвижимости|Риэлтор|Риелтор)([<\s,.]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            ad.owner = false
        }
        for key in ["datePosted", "datePublished"] {
            if let s = product?[key] as? String, let d = parseDate(s) { ad.createdAt = d; break }
        }
        if source == .kaspi { ad.crumbs = breadcrumbs(html, url: url) }
        return ad
    }

    /// Крошки карточки: сначала JSON-LD BreadcrumbList, иначе ссылки в блоке с «breadcrumb» в классе.
    /// Меню сайта не берём — оно ссылается на все рубрики.
    private static func breadcrumbs(_ html: String, url: String) -> [String] {
        var out: [String] = []
        func add(_ href: String) {
            guard let u = URL(string: decode(href), relativeTo: URL(string: url))?.absoluteURL else { return }
            let p = u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            if !p.isEmpty, !p.hasPrefix("a/"), !out.contains(p) { out.append(p) }
        }
        for x in jsonLD(html) where String(describing: x["@type"] ?? "").contains("BreadcrumbList") {
            for it in (x["itemListElement"] as? [[String: Any]]) ?? [] {
                if let s = it["item"] as? String { add(s) }
                else if let d = it["item"] as? [String: Any], let s = (d["@id"] as? String) ?? (d["url"] as? String) { add(s) }
                else if let s = it["url"] as? String { add(s) }
            }
        }
        if out.isEmpty, let block = matches(#"<(?:nav|ol|ul|div)\b[^>]*class=["'][^"']*breadcrumb[^"']*["'][^>]*>([\s\S]{0,4000}?)</(?:nav|ol|ul)>"#, in: html).first {
            for h in matches(#"href=["']([^"']+)["']"#, in: block) { add(h) }
        }
        return out
    }

    /// Kaspi по номеру: /a/<номер>/ открывает объявление без названия. Нет (или на проверке) — nil.
    static func kaspiById(_ n: Int) async throws -> Ad? {
        let link = "https://obyavleniya.kaspi.kz/a/\(n)/"
        guard let url = URL(string: link), let page = try await html(url) else { return nil }
        let ad = parseDetail(page, id: Site.kaspi.idOffset + n, url: link, source: .kaspi)
        guard !ad.title.isEmpty, ad.price != nil || !(ad.photos ?? []).isEmpty || !ad.photo.isEmpty else { return nil }
        return ad
    }

    /// Подходит ли объявление Kaspi, найденное по номеру, поиску: рубрика (по крошкам), город, слова.
    /// Не понятно — причина, и его принесёт обход выдачи.
    static func kaspiMismatch(_ sub: Sub, _ ad: Ad) -> String? {
        guard let u = URL(string: sub.url) else { return "ссылка поиска" }
        var parts = u.path.split(separator: "/").map(String.init)
        let cities = Set(kaspiCitySlugs + kaspiRounds.values.flatMap { $0.cities })
        var city = ""
        if parts.count > 1, cities.contains(parts[0]) { city = parts.removeFirst() }
        var words: [String] = []
        if let i = parts.firstIndex(where: { $0.hasPrefix("k--") }) {
            let raw = String(parts[i].dropFirst(3))
            words = (raw.removingPercentEncoding ?? raw).split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init)
            parts = Array(parts[..<i])
        }
        let path = parts.joined(separator: "/").lowercased()
        let crumbs = ad.crumbs ?? []
        if crumbs.isEmpty { return "рубрика объявления не видна" }
        var adCity = ""
        var cats: [String] = []
        for c in crumbs {
            let p = c.split(separator: "/").map(String.init)
            if p.count > 1, cities.contains(p[0]) {
                if adCity.isEmpty { adCity = p[0] }
                cats.append(p.dropFirst().joined(separator: "/"))
            } else {
                cats.append(c)
            }
        }
        if !path.isEmpty, !cats.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return "другая рубрика" }
        if !city.isEmpty {
            let same: Bool
            if !adCity.isEmpty {
                same = adCity == city
            } else if let name = kolesaCities.first(where: { $0.slug == city })?.name, !ad.city.isEmpty {
                same = ad.city.lowercased() == name.lowercased()
            } else {
                same = false
            }
            if !same { return adCity.isEmpty && ad.city.isEmpty ? "город объявления не виден" : "другой город" }
        }
        if !words.isEmpty {
            let text = (ad.title + " " + ad.description).lowercased()
            if let miss = words.first(where: { !text.contains(OLX.stem($0.lowercased())) }) { return "нет слова «\(miss)»" }
        }
        return nil
    }

    // MARK: — разбор

    private static func meta(_ prop: String, in html: String) -> [String] {
        let p = NSRegularExpression.escapedPattern(for: prop)
        let pattern = #"<meta[^>]+(?:property|name)=["']"# + p + #"["'][^>]*content=["']([^"']*)["']|<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']"# + p + #"["']"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m -> String? in
            for i in 1...2 where m.range(at: i).location != NSNotFound { return decode(ns.substring(with: m.range(at: i))) }
            return nil
        }
    }

    private static func jsonLD(_ html: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for body in matches(#"<script[^>]+type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html) {
            guard let v = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { continue }
            for x in (v as? [Any]) ?? [v] {
                guard let d = x as? [String: Any] else { continue }
                if let graph = d["@graph"] as? [[String: Any]] { out += graph } else { out.append(d) }
            }
        }
        return out
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: " ", with: "")) }
        return nil
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        return nil   // только дата без времени — не годится для «новое за минуту»
    }

    static func decode(_ s: String) -> String {
        var out = s
        for (a, b) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }
}
