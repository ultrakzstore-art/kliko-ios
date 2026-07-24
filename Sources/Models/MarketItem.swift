import Foundation

/// Товар витрины. Поля зеркалят api/listings.php (_api_item).
/// Декодер использует .convertFromSnakeCase → old_price↔oldPrice, is_top↔isTop и т.д.
struct MarketItem: Identifiable, Decodable, Hashable {
    let id: String
    var brand: String?
    var title: String?
    var price: Int
    var oldPrice: Int?
    var condition: String?
    var category: String?
    var img: String?
    var thumb: String?
    var images: [String]?
    var city: String?
    var sellerId: String?
    var isTop: Bool?
    var priceNegotiable: Bool?
    var forRent: Bool?
    var rentPriceDay: Int?
    // ── детальная карточка (приходят при ?id=; в ленте частично) ──
    var description: String?
    var seller: String?
    var sellerVerified: Bool?
    var warrantyDays: Int?
    var views: Int?
    var createdAt: String?
    var cpu: String?
    var gpu: String?
    var ram: String?
    var storage: String?
    var year: String?

    /// Все фото (images → img) абсолютными URL.
    var photoURLs: [URL] {
        let list = (images?.isEmpty == false ? images! : [img].compactMap { $0 })
        return list.compactMap { Config.url($0) }
    }

    /// Пары «характеристика → значение» для чипов (только заполненные).
    var specPairs: [(String, String)] {
        var out: [(String, String)] = []
        func add(_ k: String, _ v: String?) { if let v, !v.trimmingCharacters(in: .whitespaces).isEmpty { out.append((k, v)) } }
        add("Процессор", cpu); add("Видео", gpu); add("ОЗУ", ram); add("Накопитель", storage); add("Год", year)
        return out
    }

    /// URL превью для ленты (thumb → img → первое фото).
    var thumbURL: URL? {
        let raw = (thumb?.isEmpty == false ? thumb : nil)
            ?? (img?.isEmpty == false ? img : nil)
            ?? images?.first
        guard let raw else { return nil }
        return Config.url(raw)
    }

    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Без названия" : t
    }

    /// Цена «142 000 ₸» / «Договорная» / аренда «5 000 ₸/сут».
    var priceText: String {
        if forRent == true, let d = rentPriceDay, d > 0 {
            return "\(Self.grouped(d)) ₸/сут"
        }
        if priceNegotiable == true || price <= 0 { return "Договорная" }
        return "\(Self.grouped(price)) ₸"
    }

    var isNew: Bool { (condition ?? "") == "new" }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Обёртка ответа ленты: {ok, items:[...]}
struct FeedResponse: Decodable {
    let ok: Bool
    let items: [MarketItem]
}
