import Foundation

/**
 ЭТАП ДОСТАВКИ ПЕРЕВОЗЧИКОМ НА ПЛАШКЕ СДЕЛКИ (владелец 07.10.2026: «сделай всё, что предлагаешь»).

 У курьера Яндекса на плашке своя дорога (phase). У посылки перевозчика (СДЭК и другие) — пять этапов:
 accepted (принята) · in_transit (в пути) · in_city (в городе получателя) · pickup_point (в пункте выдачи) ·
 delivered (вручена). Ключ уходит в DealActivityAttributes.ContentState.deliveryStage.

 Источник — запись отслеживания, которую приложение уже получает (КэшТрека, Sources/Native/Tracking): сырой код СДЭК
 (кодПеревозчика), иначе нормализованный статус и слова последнего события. Сервер может прислать тот же ключ
 deliveryStage в пуше Live Activity (inc/deal_live.php) — плашка поймёт его без обновления приложения.
 */
extension ДанныеТрека {
    var этапДоставкиДляПлашки: String? {
        guard фазаКурьера == nil else { return nil }
        if let поКоду = Self.этапСДЭК(кодПеревозчика) { return поКоду }
        switch статус {
        case .принят:        return "accepted"
        case .вПути:         return вГородеПолучателя ? "in_city" : "in_transit"
        case .курьерВезёт:   return "in_city"
        case .вПунктеВыдачи: return "pickup_point"
        case .доставлен:     return "delivered"
        case .создан, .возврат, .проблема, .отменён, .неизвестно: return nil
        }
    }

    /// Слова сервера или последнего события: «прибыло в город получателя», «arrived at recipient city».
    private var вГородеПолучателя: Bool {
        let тексты = [текстСтатуса, события.first?.текст ?? ""].map { $0.lowercased() }
        let слова = ["город получателя", "городе получателя", "recipient city", "алушы қала"]
        return тексты.contains { текст in слова.contains { текст.contains($0) } }
    }

    /// Коды статусов заказа СДЭК (API v2) → этап плашки; не код СДЭК — nil.
    private static func этапСДЭК(_ код: String) -> String? {
        switch код.uppercased() {
        case "RECEIVED_AT_SHIPMENT_WAREHOUSE", "READY_FOR_SHIPMENT_IN_SENDER_CITY", "ACCEPTED_AT_SENDER_POSTAMAT":
            return "accepted"
        case "TAKEN_BY_TRANSPORTER_FROM_SENDER_CITY", "SENT_TO_TRANSIT_CITY", "ACCEPTED_IN_TRANSIT_CITY",
             "ACCEPTED_AT_TRANSIT_WAREHOUSE", "READY_FOR_SHIPMENT_IN_TRANSIT_CITY",
             "TAKEN_BY_TRANSPORTER_FROM_TRANSIT_CITY", "SENT_TO_RECIPIENT_CITY":
            return "in_transit"
        case "ACCEPTED_IN_RECIPIENT_CITY", "ACCEPTED_AT_RECIPIENT_CITY_WAREHOUSE", "TAKEN_BY_COURIER":
            return "in_city"
        case "ACCEPTED_AT_PICK_UP_POINT", "POSTOMAT_POSTED":
            return "pickup_point"
        case "DELIVERED", "POSTOMAT_RECEIVED":
            return "delivered"
        default:
            return nil
        }
    }
}
