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

    /**
     Пуш о сделке (escrow_cancel, escrow_resolved, escrow_release…, у eGov — eds с eds_id): другая сторона отменила,
     бронь истекла, спор решён. Экраны сделки при этом могут быть закрыты — узнаём статус тихим запросом и, если
     сделка закрыта, сообщаем. Значения — уже строками из userInfo (AppDelegate).
     */
    static func пуш(тип: String, сделка: String, сделкаEDS: String) {
        let номер = сделка.trimmingCharacters(in: .whitespacesAndNewlines)
        let номерEDS = сделкаEDS.trimmingCharacters(in: .whitespacesAndNewlines)
        if !номер.isEmpty, тип.hasPrefix("escrow") || тип == "refund_check" {
            guard !сообщено.contains(номер) else { return }
            Task { await проверитьГарант(номер) }
        } else if !номерEDS.isEmpty {
            guard !сообщено.contains(номерEDS) else { return }
            Task { await проверитьEDS(номерEDS) }
        }
    }

    private static func проверитьГарант(_ номер: String) async {
        guard let j = try? await СделкиAPI.получитьВФоне("escrow.php?action=deal&id=" + СделкиAPI.вАдрес(номер)),
              СделкиAPI.да(j["ok"]), let d = j["deal"] as? [String: Any] else { return }
        let статус = СделкиAPI.строка(d["status"])
        guard закрыта(статус) else { return }
        сообщить(сделка: номер, товар: СделкиAPI.строка(d["product_id"]))
    }

    private static func проверитьEDS(_ номер: String) async {
        guard let j = try? await EDSAPI.сделкаВФоне(номер), РазборEDS.да(j["ok"]),
              let d = j["deal"] as? [String: Any], let с = СделкаEDS(d), закрыта(с.статус) else { return }
        сообщить(сделка: с.id, товар: с.товарИд)
    }

    static func сообщить(сделка: String, товар: String) {
        let номер = товар.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !номер.isEmpty, номер != "0", сообщено.insert(сделка).inserted else { return }
        NotificationCenter.default.post(name: .klikoОбъявлениеСделкиИзменилось, object: номер)
    }
}
