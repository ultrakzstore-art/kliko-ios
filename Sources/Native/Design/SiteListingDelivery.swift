import SwiftUI
import CoreLocation
import UIKit

/**
 ДОСТАВКА В БЛОКЕ «РАСПОЛОЖЕНИЕ» — ТО, ЧТО SiteListingLocation.swift (c7d43c6) НЕ ПЕРЕНЁС, КАК У САЙТА.

 Образец — mkLocationBlock, mkShipRegionsLine, mkBroadcast / mkBcGeo / mkBcSend, mkIntercityToggle / mkCourierLoadLogi,
 mkShipQuote в js/marketplace.min.js; тексты — js/i18n-marketplace-ru.js (ListingLocationText, kk/ru/en/ar).
   · Строка регионов отправки (mkShipRegionsLine): ship_scope «city» — «Доставка только по городу X», «regions» —
     «Доставка только: …» (регион города объявления первым, потом ship_regions, до четырёх названий и «+N»). Ваш город
     (mkWhereAmI) вне списка — «В ваш регион продавец не отправляет — встреча или самовывоз», и «Доставки из …» нет.
   · Крупное (mkIsBulky) и довозимое: чип «Газель / Грузоперевозки» (запрос исполнителям с точкой объявления), а из
     другого города — ещё «Межгород из X» (без точки). Лист запроса — как mkBroadcast: текст (заполнен, как у сайта,
     по-русски: его читают исполнители), город и «Мой адрес», «Отправить запрос». Своё поверх сайта: перед отправкой —
     подтверждение. Запрос — POST broadcast.php {text, section (у грузоперевозок "services", у пустой ленты — её
     раздел), specialty (пусто; у «Нужна помощь?» — SVC_CAT), me_id, city, lat, lon,
     radius_km:2, csrf} с куками веб-сессии и CSRF страницы (SiteSession), ответ ok + count — «Отправлено (N)»,
     ok без count — msg сервера, иначе error.
   · «Доставка из X» / «Доставка X → Y» / «Доставка в другой город» (mkIntercityToggle): у довозимого некрупного, не
     в аренду, если вы не в том же городе и регион не закрыт. Раскрывается и один раз грузит транспортные компании:
     GET chat.php?action=logistics_partners&pid=<id>[&to_city=<ваш город>]. Компания, выбранная продавцом
     (ship_carrier), — первой, с меткой «выбор продавца». Цена «от N ₸» и «+N ₸/кг» — только сведения.
     «Оформить с доставкой» (без аукциона) — сделка с деньгами, только при Config.деньгиСделок и кнопке гаранта у
     объявления: окно «Безопасная сделка» тем же путём, что «Купить безопасно с доставкой» (SiteListingLocation.swift).
     «Собрать ставки от компаний» — mkLogiAuction: POST chat.php?action=logistics_create {pid}, итог строкой под кнопкой.
   · Расчёт доставки (mkShipQuote, GET api/ship_quote.php?item=&lat=&lon=) — в листе курьера, когда ваша точка
     определена: «Доставка ~ N ₸», кто платит и срок. Только сведения — оплаты здесь нет. У сайта offers — объект, его
     первый ключ; JSONSerialization порядка ключей не хранит, поэтому порядок берётся из текста ответа.
 */

private func тДост(_ ключ: String) -> String { ListingLocationText.т(ключ) }

// MARK: - Правила сайта

enum ДоставкаОбъявления {
    /// Строка регионов отправки (mkShipRegionsLine) и признак «в ваш регион не отправляют» (blocked).
    struct СтрокаРегионов: Equatable {
        let текст: String
        let закрыто: Bool
    }

    /// MK_REG_OF сайта: город названием (без учёта регистра) — ключ региона MK_GEO. Сначала города-регионы и
    /// областные центры, потом прочие города областей (первая область выигрывает). Не нашлось — пусто.
    static func регион(города город: String) -> String {
        let искомое = город.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !искомое.isEmpty else { return "" }
        var найдено = ""
        for регион in ГеоДанные.регионы {
            if регион.город && регион.название.lowercased() == искомое { найдено = регион.ключ }
            if !регион.центр.isEmpty && регион.центр.lowercased() == искомое { найдено = регион.ключ }
        }
        if !найдено.isEmpty { return найдено }
        for регион in ГеоДанные.регионы where регион.города.contains(where: { $0.lowercased() == искомое }) {
            return регион.ключ
        }
        return ""
    }

