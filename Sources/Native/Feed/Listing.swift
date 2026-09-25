import Foundation

/**
 ОБЪЯВЛЕНИЕ ДЛЯ НАТИВНОЙ ЛЕНТЫ (этап 1 перехода на SwiftUI, владелец 25.09.2026: «поэтапно, начни с ленты»).

 Поля зеркалят ответ api/listings.php (`_api_item` на сайте) — тот же контракт, по которому в июле жила первая
 нативная лента (коммит 8080f85). Берём только то, что нужно карточке ленты: детальная карточка пока остаётся
 страницей сайта.

 🔴 РАЗБОР ТЕРПИМЫЙ. PHP отдаёт числа то числом, то строкой («id»: 123 или «id»: "123", «price»: "14900000"), а
 поле могли переименовать с июля. Падение разбора одного поля роняло бы всю страницу ленты, поэтому каждое поле
 читается само по себе, а не пришло или не разобралось — пусто. Обязателен только номер: без него карточка
 никуда не ведёт.
 */
struct Listing: Identifiable, Hashable {
    let id: String
    var title: String
    var price: Double?
    var oldPrice: Double?
    var negotiable: Bool
    var forRent: Bool
    var rentPriceDay: Double?
    var thumb: String?
    var city: String
    var isTop: Bool
    var isNew: Bool

    // ── Карточка (этап 2): приходят в ответе на ?id=, в ленте обычно пусты ──
    var фото: [String] = []
    var описание: String?
    var продавец: String?
    /// Номер продавца — чтобы открыть с ним диалог (dm.php open, peer_id).
    var продавецID: String?
    var продавецПроверен = false
    /// Оценка продавца (0–5), число отзывов и сделок, аватар — есть и в ленте, и в ?id= (сверка с живым API, этап 22).
    var рейтингПродавца: Double?
    var отзывыПродавца: Int?
    var сделкиПродавца: Int?
    var аватарПродавца: String?
    /// Описание в ленте обрезано сервером (desc_cut: 1); полное приходит только на ?id=.
    var описаниеОбрезано = false
    var просмотры: Int?
    var создано: String?
    var гарантияДней: Int?
    /// Характеристики «название → значение», только заполненные, в порядке показа.
    var характеристики: [Характеристика] = []
    /// Раздел объявления из поля category — по нему карточка просит похожие (этап 7, cat=). Нет — нет и похожих.
    var категория: String?

    struct Характеристика: Hashable {
        let ключ: String
        let значение: String
    }

    /// Все фото абсолютными адресами; нет списка — хотя бы обложка.
    var фотоАдреса: [URL] {
        let адреса = фото.compactMap { Config.url($0) }
        return адреса.isEmpty ? [обложка].compactMap { $0 } : адреса
    }

    /// Пришла ли полная карточка, а не строка из ленты.
    /// 🔴 Сверка с живым API (этап 22): в ленте уже есть и продавец, и все фото, а описание обрезано (desc_cut: 1).
    /// Прежнее «есть описание или продавец» считало такую строку полной, и карточка не догружала ?id= — человек видел
    /// оборванный на полуслове текст. Обрезанное описание значит «не полная», что бы ещё ни пришло.
    var полная: Bool { !описаниеОбрезано && (описание != nil || продавец != nil || фото.count > 1) }

    /// Обложка абсолютным адресом: thumb → img → первое из images.
    var обложка: URL? { thumb.flatMap { Config.url($0) } }

    /// Куда ведёт карточка — тот же канонический адрес, что у превью ленты (FeedSnapshot.Item.адрес).
    var адрес: URL? {
        var ч = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false)
        ч?.path = "/marketplace"
        ч?.queryItems = [URLQueryItem(name: "item", value: id)]
        return ч?.url
    }
}

