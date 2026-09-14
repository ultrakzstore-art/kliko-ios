import ActivityKit
import Foundation

/// Данные Live Activity сделки (общие для приложения и виджет-расширения).
/// Статичная часть (attributes) — не меняется за жизнь активности; ContentState — обновляемая.
///
/// 🔴 КЛЮЧИ ContentState ОБЯЗАНЫ СОВПАДАТЬ с deal_live_state() в inc/deal_live.php сайта: пуш от
/// сервера iOS разбирает этим же Codable, и обязательный ключ, которого сервер не прислал, молча
/// отбросит обновление — плашка застынет на старом этапе. Поэтому всё, что добавлено после версии
/// 1.2, — необязательное: старый сервер и новая плашка (и наоборот) продолжают понимать друг друга.
struct DealActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String        // ключ этапа: pending/held/shipped/delivered/confirmed…
        var statusText: String    // человекочитаемо: «Оплачено, ждём отправки» или «Курьер едет к вам»
        var stepIndex: Int        // текущий шаг (1..stepsTotal)
        var stepsTotal: Int       // всего шагов в сделке
        var counterpart: String   // имя второй стороны
        var amountText: String    // «150 000 ₸»
        var etaText: String       // «Будет в 14:35» (опц., "" — скрыть)

        // ── Курьер (с версии 1.3; владелец 14.09.2026: «когда курьер, во сколько будет, забрал, отвёз, где едет») ──
        /// Где курьер: search · to_seller · at_seller · to_buyer · at_buyer · delivered · returning. nil или "" — курьера нет.
        var phase: String?
        /// Когда курьер будет на следующей точке — unix-время. Плашка сама показывает «14:35» и обратный отсчёт.
        var etaAt: Double?
        /// Машина курьера: «белый Hyundai Solaris».
        var courier: String?
    }

    var dealId: String
    var title: String             // название товара/сделки
    var role: String              // buyer / seller
}
