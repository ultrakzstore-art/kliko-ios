import ActivityKit
import Foundation

/// Управляет одной активной Live Activity сделки (как поездка в Я.Такси — одна за раз).
/// Драйвится из веба через мост window.KlikoLive.{start,update,end} (см. WebContainer).
/// Без @available: deployment target = iOS 17, а ActivityKit/ActivityContent доступны с 16.1/16.2.
final class DealActivityManager {
    static let shared = DealActivityManager()

    private var activity: Activity<DealActivityAttributes>?
    private var activeDealId: String?

    /// Точка входа из JS-моста: {action:'start'|'update'|'end', deal:{…}}.
    func handle(_ body: [String: Any]) {
        let action = (body["action"] as? String ?? "").lowercased()
        let d = body["deal"] as? [String: Any] ?? [:]
        if action == "end" { Task { await end() }; return }
        Task { await startOrUpdate(d) }
    }

    private func contentState(_ d: [String: Any]) -> DealActivityAttributes.ContentState {
        DealActivityAttributes.ContentState(
            status:     d["status"]     as? String ?? "",
            statusText: d["statusText"] as? String ?? "",
            stepIndex:  intVal(d["stepIndex"]),
            stepsTotal: intVal(d["stepsTotal"]),
            counterpart: d["counterpart"] as? String ?? "",
            amountText: d["amountText"] as? String ?? "",
            etaText:    d["etaText"]    as? String ?? ""
        )
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
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: cs, staleDate: nil),
                pushType: nil                     // пока драйвим из приложения; для обновлений при закрытом
            )                                     // приложении → pushType:.token + отправка APNs live-activity
            activeDealId = dealId
        } catch {
            activity = nil; activeDealId = nil
        }
    }

    func end() async {
        if let a = activity {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activeDealId = nil
    }
}