    /// mkShipRegionsLine: nil — продавец отправляет всюду (ship_scope пуст или «all»).
    static func строкаРегионов(_ товар: Listing, мойГород: String) -> СтрокаРегионов? {
        let поля = товар.поляВида
        let куда = (поля.отправкаКуда ?? "").lowercased()
        if куда == "city" {
            let текст = String(format: тДост("ship_only_city"), товар.city)
            let закрыто = !мойГород.isEmpty && !товар.city.isEmpty && мойГород != товар.city
            return СтрокаРегионов(текст: текст, закрыто: закрыто)
        }
        guard куда == "regions" else { return nil }
        var ключи: [String] = []
        let свой = регион(города: товар.city)
        if !свой.isEmpty { ключи.append(свой) }
        for ключ in поля.регионыОтправки where !ключи.contains(ключ) {
            ключи.append(ключ)
        }
        let имена: [String] = ключи.compactMap { ГеоДанные.регион($0)?.название }
        var список = имена.prefix(4).joined(separator: ", ")
        if имена.count > 4 {
            список += " +" + String(имена.count - 4)
        }
        let мой = мойГород.isEmpty ? "" : регион(города: мойГород)
        let закрыто = !мой.isEmpty && !ключи.contains(мой)
        return СтрокаРегионов(текст: String(format: тДост("ship_only_regions"), список), закрыто: закрыто)
    }

    /// Показывать ли «Доставка из …» (f у mkLocationBlock): довозимое некрупное, не в аренду, вы не в том же городе,
    /// регион не закрыт.
    static func естьДоставкаИзГорода(_ товар: Listing, закрыто: Bool) -> Bool {
        let мой = МаршрутОбъявления.мойГород
        let тотЖеГород = !мой.isEmpty && !товар.city.isEmpty && мой == товар.city
        return МаршрутОбъявления.довозимое(товар) && !МаршрутОбъявления.крупное(товар) && !тотЖеГород
            && !товар.forRent && !закрыто
    }

    /// «Доставка Алматы → Астана», «Доставка из Алматы» или «Доставка в другой город».
    static func подписьДоставки(_ товар: Listing) -> String {
        guard !товар.city.isEmpty else { return тДост("delivery_other") }
        if МаршрутОбъявления.изДругогоГорода(товар) {
            return String(format: тДост("delivery_route"), товар.city, МаршрутОбъявления.мойГород)
        }
        return String(format: тДост("delivery_from"), товар.city)
    }

    /// Текст запроса — как у сайта, по-русски: его читают исполнители.
    static let текстГазели = "Нужна газель или грузовик для перевозки крупного товара"

    static func текстМежгорода(_ город: String) -> String {
        "Нужна межгородская грузоперевозка из " + город
    }

