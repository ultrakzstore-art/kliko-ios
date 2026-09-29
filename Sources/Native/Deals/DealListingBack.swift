import Foundation

extension Notification.Name {
    /// Сделка закрылась (отменена, бронь истекла, возврат, спор решён, продано) — объявление этой сделки перечитать:
    /// лента, «Мои объявления» и открытая карточка. object — id объявления (String).
    static let klikoОбъявлениеСделкиИзменилось = Notification.Name("kliko.deal.listing.changed")
}

/**
 ОБЪЯВЛЕНИЕ ПОСЛЕ СДЕЛКИ. Пока сделка жива, объявление «в резерве»: витрина его не показывает, в «Моих объявлениях»
 оно с меткой «Резерв». Сделка закрылась — сервер вернул объявление (или пометил проданным), а экраны держат старое.
 Весть уходит, когда приложение само видит переход «живая → закрытая»: в карточке сделки (гарант и eGov) и в списках
 «Моих сделок». Одна весть на сделку за запуск: повторные загрузки списка экраны не дёргают.
 */
@MainActor
enum ОбъявлениеПослеСделки {
    /// Сделки, о которых уже сообщили за этот запуск.
    private static var сообщено: Set<String> = []

    /// Закрытая сделка — гарант (confirmed, resolved, cancelled…) и eGov (completed, cancelled, expired).
    static func закрыта(_ статус: String) -> Bool {
        ["done", "resolved", "released", "completed", "closed", "confirmed",
         "cancelled", "canceled", "expired", "refunded", "returned"].contains(статус.lowercased())
    }

    /// Было живой — стало закрытой: сообщить. Прежнего статуса нет (первый показ) — экраны и так читают свежее.
    static func сверить(сделка: String, товар: String, было: String?, стало: String) {
        guard let было, !было.isEmpty, !закрыта(было), закрыта(стало) else { return }
        сообщить(сделка: сделка, товар: товар)
    }

    static func сообщить(сделка: String, товар: String) {
        let номер = товар.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !номер.isEmpty, номер != "0", сообщено.insert(сделка).inserted else { return }
        NotificationCenter.default.post(name: .klikoОбъявлениеСделкиИзменилось, object: номер)
    }
}
