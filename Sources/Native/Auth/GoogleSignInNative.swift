import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
import WebKit

/**
 ВХОД ЧЕРЕЗ GOOGLE — НАТИВНО, БЕЗ SDK (владелец 13.10.2026: «регистрация по гуглу»).

 Устройство — как у ВходApple (AppleSignInNative.swift), только лист другой:
 1. Системный лист входа (ASWebAuthenticationSession) открывает https://accounts.google.com/o/oauth2/v2/auth: iOS-клиент
    Google (Config.клиентGoogle), redirect_uri — обратная схема клиента «com.googleusercontent.apps.<id>:/oauth2redirect»,
    scope «openid email profile», PKCE S256, state и nonce. В Google уходит hex(sha256(nonce)), как в лист Apple.
 2. Код из возврата приложение само меняет на id_token: POST https://oauth2.googleapis.com/token (установленное
    приложение с PKCE — без секрета клиента). access_token не нужен и нигде не хранится.
 3. POST /google_auth.php?action=native {id_token, nonce (сырой), client_id, bundle_id, csrf?} с куками WebKit, без
    перенаправлений. {ok:true, uid} с Set-Cookie сессии — куки ложатся в WebKit (вход всего приложения) и в
    HTTPCookieStorage, дальше — как после входа паролем (КабинетСайта.послеВхода: витрина, чат и кабинет узнают сразу).
 4. need_phone — Google человека подтвердил, а аккаунта ещё нет: экран входа показывает шаг «Укажите номер», номер
    уходит POST /google_auth.php?action=phone {phone, code, csrf, agree} (отправитьНомер). Сервер может попросить код
    из SMS (need_code) — у поля кода .oneTimeCode, iOS подставит его сама.

 Страницы сайта для входа через Google нет, поэтому откат честный: пока iOS-клиента нет в Info.plist — кнопки нет
 (Config.входGoogle); сервер не отвечает на пробный запрос как надо (404, перенаправление, не JSON, «unsupported») —
 кнопки тоже нет (готов()); сервер перестал понимать посреди входа — «Вход через Google скоро заработает».
 Договор с сайтом — docs/SERVER_NATIVE_AUTH.md, раздел «Вход через Google». Токены и коды не пишутся в журнал.
 */
