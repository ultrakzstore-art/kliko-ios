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
        if o.categoryId != nil { categoryId = o.categoryId }
        if o.createdAt != nil { createdAt = o.createdAt }
        if !o.status.isEmpty { status = o.status }
        if o.business { business = true }
        if o.userId != nil { userId = o.userId }
        if !o.userName.isEmpty { userName = o.userName }
        if !o.params.isEmpty { params = o.params }
        if !o.description.isEmpty { description = o.description }
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
}

struct Stats: Codable {
    var searchOk = 0
    var searchErr = 0
    var turboProbes = 0
    var turboFound = 0
    var lastTurboHit: Date?
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
}
