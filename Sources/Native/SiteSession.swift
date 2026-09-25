import Foundation
import WebKit

/**
 СЕССИЯ САЙТА ДЛЯ НАТИВНЫХ ЭКРАНОВ.

 Вход, город и права живут в веб-сессии: куки лежат в хранилище WKWebView, а CSRF-токен и признак «вошёл» страница
 отдаёт в window.KlikoCsrf и window.KlikoUser (inc/app_bridge.php на сайте). Нативные экраны второй сессии не
 заводят — они ходят к API с этими же куками и этим же токеном, как ходит сама страница. Вышел человек на сайте —
 вышел и в приложении.
 */
enum SiteSession {

    /// Куки kliko.kz из WebKit — готовым заголовком «Cookie». Хранилище WebKit живёт на главной нити.
    @MainActor
    static func куки() async -> [String: String] {
        let все = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let наши = все.filter { кука in
            let домен = кука.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return домен == "kliko.kz" || домен == "www.kliko.kz"
        }
        return HTTPCookie.requestHeaderFields(with: наши)
    }

    struct Состояние {
        /// nil — страница ещё не загрузилась, и мы не знаем.
        let вошёл: Bool?
        let csrf: String?
    }

    /// Вошёл ли человек и его CSRF-токен — спрашиваем у загруженной страницы.
    @MainActor
    static func состояние() async -> Состояние {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return Состояние(вошёл: nil, csrf: nil) }
        let js = "JSON.stringify({u: !!window.KlikoUser, c: String(window.KlikoCsrf || '')})"
        guard let строка = try? await web.evaluateJavaScript(js) as? String,
              let данные = строка.data(using: .utf8),
              let словарь = try? JSONSerialization.jsonObject(with: данные) as? [String: Any] else {
            return Состояние(вошёл: nil, csrf: nil)
        }
        let c = (словарь["c"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Состояние(вошёл: словарь["u"] as? Bool, csrf: c)
    }
}