extension Config {
    /// iOS-клиент Google из Info.plist (ключ KlikoGoogleClientID в project.yml). Пусто, не подставлено или не похоже на
    /// «<номер>-<знаки>.apps.googleusercontent.com» — пусто: входа через Google нет.
    static var клиентGoogle: String {
        let сырое = (Bundle.main.object(forInfoDictionaryKey: "KlikoGoogleClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let хвост = ".apps.googleusercontent.com"
        guard !сырое.contains("$("), сырое.hasSuffix(хвост), сырое.count > хвост.count else { return "" }
        return сырое
    }

    /// Рубильник «Продолжить с Google»: выключен, пока владелец не впишет ID iOS-клиента Google (docs/SERVER_NATIVE_AUTH.md).
    static var входGoogle: Bool { !клиентGoogle.isEmpty }
}

@MainActor
enum ВходGoogle {

    enum Итог: Equatable {
        case вошёл
        /// Человек закрыл лист Google или уже идёт другой вход — ничего не показываем.
        case отменено
        /// Аккаунта ещё нет — шаг «Укажите номер».
        case нуженНомер(ЗапросНомераGoogle)
        case удалён(причина: String)
        case нуженEgov
        case ошибка(String)
        /// Сервер ещё не умеет вход через Google — кнопка прячется, на её месте «скоро».
        case скоро
    }

    /// Ответ сервера на пробный запрос: true — вход через Google есть, false — нет, nil — не спрашивали или не дозвались.
    /// Живёт до перезапуска приложения.
    private(set) static var серверГотов: Bool? = nil
    private static var проверка: Task<Bool?, Never>? = nil
    private static var занято = false
    /// Сессия и якорь живут, пока открыт лист входа Google.
    private static var сессия: ASWebAuthenticationSession? = nil
    private static var якорь: ЯкорьВходаGoogle? = nil
    /// need_phone принёс новые куки сессии: брошенный шаг номера перезагружает страницу под слоем (её токен — от прежней).
    private static var кукиОжидания = false

    // MARK: Готов ли сервер

    /// Показывать ли кнопку: iOS-клиент вписан и сервер отвечает на пустое тело JSON-отказом (не 404, не страницей).
    static func готов() async -> Bool {
        guard Config.входGoogle else { return false }
        if let известно = серверГотов { return известно }
        if let идёт = проверка { return await идёт.value ?? false }
        let задача = Task<Bool?, Never> { @MainActor in await опросить() }
        проверка = задача
        let ответ = await задача.value
        проверка = nil
        if let ответ { серверГотов = ответ }
        return ответ ?? false
    }

    /// Пробный запрос: пустое тело без кук. Договор: ответ 200 и {"ok":false,"error":"bad_token"} — только тогда кнопка.
    /// Любой другой JSON (403/400, csrf, «Unknown action», заглушка WAF или CDN) — сервер не готов; 5xx и 429 — не
    /// дозвались, спросим при следующем показе экрана.
    private static func опросить() async -> Bool? {
        switch await послать("/google_auth.php?action=native", тело: [:], сКуками: false) {
        case .json(let j, let http, _):
            if http.statusCode >= 500 || http.statusCode == 429 { return nil }
            return http.statusCode == 200 && !да(j["ok"]) && строка(j["error"]) == "bad_token"
        case .неУмеет: return false
        case .нетСвязи, .сбойСервера: return nil
        }
    }

    // MARK: Вход

    static func войти() async -> Итог {
        guard Config.входGoogle, !занято else { return .отменено }
        занято = true
        defer { занято = false }
        let клиент = Config.клиентGoogle
        let схема = обратнаяСхема(клиент)
        let возвратный = схема + ":/oauth2redirect"
        let проверочный = base64url(Data(случайныеБайты(32)))
        let вызов = base64url(Data(SHA256.hash(data: Data(проверочный.utf8))))
        let метка = hex(случайныеБайты(16))
        let сырой = hex(случайныеБайты(32))
        guard let адрес = адресGoogle(клиент: клиент, возврат: возвратный, вызов: вызов, метка: метка,
                                      nonce: sha256hex(сырой)),
              let окно = ключевоеОкно() else { return .ошибка(т("g_err")) }

        let лист = await пройти(адрес, схема: схема, окно: окно)
        сессия = nil
        якорь = nil
        let код: String
        switch лист {
        case .отменено:
            return .отменено
        case .сбой:
            return .ошибка(т("g_err"))
        case .адрес(let возврат):
            switch разобрать(возврат, метка: метка) {
            case .код(let к): код = к
            case .отменено: return .отменено
            case .сбой: return .ошибка(т("g_err"))
            }
        }

        switch await обменять(код, клиент: клиент, возврат: возвратный, проверочный: проверочный) {
        case .нетСвязи:
            return .ошибка(ВходText.т("no_conn"))
        case .сбой:
            return .ошибка(т("g_err"))
        case .токен(let токен):
            return await отправить(токен, nonce: сырой, клиент: клиент)
        }
    }

    /// Шаг «Укажите номер»: POST /google_auth.php?action=phone. Номер — значение поля с маской (так шлёт register_quick).
    static func отправитьНомер(_ номер: String, код: String, запрос: ЗапросНомераGoogle) async -> ИтогНомераGoogle {
        var csrf = запрос.csrf
        if csrf.isEmpty { csrf = await SiteSession.csrf() ?? "" }
        var повторён = false
        while true {
            let тело: [String: Any] = ["phone": номер, "code": код, "csrf": csrf, "agree": true]
            switch await послать("/google_auth.php?action=phone", тело: тело, сКуками: true) {
            case .нетСвязи:
                return .ошибка(ВходText.т("no_conn"))
            case .сбойСервера:
                return .ошибка(ВходText.т("login_err"))
            case .неУмеет:
                серверГотов = false
                return .скоро
            case .json(let j, let http, let адрес):
                if да(j["ok"]) {
                    await переложитьКуки(http, адрес: адрес)
                    кукиОжидания = false
                    await КабинетСайта.послеВхода(uid: строка(j["uid"]))
                    return .вошёл
                }
                let ошибка = строка(j["error"])
                /* Устаревший токен — один повтор со свежим, как у остальных POST кабинета. */
                if ошибка == "csrf" && !повторён, let свежий = await SiteSession.csrf(), свежий != csrf {
                    csrf = свежий
                    повторён = true
                    continue
                }
                if да(j["deleted"]) { return .удалён(причина: строка(j["reason"])) }
                if да(j["need_egov"]) { return .нуженEgov }
                if да(j["exists"]) { return .номерЗанят }
                if да(j["need_code"]) { return .нуженКод }
                switch ошибка {
                case "expired", "no_pending":
                    return .истекло
                case "bad_code":
                    return .ошибка(т("g_code_bad"))
                case "bad_phone":
                    return .ошибка(НомерКЗ.ошибка(номер) ?? ВходText.т("phone_short"))
                default:
                    return .ошибка(текстОшибки(ошибка, запасной: ВходText.т("login_err")))
                }
            }
        }
    }

    /// Шаг номера закрыт без входа. Если need_phone сменил куку сессии, страница под слоем держит токен прежней —
    /// перечитываем её, чтобы её запросы не упёрлись в «csrf».
    static func бросить() {
        guard кукиОжидания else { return }
        кукиОжидания = false
        WebBridge.shared.webView?.reload()
    }

    // MARK: Шаги

    private enum Возврат {
        case код(String)
        case отменено
        case сбой
    }

    private enum Обмен {
        case токен(String)
        case нетСвязи
        case сбой
    }

    private enum Ответ {
        case json([String: Any], HTTPURLResponse, URL)
        /// 404/405/501, перенаправление, не JSON или error "unsupported" — сервер не знает этот action.
        case неУмеет
        case нетСвязи
        /// 5xx без JSON — сервер упал, но эндпоинт, может быть, есть.
        case сбойСервера
    }

    private static func адресGoogle(клиент: String, возврат: String, вызов: String, метка: String,
                                    nonce: String) -> URL? {
        var части = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        части?.queryItems = [
            URLQueryItem(name: "client_id", value: клиент),
            URLQueryItem(name: "redirect_uri", value: возврат),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: вызов),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: метка),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "hl", value: языкGoogle())
        ]
        return части?.url
    }

    private static func пройти(_ адрес: URL, схема: String, окно: UIWindow) async -> ОтветЛистаGoogle {
        await withCheckedContinuation { (п: CheckedContinuation<ОтветЛистаGoogle, Never>) in
            let ящик = ЯщикОтветаGoogle(п)
            let лист = ASWebAuthenticationSession(url: адрес, callbackURLScheme: схема,
                                                  completionHandler: обработчик(ящик))
            let я = ЯкорьВходаGoogle(окно: окно)
            лист.presentationContextProvider = я
            /* Не эфемерный: кто уже вошёл в Google в Safari, выбирает аккаунт одним касанием (система спросит
               разрешения войти через google.com). */
            лист.prefersEphemeralWebBrowserSession = false
            сессия = лист
            якорь = я
            if !лист.start() { ящик.ответить(.сбой) }
        }
    }

    /// Обработчик вне главного актора: система может позвать его с любой нити, ответ — через ящик, один раз.
    nonisolated private static func обработчик(_ ящик: ЯщикОтветаGoogle) -> @Sendable (URL?, Error?) -> Void {
        return { возврат, ошибка in
            if let ошибка {
                let отмена = (ошибка as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                ящик.ответить(отмена ? .отменено : .сбой)
            } else if let возврат {
                ящик.ответить(.адрес(возврат))
            } else {
                ящик.ответить(.сбой)
            }
        }
    }

    /// com.googleusercontent.apps.<id>:/oauth2redirect?state=..&code=.. или ?error=access_denied.
    private static func разобрать(_ возврат: URL, метка: String) -> Возврат {
        guard let части = URLComponents(url: возврат, resolvingAgainstBaseURL: false) else { return .сбой }
        let поля = части.queryItems ?? []
        func поле(_ имя: String) -> String { поля.first(where: { $0.name == имя })?.value ?? "" }
        let ошибка = поле("error")
        if ошибка == "access_denied" { return .отменено }
        guard ошибка.isEmpty, поле("state") == метка else { return .сбой }
        let код = поле("code")
        return код.isEmpty ? .сбой : .код(код)
    }

    /// Код → id_token: POST oauth2.googleapis.com/token, форма, PKCE, без секрета.
    private static func обменять(_ код: String, клиент: String, возврат: String, проверочный: String) async -> Обмен {
        guard let адрес = URL(string: "https://oauth2.googleapis.com/token") else { return .сбой }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        запрос.httpBody = форма([
            ("client_id", клиент),
            ("code", код),
            ("code_verifier", проверочный),
            ("grant_type", "authorization_code"),
            ("redirect_uri", возврат)
        ])
        do {
            let (данные, ответ) = try await URLSession.shared.data(for: запрос)
            guard (ответ as? HTTPURLResponse)?.statusCode == 200,
                  let j = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any],
                  let токен = j["id_token"] as? String, !токен.isEmpty else { return .сбой }
            return .токен(токен)
        } catch {
            return .нетСвязи
        }
    }

    // MARK: Сервер

    private static func отправить(_ токен: String, nonce: String, клиент: String) async -> Итог {
        var тело: [String: Any] = [
            "id_token": токен,
            "nonce": nonce,
            "client_id": клиент,
            "bundle_id": Bundle.main.bundleIdentifier ?? "kz.kliko.app"
        ]
        if let csrf = await SiteSession.csrf() { тело["csrf"] = csrf }
        switch await послать("/google_auth.php?action=native", тело: тело, сКуками: true) {
        case .нетСвязи:
            return .ошибка(ВходText.т("no_conn"))
        case .сбойСервера:
            return .ошибка(ВходText.т("login_err"))
        case .неУмеет:
            серверГотов = false
            return .скоро
        case .json(let j, let http, let адрес):
            серверГотов = true
            if да(j["ok"]) {
                await переложитьКуки(http, адрес: адрес)
                кукиОжидания = false
                await КабинетСайта.послеВхода(uid: строка(j["uid"]))
                return .вошёл
            }
            if да(j["deleted"]) { return .удалён(причина: строка(j["reason"])) }
            if да(j["need_egov"]) { return .нуженEgov }
            if да(j["need_phone"]) {
                if await переложитьКуки(http, адрес: адрес) { кукиОжидания = true }
                return .нуженНомер(ЗапросНомераGoogle(csrf: строка(j["csrf"]), почта: строка(j["email"]),
                                                      имя: строка(j["name"])))
            }
            return .ошибка(текстОшибки(строка(j["error"]), запасной: т("g_err")))
        }
    }

    /// POST JSON к сайту: URLSession, без перенаправлений, куки WebKit — заголовком (вход общий со страницей).
    private static func послать(_ путь: String, тело: [String: Any], сКуками: Bool) async -> Ответ {
        guard let адрес = Config.url(путь),
              let байты = try? JSONSerialization.data(withJSONObject: тело) else { return .неУмеет }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        запрос.httpMethod = "POST"
        запрос.httpBody = байты
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        /* Без Origin/Referer (владелец: без поддельных источников): доказательство входа — подписанный Google токен с
           nonce, у шага номера — CSRF сессии. */
        if сКуками {
            let куки = await SiteSession.куки()
            for (имя, значение) in куки {
                запрос.setValue(значение, forHTTPHeaderField: имя)
            }
        }
        let данные: Data
        let http: HTTPURLResponse
        do {
            let (d, r) = try await URLSession.shared.data(for: запрос, delegate: БезПеренаправленийGoogle())
            guard let h = r as? HTTPURLResponse else { return .неУмеет }
            данные = d
            http = h
        } catch {
            return .нетСвязи
        }
        if [404, 405, 501].contains(http.statusCode) || (300..<400).contains(http.statusCode) { return .неУмеет }
        let разобрано = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any]
        if http.statusCode >= 500 && разобрано == nil { return .сбойСервера }
        guard let j = разобрано else { return .неУмеет }
        if строка(j["error"]) == "unsupported" { return .неУмеет }
        return .json(j, http, адрес)
    }

    /// Set-Cookie ответа — в WebKit (вход всего приложения) и в общее хранилище URLSession. true — куки были.
    @discardableResult
    private static func переложитьКуки(_ http: HTTPURLResponse, адрес: URL) async -> Bool {
        var заголовки: [String: String] = [:]
        for (ключ, значение) in http.allHeaderFields {
            if let к = ключ as? String, let з = значение as? String { заголовки[к] = з }
        }
        let куки = HTTPCookie.cookies(withResponseHeaderFields: заголовки, for: адрес)
        guard !куки.isEmpty else { return false }
        let хранилище = WKWebsiteDataStore.default().httpCookieStore
        for кука in куки {
            await хранилище.setCookie(кука)
            HTTPCookieStorage.shared.setCookie(кука)
        }
        SiteSession.кукиСменились()
        return true
    }

    // MARK: Помощники

    /// «123-abc.apps.googleusercontent.com» → «com.googleusercontent.apps.123-abc» — схема возврата iOS-клиента Google.
    static func обратнаяСхема(_ клиент: String) -> String {
        let хвост = ".apps.googleusercontent.com"
        let начало = клиент.hasSuffix(хвост) ? String(клиент.dropLast(хвост.count)) : клиент
        return "com.googleusercontent.apps." + начало
    }

    /// Язык страницы Google — как у текстов приложения.
    private static func языкGoogle() -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        return ["kk", "en", "ar"].contains(язык) ? язык : "ru"
    }

    private static func форма(_ поля: [(String, String)]) -> Data {
        let можно = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let строка = поля.map { пара in
            пара.0 + "=" + (пара.1.addingPercentEncoding(withAllowedCharacters: можно) ?? "")
        }.joined(separator: "&")
        return Data(строка.utf8)
    }

    /// Криптостойкие случайные байты (SystemRandomNumberGenerator).
    private static func случайныеБайты(_ сколько: Int) -> [UInt8] {
        var генератор = SystemRandomNumberGenerator()
        var байты: [UInt8] = []
        байты.reserveCapacity(сколько)
        for _ in 0..<сколько { байты.append(UInt8.random(in: 0...255, using: &генератор)) }
        return байты
    }

    private static func hex(_ байты: [UInt8]) -> String {
        байты.map { String(format: "%02x", $0) }.joined()
    }

    /// В Google уходит hex(SHA256(nonce)); сервер сверяет поле nonce токена с хешем сырого nonce из тела.
    private static func sha256hex(_ текст: String) -> String {
        hex(Array(SHA256.hash(data: Data(текст.utf8))))
    }

    /// base64url без «=» — для PKCE (RFC 7636).
    private static func base64url(_ данные: Data) -> String {
        данные.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func текстОшибки(_ ошибка: String, запасной: String) -> String {
        let чистая = ошибка.trimmingCharacters(in: .whitespacesAndNewlines)
        if чистая.isEmpty || КабинетСайта.машинныйКод(чистая) { return запасной }
        return чистая
    }

    private static func ключевоеОкно() -> UIWindow? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return окна.first(where: { $0.isKeyWindow }) ?? окна.first
    }

    private static func да(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue != 0 }
        if let текст = значение as? String { return текст == "1" || текст == "true" }
        return false
    }

    private static func строка(_ значение: Any?) -> String {
        if let текст = значение as? String { return текст }
        if let число = значение as? NSNumber { return число.stringValue }
        return ""
    }

    private static func т(_ ключ: String) -> String { ВходGoogleText.т(ключ) }
}

