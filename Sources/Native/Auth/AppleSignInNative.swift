import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
import WebKit

/**
 ВХОД ЧЕРЕЗ APPLE — НАТИВНО, С ОТКАТОМ НА СТРАНИЦУ САЙТА.

 Лист Apple (ASAuthorizationAppleIDProvider, имя и почта, nonce) → POST /apple_auth.php?action=native с токеном Apple.
 Сервер проверяет токен и отвечает {ok:true, uid} с Set-Cookie сессии — куки перекладываются в хранилище WebKit
 (WKWebsiteDataStore.default(), там живёт вход всего приложения) и в HTTPCookieStorage.shared, дальше — как после входа
 паролем (КабинетСайта.послеВхода).

 Сервер ещё не умеет (404, перенаправление, не JSON, {ok:false,error:"unsupported"}) или лист Apple не поднялся (нет
 возможности в профиле) — .наСайт: экран входа открывает прежнюю страницу /apple_auth.php?action=start. Договор с сайтом —
 docs/SERVER_NATIVE_AUTH.md.

 Запрос — URLSession, а не fetch страницы: токену Apple гостевая сессия и CSRF не нужны, а перенаправление (старый сервер
 на незнакомый action может увести к Apple) fetch страницы превратил бы в «нет соединения» вместо отката. Куки WebKit
 уходят с запросом, чтобы сервер мог поднять вход в той же сессии. Токены не пишутся в журнал.
 */
@MainActor
enum ВходApple {

    enum Итог: Equatable {
        case вошёл
        /// Человек закрыл лист Apple — ничего не показываем.
        case отменено
        case удалён(причина: String)
        case нуженEgov
        case ошибка(String)
        /// Сервер или устройство не готовы — прежняя страница сайта.
        case наСайт
    }

    /// Идущий вход: держит контроллер и посредника, пока лист Apple открыт.
    private static var текущий: ПосредникВходаApple? = nil

    static func войти() async -> Итог {
        guard текущий == nil else { return .отменено }
        guard let окно = ключевоеОкно() else { return .наСайт }
        let сырой = случайныйNonce()
        let запрос = ASAuthorizationAppleIDProvider().createRequest()
        запрос.requestedScopes = [.fullName, .email]
        запрос.nonce = sha256(сырой)
        let контроллер = ASAuthorizationController(authorizationRequests: [запрос])
        let посредник = ПосредникВходаApple(окно: окно)
        контроллер.delegate = посредник
        контроллер.presentationContextProvider = посредник
        текущий = посредник
        let ответ = await посредник.ждать(контроллер)
        текущий = nil
        switch ответ {
        case .отменено:
            return .отменено
        case .сбой:
            return .наСайт
        case .данные(let данные):
            return await отправить(данные, nonce: сырой)
        }
    }

    // MARK: Сервер

