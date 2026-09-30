import Foundation
import WebKit

/**
 ЗАПРОС ЛЕНТЫ: GET /api/listings.php?sort=reco&page=&per=&cat=&q=

 🔴 С КУКАМИ ВЕБ-СЕССИИ. Город, радиус и вход живут в сессии сайта (FeedSnapshot, «почему снимок присылает
 страница»), а она хранится в куках WKWebView, не в общем хранилище URLSession. Без них приложение получило бы
 ленту по умолчанию — астанинскую алматинцу. Поэтому перед каждым запросом берём куки kliko.kz у WebKit и
 кладём их в заголовок сами; своё хранилище куков у запроса выключено, чтобы ответ сервера не завёл вторую,
 отдельную сессию.

 Сырой ответ первой страницы без поиска и раздела отдаём наверх целиком (`сырое`): его кладут на диск
 (ListingsCache), и следующий запуск показывает ленту мгновенно и без сети.

 Этап 32 (владелец 25.09.2026): город в куках сайт НЕ держит — он живёт в localStorage страницы и уходит в каждый
 запрос ленты параметрами (_mkApiQS в js/marketplace-feed.min.js): city=<название>, без города — region=<ключ>, и
 district=<ключ>. Поэтому выбор города приложения (ВыборГорода) каждый запрос несёт так же — Запрос.где; по умолчанию
 это сохранённый выбор, а без рубильника Config.выборГорода — вся страна, как раньше.

 Этап 33 (владелец 25.09.2026): фильтры и сортировка — тоже параметрами _mkApiQS (Запрос.фильтры: sort, cond, verified,
 photo, pmin, pmax, brands, models, gear, fuel, ymin, ymax, rooms; марка, модель, коробка и топливо — из ссылки ленты и
 листа «Фильтры»), а лента берёт страницы по 48, как сайт (mkApiNext: per=48), и со второй страницы
 несёт gs — «снимок» первой страницы из её ответа (window._mkGoldSnap сайта), чтобы выдача не перетасовывалась между
 страницами. По умолчанию фильтров нет и sort=reco — запрос прежний.

 Порядок «Новые» (владелец 26.09.2026, по умолчанию, как <option value="date" selected> сайта): _mkApiQS шлёт для него
 sort=reco (СортировкаЛенты.параметр). Правка сервера 91 (29.09.2026): «новые + 3 ТОП через 10» (авто и недвижимость
 1 через 5, на главной — разделы по кругу) расставляет сервер, карточки приходят со slot; ТОП перемешан посевом seed.
 Старый сервер без slot — лента ставит ритм у себя (ЗолотойРитм, FeedRhythm.swift). Ссылка ?sort=new — date_desc сайта,
 «новые подряд» без ТОП: sort=new.
 */
enum ListingsAPI {
    enum Ошибка: Error {
        case сеть
        case статус(Int)
        case разбор
    }

    struct Запрос: Equatable {
        var page = 1
        var per = 24
        var cat = ""
        var q = ""
        /// Где искать (этап 32): город, регион или район — выбор, сохранённый на телефоне в момент создания запроса.
        var где = ГдеИскать.сохранённое()
        /// Фильтры и сортировка (этап 33); по умолчанию — ничего и sort=reco, как раньше.
        var фильтры = ФильтрыЛенты()
        /// gs из ответа первой страницы (этап 33) — уходит со второй страницы, как у сайта; nil или 0 — не шлём.
        var gs: Int?
        /// Режим «Аренда» (mkVertical('rent') сайта): intent=rent — _mkApiQS шлёт его, только если это rent или sale.
        var аренда = false
        /// Посев порядка платных (правка сервера 91): новый на каждое открытие и «потянуть вниз», тот же у следующих
        /// страниц — ТОП вперемешку при каждом обновлении, но без скачков при листании. nil — не шлём.
        var seed: Int?

        /// Ленту по умолчанию кладём на диск; поиск, разделы и фильтры — нет, они быстро устаревают и нужны реже.
        var поУмолчанию: Bool { page == 1 && cat.isEmpty && q.isEmpty && фильтры == ФильтрыЛенты() && !аренда }
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки ставим сами, из WebKit (см. выше)
        c.httpCookieStorage = nil
        c.urlCache = .shared                  // тот же большой кэш, что поднимает WebContainer
        return URLSession(configuration: c)
    }()