/// need_phone: Google человека подтвердил, аккаунта ещё нет — нужен номер. csrf — токен сессии, в которой сервер держит
/// ожидание (из ответа; пусто — возьмём со страницы); почта и имя — только чтобы показать, каким аккаунтом входят.
struct ЗапросНомераGoogle: Identifiable, Equatable {
    let id = UUID()
    let csrf: String
    let почта: String
    let имя: String
}

/// Чем кончился шаг «Укажите номер».
enum ИтогНомераGoogle: Equatable {
    case вошёл
    /// Сервер отправил SMS — показать поле кода.
    case нуженКод
    /// Номер уже у другого аккаунта: привязывать не будем — войти по паролю или через eGov.
    case номерЗанят
    case удалён(причина: String)
    case нуженEgov
    /// Ожидание на сервере истекло — войти через Google заново.
    case истекло
    case ошибка(String)
    case скоро
}

/// Что вернул лист входа Google.
enum ОтветЛистаGoogle: Sendable {
    case адрес(URL)
    case отменено
    case сбой
}

/// Продолжение, которое отвечает ровно один раз (обработчик сессии и неудачный start не столкнутся).
final class ЯщикОтветаGoogle: @unchecked Sendable {
    private let замок = NSLock()
    private var продолжение: CheckedContinuation<ОтветЛистаGoogle, Never>?

    init(_ продолжение: CheckedContinuation<ОтветЛистаGoogle, Never>) {
        self.продолжение = продолжение
    }

    func ответить(_ ответ: ОтветЛистаGoogle) {
        замок.lock()
        let п = продолжение
        продолжение = nil
        замок.unlock()
        п?.resume(returning: ответ)
    }
}

/// Окно, над которым встаёт лист входа Google.
final class ЯкорьВходаGoogle: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let окно: UIWindow

    init(окно: UIWindow) {
        self.окно = окно
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        окно
    }
}

/// Перенаправление не выполняется: 3xx — знак, что сервер не знает action.
private final class БезПеренаправленийGoogle: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
