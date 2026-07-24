import Foundation

/// Строка инбокса (dm.php?action=list).
struct DMThreadSummary: Decodable, Identifiable {
    let tid: String
    let peerId: String
    let peerName: String
    let listingId: String
    let listingTitle: String
    let listingImg: String
    let last: DMLast?
    let unread: Int
    let count: Int
    let updated: String
    var id: String { tid }
}

struct DMLast: Decodable {
    let text: String
    let type: String
    let at: String
    let mine: Bool

    /// Текст превью для инбокса (фото/голос — иконкой).
    var preview: String {
        switch type {
        case "image": return "📷 Фото"
        case "voice": return "🎤 Голосовое"
        default:      return text
        }
    }
}

/// Одно сообщение в треде.
struct DMMessage: Decodable, Identifiable {
    let mine: Bool
    let from: String
    let type: String
    let text: String
    let at: String
    // meta (url фото/голоса) опускаем в MVP — рендерим текст/иконку типа

    // Стабильный ключ для ForEach (сервер не шлёт id сообщения)
    var id: String { from + "|" + at + "|" + String(text.hashValue) }

    var display: String {
        switch type {
        case "image": return "📷 Фото"
        case "voice": return "🎤 Голосовое сообщение"
        default:      return text
        }
    }
}

/// Тред (dm.php open/poll/send).
struct DMThread: Decodable {
    let id: String
    let messages: [DMMessage]
    let peerReadAt: String?
    let label: String?
}

struct DMPeer: Decodable {
    let id: String
    let name: String
    let verified: Bool
}

// Ответы эндпоинта
struct DMListResponse: Decodable { let ok: Bool; let threads: [DMThreadSummary] }
struct DMOpenResponse: Decodable {
    let ok: Bool
    let thread: DMThread?
    let peer: DMPeer?
    let meVerified: Bool?
    let blocked: Bool?
    let error: String?
}
struct DMPollResponse: Decodable { let ok: Bool; let thread: DMThread?; let blocked: Bool? }
struct DMSendResponse: Decodable { let ok: Bool; let thread: DMThread?; let error: String?; let blocked: Bool? }
