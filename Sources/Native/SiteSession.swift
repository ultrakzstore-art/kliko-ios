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

 Этап 36: там же — номер вошедшего (Состояние.пользователь): подписки на продавцов (СинхронПодписок) не предлагают
 подписаться на самого себя, как сайт (getMkMe() === seller_id).
 */
enum SiteSession {

    /// Куки kliko.kz из WebKit — готовым заголовком «Cookie». Хранилище WebKit живёт на главной нити.
    @MainActor
    static func куки() async -> [String: String] {
        /* Скорость: заголовок держим 2 с и одним вопросом к WebKit на все запросы, что стартуют разом (лента, главная,
           счётчики, картинки кабинета на запуске). Каждый allCookies — круг до сетевого процесса WebKit, а на холодном
           старте ещё и его запуск. Куки сменились (вход, выход, ответ сервера) — наблюдатель сбрасывает запомненное. */
        НаблюдательКук.shared.следить()
        if let есть = запомненныеКуки, Date().timeIntervalSince(есть.когда) < 2 { return есть.поля }
        if let идёт = кукиВПути { return await идёт.value }
        let поколение = поколениеКук
        let задача = Task<[String: String], Never> { @MainActor in
            let все = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            let наши = все.filter { кука in
                let домен = кука.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return домен == "kliko.kz" || домен == "www.kliko.kz"
            }
            return HTTPCookie.requestHeaderFields(with: наши)
        }
        кукиВПути = задача
        let поля = await задача.value
        if поколение == поколениеКук {
            запомненныеКуки = (когда: Date(), поля: поля)
            кукиВПути = nil
        }
        return поля
    }

    /// Скорость: запомненный заголовок «Cookie», вопрос к WebKit в пути и номер смены кук (наблюдатель его двигает).
    @MainActor private static var запомненныеКуки: (когда: Date, поля: [String: String])?
    @MainActor private static var кукиВПути: Task<[String: String], Never>?
    @MainActor private static var поколениеКук = 0

    /// Куки в WebKit сменились — следующий запрос спросит их заново.
    @MainActor
    static func кукиСменились() {
        поколениеКук += 1
        запомненныеКуки = nil
        кукиВПути = nil
    }

    struct Состояние {
        /// nil — страница ещё не загрузилась, и мы не знаем.
        let вошёл: Bool?
        let csrf: String?
        /// Этап 36 (владелец 25.09.2026): номер вошедшего — window.KlikoUser.id («u<12 hex>», как seller_id объявлений),
        /// запасной — localStorage ulx_me_id (getMkMe сайта). Нужен, чтобы, как сайт, не предлагать подписаться на самого
        /// себя. nil — гость или страница не сказала.
        var пользователь: String? = nil
    }

    /// Выражение JS для CSRF-токена страницы: window._MKP_CSRF витрины, запасной — window.KlikoCsrf моста. typeof —
    /// чтобы страница без _MKP_CSRF (кабинет) не бросила ReferenceError, а взяла запасной.
    ///
    /// Этап 40 (владелец 26.09.2026): и дальше — как советует карта кабинета (§0.2): const CSRF страницы кабинета (на
    /// гостевой странице KlikoCsrf пустой, а токен входа лежит именно там; const верхнего уровня не свойство window, его
    /// видно только по имени — отсюда typeof), последним — window.__UIP_CSRF (он есть и у гостя). Токен выдаётся на
    /// сессию: на всех страницах одной сессии все эти значения равны, порядок нужен лишь там, где первых нет.
    static let jsТокена = "String((typeof _MKP_CSRF!=='undefined'&&_MKP_CSRF)?_MKP_CSRF:(window.KlikoCsrf"
        + "||((typeof CSRF!=='undefined'&&CSRF)?CSRF:'')||window.__UIP_CSRF||''))"

    /// CSRF-токен загруженной страницы (этап 35). Страница не загружена или токена нет — nil.
    @MainActor
    static func csrf() async -> String? {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else {
            /* Config.нативнаяСессия: страница ещё не загрузилась — токен со страницы кабинета через URLSession. */
            if Config.нативнаяСессия { return await состояниеБезСтраницы().csrf }
            return nil
        }
        let js = "(function(){try{return " + jsТокена + ";}catch(e){return '';}})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String else { return nil }
        let токен = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        return токен.isEmpty ? nil : токен
    }

