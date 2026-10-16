import Foundation

/**
 ОДНА СЕССИЯ ДЛЯ ЗАПРОСОВ К САЙТУ (владелец 16.10.2026: «вопросы по производительности — как ускорить и выжать
 максимум? чтобы он не тупил от слова совсем и моментально открывал всё»).

 Раньше у каждого API была своя URLSession: лента и карточка, витрина продавца и его отзывы, карта, избранное,
 подписки, связь с продавцом, доставка, аренда, вакансии. У каждой — свой пул соединений, и первый запрос каждой заново
 договаривался с сервером (DNS, TCP, TLS) — сотни миллисекунд на первом открытии экрана. Теперь сессия одна:
 соединение с kliko.kz, открытое лентой, тут же берут карточка, витрина и отзывы (HTTP/2 — много запросов по одному
 соединению).

 Куки — из WebKit (SiteSession): своих сессия не заводит и не ставит. Кэш — общий URLCache, который поднимает
 WebContainer. Что раньше задавала своя сессия API — Accept: application/json, срок 15 с, «без кэша», — теперь ставит
 каждый запрос сам: API держит у себя СетьСайта.Запросы с этими настройками, и вызовы data(for:) остаются прежними.
 HomeAPI, разбор объявления, чат объявления и эфемерные сессии — свои, как были.
 */
enum СетьСайта {
    /// Общая сессия запросов к сайту.
    static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.urlCache = .shared                  // тот же большой кэш, что поднимает WebContainer
        return URLSession(configuration: c)
    }()

    /// Запросы одного API через общую сессию — с тем, что раньше задавала его своя: Accept JSON, срок, политика кэша.
    struct Запросы: Sendable {
        /// Accept: application/json, если запрос не задал свой (как httpAdditionalHeaders своей сессии).
        let json: Bool
        /// Срок ответа, с; nil — общий (20 с). Запрос со своим сроком его не теряет.
        let срок: TimeInterval?
        /// Без локального кэша (requestCachePolicy своей сессии), если запрос не задал свою политику.
        let безКэша: Bool

        init(json: Bool = true, срок: TimeInterval? = nil, безКэша: Bool = false) {
            self.json = json
            self.срок = срок
            self.безКэша = безКэша
        }

        func data(for запрос: URLRequest) async throws -> (Data, URLResponse) {
            var з = запрос
            if json && з.value(forHTTPHeaderField: "Accept") == nil {
                з.setValue("application/json", forHTTPHeaderField: "Accept")
            }
            /* 60 с — срок URLRequest по умолчанию: запрос свой срок не задавал. */
            if let срок, з.timeoutInterval == 60 { з.timeoutInterval = срок }
            if безКэша && з.cachePolicy == .useProtocolCachePolicy { з.cachePolicy = .reloadIgnoringLocalCacheData }
            return try await СетьСайта.сессия.data(for: з)
        }
    }
}
