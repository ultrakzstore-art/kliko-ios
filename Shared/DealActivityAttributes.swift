import ActivityKit
import Foundation

/// Данные Live Activity сделки (общие для приложения и виджет-расширения).
/// Статичная часть (attributes) — не меняется за жизнь активности; ContentState — обновляемая.
struct DealActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String        // ключ этапа: created/paid/shipped/received/confirmed/dispute…
        var statusText: String    // человекочитаемо: «Оплачено, ждём отправки»
        var stepIndex: Int        // текущий шаг (1..stepsTotal)
        var stepsTotal: Int       // всего шагов в сделке
        var counterpart: String   // имя второй стороны
        var amountText: String    // «150 000 ₸»
        var etaText: String       // «Осталось 2ч 40м» (опц., "" — скрыть)
    }

    var dealId: String
    var title: String             // название товара/сделки
    var role: String              // buyer / seller
}
