import Foundation
import UIKit

/**
 «МОИ СДЕЛКИ» — ЗАПРОСЫ И ДАННЫЕ, ЭТАП 43 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Всё по карте кабинета (§4, §8.5): те же вызовы и те же тела, что у js/cabinet.min.js (loadDeals, openDeal, dealWaitTick,
 renderDeal, clocalRender). Транспорт — КабинетСайта.вызвать (этап 40): fetch изнутри страницы сайта под слоем, с её
 куками, Origin и Referer. Токен — тот же, что у «Моих объявлений» (МоиОбъявленияAPI.отправить): один на страницу
 кабинета, «csrf» — страница заново и один повтор (запросы этого этапа не денежные, §8.0.3).

 Только чтение (без токена, как у сайта; пути относительные — /kz/<язык>/escrow.php):
   · GET escrow.php?action=my_deals&role=seller|buyer|both   → {ok, deals[]};
   · GET escrow.php?action=deal&id=<id>                       → {ok, deal, review_edit_left, review_edit_left_b};
   · GET escrow.php?action=deal_wait&id=<id>&sig=<sig>        → {ok, changed, sig} — сервер держит соединение;
   · GET escrow.php?action=car_points&deal_id=<id>            → {ok, points[], message}.
 Запись без денег — только по нажатию, тело {csrf, …} JSON:
   · accept_terms {deal_id, accept} · dispute {deal_id, reason_code, reason, image} · upload_evidence {deal_id, note, image}
   · update_review {deal_id, side, rating, review} · /escrow.php?action=warranty_ask {id} (путь от корня, как у сайта)
   · set_handover {deal_id, mode} · set_track {deal_id, url} · courier_called {deal_id} · car_order {deal_id, point}
   · cabinet.php?action=mark_notif_read_section {section:"deals"} — сайт шлёт его, когда человек открывает «Мои сделки».
 🔴 ДЕНЬГИ — НЕТ. pay, pay_card, cancel, buyer_confirm, seller_confirm, pin_enter, meet_scan, parcel_*, ship_add, ship_drop,
 clocal_* — этап 44 (Config.деньгиСделок = false): их кнопки открывают страницу сделки сайта, запрос не уходит никогда.
 */
@MainActor
enum СделкиAPI {

    /// GET без токена. nil — ответ не JSON.
    static func получить(_ хвост: String, отКорня: Bool = false) async throws -> [String: Any]? {
        try await МоиОбъявленияAPI.получить(хвост, отКорня: отКорня)
    }

    /**
     GET фонового опроса (deal_wait, запасной deal): не ждёт страницу и не уводит её на главную. Пока человек на странице
     сайта (платёжный шлюз, eGov), фоновый запрос не должен трогать страницу под ним — «не удалось» и следующий круг.
     */
    static func получитьВФоне(_ хвост: String) async throws -> [String: Any]? {
        try await КабинетСайта.вызвать(хвост, ждать: false).json
    }

    /// Нативный слой на экране и приложение активно — только тогда идут фоновые опросы карточки.
    static var опросМожно: Bool {
        WebBridge.shared.лентаВидна && UIApplication.shared.applicationState == .active
    }

    /// POST {csrf, …}: токен и повтор на «csrf» — общие с «Моими объявлениями» (один токен на страницу кабинета).
    static func отправить(_ хвост: String, тело: [String: Any], отКорня: Bool = false) async throws -> [String: Any] {
        try await МоиОбъявленияAPI.отправить(хвост, тело: тело, отКорня: отКорня)
    }

    /// Номер сделки в адресе — encodeURIComponent сайта.
    nonisolated static func вАдрес(_ значение: String) -> String {
        значение.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? значение
    }

    /// «KLK-C2D0905C» и похожие: буквы, цифры, дефис, подчёркивание — то, что может прийти ссылкой ?deal=.
    nonisolated static func годныйНомер(_ номер: String) -> Bool {
        номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }

    // MARK: - Разбор значений — те же правила, что у «Моих объявлений» (1, "1", true — да; parseInt).

    nonisolated static func да(_ з: Any?) -> Bool { МоиОбъявленияAPI.да(з) }
    nonisolated static func строка(_ з: Any?) -> String { МоиОбъявленияAPI.строка(з) }
    nonisolated static func число(_ з: Any?) -> Double { МоиОбъявленияAPI.число(з) }
    nonisolated static func целое(_ з: Any?) -> Int { МоиОбъявленияAPI.целое(з) }

    /// parseFloat сайта для координат: число или строка; пусто и мусор — nil.
    nonisolated static func координата(_ з: Any?) -> Double? {
        if let n = з as? NSNumber { return n.doubleValue }
        if let s = з as? String, let n = Double(s.trimmingCharacters(in: .whitespaces)) { return n }
        return nil
    }

    /// Явное false (peer.chat === false сайта): нет ключа — не false.
    nonisolated static func явноНет(_ з: Any?) -> Bool {
        guard let n = з as? NSNumber else { return false }
        return n.intValue == 0
    }
}

// MARK: - Роль и вкладки

/// Вкладки «Я продавец» / «Я покупатель» (#dtab-seller / #dtab-buyer). rawValue — параметр role запроса my_deals.
enum РольСделок: String, CaseIterable, Hashable {
    case seller
    case buyer

    var название: String {
        switch self {
        case .seller: return СделкиText.т("deals_tab_seller")
        case .buyer:  return СделкиText.т("deals_tab_buyer")
        }
    }
}

// MARK: - Название товара (normalizeDeal)