    /// 15000 — «15 000» (toLocaleString("ru-RU") у сайта: неразрывный пробел между тысячами).
    static func сумма(_ n: Int) -> String {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"
        ф.usesGroupingSeparator = true
        ф.maximumFractionDigits = 0
        return ф.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Цвет кружка компании — хеш имени, как у сайта (31 * n + код UTF-16, по модулю 2^32).
    static func цветКомпании(_ имя: String) -> Color {
        let палитра: [(Double, Double, Double)] = [
            (0.059, 0.478, 0.267), (0.145, 0.388, 0.922), (0.859, 0.153, 0.467), (0.851, 0.467, 0.024),
            (0.486, 0.227, 0.929), (0.031, 0.569, 0.698), (0.882, 0.114, 0.282), (0.020, 0.588, 0.412)
        ]
        let строка = имя.isEmpty ? "?" : имя
        var n: UInt32 = 0
        for код in строка.utf16 {
            n = n &* 31 &+ UInt32(код)
        }
        let ц = палитра[Int(n % UInt32(палитра.count))]
        return Color(red: ц.0, green: ц.1, blue: ц.2)
    }
}

// MARK: - Запросы к сайту

/// Транспортная компания из chat.php?action=logistics_partners.
struct ПартнёрДоставкиТК: Identifiable, Hashable {
    let id: String
    let имя: String
    /// integrated — цена и срок считаются при оформлении.
    let встроенная: Bool
    let заметка: String?
    let тариф: String?
    let база: Int
    let заКг: Int
    var выборПродавца = false
}

/// Ответ logistics_partners: межгород ли, откуда и куда, компании и какой шаг предлагает сайт дальше.
struct ОтветЛогистики {
    var межгород: Bool
    var откуда: String?
    var куда: String?
    /// auction === false у сайта — «Оформить с доставкой», иначе — «Собрать ставки».
    var безАукциона: Bool
    var партнёры: [ПартнёрДоставкиТК]
}

/// Расчёт доставки (api/ship_quote.php) — только сведения.
struct КотировкаДоставки: Equatable {
    var бесплатно: Bool
    var цена: Int
    var имя: String?
    var днейОт: Int?
    var днейДо: Int?
    var минут: Int?
}

enum ДоставкаТКAPI {
    enum ИтогЗапроса: Equatable {
        case отправлено(Int)
        case сообщение(String)
        case ошибка(String)
        /// Нет CSRF — страница сайта не загружена.
        case нетСессии
        case сеть
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    @MainActor
    private static func получить(_ путь: String, _ пункты: [URLQueryItem]) async -> [String: Any]? {
        await получитьСТекстом(путь, пункты)?.json
    }

    /// То же, но и текст ответа: по нему восстанавливается порядок ключей объекта (JSONSerialization его не хранит).
    @MainActor
    private static func получитьСТекстом(_ путь: String, _ пункты: [URLQueryItem]) async
        -> (json: [String: Any], текст: String)? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent(путь), resolvingAgainstBaseURL: false)
        ч?.queryItems = пункты
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await SiteSession.куки() {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }
        guard let результат = try? await сессия.data(for: запрос),
              let j = (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any] else { return nil }
        return (j, String(decoding: результат.0, as: UTF8.self))
    }

    /// Ключи объекта offers в порядке ответа сервера: по месту «"ключ"» в тексте после «"offers"». Не нашёлся — в конец.
    static func вПорядкеОтвета(_ ключи: [String], текст: String) -> [String] {
        let начало = текст.range(of: "\"offers\"")?.upperBound ?? текст.startIndex
        let хвост = текст[начало...]
        func место(_ ключ: String) -> Int {
            guard let r = хвост.range(of: "\"" + ключ + "\"") else { return Int.max }
            return хвост.distance(from: хвост.startIndex, to: r.lowerBound)
        }
        let места = Dictionary(uniqueKeysWithValues: ключи.map { ($0, место($0)) })
        return ключи.sorted { а, б in
            let ма = места[а] ?? Int.max
            let мб = места[б] ?? Int.max
            return ма == мб ? а < б : ма < мб
        }
    }

    /// mkCourierLoadLogi: компании для объявления; ship_carrier продавца — первой.
    @MainActor
    static func партнёры(объявление: String, мойГород: String, выборПродавца: String?) async -> ОтветЛогистики? {
        var пункты = [URLQueryItem(name: "action", value: "logistics_partners"),
                      URLQueryItem(name: "pid", value: объявление)]
        if !мойГород.isEmpty {
            пункты.append(URLQueryItem(name: "to_city", value: мойГород))
        }
        guard let j = await получить("chat.php", пункты), да(j["ok"]) else { return nil }
        let сырые = (j["partners"] as? [[String: Any]]) ?? []
        var список: [ПартнёрДоставкиТК] = []
        for (номер, п) in сырые.enumerated() {
            let имя = строка(п["name"]) ?? "?"
            список.append(ПартнёрДоставкиТК(id: строка(п["id"]) ?? ("p" + String(номер)),
                                            имя: имя,
                                            встроенная: да(п["integrated"]),
                                            заметка: строка(п["note"]),
                                            тариф: строка(п["tariff"]),
                                            база: число(п["base"]) ?? 0,
                                            заКг: число(п["per_kg"]) ?? 0))
        }
        if let выбор = выборПродавца, !выбор.isEmpty,
           let место = список.firstIndex(where: { $0.id == выбор }) {
            var первый = список.remove(at: место)
            первый.выборПродавца = true
            список.insert(первый, at: 0)
        }
        return ОтветЛогистики(межгород: да(j["intercity"]),
                              откуда: строка(j["from_city"]),
                              куда: строка(j["to_city"]),
                              безАукциона: (j["auction"] as? Bool) == false,
                              партнёры: список)
    }

