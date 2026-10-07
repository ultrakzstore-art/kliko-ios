import Foundation
import WebKit

/**
 НАТИВНЫЙ ТРАНСПОРТ КАБИНЕТА — ЗА РУБИЛЬНИКОМ Config.нативнаяСессия (выключен, владелец 28.09.2026: «всё нативным»).

 Те же запросы, что КабинетСайта и ИмпортAPI шлют fetch-ем изнутри скрытой страницы, но через URLSession:
   · адрес — тот же путь от корня, на том же хосте, что у страницы под слоем (kliko.kz или www.kliko.kz);
   · метод, тело (JSON строкой, multipart) и заголовки — как у fetch страницы: Referer страницы кабинета, Origin сайта
     у всего, кроме GET (fetch same-origin шлёт его так же), User-Agent самой страницы (navigator.userAgent, с меткой
     KlikoApp), cache no-store. Кроме дверей правок сервера 92–94 и 97–99 (broadcast, rentals, exchange, chat, dm,
     api/chat_hide, api/rank_event): туда без Origin и Referer, с заголовком X-Kliko-Csrf — токеном вошедшей сессии;
   · КУКИ. Перед запросом все куки kliko.kz из WKWebsiteDataStore.default() кладутся в собственное хранилище
     отдельной эфемерной сессии (на каждый запрос своя — параллельные запросы не мешают друг другу, редиректы несут куки
     сами). После ответа то, что сервер поставил или стёр (Set-Cookie, в том числе на редиректах), переносится обратно в
     WebKit — и дожидаемся этого до возврата: вход, сделанный здесь, сразу видят страница, eGov, банк и выход;
   · CSRF — со страницы кабинета, как и раньше (карта §0.2): GET /kz/<язык>/cabinet.php этим же транспортом и разбор
     КабинетСайта.разобрать (KlikoCsrf || const CSRF || __UIP_CSRF). Отдельного API у сайта нет.

 🔴 ЗАПАСНОЙ ПУТЬ. Если сессию здесь не узнали — повторяем один раз прежним путём (через страницу), и куки ответа
 в WebKit НЕ пишем (иначе гостевая кука ответа затёрла бы вход):
   · в WebKit нет ни одной куки сайта (первый запуск — гостевую куку пусть заведёт сама страница);
   · хранилище сессии не взяло какую-то куку, которую отправил бы WebKit;
   · 401 / 403 / 419; JSON с error «auth» или «csrf», need «auth»; вместо JSON — гостевая страница кабинета;
   · страница кабинета без признака «вошёл» (у гостя это значит лишний второй запрос — зато сбой синхронизации кук
     никогда не покажет вошедшему экран входа);
   · связь оборвалась ДО отправки (нет сети, DNS, TLS). Оборвалась ПОСЛЕ — повторяется только GET: запись могла дойти
     до сервера (вход, регистрация, публикация, разбор Kliko AI), второй раз её не шлём — «Нет соединения», как у fetch.
 Денежные записи (pay.php, escrow.php — не GET) сюда не заходят вовсе: всегда страницей, как было.

 Куки и токены никуда не пишутся и не логируются.
 */
@MainActor
enum НативныйТранспортКабинета {

    enum Тело {
        case нет
        case json(String)
        case форма([ПолеФормы])
    }

    enum ПолеФормы {
        case текст(имя: String, значение: String)
        case файл(имя: String, файл: String, тип: String, данные: Data)
    }

    enum ИтогЗапроса {
        /// Ответ сервера, сессию узнали; куки ответа уже в WebKit.
        case ответ(код: Int, текст: String)
        /// Связь оборвалась. отправлен — запрос мог дойти до сервера.
        case сеть(отправлен: Bool)
        /// Сессию не узнали или кук нет — идти прежним путём, через страницу.
        case черезСтраницу
    }

    /// User-Agent страницы под слоем (navigator.userAgent) — прочитан один раз.
    private static var агент: String?

    // MARK: - Запрос