    /// Вошёл ли человек и его CSRF-токен — спрашиваем у загруженной страницы.
    @MainActor
    static func состояние() async -> Состояние {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else {
            if Config.нативнаяСессия { return await состояниеБезСтраницы() }
            return Состояние(вошёл: nil, csrf: nil)
        }
        /* v: 1 — вошёл, 0 — гость, -1 — признаков нет (см. шапку). _MK_AUTH у сайта — число 0/1. */
        let js = "(function(){try{var u=window.KlikoUser,id=(u&&u.id!=null)?String(u.id):'';"
            + "var a=(typeof _MK_AUTH!=='undefined')?((_MK_AUTH&&_MK_AUTH!=='0')?1:0):-1;"
            + "var g=(typeof window.__ULX_GUEST==='boolean')?(window.__ULX_GUEST?1:0):-1;"
            + "var v=(id||a===1||g===0)?1:((u||a===0||g===1)?0:-1);"
            /* Этап 36: номер вошедшего — id моста, запасной — ulx_me_id витрины (getMkMe); у гостя не спрашиваем. */
            + "var m=id;if(!m&&v===1){try{m=localStorage.getItem('ulx_me_id')||'';}catch(e){}}"
            + "return JSON.stringify({v:v,c:" + jsТокена + ",m:String(m||'')});}catch(e){return '{}';}})()"
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
        let номер = (словарь["m"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Состояние(вошёл: вошёл, csrf: c, пользователь: вошёл == true && !номер.isEmpty ? номер : nil)
    }

    // MARK: - Config.нативнаяСессия: пока страница не загрузилась

    /// Идущее чтение страницы кабинета — одновременные вызовы ждут его, а не качают страницу заново.
    @MainActor private static var чтениеБезСтраницы: Task<Состояние, Never>?
    /// Последний ответ «вошёл» и когда он получен: 20 с не перечитываем.
    @MainActor private static var последнееБезСтраницы: Состояние?
    @MainActor private static var когдаБезСтраницы: Date = .distantPast

    /**
     Страница под слоем ещё не загрузилась (запуск приложения) — «вошёл», токен и номер со страницы кабинета: GET
     /kz/<язык>/cabinet.php через URLSession с куками WebKit (КабинетСайта.состояние, ждать: false). Не вышло — «не
     знаем» (nil), как раньше. Только при Config.нативнаяСессия.
     */
    @MainActor
    private static func состояниеБезСтраницы() async -> Состояние {
        if let последнее = последнееБезСтраницы, Date().timeIntervalSince(когдаБезСтраницы) < 20 { return последнее }
        if let идёт = чтениеБезСтраницы { return await идёт.value }
        let задача = Task { @MainActor () -> Состояние in
            guard let с = try? await КабинетСайта.состояние(ждать: false) else { return Состояние(вошёл: nil, csrf: nil) }
            let токен: String? = с.csrf.isEmpty ? nil : с.csrf
            let номер: String? = (с.вошёл == true && !с.uid.isEmpty) ? с.uid : nil
            return Состояние(вошёл: с.вошёл, csrf: токен, пользователь: номер)
        }
        чтениеБезСтраницы = задача
        let итог = await задача.value
        чтениеБезСтраницы = nil
        if итог.вошёл == true {
            последнееБезСтраницы = итог
            когдаБезСтраницы = Date()
        }
        return итог
    }
}

/// Скорость: следит за хранилищем кук WebKit и сбрасывает заголовок, запомненный SiteSession.куки().
@MainActor
final class НаблюдательКук: NSObject, WKHTTPCookieStoreObserver {
    static let shared = НаблюдательКук()
    private var следим = false

    func следить() {
        guard !следим else { return }
        следим = true
        WKWebsiteDataStore.default().httpCookieStore.add(self)
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in SiteSession.кукиСменились() }
    }
}
