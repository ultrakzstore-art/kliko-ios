import Foundation

/// Чат поверх боевого dm.php (bearer-аутентификация, Вариант В на бэкенде).
extension API {
    /// Инбокс: список диалогов текущего юзера.
    func dmList() async throws -> [DMThreadSummary] {
        let r: DMListResponse = try await authedGET("dm.php", [URLQueryItem(name: "action", value: "list")])
        return r.ok ? r.threads : []
    }

    /// Открыть/создать диалог с собеседником (опц. в контексте объявления).
    func dmOpen(peerId: String, listingId: String = "") async throws -> DMOpenResponse {
        var body: [String: Any] = ["action": "open", "peer_id": peerId]
        if !listingId.isEmpty { body["listing_id"] = listingId }
        return try await authedPOST("dm.php", body)
    }

    /// Отправить текстовое сообщение в тред.
    func dmSend(threadId: String, text: String) async throws -> DMSendResponse {
        try await authedPOST("dm.php", ["action": "send", "thread_id": threadId, "text": text])
    }

    /// Снимок треда (dm.php poll — мгновенный, не long-poll). Помечает прочитанным.
    func dmPoll(tid: String) async throws -> DMPollResponse {
        try await authedGET("dm.php", [URLQueryItem(name: "action", value: "poll"),
                                       URLQueryItem(name: "tid", value: tid)])
    }
}
