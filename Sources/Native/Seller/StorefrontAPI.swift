import Foundation

/**
 ВИТРИНА ПРОДАВЦА — ДАННЫЕ (seller.php сайта нативно; владелец 26.09.2026: «всё приложение нативное»).

 Что известно из кода сайта (js/marketplace.min.js, снимки shots…/site):
   · страница продавца — /kz/<язык>/seller.php?id=<seller_id> (APP_L + "/seller.php?id=", mkChatGone, mkOpenModal,
     подписки в избранном, QR на постере услуги); с неё берём только имя и фото (og:title, og:image);
   · ТОВАРЫ — НЕ СО СТРАНИЦЫ (владелец 17.10.2026: «у продавца Канат много товаров, а в профиле только 4 — где
     остальные?»). Проба CI 17.10 (ci/seller_probe.py): MK_SEED на seller.php — служебная выборка из 6 объявлений, не
     список продавца (сайт: «у seller.php нет MK_SEED, витрина собирается на сервере в HTML»); из неё выходило 4 его
     товара из 41, и список ещё считался полным. Отбора по продавцу в api/listings.php нет (seller, seller_id, uid —
     сервер молча отдаёт общую ленту). Поэтому товары — лентой по страницам (sort=new, per=48, параметр seller на
     будущее), с отбором по seller_id на телефоне, пока страницы не кончатся, но не больше страницДо;
   · шапка продавца — поля объявления seller, seller_avatar, seller_verified, seller_rating, seller_reviews,
     seller_deals, seller_followers, seller_since, shop_accent (MK_SEED[0], api-map §8) — они одинаковы у всех его
     объявлений; имя и фото без объявлений — из og:title / og:image страницы;
   · отзывы и сводка «сделок · отзывов · оценка» — /kz/ru/api/seller_reviews.php?id= (SellerAPI, этап 37);
   · подписка и подписчики — subs.php?action=status|follow|unfollow (этап 36).

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
    /// Страницы ленты кончились раньше предела — показаны все товары продавца; нет — под ними «Остальные — на сайте».
    var полныйСписок = false

    static func == (a: ВитринаПродавца, b: ВитринаПродавца) -> Bool {
        a.id == b.id && a.имя == b.имя && a.товары.map(\.id) == b.товары.map(\.id) && a.подписчиков == b.подписчиков
            && a.рейтинг == b.рейтинг && a.акцент == b.акцент && a.проверен == b.проверен
    }
}

enum ВитринаПродавцаAPI {
    /// Общая сессия сайта (СетьСайта, SiteNetwork.swift): соединение, открытое лентой и карточкой, — сразу и витрине.
    /// Без своего Accept и с общим сроком 20 с — как у прежней своей; куки — из WebKit (SiteSession).
    private static let сессия = СетьСайта.Запросы(json: false)

    /// Номер продавца годится в адрес: буквы, цифры, «_» и «-» (seller_id сайта — «u<12 hex>»).
    static func годный(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    /// Страница продавца на сайте — для «Поделиться» и запасного пути.
    static func адрес(_ id: String) -> URL? {
        let номер = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return Config.страницаСайта("seller.php?id=" + номер)
    }

    /// Вся витрина: имя и фото — со страницы продавца, товары — лентой (товарыЛентой). nil — нет связи и ничего не пришло.
    static func загрузить(_ id: String, имя: String) async -> ВитринаПродавца? {
        let куки = await SiteSession.куки()
        var витрина = ВитринаПродавца(id: id, имя: имя)
        var связь = false
        if let html = await страница(id, куки: куки) {
            связь = true
            if витрина.имя.isEmpty, let имяСтраницы = мета("og:title", в: html) { витрина.имя = чистоеИмя(имяСтраницы) }
            if let фото = мета("og:image", в: html), let адрес = Config.url(фото) { витрина.аватар = адрес }
        }
        if let лента = await товарыЛентой(id, куки: куки) {
            связь = true
            /* Цифровые товары (Ц1): разбор ленты их уже убирает, пока показ выключен; подразделы — ещё и по справочнику. */
            let скрытые = await MainActor.run { ЗагрузкаКаталогаПоиска.сейчас?.скрытые ?? [] }
            витрина.товары = лента.товары.filter { !скрытые.contains($0.категория ?? "") }
            витрина.полныйСписок = лента.все
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

    // MARK: - Товары продавца лентой

    /// Больше стольких страниц по 48 не листаем: дальше — «Остальные товары — на сайте» (полныйСписок = false).
    private static let страницДо = 6
    private static let наСтранице = 48

    /// Все объявления продавца, какие нашлись в ленте: страница за страницей, только его (seller_id), без повторов.
    /// все — страницы кончились раньше предела. nil — первая страница не пришла (нет связи или ответ не разобрался).
    private static func товарыЛентой(_ id: String, куки: [String: String]) async -> (товары: [Listing], все: Bool)? {
        var его: [Listing] = []
        var были = Set<String>()
        for номер in 1...страницДо {
            guard let страница = await страницаЛенты(id, номер: номер, куки: куки) else {
                return номер == 1 ? nil : (его, false)
            }
            for товар in страница.items where товар.продавецID == id && были.insert(товар.id).inserted {
                его.append(товар)
            }
            let последняя: Bool = страница.hasMore == false || страница.пришло < наСтранице
            if последняя { return (его, true) }
        }
        return (его, false)
    }

    private static func страницаЛенты(_ id: String, номер: Int, куки: [String: String]) async -> ListingsPage? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "sort", value: "new"),
                         URLQueryItem(name: "page", value: String(номер)),
                         URLQueryItem(name: "per", value: String(наСтранице)),
                         URLQueryItem(name: "seller", value: id)]
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        for (поле, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return nil }
        if let http = пришло.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return try? ListingsAPI.разобрать(пришло.0)
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

// MARK: - Витрина по нику (/s/<ник>, seller.php?u=<ник>)

extension ВитринаПродавцаAPI {
    enum ПоискПоНику: Equatable {
        case найден(String)
        case нетПродавца
        case нетСвязи
    }

    /**
     Ник → номер продавца. JSON-вопроса у сайта нет: seller.php сам ищет продавца по store_handle (?u=) и печатает его
     номер в разметку (const SELLER_ID='…', var SL_SELLER = "…"); не нашёл или витрина скрыта — уводит на
     marketplace.php, где номера нет. Поэтому — одна страница seller.php?u=<ник> с куками веб-сессии, как у витрины.
     */
    static func номерПоНику(_ ник: String) async -> ПоискПоНику {
        let хвост = ник.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ник
        guard let адрес = Config.страницаСайта("seller.php?u=" + хвост) else { return .нетПродавца }
        let куки = await SiteSession.куки()
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("text/html", forHTTPHeaderField: "Accept")
        for (поле, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return .нетСвязи }
        if let http = пришло.1 as? HTTPURLResponse {
            if http.statusCode >= 500 { return .нетСвязи }
            if !(200..<300).contains(http.statusCode) { return .нетПродавца }
        }
        guard let html = String(data: пришло.0, encoding: .utf8) else { return .нетПродавца }
        for метка in ["SELLER_ID='", "SL_SELLER = \""] {
            guard let начало = html.range(of: метка) else { continue }
            let хвостСтроки = html[начало.upperBound...].prefix(80)
            let номер = String(хвостСтроки.prefix(while: { $0 != "'" && $0 != "\"" }))
            if годный(номер) { return .найден(номер) }
        }
        return .нетПродавца
    }
}
