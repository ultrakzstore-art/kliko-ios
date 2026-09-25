import Foundation
import WebKit

/**
 СЕССИЯ САЙТА ДЛЯ НАТИВНЫХ ЭКРАНОВ.

 Вход, город и права живут в веб-сессии: куки лежат в хранилище WKWebView, а CSRF-токен и признак «вошёл» страница
 отдаёт в window.KlikoCsrf и window.KlikoUser (inc/app_bridge.php на сайте). Нативные экраны второй сессии не
 заводят — они ходят к API с этими же куками и этим же токеном, как ходит сама страница. Вышел человек на сайте —
 вышел и в приложении.

 Этап 35 (владелец 25.09.2026). Токен — тот же, которым подписывает запросы витрина сайта: window._MKP_CSRF (он есть
 и у гостя; им подписаны favorites.php, marketplace.php?contact= и прочие POST в js/marketplace.min.js), запасной —
 window.KlikoCsrf моста (у гостя он пустой, у вошедшего — тот же токен сессии, одинаковый на всех её страницах).
 Один геттер на всё приложение (csrf(), jsТокена): чат (ChatAPI), звонок и WhatsApp (КонтактыПродавца), избранное.

 «Вошёл» — не «есть window.KlikoUser»: у гостя он тоже есть, только с пустым id ({"id":""}, а у вошедшего —
 {"id":"u<12 hex>"}). Прежняя проверка считала вошедшим и гостя. Теперь вошёл — непустой KlikoUser.id, или
 _MK_AUTH = 1 витрины, или window.__ULX_GUEST = false кабинета; гость — пустой id, _MK_AUTH = 0 или __ULX_GUEST =
 true; ни одного признака на странице — не знаем (nil).
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

    /// Выражение JS для CSRF-токена страницы: window._MKP_CSRF витрины, запасной — window.KlikoCsrf моста. typeof —
    /// чтобы страница без _MKP_CSRF (кабинет) не бросила ReferenceError, а взяла запасной.
    static let jsТокена = "String((typeof _MKP_CSRF!=='undefined'&&_MKP_CSRF)?_MKP_CSRF:(window.KlikoCsrf||''))"

    /// CSRF-токен загруженной страницы (этап 35). Страница не загружена или токена нет — nil.
    @MainActor
    static func csrf() async -> String? {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return nil }
        let js = "(function(){try{return " + jsТокена + ";}catch(e){return '';}})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String else { return nil }
        let токен = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        return токен.isEmpty ? nil : токен
    }

    /// Вошёл ли человек и его CSRF-токен — спрашиваем у загруженной страницы.
    @MainActor
    static func состояние() async -> Состояние {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return Состояние(вошёл: nil, csrf: nil) }
        /* v: 1 — вошёл, 0 — гость, -1 — признаков нет (см. шапку). _MK_AUTH у сайта — число 0/1. */
        let js = "(function(){try{var u=window.KlikoUser,id=(u&&u.id!=null)?String(u.id):'';"
            + "var a=(typeof _MK_AUTH!=='undefined')?((_MK_AUTH&&_MK_AUTH!=='0')?1:0):-1;"
            + "var g=(typeof window.__ULX_GUEST==='boolean')?(window.__ULX_GUEST?1:0):-1;"
            + "var v=(id||a===1||g===0)?1:((u||a===0||g===1)?0:-1);"
            + "return JSON.stringify({v:v,c:" + jsТокена + "});}catch(e){return '{}';}})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String,
              let данные = строка.data(using: .utf8),
              let словарь = try? JSONSerialization.jsonObject(with: данные) as? [String: Any] else {
            return Состояние(вошёл: nil, csrf: nil)
        }
        let c = (словарь["c"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let признак = (словарь["v"] as? NSNumber)?.intValue ?? -1
        let вошёл: Bool?
        switch признак {
        case 1: вошёл = true
        case 0: вошёл = false
        default: вошёл = nil
        }
        return Состояние(вошёл: вошёл, csrf: c)
    }
}
