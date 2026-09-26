import Foundation

/**
 ВИТРИНА ПРОДАВЦА — ДАННЫЕ (seller.php сайта нативно; владелец 26.09.2026: «всё приложение нативное»).

 Что известно из кода сайта (js/marketplace.min.js, снимки shots…/site):
   · страница продавца — /kz/<язык>/seller.php?id=<seller_id> (APP_L + "/seller.php?id=", mkChatGone, mkOpenModal,
     подписки в избранном, QR на постере услуги);
   · это страница витрины того же шаблона, что главная и объявление: список товаров приходит в разметке массивом
     `var MK_SEED = [...]` (как у home.html / item.html), а витрина фильтрует его по продавцу (window._mkSellerCtx,
     mkItemMatches: t.seller_id === _mkSellerCtx). Сама разметка seller.php в снимках не сохранена — имя массива
     INFERRED по шаблону. Поэтому разбор терпимый: ищем MK_SEED и похожие имена, берём только записи этого продавца;
   · шапка продавца — поля объявления seller, seller_avatar, seller_verified, seller_rating, seller_reviews,
     seller_deals, seller_followers, seller_since, shop_accent (MK_SEED[0], api-map §8) — они одинаковы у всех его
     объявлений; имя и фото без объявлений — из og:title / og:image страницы;
   · отзывы и сводка «сделок · отзывов · оценка» — /kz/ru/api/seller_reviews.php?id= (SellerAPI, этап 37);
   · подписка и подписчики — subs.php?action=status|follow|unfollow (этап 36).
 Запасной путь, если страница не отдала массив: /api/listings.php?per=48&sort=new&seller=<id> — параметра продавца в
 _mkApiQS нет (INFERRED, сервер может его не знать), поэтому ответ всё равно фильтруется по seller_id на телефоне.

 Куки — веб-сессии (SiteSession), как у ленты: цены и избранное для вошедшего.
 */
struct ВитринаПродавца: Equatable {
    var id: String
    var имя: String = ""
    var аватар: URL? = nil
    var проверен = false
    var рейтинг: Double? = nil
    var отзывов: Int? = nil
    var сделок: Int? = nil
    var подписчиков: Int? = nil
    /// seller_since — «2024» или дата; показывается «с 2024 г.».
    var с: String? = nil
    /// shop_accent «#RRGGBB» — фирменный цвет магазина.
    var акцент: UInt32? = nil
    var товары: [Listing] = []
    /// Список пришёл со страницы продавца (а не запасным запросом ленты) — он полный.
    var полныйСписок = false

    static func == (a: ВитринаПродавца, b: ВитринаПродавца) -> Bool {
        a.id == b.id && a.имя == b.имя && a.товары.map(\.id) == b.товары.map(\.id) && a.подписчиков == b.подписчиков
            && a.рейтинг == b.рейтинг && a.акцент == b.акцент && a.проверен == b.проверен
    }
}