    static func выполнить(_ путь: String, метод: String, тело: Тело) async -> ИтогЗапроса {
        /* Путь только от корня: относительный fetch разрешал бы его от адреса страницы — такое не повторяем. */
        guard путь.hasPrefix("/"), !путь.hasPrefix("//") else { return .черезСтраницу }
        if денежный(путь, метод: метод) { return .черезСтраницу }
        let хост = хостСайта()
        guard let адрес = URL(string: "https://" + хост + путь) else { return .черезСтраницу }

        let хранилищеWK = WKWebsiteDataStore.default().httpCookieStore
        let сейчас = Date()
        let куки = await хранилищеWK.allCookies().filter { кука in
            guard свой(кука) else { return false }
            if let срок = кука.expiresDate, срок < сейчас { return false }
            return true
        }
        guard !куки.isEmpty else { return .черезСтраницу }

        let настройка = URLSessionConfiguration.ephemeral
        настройка.urlCache = nil
        настройка.requestCachePolicy = .reloadIgnoringLocalCacheData
        настройка.httpShouldSetCookies = true
        настройка.httpCookieAcceptPolicy = .always
        настройка.timeoutIntervalForRequest = 300
        настройка.timeoutIntervalForResource = 900
        guard let банка = настройка.httpCookieStorage else { return .черезСтраницу }
        /* Хранилище эфемерной сессии должно быть пустым и своим; иначе — не рискуем. */
        guard (банка.cookies ?? []).isEmpty else { return .черезСтраницу }
        банка.cookieAcceptPolicy = .always
        for кука in куки { банка.setCookie(кука) }
        /* Всё, что WebKit отправил бы по этому адресу, должно уйти и отсюда. */
        let уйдут = Set((банка.cookies(for: адрес) ?? []).map { $0.name })
        guard !уйдут.isEmpty else { return .черезСтраницу }
        for кука in куки where подходит(кука, хост: хост, путь: адрес.path) && !уйдут.contains(кука.name) {
            return .черезСтраницу
        }
        let до = (банка.cookies ?? []).filter { свой($0) }

        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        запрос.httpMethod = метод
        запрос.httpShouldHandleCookies = true
        /* Запрос «со страницы кабинета» того же сайта: куки SameSite уходят, как у fetch same-origin. */
        let страница = "https://" + хост + путьКабинета()
        запрос.mainDocumentURL = URL(string: страница)
        запрос.setValue("*/*", forHTTPHeaderField: "Accept")
        // Правки сервера 92–94, 97–99: эти двери пускают приложение по вошедшей сессии и её CSRF (заголовок
        // X-Kliko-Csrf, inc/app_origin_ok.php) — Origin и Referer туда больше не подставляем. Токена нет (гость,
        // страница не сказала) — идём прежним путём, через страницу: у её fetch настоящий Origin.
        if дверьСессииCSRF(адрес.path) {
            guard let токен = await SiteSession.csrf() else { return .черезСтраницу }
            запрос.setValue(токен, forHTTPHeaderField: "X-Kliko-Csrf")
        } else {
            запрос.setValue(страница, forHTTPHeaderField: "Referer")
            if метод != "GET" && метод != "HEAD" {
                запрос.setValue("https://" + хост, forHTTPHeaderField: "Origin")
            }
        }
        if let ua = await агентСтраницы() {
            запрос.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        switch тело {
        case .нет:
            break
        case .json(let строка):
            запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
            запрос.httpBody = Data(строка.utf8)
        case .форма(let поля):
            let собранное = многочастное(поля)
            запрос.setValue(собранное.тип, forHTTPHeaderField: "Content-Type")
            запрос.httpBody = собранное.данные
        }

        let сессия = URLSession(configuration: настройка)
        defer { сессия.finishTasksAndInvalidate() }
        /* Сессия должна ходить именно с этим хранилищем: по нему видно, что сервер поставил и стёр. */
        guard let своя = сессия.configuration.httpCookieStorage, своя === банка else { return .черезСтраницу }
        let пара: (Data, URLResponse)
        do {
            пара = try await сессия.data(for: запрос)
        } catch {
            return .сеть(отправлен: !доОтправки(error))
        }
        guard let http = пара.1 as? HTTPURLResponse else { return .сеть(отправлен: true) }
        let код = http.statusCode
        /* r.text() fetch-а — всегда UTF-8 с заменой битых байт. */
        let текст = String(decoding: пара.0, as: UTF8.self)
        if сессияНеУзнана(код: код, текст: текст, путь: путь) { return .черезСтраницу }
        // Дверь 92–99 не приняла токен ({"error":"origin"}) — отказ до записи, повтор страницей безопасен.
        if дверьСессииCSRF(адрес.path), отказИсточника(текст) { return .черезСтраницу }
        let после = (банка.cookies ?? []).filter { свой($0) }
        await вернутьКуки(до: до, после: после)
        return .ответ(код: код, текст: текст)
    }

    /// multipart как FormData: поля по порядку, csrf первым (порядок серверу не важен).
    static func форма(_ путь: String, поля: [ПолеФормы]) async -> ИтогЗапроса {
        await выполнить(путь, метод: "POST", тело: .форма(поля))
    }

    // MARK: - uploadImageSmart (КабинетСайта.загрузитьФото)

    /**
     Те же три попытки, что скрипт загрузки КабинетСайта: multipart {csrf, imgb64}, multipart {csrf, photo}, JSON
     {csrf, image_b64}; после удачной первой — миниатюра {csrf, imgb64, thumb_for}. nil — идти прежним путём (сессию не
     узнали или ни одна попытка не дошла до сервера).
     */
    static func загрузитьФото(_ путь: String, картинка: String, миниатюра: String,
                              токен: String) async -> (код: Int, json: [String: Any])? {
        var код = 0
        var ошибка = ""

        let первая: [ПолеФормы] = [.текст(имя: "csrf", значение: токен), .текст(имя: "imgb64", значение: картинка)]
        switch await выполнить(путь, метод: "POST", тело: .форма(первая)) {
        case .черезСтраницу:
            return nil
        case .сеть:
            break
        case .ответ(let к, let т):
            код = к
            if (200...299).contains(к) {
                let o = объект(т)
                if let o, истинно(o["ok"]), истинно(o["url"]), !миниатюра.isEmpty {
                    let имя = строка(o["url"]).components(separatedBy: "/").last ?? ""
                    if !имя.isEmpty {
                        let мини: [ПолеФормы] = [.текст(имя: "csrf", значение: токен),
                                                 .текст(имя: "imgb64", значение: миниатюра),
                                                 .текст(имя: "thumb_for", значение: имя)]
                        _ = await выполнить(путь, метод: "POST", тело: .форма(мини))
                    }
                }
                if let o, истинно(o["ok"]) || истинно(o["prohibited"]) || истинно(o["foreign"]) { return (к, o) }
                if let o, истинно(o["error"]) { ошибка = строка(o["error"]) }
            }
        }

        if let файл = байтыDataURL(картинка) {
            let имяФайла = файл.тип == "image/webp" ? "photo.webp" : "photo.jpg"
            let вторая: [ПолеФормы] = [.текст(имя: "csrf", значение: токен),
                                       .файл(имя: "photo", файл: имяФайла, тип: файл.тип, данные: файл.данные)]
            switch await выполнить(путь, метод: "POST", тело: .форма(вторая)) {
            case .черезСтраницу:
                return nil
            case .сеть:
                break
            case .ответ(let к, let т):
                код = к
                if (200...299).contains(к) {
                    let o = объект(т)
                    if let o, истинно(o["ok"]) || истинно(o["prohibited"]) || истинно(o["foreign"]) { return (к, o) }
                    if let o, истинно(o["error"]) { ошибка = строка(o["error"]) }
                }
            }
        }

        let третьеТело: [String: Any] = ["csrf": токен, "image_b64": картинка]
        if let данные = try? JSONSerialization.data(withJSONObject: третьеТело) {
            let строкаТела = String(decoding: данные, as: UTF8.self)
            switch await выполнить(путь, метод: "POST", тело: .json(строкаТела)) {
            case .черезСтраницу:
                return nil
            case .сеть:
                break
            case .ответ(let к, let т):
                код = к
                if (200...299).contains(к) {
                    let o = объект(т)
                    if let o, истинно(o["ok"]) || истинно(o["prohibited"]) { return (к, o) }
                    if let o, истинно(o["error"]) { ошибка = строка(o["error"]) }
                }
            }
        }

        /* Ни одна попытка не дошла до сервера — пусть попробует страница. */
        if код == 0 { return nil }
        let итог: [String: Any] = ["ok": false, "error": ошибка]
        return (код, итог)
    }

    // MARK: - Когда идти через страницу

    /// Денежные записи — только прежним путём.
    private static func денежный(_ путь: String, метод: String) -> Bool {
        guard метод != "GET" else { return false }
        let адрес = путь.lowercased()
        return адрес.contains("pay.php") || адрес.contains("escrow.php")
    }

    /// Двери, которые после правок сервера 92–94 и 97–99 принимают приложение по сессии + CSRF вместо Origin:
    /// broadcast.php, rentals.php, exchange.php, chat.php, dm.php, api/chat_hide.php, api/rank_event.php.
    private static func дверьСессииCSRF(_ дорога: String) -> Bool {
        let д = дорога.lowercased()
        let двери = ["/broadcast.php", "/rentals.php", "/exchange.php", "/chat.php", "/dm.php",
                     "/api/chat_hide.php", "/api/rank_event.php"]
        return двери.contains { д.hasSuffix($0) }
    }

    /// Ответ «источник не принят»: {"error":"origin"} (chat.php, dm.php, chat_hide, rank_event) или текст broadcast.php.
    private static func отказИсточника(_ текст: String) -> Bool {
        guard let j = объект(текст), !истинно(j["ok"]) else { return false }
        let ошибка = строка(j["error"])
        return ошибка == "origin" || ошибка == "Недопустимый источник запроса"
    }

    /// Сервер не узнал сессию (см. шапку). Такой ответ не принимаем и его куки в WebKit не пишем.
    private static func сессияНеУзнана(код: Int, текст: String, путь: String) -> Bool {
        if код == 401 || код == 403 || код == 419 { return true }
        if let j = объект(текст) {
            let ошибка = строка(j["error"])
            return ошибка == "auth" || ошибка == "csrf" || строка(j["need"]) == "auth"
        }
        let часть = путь.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let дорога = часть.first.map { String($0) } ?? путь
        let запросЧасть = часть.count > 1 ? String(часть[1]) : ""
        let страницаКабинета = дорога.hasSuffix("/cabinet.php") && !запросЧасть.contains("action=")
            && !запросЧасть.contains("logout=")
        if страницаКабинета {
            /* Страница кабинета: принимаем только «вошёл». */
            return КабинетСайта.разобрать(текст).вошёл != true
        }
        if запросЧасть.contains("action=") || дорога.hasPrefix("/api/") {
            /* Ждали JSON, пришла гостевая страница — сервер отправил на вход. */
            return КабинетСайта.разобрать(текст).вошёл == false
        }
        return false
    }

    /// Запрос точно не ушёл на сервер: соединения не было.
    private static func доОтправки(_ ошибка: Error) -> Bool {
        guard let сбой = ошибка as? URLError else { return false }
        switch сбой.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
             .appTransportSecurityRequiresSecureConnection, .badURL, .unsupportedURL:
            return true
        default:
            return false
        }
    }

