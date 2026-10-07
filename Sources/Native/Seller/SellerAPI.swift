import Foundation

/**
 ПРОДАВЕЦ: ОТЗЫВЫ, ЖАЛОБА, БЛОКИРОВКА — ЗАПРОСЫ К САЙТУ (этап 37, владелец 25.09.2026: «почти 100% похоже на сайт»).

 Витрина сайта (js/marketplace.min.js) ходит за этим так — куки веб-сессии, csrf полем JSON:
   · GET  /kz/ru/api/seller_reviews.php?id=<seller_id> → {ok, count, deals, rating, dist{5..1}, items[{name, rating,
     date, text, product}]} — mkSellerRevOpen: адрес от APP_L = "/kz/ru"; нет ok или ответ не JSON — «Не удалось
     загрузить отзывы» (_mkSellerRevPaint({ok: false}));
   · POST report.php?action=submit {target_id, listing_id, reason, comment, csrf} → {ok, exists} — mkReportSubmit,
     адрес от _MKB = "/"; reason — data-r кнопок окна жалобы: spam, fraud, prohibited, abuse, duplicate, other;
   · POST subs.php?action=block | unblock {user_id, name, csrf} → {ok} — mkBlockToggle; заблокирован ли — blocked ответа
     subs.php?action=status (его разбирает ПодпискиСайта этапа 36 и отдаёт ДействияСПродавцом).
 Отказы разбираются теми же правилами, что у избранного и подписок (ПодпискиСайта.разобрать): need/error «auth» —
 вход, «verify» — верификация, «csrf» — защита, иначе текст error, если это не машинный код (ulxErr сайта).

 Здесь только сами запросы: когда их слать и что показать, решает ДействияСПродавцом. Повторов нет: одно нажатие —
 один запрос.
 */
enum ОтзывыПродавца {
    /// Одна запись items[].
    struct Отзыв: Identifiable, Equatable, Sendable {
        /// Место в списке — у записи сайта своего номера нет.
        let id: Int
        /// name без пробелов по краям; пусто — «Покупатель», как у сайта.
        let имя: String
        /// rating 0…5; не пришло — 0.
        let оценка: Double
        /// date как пришла («2026-09-24») — показывается правилом mkDate.
        let дата: String?
        let текст: String?
        /// product — название товара сделки.
        let товар: String?
    }

    /// Ответ ok: true.
    struct Сводка: Equatable, Sendable {
        /// count — сколько отзывов.
        let отзывов: Int
        /// deals — сколько сделок.
        let сделок: Int
        /// rating — средняя оценка.
        let оценка: Double
        /// dist: оценка 1…5 → сколько отзывов с ней. Чего нет — ноль.
        let распределение: [Int: Int]
        let отзывы: [Отзыв]
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    /// GET /kz/ru/api/seller_reviews.php?id=<seller_id>. nil — нет связи, не JSON или ok не пришёл.
    static func загрузить(_ продавец: String) async -> Сводка? {
        var ч = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false)
        ч?.path = "/kz/ru/api/seller_reviews.php"
        ч?.queryItems = [URLQueryItem(name: "id", value: продавец)]
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return nil }
        guard let поля = (try? JSONSerialization.jsonObject(with: пришло.0)) as? [String: Any] else { return nil }
        return разобрать(поля)
    }

    /// Ответ сайта → сводка, терпимо, как _mkSellerRevPaint: числа строкой или числом (+t.count||0), dist объектом
    /// {"5":…} или массивом, items массивом или объектом с номерами в ключах. Нет ok — nil.
    static func разобрать(_ поля: [String: Any]) -> Сводка? {
        guard ПоляСайта.да(поля["ok"]) else { return nil }
        var распределение: [Int: Int] = [:]
        if let словарь = поля["dist"] as? [String: Any] {
            for звёзд in 1...5 { распределение[звёзд] = max(0, ПоляСайта.целое(словарь[String(звёзд)]) ?? 0) }
        } else if let массив = поля["dist"] as? [Any] {
            /* Как c[t] у массива в JS: оценка — это номер элемента. */
            for звёзд in 1...5 where звёзд < массив.count {
                распределение[звёзд] = max(0, ПоляСайта.целое(массив[звёзд]) ?? 0)
            }
        }
        var отзывы: [Отзыв] = []
        for (место, элемент) in ПоляСайта.записи(поля["items"]).enumerated() {
            guard let запись = элемент as? [String: Any] else { continue }
            отзывы.append(Отзыв(id: место,
                                имя: ПоляСайта.строка(запись["name"]) ?? "",
                                оценка: max(0, ПоляСайта.дробное(запись["rating"]) ?? 0),
                                дата: ПоляСайта.строка(запись["date"]),
                                текст: ПоляСайта.строка(запись["text"]),
                                товар: ПоляСайта.строка(запись["product"])))
        }
        return Сводка(отзывов: max(0, ПоляСайта.целое(поля["count"]) ?? 0),
                      сделок: max(0, ПоляСайта.целое(поля["deals"]) ?? 0),
                      оценка: max(0, ПоляСайта.дробное(поля["rating"]) ?? 0),
                      распределение: распределение,
                      отзывы: отзывы)
    }
}

