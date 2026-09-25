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

        /// Ленту по умолчанию кладём на диск; поиск и разделы — нет, они быстро устаревают и нужны реже.
        var поУмолчанию: Bool { page == 1 && cat.isEmpty && q.isEmpty }
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

    static func загрузить(_ з: Запрос) async throws -> (страница: ListingsPage, сырое: Data) {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"),
                              resolvingAgainstBaseURL: false)!
        var поля = [URLQueryItem(name: "sort", value: "reco"),
                    URLQueryItem(name: "page", value: String(з.page)),
                    URLQueryItem(name: "per", value: String(з.per))]
        if !з.cat.isEmpty { поля.append(URLQueryItem(name: "cat", value: з.cat)) }
        if !з.q.isEmpty { поля.append(URLQueryItem(name: "q", value: з.q)) }
        ч.queryItems = поля

        var запрос = URLRequest(url: ч.url!)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await кукиСайта() { запрос.setValue(значение, forHTTPHeaderField: имя) }

        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(for: запрос) } catch { throw Ошибка.сеть }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Ошибка.статус(http.statusCode)
        }
        return (try разобрать(данные), данные)
    }

    static func разобрать(_ данные: Data) throws -> ListingsPage {
        do { return try JSONDecoder().decode(ListingsPage.self, from: данные) } catch { throw Ошибка.разбор }
    }

    /// Куки kliko.kz из WebKit — заголовком «Cookie». Хранилище WebKit живёт на главной нити.
    @MainActor
    private static func кукиСайта() async -> [String: String] {
        let все = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let наши = все.filter { кука in
            let домен = кука.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return домен == "kliko.kz" || домен == "www.kliko.kz"
        }
        return HTTPCookie.requestHeaderFields(with: наши)
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
        guard let файл else { return }
        try? FileManager.default.removeItem(at: файл)
    }
}