    /// `куки` — заголовки заранее: фоновая проверка сохранённых поисков (этап 12) берёт их у WebKit сама, с пределом
    /// по времени, и одни на все запросы; пустые — запрос без куков. nil — как раньше, у WebKit перед запросом.
    static func загрузить(_ з: Запрос, куки заданные: [String: String]? = nil) async throws -> (страница: ListingsPage, сырое: Data) {
        var запрос = URLRequest(url: адрес(з))
        запрос.httpShouldHandleCookies = false
        let заголовки: [String: String]
        if let заданные { заголовки = заданные } else { заголовки = await SiteSession.куки() }
        for (имя, значение) in заголовки { запрос.setValue(значение, forHTTPHeaderField: имя) }

        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await данныеСПовтором(запрос) } catch { throw Ошибка.сеть }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Ошибка.статус(http.statusCode)
        }
        /* Скорость: разбор страницы (48 карточек) — не на главной очереди. */
        let страница = try await разобратьВФоне(данные)
        return (страница, данные)
    }

    /// Скорость: GET ленты и карточки — ещё раз после короткой паузы, если сеть оборвалась (не ответ сервера). Отмена
    /// задачи (сменили раздел) — сразу наверх, без повтора.
    private static func данныеСПовтором(_ запрос: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await сессия.data(for: запрос)
        } catch let e as URLError where e.code != .cancelled && !Task.isCancelled
                    && (e.code == .networkConnectionLost || e.code == .timedOut || e.code == .cannotConnectToHost
                        || e.code == .dnsLookupFailed || e.code == .cannotFindHost) {
            try await Task.sleep(nanoseconds: 600_000_000)
            return try await сессия.data(for: запрос)
        }
    }

    /// Разбор вне главной очереди: nonisolated async уходит с MainActor.
    nonisolated static func разобратьВФоне(_ данные: Data) async throws -> ListingsPage {
        try разобрать(данные)
    }

    /// Адрес запроса ленты — как _mkApiQS сайта. Он же, без page, seed и gs, — ключ копии выдачи на диске (КэшВыдачи).
    static func адрес(_ з: Запрос) -> URL {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"),
                              resolvingAgainstBaseURL: false)!
        var поля = [URLQueryItem(name: "sort", value: з.фильтры.сортировка.параметр),    // «Новые» — reco, как у сайта
                    URLQueryItem(name: "page", value: String(з.page)),
                    URLQueryItem(name: "per", value: String(з.per))]
        поля.append(contentsOf: Self.параметрыРаздела(з.cat))   // этап 49: «Товары» — cats=, как vs=goods у сайта
        if !з.q.isEmpty { поля.append(URLQueryItem(name: "q", value: з.q)) }
        поля.append(contentsOf: з.где.параметры)          // этап 32: city= / region= / district=
        поля.append(contentsOf: з.фильтры.параметры)      // этап 33: cond, verified, photo, pmin, pmax, brands, models,
                                                          // gear, fuel, ymin, ymax, rooms
        if з.аренда { поля.append(URLQueryItem(name: "intent", value: "rent")) }     // «Аренда», как _mkApiQS
        if з.page > 1, let gs = з.gs, gs > 0 { поля.append(URLQueryItem(name: "gs", value: String(gs))) }
        if let seed = з.seed, seed > 0 { поля.append(URLQueryItem(name: "seed", value: String(seed))) }   // на всех страницах
        ч.queryItems = поля
        return ч.url!
    }

    /// Полная карточка: GET /api/listings.php?id=<номер> → {ok, item}. Тоже с куками: избранное и цена для вошедшего.
    static func объявление(_ id: String) async throws -> Listing {
        try await объявлениеСОтветом(id).товар
    }

    /// То же и сырой ответ целиком (этап 13): его кладёт на диск ListingDetailCache — копия для карточки без сети.
    /// `куки` — как у загрузить(_:куки:): фоновая проверка цены избранного (этап 21) берёт их у WebKit заранее, с
    /// пределом по времени; nil — у WebKit перед запросом, как раньше.
    static func объявлениеСОтветом(_ id: String, куки заданные: [String: String]? = nil) async throws -> (товар: Listing, сырое: Data) {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"),
                              resolvingAgainstBaseURL: false)!
        ч.queryItems = [URLQueryItem(name: "id", value: id)]
        var запрос = URLRequest(url: ч.url!)
        запрос.httpShouldHandleCookies = false
        let заголовки: [String: String]
        if let заданные { заголовки = заданные } else { заголовки = await SiteSession.куки() }
        for (имя, значение) in заголовки { запрос.setValue(значение, forHTTPHeaderField: имя) }

        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await данныеСПовтором(запрос) } catch { throw Ошибка.сеть }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Ошибка.статус(http.statusCode)
        }
        let товар: Listing
        do { товар = try JSONDecoder().decode(ListingEnvelope.self, from: данные).item } catch { throw Ошибка.разбор }
        if товар.id == id { полные.setObject(ЯщикТовара(товар), forKey: id as NSString) }
        return (товар: товар, сырое: данные)
    }

    /// Скорость: полные карточки, уже пришедшие за этот запуск, — в памяти. Открыли второй раз — описание, фото и
    /// продавец на экране сразу, свежий ответ догоняет. NSCache потокобезопасен и сам отдаёт память системе.
    private final class ЯщикТовара {
        let товар: Listing
        init(_ товар: Listing) { self.товар = товар }
    }
    private static let полные: NSCache<NSString, ЯщикТовара> = {
        let кэш = NSCache<NSString, ЯщикТовара>()
        кэш.countLimit = 300
        return кэш
    }()

    /// Полная карточка из памяти этого запуска или nil.
    static func готовая(_ id: String) -> Listing? {
        полные.object(forKey: id as NSString)?.товар
    }

    /// Выход из аккаунта — карточки с ценами и избранным прежнего человека больше не показываем.
    static func забытьГотовые() {
        полные.removeAllObjects()
    }

    static func разобрать(_ данные: Data) throws -> ListingsPage {
        do { return try JSONDecoder().decode(ListingsPage.self, from: данные) } catch { throw Ошибка.разбор }
    }

    /// MK_VSETS.goods главной (home.html, 26.09.2026): из чего состоит «Товары».
    static let наборТоваров = ["clothing", "home-garden", "kids", "sport", "hobby", "food-farm", "beauty"]

    /**
     Раздел ленты → параметры запроса — как _mkApiQS сайта (этап 49). «Товары» главной — не раздел дерева, а набор
     (mkHomeGo открывает его как vs=goods): у сайта это cats=clothing,home-garden,…; раздела «goods» сервер не знает, и
     прежний cat=goods давал не ту выдачу. Вакансии — cat=jobs и jkind=vacancy (mkVertical('jobs')). Прочие — cat=.
     */
    static func параметрыРаздела(_ раздел: String) -> [URLQueryItem] {
        guard !раздел.isEmpty else { return [] }
        if раздел == "goods" {
            return [URLQueryItem(name: "cats", value: наборТоваров.joined(separator: ","))]
        }
        var поля = [URLQueryItem(name: "cat", value: раздел)]
        if раздел == "jobs" { поля.append(URLQueryItem(name: "jkind", value: "vacancy")) }
        return поля
    }
}