    /// mkShipQuote: расчёт доставки до вашей точки. Не ok или «off» — nil.
    @MainActor
    static func котировка(объявление: String, точка: CLLocationCoordinate2D) async -> КотировкаДоставки? {
        let пункты = [URLQueryItem(name: "item", value: объявление),
                      URLQueryItem(name: "lat", value: МаршрутОбъявления.число(точка.latitude)),
                      URLQueryItem(name: "lon", value: МаршрутОбъявления.число(точка.longitude))]
        guard let ответ = await получитьСТекстом("api/ship_quote.php", пункты), да(ответ.json["ok"]) else { return nil }
        let j = ответ.json
        if строка(j["mode"]) == "carriers" {
            /* Как у сайта (for..in и break): первое предложение ответа. */
            let предложения = (j["offers"] as? [String: Any]) ?? [:]
            let первый = вПорядкеОтвета(Array(предложения.keys), текст: ответ.текст)
                .first { предложения[$0] is [String: Any] }
            guard let ключ = первый, let п = предложения[ключ] as? [String: Any] else { return nil }
            return КотировкаДоставки(бесплатно: false, цена: число(п["price"]) ?? 0, имя: строка(п["name"]),
                                     днейОт: число(п["days_min"]), днейДо: число(п["days_max"]), минут: nil)
        }
        if да(j["free"]) {
            return КотировкаДоставки(бесплатно: true, цена: 0, имя: nil, днейОт: nil, днейДо: nil, минут: nil)
        }
        let минут = число(j["eta"]) ?? 0
        return КотировкаДоставки(бесплатно: false, цена: число(j["price"]) ?? 0, имя: nil, днейОт: nil, днейДо: nil,
                                 минут: минут > 0 ? минут : nil)
    }

    /// mkBcSend: POST broadcast.php с CSRF страницы и куками веб-сессии. раздел — section тела: у сайта первый аргумент
    /// mkBroadcast (грузоперевозки — «services», пустая лента — mkSt.cat или «other»).
    @MainActor
    static func отправитьЗапрос(текст: String, город: String, широта: String, долгота: String,
                                раздел: String = "services", специальность: String = "") async -> ИтогЗапроса {
        let состояние = await SiteSession.состояние()
        guard let csrf = состояние.csrf else { return .нетСессии }
        guard let адрес = URL(string: "broadcast.php", relativeTo: Config.apiBase)?.absoluteURL else { return .сеть }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (имя, значение) in await SiteSession.куки() {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }
        let тело: [String: Any] = [
            "text": текст, "section": раздел.isEmpty ? "other" : раздел, "specialty": специальность,
            "me_id": состояние.пользователь ?? "",
            "city": город, "lat": широта, "lon": долгота, "radius_km": 2, "csrf": csrf
        ]
        запрос.httpBody = try? JSONSerialization.data(withJSONObject: тело)
        guard let результат = try? await сессия.data(for: запрос),
              let j = (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any] else {
            return .сеть
        }
        if да(j["ok"]) {
            let сколько = число(j["count"]) ?? 0
            if сколько > 0 { return .отправлено(сколько) }
            return .сообщение(строка(j["msg"]) ?? "")
        }
        return .ошибка(строка(j["error"]) ?? тДост("error_short"))
    }

    enum ИтогСтавок: Equatable {
        case отправлено
        case войти
        case ошибка
        case сеть
    }

    /// mkLogiAuction: POST chat.php?action=logistics_create {pid} с куками веб-сессии — заявка компаниям, ставки
    /// потом в кабинете («Мои доставки»). error "auth" — надо войти.
    @MainActor
    static func собратьСтавки(объявление: String) async -> ИтогСтавок {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("chat.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: "logistics_create")]
        guard let адрес = ч?.url else { return .сеть }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (имя, значение) in await SiteSession.куки() {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }
        запрос.httpBody = try? JSONSerialization.data(withJSONObject: ["pid": объявление])
        guard let результат = try? await сессия.data(for: запрос),
              let j = (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any] else {
            return .сеть
        }
        if да(j["ok"]) { return .отправлено }
        return строка(j["error"]) == "auth" ? .войти : .ошибка
    }

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

    static func число(_ значение: Any?) -> Int? {
        if let n = значение as? NSNumber { return n.intValue }
        if let s = значение as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return Int(d) }
        return nil
    }
}

