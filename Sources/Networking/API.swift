import Foundation

enum APIError: Error { case badStatus(Int), decode, network }

/// Тонкий клиент к нашему PHP-API. URLSession по умолчанию хранит cookie-сессию —
/// поэтому после будущего входа авторизованные запросы «поедут» на тех же куках.
struct API {
    static let shared = API()
    // internal (не private): используется расширениями API+Chat / API+Escrow в других файлах
    let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 25
        c.httpCookieStorage = .shared
        return URLSession(configuration: c)
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Общие bearer-запросы (для чата/сделок поверх боевых эндпоинтов chat.php/dm.php/escrow.php)
    /// GET к <apiBase>/<path> с Authorization: Bearer, декод в T. JSON парсим даже при 4xx/5xx.
    func authedGET<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: Config.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        if let t = TokenStore.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw APIError.network }
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }
    /// POST JSON-тела к <apiBase>/<path> с Authorization: Bearer, декод в T.
    func authedPOST<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = TokenStore.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw APIError.network }
        do { return try decoder.decode(T.self, from: data) } catch { throw APIError.decode }
    }

    /// Лента: /api/listings.php?sort=reco&page=&per=&cat=&q=&city=
    func feed(page: Int = 1, per: Int = 24, cat: String = "", q: String = "", city: String = "", sort: String = "reco") async throws -> [MarketItem] {
        var comps = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)!
        var qi = [URLQueryItem(name: "sort", value: sort),
                  URLQueryItem(name: "page", value: String(page)),
                  URLQueryItem(name: "per", value: String(per))]
        if !cat.isEmpty  { qi.append(URLQueryItem(name: "cat",  value: cat)) }
        if !q.isEmpty    { qi.append(URLQueryItem(name: "q",    value: q)) }
        if !city.isEmpty { qi.append(URLQueryItem(name: "city", value: city)) }
        comps.queryItems = qi

        let (data, resp) = try await session.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do { return try decoder.decode(FeedResponse.self, from: data).items }
        catch { throw APIError.decode }
    }

    /// Один товар: /api/listings.php?id=<id> → {ok, item}
    func item(id: String) async throws -> MarketItem {
        var comps = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: id)]
        let (data, resp) = try await session.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do { return try decoder.decode(ItemResponse.self, from: data).item }
        catch { throw APIError.decode }
    }
}

struct ItemResponse: Decodable {
    let ok: Bool
    let item: MarketItem
}

// MARK: - Авторизация (api/mobile_auth.php, bearer-токен)
extension API {
    /// POST на токен-эндпоинт. Тело — JSON {action, ...}. Bearer добавляем, если есть токен.
    private func authRequest(action: String, fields: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/mobile_auth.php"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = fields; payload["action"] = action
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        if let t = TokenStore.shared.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }

    /// Выполнить и распарсить AuthResponse. JSON парсим даже при 4xx/5xx —
    /// чтобы показать «неверный пароль» / «техработы», а не глухую ошибку статуса.
    private func runAuth(_ req: URLRequest) async throws -> AuthResponse {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data: Data
        do { (data, _) = try await session.data(for: req) }
        catch { throw APIError.network }
        if let r = try? decoder.decode(AuthResponse.self, from: data) { return r }
        throw APIError.decode
    }

    func login(phone: String, password: String) async throws -> AuthResponse {
        try await runAuth(authRequest(action: "login", fields: ["phone": phone, "password": password]))
    }

    func register(phone: String, name: String) async throws -> AuthResponse {
        try await runAuth(authRequest(action: "register", fields: ["phone": phone, "name": name]))
    }

    /// Проверка/подтягивание профиля по сохранённому токену.
    func me() async throws -> AuthResponse {
        try await runAuth(authRequest(action: "me"))
    }

    /// Отзыв текущего токена на сервере (best-effort — локально чистим в любом случае).
    func logout() async {
        _ = try? await runAuth(authRequest(action: "logout"))
    }
}