    private static func отправить(_ данные: ДанныеApple, nonce: String) async -> Итог {
        guard let адрес = Config.url("/apple_auth.php?action=native") else { return .наСайт }
        var тело: [String: Any] = [
            "identity_token": данные.токен,
            "authorization_code": данные.код,
            "nonce": nonce,
            "full_name": данные.имя,
            "given_name": данные.имяСобственное,
            "family_name": данные.фамилия,
            "email": данные.почта,
            "user": данные.пользователь,
            "bundle_id": Bundle.main.bundleIdentifier ?? "kz.kliko.app"
        ]
        if let токен = await SiteSession.csrf() { тело["csrf"] = токен }
        guard let байты = try? JSONSerialization.data(withJSONObject: тело) else { return .наСайт }

        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        запрос.httpMethod = "POST"
        запрос.httpBody = байты
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        запрос.setValue("https://kliko.kz", forHTTPHeaderField: "Origin")
        запрос.setValue("https://kliko.kz/", forHTTPHeaderField: "Referer")
        let куки = await SiteSession.куки()
        for (имя, значение) in куки {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }

        let ответ: Data
        let http: HTTPURLResponse
        do {
            let (d, r) = try await URLSession.shared.data(for: запрос, delegate: БезПеренаправленийApple())
            guard let h = r as? HTTPURLResponse else { return .наСайт }
            ответ = d
            http = h
        } catch {
            return .ошибка(ВходText.т("no_conn"))
        }

        /* Сервер не знает action=native: 404/405/501, перенаправление или страница вместо JSON — прежний путь. */
        if [404, 405, 501].contains(http.statusCode) || (300..<400).contains(http.statusCode) { return .наСайт }
        guard let j = (try? JSONSerialization.jsonObject(with: ответ)) as? [String: Any] else { return .наСайт }

        if да(j["ok"]) {
            await переложитьКуки(http, адрес: адрес)
            await КабинетСайта.послеВхода(uid: строка(j["uid"]))
            return .вошёл
        }
        let ошибка = строка(j["error"])
        if ошибка == "unsupported" { return .наСайт }
        if да(j["deleted"]) { return .удалён(причина: строка(j["reason"])) }
        if да(j["need_egov"]) { return .нуженEgov }
        if ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) { return .ошибка(ВходText.т("login_err")) }
        return .ошибка(ошибка)
    }

    /// Set-Cookie ответа — в WebKit (вход всего приложения) и в общее хранилище URLSession.
    private static func переложитьКуки(_ http: HTTPURLResponse, адрес: URL) async {
        var заголовки: [String: String] = [:]
        for (ключ, значение) in http.allHeaderFields {
            if let к = ключ as? String, let з = значение as? String { заголовки[к] = з }
        }
        let куки = HTTPCookie.cookies(withResponseHeaderFields: заголовки, for: адрес)
        guard !куки.isEmpty else { return }
        let хранилище = WKWebsiteDataStore.default().httpCookieStore
        for кука in куки {
            await хранилище.setCookie(кука)
            HTTPCookieStorage.shared.setCookie(кука)
        }
    }

    // MARK: Nonce

    /// 32 случайных байта (SystemRandomNumberGenerator — криптостойкий) строкой hex.
    private static func случайныйNonce() -> String {
        var генератор = SystemRandomNumberGenerator()
        var байты: [UInt8] = []
        байты.reserveCapacity(32)
        for _ in 0..<32 { байты.append(UInt8.random(in: 0...255, using: &генератор)) }
        return hex(байты)
    }

    /// В запрос Apple уходит hex(SHA256(nonce)); сервер сверяет его с полем nonce токена.
    private static func sha256(_ текст: String) -> String {
        hex(Array(SHA256.hash(data: Data(текст.utf8))))
    }

    private static func hex(_ байты: [UInt8]) -> String {
        байты.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Помощники

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
}

/// Что вернул лист Apple.
enum ОтветЛистаApple: Sendable {
    case данные(ДанныеApple)
    case отменено
    case сбой
}

/// Данные удостоверения Apple — только для одного запроса к серверу, нигде не хранятся.
struct ДанныеApple: Sendable {
    let токен: String
    let код: String
    let пользователь: String
    let имя: String
    let имяСобственное: String
    let фамилия: String
    let почта: String
}

/// Делегат и якорь листа Apple. Держит контроллер, пока лист открыт; ответ — один раз.
final class ПосредникВходаApple: NSObject, ASAuthorizationControllerDelegate,
                                  ASAuthorizationControllerPresentationContextProviding {
    private let окно: UIWindow
    private var контроллер: ASAuthorizationController? = nil
    private var продолжение: CheckedContinuation<ОтветЛистаApple, Never>? = nil

    init(окно: UIWindow) {
        self.окно = окно
        super.init()
    }

    @MainActor
    func ждать(_ контроллер: ASAuthorizationController) async -> ОтветЛистаApple {
        await withCheckedContinuation { (п: CheckedContinuation<ОтветЛистаApple, Never>) in
            self.продолжение = п
            self.контроллер = контроллер
            контроллер.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let удостоверение = authorization.credential as? ASAuthorizationAppleIDCredential,
              let токенДанные = удостоверение.identityToken,
              let токен = String(data: токенДанные, encoding: .utf8), !токен.isEmpty else {
            завершить(.сбой)
            return
        }
        let код = удостоверение.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let части = удостоверение.fullName
        let имяСобственное = части?.givenName ?? ""
        let фамилия = части?.familyName ?? ""
        let полное = [имяСобственное, фамилия].filter { !$0.isEmpty }.joined(separator: " ")
        let данные = ДанныеApple(токен: токен, код: код, пользователь: удостоверение.user, имя: полное,
                                 имяСобственное: имяСобственное, фамилия: фамилия, почта: удостоверение.email ?? "")
        завершить(.данные(данные))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let отмена = (error as? ASAuthorizationError)?.code == .canceled
        завершить(отмена ? .отменено : .сбой)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        окно
    }

    private func завершить(_ ответ: ОтветЛистаApple) {
        let п = продолжение
        продолжение = nil
        контроллер = nil
        п?.resume(returning: ответ)
    }
}

/// Перенаправление не выполняется: 3xx — знак, что сервер не знает action=native.
private final class БезПеренаправленийApple: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
