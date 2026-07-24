import SwiftUI

/// Состояние одного диалога: открытие, отправка, цикл опроса (dm.php poll — мгновенный снимок).
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [DMMessage] = []
    @Published var draft = ""
    @Published var loading = true
    @Published var sending = false
    @Published var blocked = false
    @Published var errorText: String?

    let peerId: String
    let peerName: String
    let listingId: String
    private(set) var tid = ""

    init(peerId: String, peerName: String, listingId: String = "") {
        self.peerId = peerId; self.peerName = peerName; self.listingId = listingId
    }

    /// Открыть тред (создаётся при первом обращении), подтянуть историю.
    func start() async {
        do {
            let r = try await API.shared.dmOpen(peerId: peerId, listingId: listingId)
            guard r.ok else { errorText = errText(r.error); loading = false; return }
            if let th = r.thread { tid = th.id; messages = th.messages }
            blocked = r.blocked ?? false
        } catch {
            errorText = "Не удалось открыть чат. Проверьте интернет."
        }
        loading = false
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !tid.isEmpty, !sending else { return }
        sending = true
        let backup = draft; draft = ""
        do {
            let r = try await API.shared.dmSend(threadId: tid, text: text)
            if r.ok, let th = r.thread { messages = th.messages }
            else if r.blocked == true { blocked = true; draft = backup }
            else { draft = backup; errorText = "Сообщение не отправлено" }
        } catch {
            draft = backup; errorText = "Нет связи. Попробуйте ещё раз."
        }
        sending = false
    }

    /// Мягкий опрос обновлений каждые 3 сек, пока экран открыт (Task отменяется на .onDisappear).
    func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled || tid.isEmpty { continue }
            if let r = try? await API.shared.dmPoll(tid: tid), let th = r.thread {
                if th.messages.count != messages.count { messages = th.messages }
                blocked = r.blocked ?? blocked
            }
        }
    }

    private func errText(_ e: String?) -> String {
        switch e {
        case "no_peer": return "Пользователь не найден"
        case "peer":    return "Нельзя написать самому себе"
        default:        return "Не удалось открыть чат"
        }
    }
}