/// Причины жалобы — data-r кнопок .mk-rr окна #mk-report-scrim сайта, в его порядке.
enum ПричинаЖалобы: String, CaseIterable, Identifiable, Sendable {
    case spam, fraud, prohibited, abuse, duplicate, other

    var id: String { rawValue }

    /// «Спам или реклама», «Мошенничество»… — подписи кнопок сайта.
    var подпись: String { SellerText.т("r_" + rawValue) }
}

/// Записи на сайт: жалоба и блокировка. Только по нажатию человека — зовёт их ДействияСПродавцом.
enum ЗапросыПродавца {
    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// POST report.php?action=submit — ровно тело mkReportSubmit: target_id — продавец, listing_id — объявление.
    static func пожаловаться(на продавец: String, объявление: String, причина: ПричинаЖалобы, комментарий: String,
                             csrf: String) async -> ПодпискиСайта.Итог {
        let тело: [String: Any] = ["target_id": продавец, "listing_id": объявление, "reason": причина.rawValue,
                                   "comment": комментарий, "csrf": csrf]
        return await отправить("report.php", действие: "submit", тело: тело)
    }

    /// POST subs.php?action=block {user_id, name, csrf} — тело mkBlockToggle.
    static func заблокировать(_ продавец: String, имя: String, csrf: String) async -> ПодпискиСайта.Итог {
        await отправить("subs.php", действие: "block", тело: ["user_id": продавец, "name": имя, "csrf": csrf])
    }

    /// POST subs.php?action=unblock — то же тело, что у block (сайт шлёт его одним вызовом для обоих).
    static func разблокировать(_ продавец: String, имя: String, csrf: String) async -> ПодпискиСайта.Итог {
        await отправить("subs.php", действие: "unblock", тело: ["user_id": продавец, "name": имя, "csrf": csrf])
    }

    private static func отправить(_ файл: String, действие: String, тело: [String: Any]) async -> ПодпискиСайта.Итог {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent(файл), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: действие)]
        guard let адрес = ч?.url, let данные = try? JSONSerialization.data(withJSONObject: тело) else {
            return .отказ(nil)
        }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        /* Origin не подставляем (владелец: без поддельных Origin/Referer): report.php и subs.php источник не проверяют. */
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        запрос.httpBody = данные
        let ответныеДанные: Data
        let ответ: URLResponse
        do { (ответныеДанные, ответ) = try await сессия.data(for: запрос) } catch { return .сеть }
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        /* JSON разбираем и при 4xx: сайт объясняет отказ полями need/error, а не кодом. */
        guard let поля = (try? JSONSerialization.jsonObject(with: ответныеДанные)) as? [String: Any] else {
            return (код == 401 || код == 403) ? .нуженВход : .отказ(nil)
        }
        return ПодпискиСайта.разобрать(поля, код: код)
    }
}

/// Терпимое чтение полей ответа PHP: числа то числом, то строкой; массив — иногда объектом {"0":…,"2":…}.
private enum ПоляСайта {
    static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    static func строка(_ значение: Any?) -> String? {
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = значение as? NSNumber { return n.stringValue }
        return nil
    }

    static func целое(_ значение: Any?) -> Int? {
        if let n = значение as? NSNumber { return n.intValue }
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            /* «4.0» — тоже число; Int(exactly:) не падает на nan, inf и огромных значениях, а даёт nil. */
            return Int(t) ?? Double(t).flatMap { Int(exactly: $0.rounded(.towardZero)) }
        }
        return nil
    }

    static func дробное(_ значение: Any?) -> Double? {
        if let n = значение as? NSNumber { return n.doubleValue }
        if let s = значение as? String {
            /* «nan» и «inf» строкой Double() тоже понимает — такие не берём: дальше из оценки считаются звёзды. */
            let число = Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
            return число.flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    /// Массив записей; объект с номерами в ключах — по порядку ключей; иное — пусто.
    static func записи(_ значение: Any?) -> [Any] {
        if let массив = значение as? [Any] { return массив }
        if let словарь = значение as? [String: Any] {
            let ключи = словарь.keys.sorted { (Int($0) ?? Int.max) < (Int($1) ?? Int.max) }
            return ключи.compactMap { словарь[$0] }
        }
        return []
    }
}