// MARK: - Строка регионов отправки (.mk-loc-shipreg / .mk-loc-shipno)

struct СтрокаРегионовОтправки: View {
    let строка: ДоставкаОбъявления.СтрокаРегионов

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "truck.box")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .accessibilityHidden(true)
                Text(строка.текст)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if строка.закрыто {
                Text(тДост("ship_not_yours"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.оранжевый.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
    }
}

// MARK: - «Газель / Грузоперевозки» и «Межгород из …» (mkBroadcast)

/// Что уйдёт исполнителям: текст, город и точка (у межгорода точки нет, как у сайта).
struct ЗапросИсполнителям: Identifiable, Hashable {
    let id = UUID()
    let текст: String
    let город: String
    let широта: String
    let долгота: String
    /// section запроса (первый аргумент mkBroadcast): по умолчанию «services», как у грузоперевозок; пустая лента
    /// передаёт свой раздел (mkAskSellers: mkSt.cat или «other»).
    var раздел: String = "services"
    /// specialty запроса (последний аргумент mkBroadcast, SVC_CAT сайта): у пилюль «Нужна помощь?» — раздел услуг
    /// («evacuation», «moving-service»…), у грузоперевозок и пустой ленты — пусто.
    var специальность: String = ""
}

/// Чипы крупного товара: газель всегда, межгород — если вы смотрите из другого города.
struct ЧипыГрузоперевозокСайта: View {
    let товар: Listing
    let другойГород: Bool

    @State private var запрос: ЗапросИсполнителям?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { чипы }
            VStack(alignment: .leading, spacing: 8) { чипы }
        }
        .sheet(item: $запрос) { какой in
            ЛистЗапросаИсполнителям(запрос: какой)
        }
    }

    @ViewBuilder
    private var чипы: some View {
        Button { запрос = газель } label: {
            ЧипМестаСайта(значок: "truck.box", текст: тДост("gazelle_freight"))
        }
        .buttonStyle(.plain)
        if другойГород && !товар.city.isEmpty {
            Button { запрос = межгород } label: {
                ЧипМестаСайта(значок: "truck.box.fill", текст: String(format: тДост("intercity_from"), товар.city))
            }
            .buttonStyle(.plain)
        }
    }

    private var газель: ЗапросИсполнителям {
        let поля = товар.поляВида
        return ЗапросИсполнителям(текст: ДоставкаОбъявления.текстГазели, город: товар.city,
                                  широта: поля.широта.map { МаршрутОбъявления.число($0) } ?? "",
                                  долгота: поля.долгота.map { МаршрутОбъявления.число($0) } ?? "")
    }

    private var межгород: ЗапросИсполнителям {
        ЗапросИсполнителям(текст: ДоставкаОбъявления.текстМежгорода(товар.city), город: товар.city,
                           широта: "", долгота: "")
    }
}

/// Лист .mk-bc: текст, город и «Мой адрес», подтверждение и отправка.
struct ЛистЗапросаИсполнителям: View {
    let запрос: ЗапросИсполнителям

    @Environment(\.dismiss) private var закрыть
    @State private var текст: String
    @State private var город: String
    @State private var широта: String
    @State private var долгота: String
    @State private var статус: Статус = .нет
    @State private var спросить = false
    @State private var отправляем = false
    @State private var отправлено = false
    @State private var гео = ГеопозицияКарты()
    @FocusState private var вПоле: Bool

    enum Статус: Equatable {
        case нет, ищем, найден, нетДоступа, нетГорода, пусто, итог(String, Bool)
    }