enum НазваниеСделки {
    /**
     normalizeDeal сайта: убирает повтор первого слова («Apple Apple iPhone» → «Apple iPhone») и повтор бренда в начале.
     Регистр не важен, как у регулярного выражения сайта с флагом i.
     */
    static func чистое(_ название: String, бренд: String) -> String {
        var t = название.trimmingCharacters(in: .whitespacesAndNewlines)
        let слова = t.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        if слова.count >= 2 && слова[0].lowercased() == слова[1].lowercased() {
            t = ([слова[0]] + Array(слова.dropFirst(2))).joined(separator: " ")
        }
        let б = бренд.trimmingCharacters(in: .whitespacesAndNewlines)
        if !б.isEmpty {
            let двойной = б + " " + б
            if t.lowercased().hasPrefix(двойной.lowercased()) {
                let хвост = t.dropFirst(двойной.count)
                if хвост.isEmpty || хвост.first == " " {
                    t = б + String(хвост)
                }
            }
        }
        return t
    }
}

// MARK: - Сделка в списке (my_deals)

/// Запись deals[] ответа my_deals — только поля, которые читает список сайта (карта §4.2.2).
struct СделкаКратко: Identifiable, Equatable {
    let id: String
    var статус: String = ""
    var возврат: Bool = false
    var сумма: Int = 0
    var сборПродавца: Int = 0
    var продавецПолучит: Int = 0
    var кОплате: Int = 0
    var сборПокупателя: Int = 0
    var создана: String = ""
    var продавец: Bool = false
    var осталосьСек: Double = 0
    var фото: String = ""
    var название: String = ""
    var услуга: Bool = false
    var аренда: Bool = false
    var имяПокупателя: String = ""
    var имяПродавца: String = ""

    init?(_ j: [String: Any]) {
        typealias A = СделкиAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        статус = A.строка(j["status"])
        возврат = A.да(j["return_hold"])
        сумма = A.целое(j["amount"])
        сборПродавца = A.целое(j["seller_fee"])
        продавецПолучит = A.целое(j["seller_get"])
        кОплате = A.целое(j["total_pay"])
        сборПокупателя = A.целое(j["buyer_fee"])
        создана = A.строка(j["created_at"])
        продавец = A.строка(j["my_role"]) == "seller"
        осталосьСек = A.число(j["deadline_left"])
        фото = A.строка(j["product_img"]).trimmingCharacters(in: .whitespaces)
        название = НазваниеСделки.чистое(A.строка(j["product_title"]), бренд: A.строка(j["product_brand"]))
        услуга = A.строка(j["kind"]) == "service"
        аренда = A.строка(j["kind"]) == "rent" || A.строка(j["mode"]) == "rent"
        имяПокупателя = A.строка(j["buyer_name"])
        let собеседник = (j["peer"] as? [String: Any]).map { A.строка($0["name"]) } ?? ""
        let продавецИмя = A.строка(j["seller_name"])
        имяПродавца = продавецИмя.isEmpty ? собеседник : продавецИмя
    }

    /// cancelled|canceled|refunded|expired — «сделка не состоялась» в строке денег.
    var несостоялась: Bool { ["cancelled", "canceled", "refunded", "expired"].contains(статус) }

    /// Возврат при живой сделке: плашка «Возврат — деньги заморожены» вместо статуса.
    var идётВозврат: Bool { возврат && !["cancelled", "confirmed", "resolved"].contains(статус) }
}

// MARK: - Сделка целиком (deal)

/// Вторая сторона (deal.peer): имя, контакты, чат.
struct СобеседникСделки: Equatable {
    var id: String = ""
    var имя: String = ""
    var телефон: String = ""
    var whatsApp: String = ""
    var telegram: String = ""
    /// peer.chat === false: сделка закрыта, чат по ней не ведётся.
    var чатЗакрыт: Bool = false
    var роль: String = ""
}

/// Дверь (from_door / to_door): кв., подъезд, этаж, домофон, комментарий или «встреча у подъезда».
struct ДверьСделки: Equatable {
    var уПодъезда: Bool = false
    var квартира: String = ""
    var подъезд: String = ""
    var этаж: String = ""
    var домофон: String = ""
    var комментарий: String = ""

    init() {}

