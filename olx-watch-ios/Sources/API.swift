import Foundation

// Модели ответа olx-watch-server/api.php. Ключи сервера — snake_case, здесь camelCase:
// декодер переводит сам (.convertFromSnakeCase).

struct Ad: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let url: String
    let price: Double?
    let priceLabel: String
    let city: String
    let region: String
    let photo: String
    let createdAt: Int?
    let foundAt: Int
    let via: String
    let status: String
    let business: Bool
    let promoted: Bool
    let userName: String
    let params: [String]
    let description: String
    let sellerUrl: String?
    let subIds: [Int]

    /// Пойман «турбо» — по номеру, раньше, чем объявление попало в поиск OLX.
    var early: Bool { via == "turbo" }
    /// OLX ещё не одобрил: статус не active.
    var onReview: Bool { !status.isEmpty && status != "active" }

    var priceText: String {
        if !priceLabel.isEmpty { return priceLabel }
        guard let price else { return "" }
        return price.formatted(.number.grouping(.automatic).precision(.fractionLength(0))) + " ₸"
    }

    var postedDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt ?? foundAt)) }
}

struct Sub: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let url: String
    let paused: Bool
    let ready: Bool
    let sent: Int
    let error: String
    let lastPoll: Int?
}

struct ServerStatus: Codable {
    let cronOk: Bool
    let lastCron: Int?
    let turbo: Bool
    let frontier: Int?
    let lastTurboHit: Int?
    let stats: [String: Int]
    let blockedUntil: Int?
    let devices: Int
    let pushReady: Bool
}

enum APIError: LocalizedError {
    case notConfigured
    case server(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Сервер не настроен — откройте «Настройки»."
        case .server(let message): return message
        case .http(let code): return "Сервер ответил \(code)."
        }
    }
}

private struct ErrorBody: Decodable { let error: String }
private struct FeedBody: Decodable { let ads: [Ad] }
private struct SubsBody: Decodable { let subs: [Sub] }
private struct SubBody: Decodable { let sub: Sub }
private struct Empty: Decodable {}

struct API {
    /// Полный адрес api.php, например https://kliko.kz/olx-watch/api.php
    let endpoint: URL
    let token: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func call<T: Decodable>(_ action: String, _ type: T.Type, method: String = "GET",
                                    query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> T {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw APIError.notConfigured }
        parts.queryItems = [URLQueryItem(name: "a", value: action)] + query
        guard let url = parts.url else { throw APIError.notConfigured }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            if let e = try? Self.decoder.decode(ErrorBody.self, from: data) { throw APIError.server(e.error) }
            throw APIError.http(code)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    func feed(before: Int? = nil) async throws -> [Ad] {
        let q = before.map { [URLQueryItem(name: "before", value: String($0))] } ?? []
        return try await call("feed", FeedBody.self, query: q).ads
    }

    func subs() async throws -> [Sub] {
        try await call("subs", SubsBody.self).subs
    }

    func addSub(url: String, name: String) async throws -> Sub {
        try await call("subs", SubBody.self, method: "POST", body: ["url": url, "name": name]).sub
    }

    func setPaused(_ id: Int, _ paused: Bool) async throws {
        _ = try await call("sub", Empty.self, method: "POST", body: ["id": id, "paused": paused])
    }

    func deleteSub(_ id: Int) async throws {
        _ = try await call("sub_del", Empty.self, method: "POST", body: ["id": id])
    }

    func registerDevice(_ token: String) async throws {
        _ = try await call("device", Empty.self, method: "POST", body: ["token": token])
    }

    func setTurbo(_ on: Bool) async throws {
        _ = try await call("turbo", Empty.self, method: "POST", body: ["on": on])
    }

    func status() async throws -> ServerStatus {
        try await call("status", ServerStatus.self)
    }

    func testPush() async throws {
        _ = try await call("test_push", Empty.self, method: "POST")
    }
}