enum ВитринаПродавцаAPI {
    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.urlCache = .shared
        return URLSession(configuration: c)
    }()

    /// Номер продавца годится в адрес: буквы, цифры, «_» и «-» (seller_id сайта — «u<12 hex>»).
    static func годный(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    /// Страница продавца на сайте — для «Поделиться» и запасного пути.
    static func адрес(_ id: String) -> URL? {
        let номер = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return Config.страницаСайта("seller.php?id=" + номер)
    }

    /// Вся витрина: страница продавца, при пустом списке — запасной запрос ленты. nil — нет связи и ничего не пришло.
    static func загрузить(_ id: String, имя: String) async -> ВитринаПродавца? {
        let куки = await SiteSession.куки()
        var витрина = ВитринаПродавца(id: id, имя: имя)
        var связь = false
        if let html = await страница(id, куки: куки) {
            связь = true
            let товары = товарыСоСтраницы(html, продавец: id)
            if !товары.isEmpty {
                витрина.товары = товары
                витрина.полныйСписок = true
            }
            if витрина.имя.isEmpty, let имяСтраницы = мета("og:title", в: html) { витрина.имя = чистоеИмя(имяСтраницы) }
            if let фото = мета("og:image", в: html), let адрес = Config.url(фото) { витрина.аватар = адрес }
        }
        if витрина.товары.isEmpty, let запасные = await запасныеТовары(id, куки: куки) {
            связь = true
            витрина.товары = запасные
        }
        guard связь else { return nil }
        заполнитьШапку(&витрина)
        return витрина
    }

    // MARK: - Страница seller.php

    private static func страница(_ id: String, куки: [String: String]) async -> String? {
        guard let адрес = адрес(id) else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("text/html", forHTTPHeaderField: "Accept")
        for (поле, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return nil }
        if let http = пришло.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return String(data: пришло.0, encoding: .utf8)
    }

    /// Имена массивов, в которых шаблон витрины кладёт товары (MK_SEED — CONFIRMED на главной и объявлении).
    private static let именаМассивов = ["MK_SEED", "MK_SELLER_ITEMS", "SELLER_ITEMS", "MK_ITEMS"]

    static func товарыСоСтраницы(_ html: String, продавец: String) -> [Listing] {
        for имя in именаМассивов {
            guard let json = массивJS(имя, в: html), let данные = json.data(using: .utf8) else { continue }
            let товары = разобратьМассив(данные)
            /* Как mkItemMatches: только этого продавца; без seller_id запись со страницы продавца — его. */
            let его = товары.filter { ($0.продавецID ?? продавец) == продавец }
            if !его.isEmpty { return его }
        }
        return []
    }

    /// [ {...}, … ] → объявления тем же терпимым разбором, что лента (ListingsPage пропускает неразобранные).
    static func разобратьМассив(_ данные: Data) -> [Listing] {
        var обёртка = Data("{\"items\":".utf8)
        обёртка.append(данные)
        обёртка.append(Data("}".utf8))
        return (try? ListingsAPI.разобрать(обёртка).items) ?? []
    }

    /**
     Текст массива `имя = [ … ]` из разметки: от первой «[» после «=» до парной «]», с учётом строк и экранирования.
     nil — такого присваивания нет.
     */
    static func массивJS(_ имя: String, в html: String) -> String? {
        var поиск = html.startIndex
        while let найдено = html.range(of: имя, range: поиск..<html.endIndex) {
            поиск = найдено.upperBound
            var i = найдено.upperBound
            while i < html.endIndex, html[i].isWhitespace {
                i = html.index(after: i)
            }
            guard i < html.endIndex, html[i] == "=" else { continue }
            i = html.index(after: i)
            while i < html.endIndex, html[i].isWhitespace {
                i = html.index(after: i)
            }
            guard i < html.endIndex, html[i] == "[" else { continue }
            if let конец = параЗакрытия(html, от: i) {
                return String(html[i...конец])
            }
        }
        return nil
    }

    /// Парная закрывающая скобка для «[» или «{» в позиции начало.
    private static func параЗакрытия(_ s: String, от начало: String.Index) -> String.Index? {
        var глубина = 0
        var вСтроке: Character? = nil
        var экран = false
        var i = начало
        while i < s.endIndex {
            let c = s[i]
            if let кавычка = вСтроке {
                if экран {
                    экран = false
                } else if c == "\\" {
                    экран = true
                } else if c == кавычка {
                    вСтроке = nil
                }
            } else if c == "\"" || c == "'" {
                вСтроке = c
            } else if c == "[" || c == "{" {
                глубина += 1
            } else if c == "]" || c == "}" {
                глубина -= 1
                if глубина == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    /// content у <meta property="…" content="…"> (или name=…); HTML-сущности кавычек и амперсанда — обратно.
    static func мета(_ свойство: String, в html: String) -> String? {
        let шаблон = "<meta[^>]+(?:property|name)=[\"']" + NSRegularExpression.escapedPattern(for: свойство)
            + "[\"'][^>]*content=[\"']([^\"']*)[\"']"
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive]) else { return nil }
        let весь = NSRange(html.startIndex..., in: html)
        guard let совпадение = выражение.firstMatch(in: html, range: весь),
              let r = Range(совпадение.range(at: 1), in: html) else { return nil }
        var текст = String(html[r])
        for (сущность, знак) in [("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                 ("&amp;", "&")] {
            текст = текст.replacingOccurrences(of: сущность, with: знак)
        }
        текст = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        return текст.isEmpty ? nil : текст
    }

    /// «Иван — Kliko.kz» / «Иван | Kliko» → «Иван».
    private static func чистоеИмя(_ заголовок: String) -> String {
        var имя = заголовок
        for разделитель in [" — ", " | ", " - ", " · "] {
            if let r = имя.range(of: разделитель) { имя = String(имя[..<r.lowerBound]) }
        }
        return имя.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Запасной путь: лента

    private static func запасныеТовары(_ id: String, куки: [String: String]) async -> [Listing]? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "sort", value: "new"),
                         URLQueryItem(name: "page", value: "1"),
                         URLQueryItem(name: "per", value: "48"),
                         URLQueryItem(name: "seller", value: id)]
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        for (поле, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return nil }
        if let http = пришло.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let страница = try? ListingsAPI.разобрать(пришло.0) else { return nil }
        return страница.items.filter { $0.продавецID == id }
    }

    // MARK: - Шапка из полей объявлений

    private static func заполнитьШапку(_ в: inout ВитринаПродавца) {
        guard let первый = в.товары.first else { return }
        if в.имя.isEmpty, let имя = первый.продавец { в.имя = имя }
        if let фото = в.товары.lazy.compactMap({ $0.аватарПродавца }).first, let адрес = Config.url(фото) { в.аватар = адрес }
        в.проверен = в.товары.contains { $0.продавецПроверен }
        в.рейтинг = в.товары.lazy.compactMap { $0.рейтингПродавца }.first
        в.отзывов = в.товары.lazy.compactMap { $0.отзывыПродавца }.first
        в.сделок = в.товары.lazy.compactMap { $0.сделкиПродавца }.first
        в.подписчиков = в.товары.lazy.compactMap { $0.подписчикиПродавца }.first
        в.с = в.товары.lazy.compactMap { $0.продавецС }.first
        в.акцент = в.товары.lazy.compactMap { $0.акцентМагазина }.first
    }
}