extension Listing: Decodable {
    private struct Ключ: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключ.self)

        func строка(_ k: String) -> String? {
            if let s = try? c.decode(String.self, forKey: Ключ(k)) { return s }
            if let i = try? c.decode(Int.self, forKey: Ключ(k)) { return String(i) }
            if let d = try? c.decode(Double.self, forKey: Ключ(k)) { return String(Int(d)) }
            return nil
        }
        func число(_ k: String) -> Double? {
            if let d = try? c.decode(Double.self, forKey: Ключ(k)) { return d }
            if let s = try? c.decode(String.self, forKey: Ключ(k)) {
                return Double(s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
            }
            return nil
        }
        func да(_ k: String) -> Bool {
            if let b = try? c.decode(Bool.self, forKey: Ключ(k)) { return b }
            if let i = try? c.decode(Int.self, forKey: Ключ(k)) { return i != 0 }
            if let s = try? c.decode(String.self, forKey: Ключ(k)) { return s == "1" || s.lowercased() == "true" }
            return false
        }
        func непусто(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }

        guard let id = непусто(строка("id")) else {
            throw DecodingError.keyNotFound(Ключ("id"), .init(codingPath: c.codingPath, debugDescription: "нет id"))
        }
        self.id = id
        title = непусто(строка("title")) ?? непусто(строка("brand")) ?? ""
        price = число("price")
        oldPrice = число("old_price")
        negotiable = да("price_negotiable")
        forRent = да("for_rent")
        rentPriceDay = число("rent_price_day")
        let первоеФото = (try? c.decode([String].self, forKey: Ключ("images")))?.first
        thumb = непусто(строка("thumb")) ?? непусто(строка("img")) ?? непусто(первоеФото)
        city = непусто(строка("city")) ?? ""
        isTop = да("is_top")
        isNew = строка("condition") == "new"

        фото = ((try? c.decode([String].self, forKey: Ключ("images"))) ?? [])
            .compactMap { непусто($0) }
        описание = непусто(строка("description"))
        продавец = непусто(строка("seller"))
        продавецID = непусто(строка("seller_id"))
        продавецПроверен = да("seller_verified")
        рейтингПродавца = число("seller_rating").flatMap { $0 > 0 ? $0 : nil }
        отзывыПродавца = число("seller_reviews").map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        сделкиПродавца = число("seller_deals").map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        аватарПродавца = непусто(строка("seller_avatar"))
        описаниеОбрезано = да("desc_cut")
        просмотры = число("views").map { Int($0) }
        создано = непусто(строка("created_at"))
        гарантияДней = число("warranty_days").map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }

        /* Характеристики: у июльского API — плоские поля ноутбука (cpu, gpu…). Если сайт отдаёт общий словарь
           (specs / attrs: {"Пробег": "120 000 км"}), берём его — Kliko продаёт не только ноутбуки. */
        var х: [Характеристика] = []
        /* Живой API (этап 22): specs — массив [{label, value, emoji}] или null. emoji — это SVG-разметка для сайта, её не
           берём. Если массив есть, плоские поля ниже не добавляем: сайт уже положил туда то же самое (у мебели
           «Размер 190×110» лежит и в specs, и в storage — вышло бы «Накопитель 190×110»). */
        struct ПунктХарактеристик: Decodable {
            let label: String?
            let value: String?
        }
        if let пункты = try? c.decode([ПунктХарактеристик].self, forKey: Ключ("specs")) {
            for п in пункты {
                if let к = непусто(п.label), let з = непусто(п.value) { х.append(Характеристика(ключ: к, значение: з)) }
            }
        }
        let изМассива = !х.isEmpty
        for имя in ["specs", "attrs"] {
            if let словарь = try? c.decode([String: String].self, forKey: Ключ(имя)) {
                for (к, з) in словарь.sorted(by: { $0.key < $1.key }) {
                    if let к = непусто(к), let з = непусто(з) { х.append(Характеристика(ключ: к, значение: з)) }
                }
            }
        }
        for (поле, подпись) in [("cpu", "cpu"), ("gpu", "gpu"), ("ram", "ram"), ("storage", "storage"), ("year", "year")] where !изМассива {
            if let з = непусто(строка(поле)) { х.append(Характеристика(ключ: FeedText.т("spec_" + подпись), значение: з)) }
        }
        характеристики = х
        категория = непусто(строка("category"))
    }
}

/// Ответ на один товар: {ok, item:{…}}.
struct ListingEnvelope: Decodable {
    let item: Listing
}

/// Ответ ленты: {ok, items:[…], total, has_more}. Объявление, которое не разобралось, пропускаем, а не роняем всю страницу.
struct ListingsPage: Decodable {
    let items: [Listing]
    /// Сколько всего объявлений по запросу — «26 предложений» на плитке и число в заголовке ряда главной (этап 26).
    /// nil — поле не пришло или не разобралось: тогда числа просто нет, лента от этого не ломается.
    let total: Int?
    /// Есть ли следующая страница (has_more). nil — не пришло; лента по-прежнему судит по размеру страницы.
    let hasMore: Bool?

    private enum Ключи: String, CodingKey {
        case items
        case total
        case hasMore = "has_more"
    }
    private struct Любое: Decodable {
        let значение: Listing?
        init(from decoder: Decoder) throws { значение = try? Listing(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Ключи.self)
        items = try c.decode([Любое].self, forKey: .items).compactMap(\.значение)
        /* Терпимо, как и поля объявления: PHP отдаёт число то числом, то строкой. */
        if let n = try? c.decode(Int.self, forKey: .total) {
            total = n
        } else if let строка = try? c.decode(String.self, forKey: .total) {
            total = Int(строка.trimmingCharacters(in: .whitespaces))
        } else {
            total = nil
        }
        if let да = try? c.decode(Bool.self, forKey: .hasMore) {
            hasMore = да
        } else if let n = try? c.decode(Int.self, forKey: .hasMore) {
            hasMore = n != 0
        } else {
            hasMore = nil
        }
    }
}