/**
 ПОСЛЕДНЯЯ ЛЕНТА НА ДИСКЕ — как снимок превью (FeedStore), но целая страница из API.

 Один файл в Application Support, вне резервной копии. Срок — сутки, как у снимка: вчерашние цены на запуске —
 помощь, позавчерашние — обман. Стирается при выходе из аккаунта вместе со снимком (WebContainer, bye=1).
 */
enum ListingsCache {
    static let срок: TimeInterval = 24 * 3600

    private static var файл: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-listings.json")
    }

    static func сохранить(_ данные: Data) {
        guard let файл, данные.count <= 2 * 1024 * 1024 else { return }
        do {
            try данные.write(to: файл, options: .atomic)
            var значения = URLResourceValues()
            значения.isExcludedFromBackup = true
            var изменяемый = файл
            try? изменяемый.setResourceValues(значения)
        } catch {
            // Диск полон — лента на диске удобство, а не обязанность.
        }
    }

    static func прочитать() -> [Listing]? {
        guard let файл,
              let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey]),
              let когда = свойства.contentModificationDate,
              Date().timeIntervalSince(когда) <= срок,
              let данные = try? Data(contentsOf: файл),
              let страница = try? ListingsAPI.разобрать(данные),
              !страница.items.isEmpty else { return nil }
        return страница.items
    }

    static func стереть() {
        /* Скорость: вместе с лентой — копии выдач и полные карточки в памяти: они тоже прежнего человека. */
        КэшВыдачи.стереть()
        ListingsAPI.забытьГотовые()
        guard let файл else { return }
        try? FileManager.default.removeItem(at: файл)
    }
}