    // MARK: - Куки

    /// Кука сайта — как у SiteSession.куки: kliko.kz и www.kliko.kz.
    private static func свой(_ кука: HTTPCookie) -> Bool {
        let домен = кука.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return домен == "kliko.kz" || домен == "www.kliko.kz"
    }

    /// Отправил бы WebKit эту куку по адресу (домен и путь).
    private static func подходит(_ кука: HTTPCookie, хост: String, путь: String) -> Bool {
        let домен = кука.domain.lowercased()
        let доменПодходит: Bool
        if домен.hasPrefix(".") {
            let голый = String(домен.dropFirst())
            доменПодходит = хост == голый || хост.hasSuffix(домен)
        } else {
            доменПодходит = хост == домен
        }
        guard доменПодходит else { return false }
        let путьКуки = кука.path.isEmpty ? "/" : кука.path
        let путьАдреса = путь.isEmpty ? "/" : путь
        return путьАдреса.hasPrefix(путьКуки)
    }

    private static func такаяЖе(_ а: HTTPCookie, _ б: HTTPCookie) -> Bool {
        а.name == б.name && а.domain.lowercased() == б.domain.lowercased() && а.path == б.path
    }

    /// Что сервер поставил или стёр за этот запрос — в WebKit. Ждём, пока WebKit примет.
    private static func вернутьКуки(до: [HTTPCookie], после: [HTTPCookie]) async {
        let хранилищеWK = WKWebsiteDataStore.default().httpCookieStore
        for кука in после {
            let прежняя = до.first(where: { такаяЖе($0, кука) })
            if let прежняя, прежняя.value == кука.value, прежняя.expiresDate == кука.expiresDate { continue }
            await хранилищеWK.setCookie(кука)
        }
        for кука in до where !после.contains(where: { такаяЖе($0, кука) }) {
            await хранилищеWK.deleteCookie(кука)
        }
    }