    init?(_ j: Any?) {
        guard let d = j as? [String: Any] else { return nil }
        typealias A = СделкиAPI
        уПодъезда = A.да(d["out"])
        квартира = A.строка(d["flat"]).trimmingCharacters(in: .whitespaces)
        подъезд = A.строка(d["porch"]).trimmingCharacters(in: .whitespaces)
        этаж = A.строка(d["floor"]).trimmingCharacters(in: .whitespaces)
        домофон = A.строка(d["code"]).trimmingCharacters(in: .whitespaces)
        комментарий = A.строка(d["note"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// dealDoorTxt сайта.
    var текст: String {
        let т = СделкиText.т
        if уПодъезда {
            return т("door_out") + (комментарий.isEmpty ? "" : "; " + т("door_note") + ": " + комментарий)
        }
        var части: [String] = []
        if !квартира.isEmpty { части.append(т("door_flat") + " " + квартира) }
        if !подъезд.isEmpty { части.append(т("door_porch") + " " + подъезд) }
        if !этаж.isEmpty { части.append(т("door_floor") + " " + этаж) }
        if !домофон.isEmpty { части.append(т("door_code") + " " + домофон) }
        let основа = части.joined(separator: ", ")
        if комментарий.isEmpty { return основа }
        return основа + (части.isEmpty ? "" : "; ") + т("door_note") + ": " + комментарий
    }
}

/// Точка на карте (_hovPt сайта): неверные и нулевые координаты — nil.
struct ТочкаСделки: Equatable {
    let широта: Double
    let долгота: Double

    init?(_ широта: Double?, _ долгота: Double?) {
        guard let ш = широта, let д = долгота, ш.isFinite, д.isFinite else { return nil }
        if abs(ш) > 90 || abs(д) > 180 || (abs(ш) < 0.01 && abs(д) < 0.01) { return nil }
        self.широта = ш
        self.долгота = д
    }
}

/// Строка истории (timeline[]).
struct СобытиеСделки: Equatable, Identifiable {
    let id: Int
    let статус: String
    let когда: String
    let заметка: String
}

/// Доказательство в споре (evidence[]).
struct ДоказательствоСделки: Equatable, Identifiable {
    let id: Int
    let покупатель: Bool
    let заметка: String
    let картинка: String
}

/// Перевозчик (ship_car + ship_car_*): СДЭК, Exline, Avis.
struct ПеревозчикСделки: Equatable {
    var имя: String = ""
    var доДвери: Bool = false
    var адресПВЗ: String = ""
    var точкаПВЗ: ТочкаСделки? = nil
    var днейОт: Int = 0
    var днейДо: Int = 0
    var заказ: String = ""
    var трек: String = ""
    var адресПриёма: String = ""
    var точкаПриёма: ТочкаСделки? = nil
    var этап: String = ""
    var отменена: Bool = false
    var ссылкаТрека: String = ""
}

/// Межгород (deal.carrier).
struct МежгородСделки: Equatable {
    var откуда: String = ""
    var куда: String = ""
    var перевозчик: String = ""
    var трек: String = ""
}

/// Доставка курьером по городу (clocal.delivery) — то, что показывается без действий.
struct КурьерСделки: Equatable {
    var статус: String = ""
    var яндекс: Bool = false
    var статусЯндекса: String = ""
    var кодЗабора: String = ""
    var пин: String = ""
    var ссылкаСлежения: String = ""
    var организатор: String = ""
}

/// Одна гарант-сделка (deal ответа escrow.php?action=deal) — поля, которые читает карточка сайта (карта §4.3.3).
struct Сделка: Equatable, Identifiable {
    let id: String
    var статус: String = ""
    var продавец: Bool = false
    var услуга: Bool = false
    /// mode || (услуга ? "service" : "goods").
    var режим: String = "goods"
    var создана: String = ""
    var завершена: String = ""
    var оплачена: Bool = false
    var подпись: String = ""

    var товар: String = ""
    var название: String = ""
    var фото: String = ""
    var раздел: String = ""
    var гарантияДней: Int = 0

    var сумма: Int = 0
    var сборПокупателя: Int = 0
    var сборПродавца: Int = 0
    var кОплате: Int = 0
    var оплачено: Int = 0
    var продавецПолучит: Int = 0
    var полнаяЦена: Int = 0
    var авансПроцент: Int = 0
    var аванс: Int = 0
    var баллыСписано: Int = 0
    var баллыПокупателю: Int = 0
    var баллыПродавцу: Int = 0
    var способОплаты: String = ""
    var срокОплаты: Int = 0

    var осталосьСек: Double = 0
    var наПроверкуСек: Double = 0
    var часовНаПроверку: Int = 72
    var срокУслуги: String = ""
    var чтоСделать: String = ""

    var имяПокупателя: String = ""
    var имяПродавца: String = ""
    var собеседник = СобеседникСделки()
    var моёИмя: String = ""
    var мойТелефон: String = ""

    var причинаСпора: String = ""
    var доказательства: [ДоказательствоСделки] = []
    var оценкаПокупателя: Int = 0
    var отзывПокупателя: String = ""
    var оценкаПродавца: Int = 0
    var отзывПродавца: String = ""
    /// review_edit_left / review_edit_left_b — ещё можно поставить или поменять оценку.
    var правкаОценки: Double = 0
    var правкаОценкиПокупателя: Double = 0

    var история: [СобытиеСделки] = []

    var передача: String = ""
    var способПередачи: String = ""
    var выбралСпособ: String = ""
    var курьерВызван: Bool = false
    var ссылкаСлежения: String = ""
    var кодыВключены: Bool = false
    var кодПринят: Bool = false
    var курьерПоГороду: Bool = false
    var возврат: Bool = false
    var межгород: Bool = false

    var адресОткуда: String = ""
    var точкаОткуда: ТочкаСделки? = nil
    var дверьОткуда: ДверьСделки? = nil
    var адресКуда: String = ""
    var точкаКуда: ТочкаСделки? = nil
    var дверьКуда: ДверьСделки? = nil
    /// recipient{name, phone} — «Отправить другому человеку — подарок» (rcpRowHtml); recipient_editable — можно менять.
    var имяПолучателя: String = ""
    var телефонПолучателя: String = ""
    var получательМеняется: Bool = false

    var доставка: Int = 0
    var доставкаЗаСчётПродавца: Int = 0
    var видДоставки: String = ""
    var перевозчик = ПеревозчикСделки()
    var межгородДанные: МежгородСделки? = nil

    /// clocal.yandex_avail / courier_avail — как window.__YADEL / __CRDEL страницы (на ней оба true); нет поля — true.
    var яндексДоступен: Bool = true
    var курьерДоступен: Bool = true
    var естьВстреча: Bool = false
    var естьПосылка: Bool = false
    var посылкаЧерезТК: Bool = false
    var курьер: КурьерСделки? = nil

    var талонПодписан: Bool = false
    /// deal.live — данные Live Activity от сервера (§4.16); nil — считаем сами, как сайт.
    var живое: [String: String]? = nil
    /// Этап 44: то, что читают только денежные блоки (код продавца, застой, возврат товара, заявка курьера).
    var деньги = ДанныеДенегСделки()

    init(id: String) {
        self.id = id
    }

    /// Разбор ответа deal: сама сделка и окна правки оценки из верхнего уровня ответа.
    init?(_ j: [String: Any], ответ: [String: Any]) {
        typealias A = СделкиAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        self.init(id: номер)
        статус = A.строка(j["status"])
        продавец = A.строка(j["my_role"]) == "seller"
        услуга = A.строка(j["kind"]) == "service"
        let вид = A.строка(j["mode"])
        режим = вид.isEmpty ? (услуга ? "service" : "goods") : вид
        создана = A.строка(j["created_at"])
        завершена = A.строка(j["confirmed_at"])
        оплачена = !A.строка(j["paid_at"]).isEmpty && A.строка(j["paid_at"]) != "0"
        подпись = A.строка(j["sig"])
        разобратьТовар(j)
        разобратьДеньги(j)
        разобратьСроки(j)
        разобратьСтороны(j)
        разобратьСпор(j, ответ: ответ)
        разобратьПередачу(j)
        разобратьДоставку(j)
        деньги = ДанныеДенегСделки(j)
    }

    private mutating func разобратьТовар(_ j: [String: Any]) {
        typealias A = СделкиAPI
        for ключ in ["product_id", "product_pid", "pid", "listing_id"] {
            let з = A.строка(j[ключ])
            if !з.isEmpty && з != "0" {
                товар = з
                break
            }
        }
        название = НазваниеСделки.чистое(A.строка(j["product_title"]), бренд: A.строка(j["product_brand"]))
        фото = A.строка(j["product_img"]).trimmingCharacters(in: .whitespaces)
        раздел = A.строка(j["category"])
        if let снимок = j["listing_snapshot"] as? [String: Any] {
            гарантияДней = max(0, A.целое(снимок["warranty_days"]))
        }
        if let талон = j["warranty_card"] as? [String: Any] {
            let когда = A.строка(талон["signed_at"])
            талонПодписан = !когда.isEmpty && когда != "0"
        }
    }

    private mutating func разобратьДеньги(_ j: [String: Any]) {
        typealias A = СделкиAPI
        сумма = A.целое(j["amount"])
        сборПокупателя = A.целое(j["buyer_fee"])
        сборПродавца = A.целое(j["seller_fee"])
        кОплате = A.целое(j["total_pay"])
        оплачено = A.целое(j["actual_pay"])
        продавецПолучит = A.целое(j["seller_get"])
        полнаяЦена = A.целое(j["full_price"])
        авансПроцент = A.целое(j["advance_pct"])
        аванс = A.целое(j["advance_amount"])
        баллыСписано = A.целое(j["points_spent"])
        баллыПокупателю = A.целое(j["points_buyer"])
        баллыПродавцу = A.целое(j["points_seller"])
        способОплаты = A.строка(j["pay_wish"])
        срокОплаты = A.целое(j["pay_wish_term"])
    }

    private mutating func разобратьСроки(_ j: [String: Any]) {
        typealias A = СделкиAPI
        осталосьСек = A.число(j["deadline_left"])
        наПроверкуСек = A.число(j["confirm_left"])
        let часы = A.целое(j["confirm_hours"])
        часовНаПроверку = часы > 0 ? часы : 72
        срокУслуги = A.строка(j["deadline"])
        чтоСделать = A.строка(j["scope"])
    }

    private mutating func разобратьСтороны(_ j: [String: Any]) {
        typealias A = СделкиAPI
        имяПокупателя = A.строка(j["buyer_name"])
        имяПродавца = A.строка(j["seller_name"])
        if let p = j["peer"] as? [String: Any] {
            собеседник.id = A.строка(p["id"])
            собеседник.имя = A.строка(p["name"]).trimmingCharacters(in: .whitespaces)
            собеседник.телефон = A.строка(p["phone"])
            собеседник.whatsApp = A.строка(p["wa"])
            собеседник.telegram = A.строка(p["tg"])
            собеседник.чатЗакрыт = A.явноНет(p["chat"])
            собеседник.роль = A.строка(p["role"])
        }
        if let я = j["me"] as? [String: Any] {
            моёИмя = A.строка(я["name"])
            мойТелефон = A.строка(я["phone"])
        }
    }

    private mutating func разобратьСпор(_ j: [String: Any], ответ: [String: Any]) {
        typealias A = СделкиAPI
        причинаСпора = A.строка(j["dispute_reason"])
        let сырые: [Any] = (j["evidence"] as? [Any]) ?? []
        var список: [ДоказательствоСделки] = []
        for (i, з) in сырые.enumerated() {
            guard let d = з as? [String: Any] else { continue }
            список.append(ДоказательствоСделки(id: i, покупатель: A.строка(d["role"]) == "buyer",
                                               заметка: A.строка(d["note"]), картинка: A.строка(d["img"])))
        }
        доказательства = список
        оценкаПокупателя = min(5, max(0, A.целое(j["buyer_rating"])))
        отзывПокупателя = A.строка(j["buyer_review"])
        оценкаПродавца = min(5, max(0, A.целое(j["seller_rating"])))
        отзывПродавца = A.строка(j["seller_review"])
        правкаОценки = A.число(ответ["review_edit_left"])
        правкаОценкиПокупателя = A.число(ответ["review_edit_left_b"])
        let события: [Any] = (j["timeline"] as? [Any]) ?? []
        var строки: [СобытиеСделки] = []
        for (i, з) in события.enumerated() {
            guard let d = з as? [String: Any] else { continue }
            строки.append(СобытиеСделки(id: i, статус: A.строка(d["status"]), когда: A.строка(d["at"]),
                                         заметка: A.строка(d["note"])))
        }
        /* (e.timeline||[]).reverse() — новые сверху. */
        история = строки.reversed()
    }

    private mutating func разобратьПередачу(_ j: [String: Any]) {
        typealias A = СделкиAPI
        передача = A.строка(j["handover"])
        способПередачи = A.строка(j["handover_mode"])
        выбралСпособ = A.строка(j["handover_by"])
        курьерВызван = A.да(j["courier_called"])
        ссылкаСлежения = A.строка(j["track_url"]).trimmingCharacters(in: .whitespacesAndNewlines)
        кодыВключены = A.да(j["pin_on"])
        кодПринят = A.да(j["pin_done"])
        курьерПоГороду = A.да(j["delivery_local"])
        возврат = A.да(j["return_hold"])
        межгород = (j["intercity"] as? NSNumber)?.boolValue == true
        адресОткуда = A.строка(j["from_addr"]).trimmingCharacters(in: .whitespacesAndNewlines)
        точкаОткуда = ТочкаСделки(A.координата(j["from_lat"]), A.координата(j["from_lon"]))
        дверьОткуда = ДверьСделки(j["from_door"])
        адресКуда = A.строка(j["to_addr"]).trimmingCharacters(in: .whitespacesAndNewlines)
        точкаКуда = ТочкаСделки(A.координата(j["to_lat"]), A.координата(j["to_lon"]))
        дверьКуда = ДверьСделки(j["to_door"])
        let получатель = (j["recipient"] as? [String: Any]) ?? [:]
        имяПолучателя = A.строка(получатель["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
        телефонПолучателя = A.строка(получатель["phone"]).trimmingCharacters(in: .whitespacesAndNewlines)
        получательМеняется = A.да(j["recipient_editable"])
        if let сырое = j["live"] as? [String: Any] {
            var словарь: [String: String] = [:]
            for (ключ, значение) in сырое { словарь[ключ] = A.строка(значение) }
            живое = словарь
        }
    }

    private mutating func разобратьДоставку(_ j: [String: Any]) {
        typealias A = СделкиAPI
        доставка = A.целое(j["ship_fee"])
        доставкаЗаСчётПродавца = A.целое(j["ship_by_seller"])
        видДоставки = A.строка(j["ship_mode"])
        let машина = (j["ship_car"] as? [String: Any]) ?? [:]
        let имя = A.строка(машина["name"]).trimmingCharacters(in: .whitespaces)
        let код = A.строка(j["ship_carrier"])
        let известные: [String: String] = ["cdek": "СДЭК", "exline": "Exline", "avis": "Avis"]
        перевозчик.имя = !имя.isEmpty ? имя : (известные[код] ?? код.uppercased())
        перевозчик.доДвери = A.строка(машина["kind"]) == "door"
        перевозчик.адресПВЗ = A.строка(машина["pvz_addr"]).trimmingCharacters(in: .whitespaces)
        перевозчик.точкаПВЗ = ТочкаСделки(A.координата(машина["pvz_lat"]), A.координата(машина["pvz_lon"]))
        перевозчик.днейОт = A.целое(машина["days_min"])
        перевозчик.днейДо = A.целое(машина["days_max"])
        перевозчик.заказ = A.строка(j["ship_car_order"]).trimmingCharacters(in: .whitespaces)
        перевозчик.трек = A.строка(j["ship_car_number"]).trimmingCharacters(in: .whitespaces)
        перевозчик.адресПриёма = A.строка(j["ship_car_point_addr"]).trimmingCharacters(in: .whitespaces)
        перевозчик.точкаПриёма = ТочкаСделки(A.координата(j["ship_car_point_lat"]), A.координата(j["ship_car_point_lon"]))
        перевозчик.этап = A.строка(j["ship_car_stage"])
        перевозчик.отменена = A.да(j["ship_car_cancelled"])
        перевозчик.ссылкаТрека = A.строка(j["ship_car_track_url"])
        if let м = j["carrier"] as? [String: Any], A.да(м["intercity"]) {
            межгородДанные = МежгородСделки(откуда: A.строка(м["from"]), куда: A.строка(м["to"]),
                                            перевозчик: A.строка(м["name"]), трек: A.строка(м["track"]))
        }
        let блок = (j["clocal"] as? [String: Any]) ?? [:]
        if блок["yandex_avail"] != nil { яндексДоступен = A.да(блок["yandex_avail"]) }
        if блок["courier_avail"] != nil { курьерДоступен = A.да(блок["courier_avail"]) }
        естьВстреча = блок["meet"] is [String: Any]
        естьПосылка = блок["parcel"] is [String: Any]
        посылкаЧерезТК = межгород
        if let д = блок["delivery"] as? [String: Any] {
            var к = КурьерСделки()
            к.статус = A.строка(д["status"])
            к.яндекс = A.да(д["yandex_on"])
            к.статусЯндекса = A.строка(д["yandex_status"]).lowercased()
            к.кодЗабора = A.строка(д["pickup_code"])
            к.пин = A.строка(д["delivery_pin"])
            к.ссылкаСлежения = A.строка(д["yandex_share_url"])
            к.организатор = A.строка(д["arranger"])
            курьер = к
        }
    }

    // MARK: - Правила сайта

    /**
     dealTerminal сайта: confirmed, cancelled, resolved — опрос больше не нужен, плашка Live Activity закрывается. Сайт не
     знает expired («Авто-завершена», §4.21) и опрашивал бы закрытую сделку вечно — здесь она тоже конечная.
     */
    var конечная: Bool {
        статус == "confirmed" || статус == "cancelled" || статус == "resolved" || статус == "expired"
    }

    /// Задаток и аренда.
    var задаток: Bool { режим == "deposit" }
    var аренда: Bool { режим == "rent" }

    /// l сайта: возврат товара при живой сделке — вместо действий одна плашка.
    var идётВозврат: Bool {
        возврат && ["pending", "held", "shipped", "delivered", "disputed"].contains(статус)
    }

    /// dealShipCost / dealShipCar / dealShipYa.
    var стоимостьДоставки: Int { доставка > 0 ? доставка : max(0, доставкаЗаСчётПродавца) }
    var черезПеревозчика: Bool { видДоставки == "carrier" && стоимостьДоставки > 0 }
    var курьерЯндексаОплачен: Bool { стоимостьДоставки > 0 && (видДоставки == "yandex" || видДоставки.isEmpty) }

    /**
     Отмена недоступна (k() в renderDeal): перевозчик уже везёт, курьер забрал или Яндекс в пути. Сама отмена — деньги
     (этап 44), но пояснение сайта «Посылка уже в пути…» видно и здесь.
     */
    var отменаЗаперта: Bool {
        let этап = перевозчик.этап
        if !этап.isEmpty && этап != "created" && !перевозчик.отменена { return true }
        guard let к = курьер else { return false }
        let вПути: Set<String> = ["pickuped", "delivery_arrived", "ready_for_delivery_confirmation", "delivered",
                                  "delivered_finish", "returning", "return_arrived", "ready_for_return_confirmation"]
        return вПути.contains(к.статусЯндекса)
    }

    /**
     dealStateKey сайта — то, что меняет вид карточки. Натив перерисовывает сам, а ключ нужен, чтобы не дёргать Live
     Activity на каждом опросе.
     */
    var ключСостояния: String {
        [статус, возврат ? "1" : "0", курьерПоГороду ? "1" : "0", передача, оплачена ? "1" : "0", адресОткуда,
         способПередачи, курьерВызван ? "1" : "0", ссылкаСлежения, кодПринят ? "1" : "0"].joined(separator: "|")
    }

    /// dealIsPhone: смартфон или планшет — по разделу и по названию, как у сайта.
    var телефонИлиПланшет: Bool {
        if раздел == "smartphones" || раздел == "tablets" || раздел.hasPrefix("smartphones") || раздел.hasPrefix("tablets") {
            return true
        }
        let t = название.lowercased()
        return t.range(of: "iphone|айфон|ipad|айпад|galaxy|redmi|\\bpoco\\b|realme|oneplus|смартфон|планшет|tablet",
                       options: .regularExpression) != nil
    }
}

// MARK: - Пункт приёма перевозчика (car_points)

struct ПунктПриёма: Identifiable, Equatable {
    let id: String
    let адрес: String
    let часы: String
    let км: Double
    let точка: ТочкаСделки?

    init?(_ j: [String: Any]) {
        typealias A = СделкиAPI
        let код = A.строка(j["code"])
        guard !код.isEmpty else { return nil }
        id = код
        адрес = A.строка(j["addr"])
        часы = A.строка(j["hours"])
        км = A.число(j["km"])
        точка = ТочкаСделки(A.координата(j["lat"]), A.координата(j["lon"]))
    }

    /// «addr · hours · N км» — строка списка сайта.
    var подпись: String {
        var части: [String] = [адрес.isEmpty ? id : адрес]
        if !часы.isEmpty { части.append(часы) }
        if км > 0 {
            let округлено = (км * 10).rounded() / 10
            части.append(String(format: СделкиText.т("car_km"), СделкиФормат.дробь(округлено)))
        }
        return части.joined(separator: " · ")
    }
}

// MARK: - Формат чисел и дат

enum СделкиФормат {
    /// toLocaleString("ru-RU") целого: «12 345».
    static func деньги(_ n: Int) -> String {
        let ф = NumberFormatter()
        ф.locale = Locale(identifier: "ru_RU")
        ф.numberStyle = .decimal
        ф.maximumFractionDigits = 0
        return ф.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// «12 345 ₸».
    static func тенге(_ n: Int) -> String { (деньги(n) + " ₸").слеваНаправо }

    static func дробь(_ n: Double) -> String {
        let ф = NumberFormatter()
        ф.locale = Locale(identifier: "ru_RU")
        ф.numberStyle = .decimal
        ф.maximumFractionDigits = 1
        return ф.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Дата ISO сервера (created_at, timeline.at). Есть и «2026-09-25 14:03:00» — берём оба вида.
    static func дата(_ строка: String) -> Date? {
        let s = строка.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ф.date(from: s)
    }

    /// «25 сент.» — toLocaleDateString(ru-RU, {day:"2-digit", month:"short"}) строки списка.
    static func деньМесяц(_ строка: String) -> String {
        guard let d = дата(строка) else { return "" }
        let ф = DateFormatter()
        ф.locale = СделкиText.локаль
        ф.setLocalizedDateFormatFromTemplate("ddMMM")
        return ф.string(from: d)
    }

    /// «25 сент., 14:03» — история сделки (DEAL_LOCALE, day 2-digit, month short, hour, minute).
    static func сВременем(_ строка: String) -> String {
        guard let d = дата(строка) else { return "" }
        let ф = DateFormatter()
        ф.locale = СделкиText.локаль
        ф.setLocalizedDateFormatFromTemplate("ddMMMHHmm")
        return ф.string(from: d)
    }

    /// «25 сентября 2026 г., 14:03» — чек (month long, year numeric).
    static func полная(_ строка: String) -> String {
        guard let d = дата(строка) else { return "" }
        let ф = DateFormatter()
        ф.locale = СделкиText.локаль
        ф.setLocalizedDateFormatFromTemplate("ddMMMMyyyyHHmm")
        return ф.string(from: d)
    }

    /// «Hч Mм» — таймер авто-подтверждения.
    static func часыМинуты(_ секунд: Double) -> String {
        let всего = max(0, Int(секунд))
        return String(всего / 3600) + СделкиText.т("h_short") + " " + String((всего % 3600) / 60) + СделкиText.т("m_short")
    }

    /// dealLeftTxt: «2 дн 5ч», «5ч», «12 мин».
    static func осталось(_ секунд: Double) -> String {
        let всего = Int(секунд)
        if всего <= 0 { return "" }
        let дни = всего / 86400
        let часы = (всего % 86400) / 3600
        if дни > 0 {
            return String(дни) + " " + СделкиText.т("dl_d_short") + (часы > 0 ? " " + String(часы) + СделкиText.т("h_short") : "")
        }
        if часы > 0 { return String(часы) + СделкиText.т("h_short") }
        return String(max(1, всего / 60)) + " " + СделкиText.т("min_short")
    }
}

// MARK: - Шаги мастера и заголовок статуса

/// dealStepModel сайта: подписи пяти шагов, текущий, «все пройдены», надпись паузы.
struct ШагиСделки: Equatable {
    let подписи: [String]
    let текущий: Int
    let всеПройдены: Bool
    let пауза: String
}

extension Сделка {
    /// Порядок статусов мастера: товар (и задаток, и аренда) — pending…confirmed; услуга — proposed…confirmed.
    var порядокШагов: [String] {
        услуга ? ["proposed", "accepted", "held", "delivered", "confirmed"]
               : ["pending", "held", "shipped", "delivered", "confirmed"]
    }

    var подписиШагов: [String] {
        let т = СделкиText.т
        if услуга {
            return [т("dstep_request"), т("dstep_agreed"), т("dstep_pay"), т("dstep_done"), т("dstep_accepted")]
        }
        if задаток {
            return [т("dstep_pay"), т("dstep_deposit"), т("dstep_meeting"), т("dstep_reissue"), т("dstep_ready")]
        }
        if аренда {
            return [т("dstep_pay"), т("dstep_pledge"), т("dstep_handover"), т("dstep_return"), т("dstep_ready")]
        }
        return [т("dstep_pay"), т("dstep_freeze"), т("dstep_ship"), т("dstep_receive"), т("dstep_ready")]
    }

    /**
     dealStepModel: вызванный курьер у товара двигает мастер на «Отправку»; спор — шаг 4 с надписью «Спор — шаги
     приостановлены»; возврат — «Возврат — деньги придержаны». expired сайт ставит на шаг 1 (indexOf −1 → 0), хотя в
     теле пишет «Сделка завершена» — здесь, как confirmed, все шаги пройдены (§4.21).
     */
    var шаги: ШагиСделки {
        let подписи = подписиШагов
        var i = max(0, порядокШагов.firstIndex(of: статус) ?? 0)
        var готово = false
        var пауза = ""
        if !услуга && курьерВызван && i < 2 && статус != "disputed" { i = 2 }
        if статус == "confirmed" || статус == "resolved" || статус == "expired" {
            i = подписи.count - 1
            готово = true
        } else if статус == "disputed" {
            i = 3
            пауза = СделкиText.т("dw_frozen")
        } else if возврат {
            пауза = СделкиText.т("dw_return")
        }
        return ШагиСделки(подписи: подписи, текущий: i, всеПройдены: готово, пауза: пауза)
    }

    /// Заголовок статуса в шапке карточки (объект a в renderDeal) — с подменами услуги, задатка и аренды.
    var заголовокСтатуса: String {
        let т = СделкиText.т
        if идётВозврат { return т("deal_st_return") }
        switch статус {
        case "proposed": return т("dl_proposed")
        case "accepted": return т("dl_accepted")
        case "pending": return т("deal_st_pending")
        case "held":
            if задаток { return т("dl_dep_held") }
            if аренда { return т("dl_rent_held") }
            return т(услуга ? "dl_svc_held" : "deal_st_held")
        case "shipped":
            if задаток { return т("dl_dep_shipped") }
            if аренда { return т("dl_rent_shipped") }
            return т("deal_st_shipped")
        case "delivered":
            if задаток { return т("dl_dep_delivered") }
            if аренда { return т("dl_rent_delivered") }
            if услуга { return т("dl_svc_delivered") }
            return т(продавец ? "dl_delivered_s" : "dl_delivered")
        case "confirmed": return т("deal_st_confirmed")
        case "disputed": return т("dl_disputed")
        case "resolved": return т("deal_st_resolved")
        case "cancelled": return т("deal_st_cancelled")
        case "expired": return т("deal_st_expired")
        default: return статус
        }
    }

    /// dealRoleLine: «Я продаю · Имя», для услуги и аренды свои слова.
    var строкаРоли: String {
        СтрокаРолиСделки.текст(продавец: продавец, услуга: услуга, аренда: аренда,
                               имя: продавец ? имяПокупателя : (имяПродавца.isEmpty ? собеседник.имя : имяПродавца))
    }
}

enum СтрокаРолиСделки {
    static func текст(продавец: Bool, услуга: Bool, аренда: Bool, имя: String) -> String {
        let т = СделкиText.т
        let роль: String
        if аренда {
            роль = т(продавец ? "role_rent_s" : "role_rent_b")
        } else if услуга {
            роль = т(продавец ? "role_svc_s" : "role_svc_b")
        } else {
            роль = т(продавец ? "role_sell" : "role_buy")
        }
        let чистое = имя.trimmingCharacters(in: .whitespaces)
        return чистое.isEmpty ? роль : роль + " · " + чистое
    }
}

// MARK: - Live Activity (dealLiveActivity сайта)

enum ЖиваяСделка {
    /**
     То же, что dealLiveActivity сайта при каждой отрисовке: конечная сделка — плашку закрыть (но только если это она:
     сайт шлёт end() без номера, и натив закрывал бы чужую, §4.21); есть deal.live сервера — его; иначе шаги мастера,
     посчитанные здесь. start сайт не зовёт — update сам начинает активность, как у моста WebContainer.
     */
    @MainActor
    static func показать(_ с: Сделка) {
        guard Config.нативныеСделки else { return }
        if с.конечная {
            let номер = с.id
            DealActivityManager.shared.завершить(сделку: номер)
            return
        }
        let название = с.название.isEmpty ? СделкиText.т("deal_word") : с.название
        let роль = с.продавец ? "seller" : "buyer"
        var данные: [String: Any] = ["dealId": с.id, "title": название, "role": роль]
        if let ж = с.живое {
            данные["status"] = (ж["status"] ?? "").isEmpty ? с.статус : (ж["status"] ?? "")
            данные["statusText"] = ж["statusText"] ?? ""
            данные["stepIndex"] = max(1, Int(ж["stepIndex"] ?? "") ?? 1)
            данные["stepsTotal"] = Int(ж["stepsTotal"] ?? "") ?? 0
            данные["counterpart"] = ж["counterpart"] ?? ""
            данные["amountText"] = ж["amountText"] ?? ""
            данные["etaText"] = ж["etaText"] ?? ""
            данные["phase"] = ж["phase"] ?? ""
            данные["etaAt"] = Double(ж["etaAt"] ?? "") ?? 0
            данные["courier"] = ж["courier"] ?? ""
        } else {
            let порядок = с.порядокШагов
            let подписи = с.подписиШагов
            let i = max(0, порядок.firstIndex(of: с.статус) ?? 0)
            данные["status"] = с.статус
            данные["statusText"] = i < подписи.count ? подписи[i] : ""
            данные["stepIndex"] = i + 1
            данные["stepsTotal"] = подписи.count
            данные["counterpart"] = с.продавец ? с.имяПокупателя : с.имяПродавца
            данные["amountText"] = с.сумма > 0 ? СделкиФормат.тенге(с.сумма) : ""
            данные["etaText"] = ""
            /* Отслеживание (Sources/Native/Tracking): статус курьера Яндекса или перевозчика — на плашке. */
            if let трек = КэшТрека.прочитать(с.id), трек.содержательно, !трек.статус.конечный {
                let фаза = трек.фазаКурьера
                let части: [String] = фаза == nil ? [трек.название, трек.подпись] : [трек.подпись]
                данные["statusText"] = части.filter { !$0.isEmpty }.joined(separator: " · ")
                if let фаза { данные["phase"] = фаза }
                if let срок = трек.срокДляПлашки { данные["etaAt"] = срок }
                if let машина = трек.машинаДляПлашки { данные["courier"] = машина }
            }
        }
        DealActivityManager.shared.handle(["action": "update", "deal": данные])
    }
}

// MARK: - Отслеживание доставки (Sources/Native/Tracking)

extension Сделка {
    /// Карточка «Отслеживание»: есть кого отслеживать (перевозчик, курьер Яндекса, ссылка, трек межгорода), сделка в пути
    /// или только что закрыта.
    var естьОтслеживание: Bool {
        let этапы: Set<String> = ["held", "shipped", "delivered", "disputed", "confirmed"]
        guard этапы.contains(статус) else { return false }
        if черезПеревозчика && (!перевозчик.трек.isEmpty || !перевозчик.заказ.isEmpty || !перевозчик.этап.isEmpty) {
            return true
        }
        if let к = курьер, к.яндекс || !к.статусЯндекса.isEmpty { return true }
        if !ссылкаСлежения.isEmpty { return true }
        if let м = межгородДанные, !м.трек.isEmpty { return true }
        /* Отправка транспортной компанией (handover_mode carrier): карточка ждёт трек-номер ТК — продавец добавит его
           здесь же («Добавить трек»), покупатель увидит статус, как только номер появится. */
        if способПередачи == "carrier" && ["held", "shipped", "delivered"].contains(статус) { return true }
        return false
    }

    /// «Изменить трек или ссылку» — как dealTrackLink сайта: не «сам», held/shipped.
    var можноМенятьТрек: Bool {
        способПередачи != "self" && (статус == "held" || статус == "shipped")
    }
}
