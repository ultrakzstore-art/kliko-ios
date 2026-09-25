import Foundation

/**
 ЗАПРОСЫ ЧАТА: /dm.php поверх веб-сессии.

 list, poll — GET: только читают. open, send — POST: создают диалог и пишут сообщение, и потому несут CSRF-токен
 страницы (window.KlikoCsrf) — заголовком X-Kliko-Csrf и полем csrf, так же как регистрация пушей
 (WebContainer.registerPush). Без токена сайт отвечает {ok:false, error:'csrf'}, и молча считать это
 «отправлено» нельзя.

 🔴 КОНТРАКТ ИЗ ИЮЛЯ. dm.php в июле принимал bearer-токен приложения; сейчас приложение живёт на куках веб-сессии,
 как сама страница. Что dm.php отвечает на куки так же, проверено не было (кода сайта нет под рукой): отправка
 потому включается рубильником Config.нативныйЧатОтправка, а до проверки ответ пишется на сайте.
 */
enum ChatAPI {
    enum Ошибка: Error, Equatable {
        case сеть
        case нуженВход
        case статус(Int)
        case разбор
        case отказ(String)
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData    // переписка всегда свежая
        return URLSession(configuration: c)
    }()

    private static var адрес: URL { Config.apiBase.appendingPathComponent("dm.php") }

    // MARK: - Чтение

    static func диалоги() async throws -> [ЧатДиалог] {
        try await получить([URLQueryItem(name: "action", value: "list")]).диалоги
    }

    /// Снимок переписки; сервер заодно помечает её прочитанной.
    static func переписка(_ tid: String) async throws -> (ЧатПереписка?, заблокирован: Bool) {
        let ответ = try await получить([URLQueryItem(name: "action", value: "poll"), URLQueryItem(name: "tid", value: tid)])
        return (ответ.переписка, ответ.заблокирован)
    }

    // MARK: - Запись

    /// Открыть (или создать) диалог с собеседником, при необходимости — по объявлению.
    static func открыть(собеседник: String, объявление: String) async throws -> (ЧатПереписка?, заблокирован: Bool) {
        var поля: [String: Any] = ["action": "open", "peer_id": собеседник]
        if !объявление.isEmpty { поля["listing_id"] = объявление }
        let ответ = try await отправить(поля)
        return (ответ.переписка, ответ.заблокирован)
    }

    static func написать(tid: String, текст: String) async throws -> ЧатПереписка? {
        try await отправить(["action": "send", "thread_id": tid, "text": текст]).переписка
    }

    // MARK: - Транспорт

    private static func получить(_ поля: [URLQueryItem]) async throws -> ЧатОтвет {
        var ч = URLComponents(url: адрес, resolvingAgainstBaseURL: false)!
        ч.queryItems = поля
        var запрос = URLRequest(url: ч.url!)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        return try await выполнить(запрос)
    }

    private static func отправить(_ поля: [String: Any]) async throws -> ЧатОтвет {
        let состояние = await SiteSession.состояние()
        if состояние.вошёл == false { throw Ошибка.нуженВход }
        guard let csrf = состояние.csrf else { throw Ошибка.нуженВход }

        var тело = поля
        тело["csrf"] = csrf
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.setValue(csrf, forHTTPHeaderField: "X-Kliko-Csrf")
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.httpBody = try? JSONSerialization.data(withJSONObject: тело)
        return try await выполнить(запрос)
    }

    private static func выполнить(_ запрос: URLRequest) async throws -> ЧатОтвет {
        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(for: запрос) } catch { throw Ошибка.сеть }
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        if код == 401 || код == 403 { throw Ошибка.нуженВход }
        /* JSON разбираем и при 4xx: сайт объясняет отказ полем error («no_peer», «csrf», «auth»), а не кодом. */
        guard let разобранный = try? JSONDecoder().decode(ЧатОтвет.self, from: данные) else {
            if !(200..<300).contains(код) { throw Ошибка.статус(код) }
            throw Ошибка.разбор
        }
        if !разобранный.ok {
            let причина = разобранный.ошибка ?? ""
            if ["auth", "login", "unauthorized", "no_auth", "csrf"].contains(причина) { throw Ошибка.нуженВход }
            if !разобранный.заблокирован { throw Ошибка.отказ(причина) }
        }
        return разобранный
    }
}