    // MARK: - Адрес и заголовки

    /// Хост страницы под слоем, если она на сайте; иначе — Config.apiBase.
    private static func хостСайта() -> String {
        if let адрес = WebBridge.shared.webView?.url, адрес.scheme?.lowercased() == "https",
           let хост = адрес.host?.lowercased(), хост == "kliko.kz" || хост == "www.kliko.kz" {
            return хост
        }
        return Config.apiBase.host?.lowercased() ?? "kliko.kz"
    }

    /// «/kz/<язык>/cabinet.php» — Referer, как у запросов со страницы кабинета.
    private static func путьКабинета() -> String {
        guard let полный = Config.страницаСайта("cabinet.php"),
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return "/kz/ru/cabinet.php" }
        return части.percentEncodedPath
    }

    private static func агентСтраницы() async -> String? {
        if let агент { return агент }
        guard let web = WebBridge.shared.webView else { return nil }
        guard let строка = try? await web.evaluateJavaScript("navigator.userAgent") as? String, !строка.isEmpty else {
            return nil
        }
        агент = строка
        return строка
    }

    // MARK: - multipart

    private static func многочастное(_ поля: [ПолеФормы]) -> (тип: String, данные: Data) {
        let граница = "----KlikoFormBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var данные = Data()
        for поле in поля {
            данные.append(Data("--\(граница)\r\n".utf8))
            switch поле {
            case .текст(let имя, let значение):
                данные.append(Data("Content-Disposition: form-data; name=\"\(экран(имя))\"\r\n\r\n".utf8))
                данные.append(Data(значение.utf8))
            case .файл(let имя, let файл, let тип, let байты):
                let заголовок = "Content-Disposition: form-data; name=\"\(экран(имя))\"; filename=\"\(экран(файл))\"\r\n"
                данные.append(Data(заголовок.utf8))
                данные.append(Data("Content-Type: \(тип)\r\n\r\n".utf8))
                данные.append(байты)
            }
            данные.append(Data("\r\n".utf8))
        }
        данные.append(Data("--\(граница)--\r\n".utf8))
        return ("multipart/form-data; boundary=" + граница, данные)
    }

    /// Имя поля и файла в кавычках — как FormData браузера: " → %22, перевод строки → %0D / %0A.
    private static func экран(_ текст: String) -> String {
        текст.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    /// dataURL → тип и байты (toBlob скрипта загрузки). Не разобрался — nil (скрипт в этом случае пропускает попытку).
    private static func байтыDataURL(_ du: String) -> (тип: String, данные: Data)? {
        guard du.hasPrefix("data:"), let запятая = du.firstIndex(of: ",") else { return nil }
        let голова = du[du.index(du.startIndex, offsetBy: 5)..<запятая]
        let первое = голова.split(separator: ";", omittingEmptySubsequences: false).first.map { String($0) } ?? ""
        let хвост = String(du[du.index(after: запятая)...])
        guard let байты = Data(base64Encoded: хвост, options: .ignoreUnknownCharacters) else { return nil }
        return (первое.isEmpty ? "image/jpeg" : первое, байты)
    }

    // MARK: - Разбор значений (как JS)

    private static func объект(_ текст: String) -> [String: Any]? {
        guard let данные = текст.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any]
    }

    /// Истинность JS: null, false, 0, NaN и пустая строка — ложь; прочее — истина.
    private static func истинно(_ значение: Any?) -> Bool {
        guard let значение, !(значение is NSNull) else { return false }
        if let текст = значение as? String { return !текст.isEmpty }
        if let число = значение as? NSNumber {
            let d = число.doubleValue
            return d != 0 && !d.isNaN
        }
        return true
    }

    private static func строка(_ значение: Any?) -> String {
        if let текст = значение as? String { return текст }
        if let число = значение as? NSNumber { return число.stringValue }
        return ""
    }
}