/**
 СКОРОСТЬ: ПЕРВАЯ СТРАНИЦА КАЖДОЙ ВЫДАЧИ НА ДИСКЕ (владелец 30.09.2026: «чтобы моментально открывалось независимо от сети»).

 Раздел, поиск, фильтры, «Аренда» — первая страница ответа лежит в Caches (система может её стереть — это копия, не
 данные), файл на выдачу: ключ — адрес запроса без page, seed и gs. Открыли выдачу снова — копия на экране сразу, а
 свежая подменяет её, как только придёт; нет сети — копия и строка «нет связи». Лента по умолчанию — как раньше, в
 ListingsCache. Срок — сутки, не больше 40 файлов (лишние — самые давние). Версия в имени папки: сменится формат —
 старые копии просто не найдутся. Чтение и запись — не на главной очереди.
 */
enum КэшВыдачи {
    static let срок: TimeInterval = 24 * 3600
    private static let предел = 40
    private static let размер = 2 * 1024 * 1024
    private static let очередь = DispatchQueue(label: "kz.kliko.feed-queries", qos: .utility)

    private static var папка: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("kliko-feed-queries-v1", isDirectory: true)
    }

    /// Ключ выдачи: адрес первой страницы без посева и снимка. FNV-1a — одинаковый между запусками (Hasher — нет).
    static func ключ(_ з: ListingsAPI.Запрос) -> String {
        var первая = з
        первая.page = 1
        первая.seed = nil
        первая.gs = nil
        var х: UInt64 = 0xcbf29ce484222325
        for байт in ListingsAPI.адрес(первая).absoluteString.utf8 {
            х ^= UInt64(байт)
            х = х &* 0x100000001b3
        }
        return String(х, radix: 16)
    }

    static func сохранить(_ данные: Data, ключ: String) {
        guard данные.count <= размер, let корень = папка else { return }
        очередь.async {
            let диск = FileManager.default
            do {
                try диск.createDirectory(at: корень, withIntermediateDirectories: true)
                try данные.write(to: корень.appendingPathComponent(ключ + ".json"), options: .atomic)
            } catch {
                return        // диск полон — копия удобство, а не обязанность
            }
            guard let файлы = try? диск.contentsOfDirectory(at: корень,
                                                           includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: [.skipsHiddenFiles]),
                  файлы.count > предел else { return }
            let поДате = файлы.map { файл -> (URL, Date) in
                let когда = (try? файл.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (файл, когда ?? .distantPast)
            }.sorted { $0.1 > $1.1 }
            for (файл, _) in поДате.dropFirst(предел) { try? диск.removeItem(at: файл) }
        }
    }

    /// Копия первой страницы этой выдачи, не старше суток и не пустая; иначе nil.
    static func прочитать(_ ключ: String) async -> [Listing]? {
        guard let корень = папка else { return nil }
        let файл = корень.appendingPathComponent(ключ + ".json")
        return await withCheckedContinuation { (готово: CheckedContinuation<[Listing]?, Never>) in
            очередь.async {
                guard let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey]),
                      let когда = свойства.contentModificationDate,
                      Date().timeIntervalSince(когда) <= срок,
                      let данные = try? Data(contentsOf: файл),
                      let страница = try? ListingsAPI.разобрать(данные),
                      !страница.items.isEmpty else {
                    готово.resume(returning: nil)
                    return
                }
                готово.resume(returning: страница.items)
            }
        }
    }

    static func стереть() {
        guard let корень = папка else { return }
        очередь.async { try? FileManager.default.removeItem(at: корень) }
    }
}
