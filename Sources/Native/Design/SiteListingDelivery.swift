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
     раздел), specialty:"", me_id, city, lat, lon,
     radius_km:2, csrf} с куками веб-сессии и CSRF страницы (SiteSession), ответ ok + count — «Отправлено (N)»,
     ok без count — msg сервера, иначе error.
   · «Доставка из X» / «Доставка X → Y» / «Доставка в другой город» (mkIntercityToggle): у довозимого некрупного, не
     в аренду, если вы не в том же городе и регион не закрыт. Раскрывается и один раз грузит транспортные компании:
     GET chat.php?action=logistics_partners&pid=<id>[&to_city=<ваш город>]. Компания, выбранная продавцом
     (ship_carrier), — первой, с меткой «выбор продавца». Цена «от N ₸» и «+N ₸/кг» — только сведения.
     «Оформить с доставкой» / «Собрать ставки от компаний» ведут в сделку с деньгами — только при Config.деньгиСделок
     (сейчас false), и тогда открывают страницу объявления сайта.
   · Расчёт доставки (mkShipQuote, GET api/ship_quote.php?item=&lat=&lon=) — в листе курьера, когда ваша точка
     определена: «Доставка ~ N ₸», кто платит и срок. Только сведения — оплаты здесь нет. У сайта offers — объект, его
     первый ключ; JSONSerialization порядка ключей не хранит, поэтому здесь берётся самое дешёвое предложение.
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
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent(путь), resolvingAgainstBaseURL: false)
        ч?.queryItems = пункты
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await SiteSession.куки() {
            запрос.setValue(значение, forHTTPHeaderField: имя)
        }
        guard let результат = try? await сессия.data(for: запрос) else { return nil }
        return (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any]
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
        guard let j = await получить("api/ship_quote.php", пункты), да(j["ok"]) else { return nil }
        if строка(j["mode"]) == "carriers" {
            let предложения = (j["offers"] as? [String: Any]) ?? [:]
            var лучшее: [String: Any]?
            var лучшаяЦена = Int.max
            for ключ in предложения.keys.sorted() {
                guard let п = предложения[ключ] as? [String: Any] else { continue }
                let цена = число(п["price"]) ?? 0
                if лучшее == nil || (цена > 0 && цена < лучшаяЦена) {
                    лучшее = п
                    лучшаяЦена = цена
                }
            }
            guard let п = лучшее else { return nil }
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
                                раздел: String = "services") async -> ИтогЗапроса {
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
            "text": текст, "section": раздел.isEmpty ? "other" : раздел, "specialty": "",
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
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
                                                           раздел: запрос.раздел)
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
            if Config.деньгиСделок, let оформить {
                кнопкаДальше(оформить)
            }
        }
        .padding(14)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.оттенокАкцента, lineWidth: 1.5)
        }
    }

    /// 🔴 Сделка с деньгами: без аукциона — «Оформить с доставкой» (если гарант не выключен), иначе — «Собрать ставки».
    @ViewBuilder
    private func кнопкаДальше(_ действие: @escaping () -> Void) -> some View {
        if ответ.безАукциона {
            if !товар.безГаранта {
                Button(action: действие) {
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
        } else {
            Button(action: действие) {
                Label(тДост("collect_bids"), systemImage: "bolt.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.зелёный2,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
            .padding(.top, 4)
            Text(тДост("collect_bids_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
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
                VStack(alignment: .leading, spacing: 3) {
                    if к.бесплатно {
                        Text(тДост("co_ship_free"))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.зелёный2)
                    } else {
                        Text(String(format: тДост("ship_quote"), ДоставкаОбъявления.сумма(к.цена) + "\u{00A0}₸"))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.зелёный2)
                        if let строкаСрока = срок(к) {
                            Text(строкаСрока)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        Text(тДост("ship_quote_who"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
        }
        .task(id: ключ) {
            котировка = nil
            котировка = await ДоставкаТКAPI.котировка(объявление: товар.id, точка: точка)
        }
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

// MARK: - «Нужна помощь?» (mkServiceBlock) — услуги рядом по разделу

/**
 Под «Расположением» у не-услуг — .mk-svc сайта: «НУЖНА ПОМОЩЬ?» с пульсирующей точкой и пилюли услуг по разделу
 объявления (MK_SVC_MAP.M, с подъёмом к родителю и к корню; ничего — «Найти специалиста»). Нажатие — тот же запрос
 исполнителям рядом (mkBroadcast), что у грузоперевозок: ЛистЗапросаИсполнителям с текстом услуги, городом и точкой.
 */
struct БлокУслугСайта: View {
    let товар: Listing
    @State private var запрос: ЗапросИсполнителям?
    @State private var пульс = false

    init(товар: Listing) {
        self.товар = товар
    }

    /// Ключи пилюль: раздел, его родители, корень; нет — «spec».
    static func ключи(_ товар: Listing) -> [String] {
        var раздел = товар.категория
        var шагов = 0
        while let р = раздел, шагов < 25 {
            if let набор = ТекстыУслугРядом.разделы[р] { return набор }
            раздел = РазделыСайта.родитель(р)
            шагов += 1
        }
        return ТекстыУслугРядом.разделы[товар.корень] ?? ["spec"]
    }

    var body: some View {
        let ключи = Self.ключи(товар).filter { ТекстыУслугРядом.значки[$0] != nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(RadialGradient(colors: [Color(uiColor: Theme.hex(0x4FD9A4)), Theme.зелёный2],
                                         center: UnitPoint(x: 0.32, y: 0.3), startRadius: 0, endRadius: 6))
                    .frame(width: 9, height: 9)
                    .background {
                        Circle()
                            .fill(Theme.зелёный2.opacity(пульс ? 0.05 : 0.22))
                            .frame(width: пульс ? 21 : 15, height: пульс ? 21 : 15)
                    }
                    .accessibilityHidden(true)
                Text(ТекстыУслугРядом.т("need_help").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            ПереносСтрок(промежуток: 6, междуСтрок: 6) {
                ForEach(ключи, id: \.self) { ключ in
                    Button { запрос = запросПо(ключ) } label: {
                        ПилюляУслугиСайта(значок: ТекстыУслугРядом.значки[ключ] ?? "wrench.and.screwdriver",
                                          текст: ТекстыУслугРядом.т("svc_" + ключ))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Theme.цвет(светлый: Theme.hex(0xF4F8F6), тёмный: Theme.hex(0x163024, 0.45))
                RadialGradient(colors: [Theme.оттенокАкцента, Color.clear], center: .topLeading, startRadius: 0,
                               endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .shadow(color: Color(red: 16 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.08), radius: 8, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.оттенокАкцента, lineWidth: 1)
        }
        .onAppear {
            guard !ДвижениеСайта.тихо else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { пульс = true }
        }
        .sheet(item: $запрос) { какой in
            ЛистЗапросаИсполнителям(запрос: какой)
        }
    }

    private func запросПо(_ ключ: String) -> ЗапросИсполнителям {
        let широта = товар.поляВида.широта.map { String($0) } ?? ""
        let долгота = товар.поляВида.долгота.map { String($0) } ?? ""
        return ЗапросИсполнителям(текст: ТекстыУслугРядом.вопрос(ключ), город: товар.city, широта: широта,
                                  долгота: долгота, раздел: "services")
    }
}

/// .mk-svc-chip в .mk-mwrap: пилюля 32 pt, значок 14 зелёным (0,82), текст 12 полужирным.
private struct ПилюляУслугиСайта: View {
    let значок: String
    let текст: String

    private static let фон = Theme.цвет(светлый: Theme.hex(0xFFFFFF), тёмный: Theme.hex(0xFFFFFF, 0.05))
    private static let рамка = Theme.цвет(светлый: Theme.hex(0x1D7D4A, 0.10), тёмный: Theme.hex(0xFFFFFF, 0.12))
    private static let краска = Theme.цвет(0x1D7D4A, 0xD8EFE2)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: значок)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .opacity(0.82)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.краска)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(Self.фон, in: Capsule())
        .overlay { Capsule().strokeBorder(Self.рамка, lineWidth: 1) }
        .contentShape(Capsule())
    }
}

/// Словарь MK_SVC_MAP сайта (T — значок, подпись, вопрос; M — пилюли раздела) и тексты блока на языке телефона.
enum ТекстыУслугРядом {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// Текст запроса исполнителям (T[ключ][3] / svcq_<ключ>); у «spec» — пусто, человек пишет сам.
    static func вопрос(_ ключ: String) -> String {
        let текст = т("q_" + ключ)
        return текст.hasPrefix("q_") ? "" : текст
    }

    static let значки: [String: String] = [
        "evak": "car",
        "sto": "wrench.and.screwdriver",
        "tire": "circle.circle",
        "carwash": "drop",
        "autoexp": "magnifyingglass",
        "autopaint": "paintbrush",
        "autoglass": "eye",
        "autoelec": "bolt",
        "diag": "cpu",
        "microfix": "wrench.and.screwdriver",
        "boatfix": "wrench.and.screwdriver",
        "realtor": "house",
        "jurcheck": "checkmark.shield",
        "renovate": "wrench.and.screwdriver",
        "mover": "truck.box",
        "plumb": "drop",
        "electro": "bolt",
        "wininstall": "door.left.hand.closed",
        "winrepair": "wrench.and.screwdriver",
        "mosquito": "square.grid.3x3",
        "phonefix": "iphone",
        "screen": "iphone",
        "battery": "bolt",
        "lapfix": "laptopcomputer",
        "pcfix": "cpu",
        "upgrade": "cpu",
        "virus": "checkmark.shield",
        "os": "wrench.and.screwdriver",
        "tvfix": "tv",
        "fridgefix": "wrench.and.screwdriver",
        "washfix": "wrench.and.screwdriver",
        "acfix": "wind",
        "acinstall": "wind",
        "delivery": "truck.box",
        "assembly": "wrench.and.screwdriver",
        "bigdeliv": "truck.box",
        "vet": "pawprint",
        "grooming": "scissors",
        "pet-walk": "pawprint",
        "tailor": "tshirt",
        "shoefix": "shoeprints.fill",
        "babycour": "truck.box",
        "sportcour": "truck.box",
        "trainer": "dumbbell",
        "photosvc": "camera",
        "dronsvc": "airplane",
        "spec": "dot.radiowaves.left.and.right",
    ]

    static let разделы: [String: [String]] = [
        "transport": ["evak", "sto", "tire", "carwash", "autoexp"],
        "cars": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-sedan": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-suv": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-electric": ["evak", "sto", "autoelec", "diag", "carwash"],
        "motorcycles": ["sto", "tire", "carwash", "spec"],
        "scooters": ["sto", "tire", "carwash", "spec"],
        "e-scooters": ["microfix", "delivery", "spec"],
        "trucks-special": ["evak", "sto", "tire", "spec"],
        "auto-parts": ["sto", "autoelec", "diag", "spec"],
        "tires-wheels": ["tire", "sto", "spec"],
        "water-transport": ["boatfix", "bigdeliv", "spec"],
        "boats": ["boatfix", "bigdeliv", "spec"],
        "jet-skis": ["boatfix", "bigdeliv", "spec"],
        "realty": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "apartments": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "rooms": ["realtor", "renovate", "mover", "plumb", "electro"],
        "houses": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "cottages": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "commercial-realty": ["realtor", "jurcheck", "renovate", "electro"],
        "land": ["realtor", "jurcheck", "spec"],
        "windows-doors": ["wininstall", "winrepair", "mosquito", "electro"],
        "repair": ["plumb", "electro", "mover", "renovate", "wininstall"],
        "home-garden": ["renovate", "mover", "assembly", "plumb", "electro", "wininstall"],
        "phones-tablets": ["phonefix", "screen", "battery"],
        "smartphones": ["phonefix", "screen", "battery"],
        "tablets": ["phonefix", "screen", "battery"],
        "phone-parts": ["phonefix", "screen", "battery", "spec"],
        "computers": ["lapfix", "pcfix", "upgrade", "virus", "os"],
        "laptops": ["lapfix", "upgrade", "virus", "os"],
        "desktops": ["pcfix", "upgrade", "virus", "os"],
        "pc-components": ["pcfix", "upgrade", "spec"],
        "monitors": ["spec"],
        "tv-audio": ["tvfix"],
        "tv": ["tvfix"],
        "appliances": ["fridgefix", "washfix", "acfix"],
        "fridges": ["fridgefix"],
        "washing-machines": ["washfix"],
        "air-conditioners": ["acfix", "acinstall"],
        "furniture": ["assembly", "mover"],
        "sofas": ["assembly", "mover"],
        "beds": ["assembly", "mover"],
        "wardrobes": ["assembly", "mover"],
        "animals": ["vet", "grooming", "pet-walk"],
        "dogs": ["vet", "grooming", "pet-walk"],
        "cats": ["vet", "grooming"],
        "clothing": ["tailor", "shoefix"],
        "shoes": ["shoefix", "tailor"],
        "kids": ["babycour", "spec"],
        "strollers-carseats": ["babycour", "assembly"],
        "sport": ["trainer", "spec"],
        "bicycles": ["microfix", "delivery", "spec"],
        "fitness": ["trainer", "assembly"],
        "photo-video": ["photosvc", "dronsvc"],
        "drones": ["dronsvc", "photosvc"],
        "cameras": ["photosvc", "spec"],
        "electronics": ["spec"],
    ]

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "need_help": "Нужна помощь?",
            "svc_evak": "Эвакуатор", "q_evak": "Нужен эвакуатор",
            "svc_sto": "СТО рядом", "q_sto": "Ищу СТО / автосервис",
            "svc_tire": "Шиномонтаж", "q_tire": "Нужен шиномонтаж",
            "svc_carwash": "Автомойка", "q_carwash": "Ищу автомойку рядом",
            "svc_autoexp": "Подборщик авто", "q_autoexp": "Ищу подборщика / автоэксперта",
            "svc_autopaint": "Кузовной ремонт", "q_autopaint": "Нужен кузовной ремонт или покраска",
            "svc_autoglass": "Замена стёкол авто", "q_autoglass": "Нужна замена или ремонт стекла авто",
            "svc_autoelec": "Авто-электрик", "q_autoelec": "Ищу авто-электрика",
            "svc_diag": "Диагностика авто", "q_diag": "Нужна компьютерная диагностика авто",
            "svc_microfix": "Ремонт самоката/велосипеда", "q_microfix": "Нужен ремонт электросамоката или велосипеда",
            "svc_boatfix": "Ремонт лодки/мотора", "q_boatfix": "Нужен ремонт лодки или лодочного мотора",
            "svc_realtor": "Риелтор", "q_realtor": "Ищу риелтора",
            "svc_jurcheck": "Юр. проверка", "q_jurcheck": "Нужна юридическая проверка объекта недвижимости",
            "svc_renovate": "Ремонт под ключ", "q_renovate": "Ищу бригаду для ремонта квартиры",
            "svc_mover": "Переезд / грузчики", "q_mover": "Нужны грузчики или перевозка мебели",
            "svc_plumb": "Сантехник", "q_plumb": "Нужен сантехник",
            "svc_electro": "Электрик", "q_electro": "Нужен электрик",
            "svc_wininstall": "Установка окон", "q_wininstall": "Нужна установка пластиковых окон",
            "svc_winrepair": "Ремонт окон", "q_winrepair": "Нужен ремонт окна / замена ручки / уплотнителя",
            "svc_mosquito": "Москитные сетки", "q_mosquito": "Нужны москитные сетки на окна",
            "svc_phonefix": "Ремонт телефона", "q_phonefix": "Нужен ремонт телефона",
            "svc_screen": "Замена экрана", "q_screen": "Нужна замена экрана телефона",
            "svc_battery": "Замена аккумулятора", "q_battery": "Нужна замена аккумулятора телефона",
            "svc_lapfix": "Ремонт ноутбука", "q_lapfix": "Нужен ремонт ноутбука",
            "svc_pcfix": "Ремонт компьютера", "q_pcfix": "Нужен ремонт компьютера",
            "svc_upgrade": "Апгрейд ПК", "q_upgrade": "Хочу апгрейд компьютера / заменить комплектующие",
            "svc_virus": "Удалить вирусы", "q_virus": "Нужно удаление вирусов и настройка Windows",
            "svc_os": "Установка Windows", "q_os": "Нужна установка / переустановка Windows",
            "svc_tvfix": "Ремонт телевизора", "q_tvfix": "Нужен ремонт телевизора",
            "svc_fridgefix": "Ремонт холодильника", "q_fridgefix": "Нужен ремонт холодильника",
            "svc_washfix": "Ремонт стиралки", "q_washfix": "Нужен ремонт стиральной машины",
            "svc_acfix": "Ремонт кондиционера", "q_acfix": "Нужен ремонт или чистка кондиционера",
            "svc_acinstall": "Установка кондиц.", "q_acinstall": "Нужна установка кондиционера",
            "svc_delivery": "Доставка / перевозка", "q_delivery": "Нужна доставка или перевозка",
            "svc_assembly": "Сборка мебели", "q_assembly": "Нужна сборка мебели",
            "svc_bigdeliv": "Газель / грузовик", "q_bigdeliv": "Нужна газель или грузовик для перевозки",
            "svc_vet": "Ветеринар рядом", "q_vet": "Нужен ветеринар / выезд на дом",
            "svc_grooming": "Грумер / стрижка", "q_grooming": "Нужен грумер для животного",
            "svc_pet-walk": "Выгул собаки", "q_pet-walk": "Нужен выгул собаки",
            "svc_tailor": "Пошив / ремонт", "q_tailor": "Нужен ателье / ремонт одежды",
            "svc_shoefix": "Ремонт обуви", "q_shoefix": "Нужен ремонт обуви",
            "svc_babycour": "Доставка", "q_babycour": "Нужна доставка детских товаров",
            "svc_sportcour": "Доставка", "q_sportcour": "Нужна доставка спортинвентаря",
            "svc_trainer": "Тренер", "q_trainer": "Ищу персонального тренера",
            "svc_photosvc": "Фотограф", "q_photosvc": "Ищу фотографа",
            "svc_dronsvc": "Съёмка с дрона", "q_dronsvc": "Нужна аэро-фотосъёмка / видео с дрона",
            "svc_spec": "Найти специалиста",
        ],
        "kk": [
            "need_help": "Көмек керек пе?",
            "svc_evak": "Эвакуатор", "q_evak": "Эвакуатор керек",
            "svc_sto": "Жақын СТО", "q_sto": "СТО / автосервис іздеймін",
            "svc_tire": "Шиномонтаж", "q_tire": "Шиномонтаж керек",
            "svc_carwash": "Автожуу", "q_carwash": "Жақын жерден автожуу іздеймін",
            "svc_autoexp": "Көлік таңдаушы", "q_autoexp": "Көлік таңдаушы / автосарапшы іздеймін",
            "svc_autopaint": "Шанақ жөндеу", "q_autopaint": "Шанақ жөндеу немесе бояу керек",
            "svc_autoglass": "Көлік әйнегін ауыстыру", "q_autoglass": "Көлік әйнегін ауыстыру не жөндеу керек",
            "svc_autoelec": "Автоэлектрик", "q_autoelec": "Автоэлектрик іздеймін",
            "svc_diag": "Көлік диагностикасы", "q_diag": "Көлікке компьютерлік диагностика керек",
            "svc_microfix": "Самокат/велосипед жөндеу", "q_microfix": "Электросамокат не велосипед жөндеу керек",
            "svc_boatfix": "Қайық/мотор жөндеу", "q_boatfix": "Қайық не қайық моторын жөндеу керек",
            "svc_realtor": "Риелтор", "q_realtor": "Риелтор іздеймін",
            "svc_jurcheck": "Заң тексеруі", "q_jurcheck": "Жылжымайтын мүлікті заңдық тексеру керек",
            "svc_renovate": "Кілтке дейін жөндеу", "q_renovate": "Пәтер жөндеуге бригада іздеймін",
            "svc_mover": "Көшу / жүкшілер", "q_mover": "Жүкшілер не жиһаз тасымалы керек",
            "svc_plumb": "Сантехник", "q_plumb": "Сантехник керек",
            "svc_electro": "Электрик", "q_electro": "Электрик керек",
            "svc_wininstall": "Терезе орнату", "q_wininstall": "Пластик терезе орнату керек",
            "svc_winrepair": "Терезе жөндеу", "q_winrepair": "Терезе жөндеу / тұтқа не тығыздағыш ауыстыру керек",
            "svc_mosquito": "Москит торлары", "q_mosquito": "Терезеге москит торы керек",
            "svc_phonefix": "Телефон жөндеу", "q_phonefix": "Телефон жөндеу керек",
            "svc_screen": "Экран ауыстыру", "q_screen": "Телефон экранын ауыстыру керек",
            "svc_battery": "Аккумулятор ауыстыру", "q_battery": "Телефон аккумуляторын ауыстыру керек",
            "svc_lapfix": "Ноутбук жөндеу", "q_lapfix": "Ноутбук жөндеу керек",
            "svc_pcfix": "Компьютер жөндеу", "q_pcfix": "Компьютер жөндеу керек",
            "svc_upgrade": "ДК жаңарту", "q_upgrade": "Компьютерді жаңартқым / бөлшектерін ауыстырғым келеді",
            "svc_virus": "Вирустарды жою", "q_virus": "Вирустарды жою және Windows баптау керек",
            "svc_os": "Windows орнату", "q_os": "Windows орнату / қайта орнату керек",
            "svc_tvfix": "Теледидар жөндеу", "q_tvfix": "Теледидар жөндеу керек",
            "svc_fridgefix": "Тоңазытқыш жөндеу", "q_fridgefix": "Тоңазытқыш жөндеу керек",
            "svc_washfix": "Кір жуғыш жөндеу", "q_washfix": "Кір жуғыш машина жөндеу керек",
            "svc_acfix": "Кондиционер жөндеу", "q_acfix": "Кондиционер жөндеу не тазалау керек",
            "svc_acinstall": "Кондиционер орнату", "q_acinstall": "Кондиционер орнату керек",
            "svc_delivery": "Жеткізу / тасымал", "q_delivery": "Жеткізу не тасымал керек",
            "svc_assembly": "Жиһаз құрастыру", "q_assembly": "Жиһаз құрастыру керек",
            "svc_bigdeliv": "Газель / жүк көлігі", "q_bigdeliv": "Тасымалға газель не жүк көлігі керек",
            "svc_vet": "Жақын ветеринар", "q_vet": "Ветеринар / үйге шақыру керек",
            "svc_grooming": "Грумер / қырқу", "q_grooming": "Жануарға грумер керек",
            "svc_pet-walk": "Итті серуендету", "q_pet-walk": "Итті серуендету керек",
            "svc_tailor": "Тігу / жөндеу", "q_tailor": "Ателье / киім жөндеу керек",
            "svc_shoefix": "Аяқ киім жөндеу", "q_shoefix": "Аяқ киім жөндеу керек",
            "svc_babycour": "Жеткізу", "q_babycour": "Балалар тауарларын жеткізу керек",
            "svc_sportcour": "Жеткізу", "q_sportcour": "Спорт құралдарын жеткізу керек",
            "svc_trainer": "Жаттықтырушы", "q_trainer": "Жеке жаттықтырушы іздеймін",
            "svc_photosvc": "Фотограф", "q_photosvc": "Фотограф іздеймін",
            "svc_dronsvc": "Дроннан түсіру", "q_dronsvc": "Дроннан фото / бейне түсіру керек",
            "svc_spec": "Маман табу",
        ],
        "en": [
            "need_help": "Need help?",
            "svc_evak": "Tow truck", "q_evak": "Need a tow truck",
            "svc_sto": "Car service nearby", "q_sto": "Looking for a car service",
            "svc_tire": "Tyre service", "q_tire": "Need a tyre service",
            "svc_carwash": "Car wash", "q_carwash": "Looking for a car wash nearby",
            "svc_autoexp": "Car inspector", "q_autoexp": "Looking for a car inspector",
            "svc_autopaint": "Body repair", "q_autopaint": "Need body repair or painting",
            "svc_autoglass": "Auto glass", "q_autoglass": "Need car glass replaced or repaired",
            "svc_autoelec": "Auto electrician", "q_autoelec": "Looking for an auto electrician",
            "svc_diag": "Car diagnostics", "q_diag": "Need computer diagnostics for my car",
            "svc_microfix": "Scooter/bike repair", "q_microfix": "Need an e-scooter or bike repaired",
            "svc_boatfix": "Boat/motor repair", "q_boatfix": "Need a boat or outboard motor repaired",
            "svc_realtor": "Realtor", "q_realtor": "Looking for a realtor",
            "svc_jurcheck": "Legal check", "q_jurcheck": "Need a legal check of the property",
            "svc_renovate": "Full renovation", "q_renovate": "Looking for a crew to renovate an apartment",
            "svc_mover": "Movers", "q_mover": "Need movers or furniture transport",
            "svc_plumb": "Plumber", "q_plumb": "Need a plumber",
            "svc_electro": "Electrician", "q_electro": "Need an electrician",
            "svc_wininstall": "Window installation", "q_wininstall": "Need PVC windows installed",
            "svc_winrepair": "Window repair", "q_winrepair": "Need a window repaired / handle or seal replaced",
            "svc_mosquito": "Insect screens", "q_mosquito": "Need insect screens for windows",
            "svc_phonefix": "Phone repair", "q_phonefix": "Need a phone repaired",
            "svc_screen": "Screen replacement", "q_screen": "Need a phone screen replaced",
            "svc_battery": "Battery replacement", "q_battery": "Need a phone battery replaced",
            "svc_lapfix": "Laptop repair", "q_lapfix": "Need a laptop repaired",
            "svc_pcfix": "PC repair", "q_pcfix": "Need a computer repaired",
            "svc_upgrade": "PC upgrade", "q_upgrade": "Want to upgrade my PC / replace components",
            "svc_virus": "Virus removal", "q_virus": "Need viruses removed and Windows set up",
            "svc_os": "Windows install", "q_os": "Need Windows installed / reinstalled",
            "svc_tvfix": "TV repair", "q_tvfix": "Need a TV repaired",
            "svc_fridgefix": "Fridge repair", "q_fridgefix": "Need a fridge repaired",
            "svc_washfix": "Washer repair", "q_washfix": "Need a washing machine repaired",
            "svc_acfix": "AC repair", "q_acfix": "Need an AC repaired or cleaned",
            "svc_acinstall": "AC installation", "q_acinstall": "Need an AC installed",
            "svc_delivery": "Delivery", "q_delivery": "Need delivery or transport",
            "svc_assembly": "Furniture assembly", "q_assembly": "Need furniture assembled",
            "svc_bigdeliv": "Van / truck", "q_bigdeliv": "Need a van or truck for transport",
            "svc_vet": "Vet nearby", "q_vet": "Need a vet / home visit",
            "svc_grooming": "Groomer", "q_grooming": "Need a groomer for my pet",
            "svc_pet-walk": "Dog walking", "q_pet-walk": "Need a dog walker",
            "svc_tailor": "Tailoring", "q_tailor": "Need a tailor / clothing repair",
            "svc_shoefix": "Shoe repair", "q_shoefix": "Need shoes repaired",
            "svc_babycour": "Delivery", "q_babycour": "Need kids' goods delivered",
            "svc_sportcour": "Delivery", "q_sportcour": "Need sports gear delivered",
            "svc_trainer": "Trainer", "q_trainer": "Looking for a personal trainer",
            "svc_photosvc": "Photographer", "q_photosvc": "Looking for a photographer",
            "svc_dronsvc": "Drone shooting", "q_dronsvc": "Need aerial photo / drone video",
            "svc_spec": "Find a specialist",
        ],
        "ar": [
            "need_help": "تحتاج مساعدة؟",
            "svc_evak": "سحب السيارات", "q_evak": "أحتاج سيارة سحب",
            "svc_sto": "ورشة قريبة", "q_sto": "أبحث عن ورشة سيارات",
            "svc_tire": "إطارات", "q_tire": "أحتاج خدمة إطارات",
            "svc_carwash": "غسيل سيارات", "q_carwash": "أبحث عن مغسلة سيارات قريبة",
            "svc_autoexp": "خبير سيارات", "q_autoexp": "أبحث عن خبير لفحص السيارة",
            "svc_autopaint": "إصلاح الهيكل", "q_autopaint": "أحتاج إصلاح الهيكل أو الطلاء",
            "svc_autoglass": "زجاج السيارات", "q_autoglass": "أحتاج استبدال أو إصلاح زجاج السيارة",
            "svc_autoelec": "كهربائي سيارات", "q_autoelec": "أبحث عن كهربائي سيارات",
            "svc_diag": "تشخيص السيارة", "q_diag": "أحتاج تشخيصًا حاسوبيًا للسيارة",
            "svc_microfix": "إصلاح سكوتر/دراجة", "q_microfix": "أحتاج إصلاح سكوتر كهربائي أو دراجة",
            "svc_boatfix": "إصلاح قارب/محرك", "q_boatfix": "أحتاج إصلاح قارب أو محرك قارب",
            "svc_realtor": "وسيط عقاري", "q_realtor": "أبحث عن وسيط عقاري",
            "svc_jurcheck": "فحص قانوني", "q_jurcheck": "أحتاج فحصًا قانونيًا للعقار",
            "svc_renovate": "تجديد شامل", "q_renovate": "أبحث عن فريق لتجديد شقة",
            "svc_mover": "نقل / عمال", "q_mover": "أحتاج عمال نقل أو نقل أثاث",
            "svc_plumb": "سباك", "q_plumb": "أحتاج سباكًا",
            "svc_electro": "كهربائي", "q_electro": "أحتاج كهربائيًا",
            "svc_wininstall": "تركيب نوافذ", "q_wininstall": "أحتاج تركيب نوافذ بلاستيكية",
            "svc_winrepair": "إصلاح نوافذ", "q_winrepair": "أحتاج إصلاح نافذة / استبدال مقبض أو عازل",
            "svc_mosquito": "شبكات البعوض", "q_mosquito": "أحتاج شبكات بعوض للنوافذ",
            "svc_phonefix": "إصلاح الهاتف", "q_phonefix": "أحتاج إصلاح هاتف",
            "svc_screen": "استبدال الشاشة", "q_screen": "أحتاج استبدال شاشة الهاتف",
            "svc_battery": "استبدال البطارية", "q_battery": "أحتاج استبدال بطارية الهاتف",
            "svc_lapfix": "إصلاح اللابتوب", "q_lapfix": "أحتاج إصلاح لابتوب",
            "svc_pcfix": "إصلاح الكمبيوتر", "q_pcfix": "أحتاج إصلاح كمبيوتر",
            "svc_upgrade": "ترقية الكمبيوتر", "q_upgrade": "أريد ترقية الكمبيوتر / استبدال القطع",
            "svc_virus": "إزالة الفيروسات", "q_virus": "أحتاج إزالة الفيروسات وضبط ويندوز",
            "svc_os": "تثبيت ويندوز", "q_os": "أحتاج تثبيت / إعادة تثبيت ويندوز",
            "svc_tvfix": "إصلاح التلفاز", "q_tvfix": "أحتاج إصلاح تلفاز",
            "svc_fridgefix": "إصلاح الثلاجة", "q_fridgefix": "أحتاج إصلاح ثلاجة",
            "svc_washfix": "إصلاح الغسالة", "q_washfix": "أحتاج إصلاح غسالة",
            "svc_acfix": "إصلاح المكيف", "q_acfix": "أحتاج إصلاح أو تنظيف مكيف",
            "svc_acinstall": "تركيب مكيف", "q_acinstall": "أحتاج تركيب مكيف",
            "svc_delivery": "توصيل / نقل", "q_delivery": "أحتاج توصيلًا أو نقلًا",
            "svc_assembly": "تركيب الأثاث", "q_assembly": "أحتاج تركيب أثاث",
            "svc_bigdeliv": "شاحنة صغيرة / كبيرة", "q_bigdeliv": "أحتاج شاحنة للنقل",
            "svc_vet": "بيطري قريب", "q_vet": "أحتاج طبيبًا بيطريًا / زيارة منزلية",
            "svc_grooming": "تجميل الحيوانات", "q_grooming": "أحتاج مزيّنًا لحيواني الأليف",
            "svc_pet-walk": "تمشية الكلاب", "q_pet-walk": "أحتاج من يمشّي كلبي",
            "svc_tailor": "خياطة / إصلاح", "q_tailor": "أحتاج خياطًا / إصلاح ملابس",
            "svc_shoefix": "إصلاح الأحذية", "q_shoefix": "أحتاج إصلاح حذاء",
            "svc_babycour": "توصيل", "q_babycour": "أحتاج توصيل مستلزمات أطفال",
            "svc_sportcour": "توصيل", "q_sportcour": "أحتاج توصيل معدات رياضية",
            "svc_trainer": "مدرب", "q_trainer": "أبحث عن مدرب شخصي",
            "svc_photosvc": "مصور", "q_photosvc": "أبحث عن مصور",
            "svc_dronsvc": "تصوير بالدرون", "q_dronsvc": "أحتاج تصويرًا جويًا / فيديو بالدرون",
            "svc_spec": "ابحث عن مختص",
        ],
    ]
}
