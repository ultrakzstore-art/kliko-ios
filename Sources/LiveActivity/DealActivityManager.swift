import ActivityKit
import Foundation

/// Управляет одной активной Live Activity сделки (как поездка в Я.Такси — одна за раз).
/// Драйвится из веба через мост window.KlikoLive.{start,update,end} (см. WebContainer).
/// Без @available: deployment target = iOS 17, а ActivityKit/ActivityContent доступны с 16.1/16.2.
///
/// ДВА ИСТОЧНИКА ОБНОВЛЕНИЙ, И ОБА НУЖНЫ.
/// Пока приложение открыто, плашку кормит сам сайт: js/cabinet.js → dealLiveActivity().
/// Но человек закрывает приложение сразу после оплаты и дальше смотрит на локскрин —
/// а там висел бы этап на момент закрытия. «Оплачено, ждём отправки» через сутки после
/// отправки хуже, чем отсутствие плашки: это уже не информация, а дезинформация.
/// Поэтому активность запрашивается с pushType:.token, её токен уезжает на сервер, и
/// дальше этапы приходят пушем (inc/deal_live.php → apns_send_live).
final class DealActivityManager {
    static let shared = DealActivityManager()

    private var activity: Activity<DealActivityAttributes>?
    private var activeDealId: String?
    /// Слежение за токеном активности. Токен может смениться за её жизнь — система
    /// присылает новый в тот же поток, и старый перестаёт работать молча.
    private var tokenTask: Task<Void, Never>?

    /// Точка входа из JS-моста: {action:'start'|'update'|'end', deal:{…}}.
    func handle(_ body: [String: Any]) {
        let action = (body["action"] as? String ?? "").lowercased()
        let d = body["deal"] as? [String: Any] ?? [:]
        if action == "end" { Task { await end() }; return }
        Task { await startOrUpdate(d) }
    }

    /// Состояние из моста страницы. Сайт присылает и курьера (phase/etaAt/courier) — то же состояние,
    /// что сервер шлёт пушем. Прежняя версия сайта курьера не присылает: тогда, пока этап сделки тот
    /// же, оставляем курьера и его подписи из текущей плашки — иначе открытие приложения стирало бы
    /// «Курьер едет к вам, будет в 14:35», присланное пушем.
    private func contentState(_ d: [String: Any]) -> DealActivityAttributes.ContentState {
        let dealId = d["dealId"] as? String ?? ""
        let prev: DealActivityAttributes.ContentState? = (activeDealId == dealId) ? activity?.content.state : nil
        let status = d["status"] as? String ?? ""
        let withCourier = d.keys.contains("phase")
        let keep = !withCourier && !(prev?.phase ?? "").isEmpty && prev?.status == status
        return DealActivityAttributes.ContentState(
            status:     status,
            statusText: keep ? (prev?.statusText ?? "") : (d["statusText"] as? String ?? ""),
            stepIndex:  intVal(d["stepIndex"]),
            stepsTotal: intVal(d["stepsTotal"]),
            counterpart: d["counterpart"] as? String ?? "",
            amountText: d["amountText"] as? String ?? "",
            etaText:    keep ? (prev?.etaText ?? "") : (d["etaText"] as? String ?? ""),
            phase:      withCourier ? (d["phase"] as? String) : (keep ? prev?.phase : nil),
            etaAt:      withCourier ? positive(d["etaAt"]) : (keep ? prev?.etaAt : nil),
            courier:    withCourier ? (d["courier"] as? String) : (keep ? prev?.courier : nil)
        )
    }
    /// Время прибытия из моста: число или строка; ноль и мусор — «времени нет».
    private func positive(_ v: Any?) -> Double? {
        if let n = v as? Double { return n > 0 ? n : nil }
        if let n = v as? Int { return n > 0 ? Double(n) : nil }
        if let s = v as? String, let n = Double(s) { return n > 0 ? n : nil }
        return nil
    }
    private func intVal(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    private func startOrUpdate(_ d: [String: Any]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }   // юзер выключил Live Activities
        let dealId = d["dealId"] as? String ?? ""
        guard !dealId.isEmpty else { return }

        let cs = contentState(d)

        // Та же сделка уже показывается → просто обновляем.
        if let a = activity, activeDealId == dealId {
            await a.update(ActivityContent(state: cs, staleDate: nil))
            return
        }
        // Другая сделка (или нет активной) → закрываем старую, стартуем новую.
        if activity != nil { await end() }

        let attrs = DealActivityAttributes(
            dealId: dealId,
            title:  d["title"] as? String ?? "Сделка",
            role:   d["role"]  as? String ?? "buyer"
        )
        do {
            let a = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: cs, staleDate: nil),
                // .token, а не nil: без токена сервер не может дотянуться до плашки, и
                // она замирает в момент, когда приложение ушло в фон.
                pushType: .token
            )
            activity = a
            activeDealId = dealId
            observeToken(of: a, dealId: dealId)
        } catch {
            activity = nil; activeDealId = nil
        }
    }

    /// Токен активности → в веб-сессию → api/push_register.php (kind=live).
    /// Отдаём через WebBridge, а не шлём отсюда: запрос должен уйти С COOKIE ВЕБ-СЕССИИ
    /// и с CSRF-токеном страницы, а они есть только внутри WKWebView.
    private func observeToken(of a: Activity<DealActivityAttributes>, dealId: String) {
        tokenTask?.cancel()
        tokenTask = Task {
            for await data in a.pushTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    WebBridge.shared.liveToken = LiveToken(deal: dealId, token: hex, drop: false)
                }
            }
        }
    }

    func end() async {
        let closing = activeDealId
        tokenTask?.cancel(); tokenTask = nil
        if let a = activity {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activeDealId = nil
        // Сообщаем серверу, что адресата больше нет: иначе он будет слать пуши в
        // закрытую активность до первой ошибки от Apple, а до неё могут пройти сутки.
        if let did = closing {
            await MainActor.run {
                WebBridge.shared.liveToken = LiveToken(deal: did, token: "", drop: true)
            }
        }
    }
}
