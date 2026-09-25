import Foundation

/// Объявление в ленте. Всё хранится в телефоне (state.json в Application Support).
struct Ad: Codable, Identifiable, Hashable {
    var id: Int
    var title: String = ""
    var url: String = ""
    var price: Double?
    var priceLabel: String = ""
    var city: String = ""
    var region: String = ""
    var photo: String = ""
    var categoryId: Int?
    var createdAt: Date?
    var foundAt = Date()
    var via = "search"            // search | turbo
    var status = ""
    var business = false
    var promoted = false
    var userId: String?
    var userName = ""
    var params: [String] = []
    var description = ""
    var subIds: [Int] = []
    /// Все фото объявления. Необязательное: в state.json версий до 1.3 его нет.
    var photos: [String]?
    /// Рубрика словами (из карточки OLX). Необязательное — в старых state.json нет.
    var category: String?

    /// Пойман «турбо» — по номеру, раньше, чем объявление попало в поиск OLX.
    var early: Bool { via == "turbo" }
    /// OLX ещё не одобрил: статус не active.
    var onReview: Bool { !status.isEmpty && status != "active" }

    var priceText: String {
        if !priceLabel.isEmpty { return priceLabel }
        guard let price else { return "" }
        return price.formatted(.number.grouping(.automatic).precision(.fractionLength(0))) + " ₸"
    }

    var postedDate: Date { createdAt ?? foundAt }

    /// Все фото (или хотя бы обложка).
    var gallery: [String] {
        if let photos, !photos.isEmpty { return photos }
        return photo.isEmpty ? [] : [photo]
    }

    /// Номера телефонов, которые продавец написал в заголовке или описании (OLX прячет номер
    /// за входом — его не достаём, берём только то, что написано в тексте).
    var phones: [String] { Phone.find(in: title + "\n" + description) }

    /// Сколько секунд прошло от подачи до того, как мы его поймали.
    var lagText: String? {
        guard let createdAt else { return nil }
        let s = max(0, Int(foundAt.timeIntervalSince(createdAt)))
        return s < 120 ? "поймано через \(s) с" : "поймано через \(s / 60) мин"
    }

    /// Ссылка с номером после # — сайт эту часть игнорирует, а номер под рукой.
    var link: URL? {
        let base = url.hasPrefix("http") ? String(url.split(separator: "#").first ?? "") : "\(OLX.base)/d/obyavlenie/-ID\(OLX.encode(id)).html"
        return URL(string: "\(base)#\(id)")
    }

    var sellerURL: URL? {
        guard let userId, !userId.isEmpty else { return nil }
        return URL(string: "\(OLX.base)/list/user/\(userId)/")
    }

    /// Дополнить данными карточки: непустое из карточки побеждает.
    mutating func merge(_ o: Ad) {
        if !o.title.isEmpty { title = o.title }
        if !o.url.isEmpty { url = o.url }
        if o.price != nil { price = o.price }
        if !o.priceLabel.isEmpty { priceLabel = o.priceLabel }
        if !o.city.isEmpty { city = o.city }
        if !o.region.isEmpty { region = o.region }
        if !o.photo.isEmpty { photo = o.photo }
        if let more = o.photos, !more.isEmpty { photos = more }
        if o.categoryId != nil { categoryId = o.categoryId }
        if o.createdAt != nil { createdAt = o.createdAt }
        if !o.status.isEmpty { status = o.status }
        if o.business { business = true }
        if o.userId != nil { userId = o.userId }
        if !o.userName.isEmpty { userName = o.userName }
        if !o.params.isEmpty { params = o.params }
        if !o.description.isEmpty { description = o.description }
        if let c = o.category, !c.isEmpty { category = c }
    }
}

/// Поиск — ссылка на выдачу OLX плюс то, что выучено по ней для турбо.
struct Sub: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var url: String
    var paused = false
    var ready = false             // первый проход сделан: выдача запомнена
    var sent = 0
    var error = ""
    var lastPoll: Date?
    var learnedCategories: [Int] = []
    var learnedCities: [String] = []
    var learnedTotal = 0
    /// Рубрика поиска словами — для подписи в карточках. В старых state.json нет.
    var categoryLabel: String?
}

struct Stats: Codable, Equatable {
    var searchOk = 0
    var searchErr = 0
    var turboProbes = 0
    var turboFound = 0
    var lastTurboHit: Date?
}

/// Связь с OLX — для индикатора «работает / пауза / нет связи» в настройках.
struct Health: Equatable {
    var lastSuccess: Date?
    var lastFailure: Date?
    var lastCode: Int?
    var lastError = ""
    var lastLatencyMs: Int?
}

/// Всё состояние приложения, одним файлом.
struct Persisted: Codable {
    var subs: [Sub] = []
    var ads: [Ad] = []
    var seen: [Int] = []          // уже виденные номера (порядок — от старых к новым)
    var frontier = 0              // самый большой известный номер объявления
    var nextSubId = 1
    var turbo = true
    var stats = Stats()
    /// Все новые объявления, которые поймал сборщик, — в любой рубрике. Необязательное поле:
    /// state.json версии 1.1 его не знает, и обязательное поле сбросило бы сохранённые поиски.
    var all: [Ad]?
}

/// Казахстанские мобильные номера в тексте: +7 777 123 45 67, 8(701)1234567, 87071234567 и т.п.
enum Phone {
    private static let regex = try? NSRegularExpression(
        pattern: #"(?<!\d)(?:\+?7|8)[\s\-\(\)]*(7\d{2})[\s\-\(\)]*(\d{3})[\s\-]*(\d{2})[\s\-]*(\d{2})(?!\d)"#)

    static func find(in text: String) -> [String] {
        guard let regex else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let digits = (1...4).map { ns.substring(with: m.range(at: $0)) }.joined()
            let number = "+7" + digits
            if !out.contains(number) { out.append(number) }
        }
        return out
    }

    /// +77071234567 → +7 707 123 45 67
    static func pretty(_ n: String) -> String {
        let d = Array(n.dropFirst(2))
        guard d.count == 10 else { return n }
        return "+7 \(String(d[0..<3])) \(String(d[3..<6])) \(String(d[6..<8])) \(String(d[8..<10]))"
    }
}

/// Фото OLX отдаёт по шаблону размера (;s=800x600). В списке берём маленькую копию — быстрее.
enum PhotoSize {
    static func thumb(_ url: String) -> String {
        url.replacingOccurrences(of: ";s=800x600", with: ";s=400x300")
    }
}