    init(запрос: ЗапросИсполнителям) {
        self.запрос = запрос
        _текст = State(initialValue: запрос.текст)
        _город = State(initialValue: запрос.город)
        _широта = State(initialValue: запрос.широта)
        _долгота = State(initialValue: запрос.долгота)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(тДост("bc_head"), systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЗакрытьМеста { закрыть() }
                }
                Text(тДост("bc_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                поле
                HStack(spacing: 10) {
                    Label(город.isEmpty ? тДост("city_fail") : город, systemImage: "mappin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { определить() } label: {
                        Label(тДост("my_address"), systemImage: "location.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.зелёный2)
                    }
                    .buttonStyle(.plain)
                    .disabled(статус == .ищем)
                }
                if let строка = строкаСтатуса {
                    строка
                }
                Button {
                    вПоле = false
                    if текст.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        статус = .пусто
                    } else {
                        спросить = true
                    }
                } label: {
                    Label(тДост(отправлено ? "request_sent" : (отправляем ? "report_sending" : "send_request")),
                          systemImage: отправлено ? "checkmark" : "paperplane.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.зелёный2.opacity(отправляем || отправлено ? 0.6 : 1),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                .disabled(отправляем || отправлено)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        /* По высоте содержимого, без пустоты под кнопкой. */
        .листПоВысоте()
        .alert(тДост("bc_confirm_t"), isPresented: $спросить) {
            Button(тДост("send_request")) { отправить() }
            Button(тДост("cancel"), role: .cancel) {}
        } message: {
            Text(тДост("bc_confirm_s"))
        }
    }

    private var поле: some View {
        ZStack(alignment: .topLeading) {
            if текст.isEmpty {
                Text(тДост("ph_broadcast"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $текст)
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .scrollContentBackground(.hidden)
                .focused($вПоле)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(minHeight: 110)
        }
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var строкаСтатуса: AnyView? {
        let надпись: String
        let значок: String
        let цвет: Color
        switch статус {
        case .нет:
            return nil
        case .ищем:
            надпись = тДост("detecting_addr"); значок = "location"; цвет = Theme.текстВторой
        case .найден:
            надпись = тДост("addr_detected"); значок = "checkmark.circle.fill"; цвет = Theme.зелёный2
        case .нетДоступа:
            надпись = тДост("no_geo_access"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .нетГорода:
            надпись = тДост("city_fail"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .пусто:
            надпись = тДост("write_need"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .итог(let текстИтога, let удачно):
            надпись = текстИтога
            значок = удачно ? "checkmark.circle.fill" : "info.circle"
            цвет = удачно ? Theme.зелёный2 : Theme.текстВторой
        }
        return AnyView(
            Label(надпись, systemImage: значок)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(цвет)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    /// mkBcGeo: точка телефона и город по ней. Разрешение спрашивается здесь — по нажатию.
    private func определить() {
        статус = .ищем
        гео.узнать { координата in
            Task { @MainActor in
                guard let координата else {
                    статус = .нетДоступа
                    return
                }
                широта = String(координата.latitude)
                долгота = String(координата.longitude)
                let место = CLLocation(latitude: координата.latitude, longitude: координата.longitude)
                let найдено = try? await CLGeocoder().reverseGeocodeLocation(место)
                if let имя = найдено?.first?.locality, !имя.isEmpty {
                    город = имя
                    статус = .найден
                } else {
                    статус = .нетГорода
                }
            }
        }
    }

    private func отправить() {
        отправляем = true
        статус = .нет
        let чтоОтправить = текст
        Task { @MainActor in
            let итог = await ДоставкаТКAPI.отправитьЗапрос(текст: чтоОтправить, город: город,
                                                           широта: широта, долгота: долгота,
                                                           раздел: запрос.раздел,
                                                           специальность: запрос.специальность)
            отправляем = false
            switch итог {
            case .отправлено(let сколько):
                отправлено = true
                статус = .итог(String(format: тДост("request_sent_n"), String(сколько)), true)
            case .сообщение(let текстСервера):
                статус = .итог(текстСервера.isEmpty ? тДост("request_sent") : текстСервера, false)
            case .ошибка(let текстОшибки):
                статус = .итог(текстОшибки, false)
            case .нетСессии:
                /* Не вошли — своё окно входа, а не страница сайта (как у панели связи); вошли — просто ещё раз. */
                if await SiteSession.состояние().вошёл == true {
                    статус = .итог(тДост("need_session"), false)
                } else {
                    статус = .нет
                    закрыть()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        if !ОкнаПриложения.shared.показать(.вход) { ВходПоверх.показать() }
                    }
                }
            case .сеть:
                статус = .итог(тДост("net_error"), false)
            }
        }
    }
}

// MARK: - «Доставка из …» и транспортные компании (mkIntercityToggle / mkCourierLoadLogi)

struct ДоставкаИзГородаСайта: View {
    let товар: Listing
    /// 🔴 «Оформить с доставкой» / «Собрать ставки» — сделка с деньгами; nil, пока Config.деньгиСделок выключен.
    let оформить: (() -> Void)?

    @State private var открыто = false
    @State private var загрузка: Загрузка = .нет

    enum Загрузка {
        case нет, идёт, сбой
        case готово(ОтветЛогистики)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { открыто.toggle() }
                if открыто, case .нет = загрузка {
                    загрузить()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "truck.box")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.зелёный2)
                        .accessibilityHidden(true)
                    Text(ДоставкаОбъявления.подписьДоставки(товар))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .rotationEffect(.degrees(открыто ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
            if открыто {
                панель
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var панель: some View {
        switch загрузка {
        case .нет, .сбой:
            EmptyView()
        case .идёт:
            HStack(spacing: 8) {
                ProgressView()
                Text(тДост("logi_loading"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(.vertical, 6)
        case .готово(let ответ):
            if ответ.партнёры.isEmpty {
                Text(тДост("logi_none"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.vertical, 6)
            } else {
                КарточкаТКСайта(товар: товар, ответ: ответ, оформить: оформить)
            }
        }
    }

    private func загрузить() {
        загрузка = .идёт
        let номер = товар.id
        let мойГород = МаршрутОбъявления.мойГород
        let выбор = товар.поляВида.перевозчик
        Task { @MainActor in
            if let ответ = await ДоставкаТКAPI.партнёры(объявление: номер, мойГород: мойГород, выборПродавца: выбор) {
                загрузка = .готово(ответ)
            } else {
                // Как у сайта: не загрузилось — панели нет.
                загрузка = .сбой
            }
        }
    }
}

/// Мятная карточка «Межгород-доставка» со списком компаний.
private struct КарточкаТКСайта: View {
    let товар: Listing
    let ответ: ОтветЛогистики
    let оформить: (() -> Void)?

    @State private var ставки: Ставки = .нет

    /// «Собрать ставки от компаний»: кнопка, отправка, итог (тост сайта — строкой под кнопкой).
    enum Ставки: Equatable {
        case нет, идёт
        case итог(String, Bool)
    }

    private var маршрут: String? {
        guard let а = ответ.откуда, let б = ответ.куда else { return nil }
        return а + " → " + б
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(тДост(ответ.межгород ? "logi_intercity_h" : "logi_other_h"))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.зелёный2)
                    if let маршрут {
                        Text(маршрут)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
            }
            if товар.доставкаБесплатно {
                Label(тДост("logi_free"), systemImage: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.оттенокАкцента,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            Text(тДост("delivered_by_tk"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .padding(.top, 2)
            VStack(spacing: 0) {
                ForEach(ответ.партнёры) { п in
                    СтрокаПартнёраТК(партнёр: п)
                }
            }
            кнопкаДальше
        }
        .padding(14)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.оттенокАкцента, lineWidth: 1.5)
        }
    }

    /// Без аукциона — 🔴 «Оформить с доставкой» (сделка с деньгами: окно «Безопасная сделка», если гарант у объявления
    /// есть), иначе — «Собрать ставки» (mkLogiAuction: заявка компаниям, денег не трогает).
    @ViewBuilder
    private var кнопкаДальше: some View {
        if ответ.безАукциона {
            if !товар.безГаранта, let оформить {
                Button(action: оформить) {
                    Text(тДост("logi_car_cta"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.зелёный2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                .padding(.top, 4)
            }
        } else if case .итог(let текст, let удачно) = ставки, удачно {
            Label(текст, systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } else {
            Button { собратьСтавки() } label: {
                Label(тДост(ставки == .идёт ? "bids_sending" : "collect_bids"), systemImage: "bolt.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.зелёный2,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
            .disabled(ставки == .идёт)
            .padding(.top, 4)
            if case .итог(let текст, _) = ставки {
                Text(текст)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Text(тДост("collect_bids_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func собратьСтавки() {
        guard ставки != .идёт else { return }
        ставки = .идёт
        let номер = товар.id
        Task { @MainActor in
            switch await ДоставкаТКAPI.собратьСтавки(объявление: номер) {
            case .отправлено:
                ставки = .итог(тДост("bids_sent"), true)
            case .войти:
                ставки = .итог(тДост("bids_auth"), false)
            case .ошибка:
                ставки = .итог(тДост("bids_fail"), false)
            case .сеть:
                ставки = .итог(тДост("net_error"), false)
            }
        }
    }
}

/// Строка компании: цветной квадрат с буквой, имя (и «выбор продавца»), заметка, цена «от N ₸».
private struct СтрокаПартнёраТК: View {
    let партнёр: ПартнёрДоставкиТК

    private var буква: String {
        let имя = партнёр.имя.trimmingCharacters(in: .whitespaces)
        return имя.first.map { String($0).uppercased() } ?? "?"
    }

    private var подпись: String? {
        if партнёр.встроенная { return тДост("logi_car_note") }
        return партнёр.заметка ?? партнёр.тариф
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(буква)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ДоставкаОбъявления.цветКомпании(партнёр.имя),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(партнёр.имя)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if партнёр.выборПродавца {
                        Text(тДост("seller_choice"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                if let подпись {
                    HStack(spacing: 4) {
                        if партнёр.встроенная || партнёр.заметка != nil {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                        }
                        Text(подпись)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if партнёр.база > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: тДост("logi_price_from"), ДоставкаОбъявления.сумма(партнёр.база)))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.зелёный2)
                        .lineLimit(1)
                        .fixedSize()
                    if партнёр.заКг > 0 {
                        Text(String(format: тДост("logi_per_kg"), ДоставкаОбъявления.сумма(партнёр.заКг)))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, партнёр.выборПродавца ? 6 : 0)
        .background {
            if партнёр.выборПродавца {
                RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous).fill(Theme.оттенокАкцента)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1).accessibilityHidden(true)
        }
    }
}

// MARK: - Расчёт доставки в листе курьера (mkShipQuote) — только сведения

struct КотировкаДоставкиСайта: View {
    let товар: Listing
    let точка: CLLocationCoordinate2D

    @State private var котировка: КотировкаДоставки?

    private var ключ: String {
        товар.id + "|" + МаршрутОбъявления.число(точка.latitude) + "," + МаршрутОбъявления.число(точка.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let к = котировка {
                /* .mk-ship-quote: заголовок цветом текста на surf2. Порядок строк — как у сайта: у компаний «имя · срок»,
                   потом кто платит; у курьера кто платит, потом «~N мин в пути». */
                VStack(alignment: .leading, spacing: 3) {
                    if к.бесплатно {
                        Text(тДост("co_ship_free"))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                    } else {
                        Text(String(format: тДост("ship_quote"), ДоставкаОбъявления.сумма(к.цена) + "\u{00A0}₸"))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        if к.минут == nil, let строкаСрока = срок(к) {
                            строкаКотировки(строкаСрока)
                        }
                        строкаКотировки(тДост("ship_quote_who"))
                        if к.минут != nil, let строкаСрока = срок(к) {
                            строкаКотировки(строкаСрока)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
        }
        .task(id: ключ) {
            котировка = nil
            котировка = await ДоставкаТКAPI.котировка(объявление: товар.id, точка: точка)
        }
    }

    private func строкаКотировки(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 12))
            .foregroundStyle(Theme.текстВторой)
    }

    /// «СДЭК · 2–4 дн.» у компаний, «~25 мин в пути» у курьера.
    private func срок(_ к: КотировкаДоставки) -> String? {
        if let от = к.днейОт, let до = к.днейДо {
            let дни = от == до
                ? String(format: тДост("eta_days_one"), String(от))
                : String(format: тДост("eta_days"), String(от), String(до))
            if let имя = к.имя { return имя + " · " + дни }
            return дни
        }
        if let минут = к.минут {
            return String(format: тДост("ship_eta"), String(минут))
        }
        return к.имя
    }
}
