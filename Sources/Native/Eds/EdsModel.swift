import Foundation
import SwiftUI
import UIKit
import Combine

/**
 СДЕЛКА С ПОДПИСЬЮ eGov — ДАННЫЕ И МОДЕЛЬ ОКНА (edsOpen / _edsRender / _edsPost модуля js/cabinet-eds.min.js).

 Сделка без гаранта: договор купли-продажи обе стороны подписывают кодом eGov, товар передают на встрече (код передачи
 или QR), курьером Яндекса по городу или почтой с наложенным платежом, потом обе подписывают акт приёма-передачи.
 Деньги за товар идут продавцу напрямую; площадке — только плата за подпись договора и доставка курьером (с баланса
 кошелька). Статусы — _edsSt: signing, signed, shipping, met, completed, disputed, cancelled, expired. Что можно сейчас —
 флаги deal.can.* сервера, как у сайта.
 */

// MARK: - Разбор значений

enum РазборEDS {
    static func строка(_ з: Any?) -> String { МоиОбъявленияAPI.строка(з) }
    static func да(_ з: Any?) -> Bool { МоиОбъявленияAPI.да(з) }
    static func число(_ з: Any?) -> Double { МоиОбъявленияAPI.число(з) }
    static func целое(_ з: Any?) -> Int { МоиОбъявленияAPI.целое(з) }

    /// Истинное значение JS: объект, непустая строка, ненулевое число, true.
    static func есть(_ з: Any?) -> Bool {
        guard let з, !(з is NSNull) else { return false }
        if let n = з as? NSNumber { return n.doubleValue != 0 }
        if let s = з as? String { return !s.isEmpty }
        return true
    }

    /// Подпись стороны (contract.seller, act.buyer…): объект {at} — подписано; null — нет.
    static func подпись(_ з: Any?) -> String? {
        guard есть(з) else { return nil }
        if let d = з as? [String: Any] { return строка(d["at"]) }
        if let s = з as? String { return s }
        return ""
    }

    static func словарь(_ з: Any?) -> [String: Any] {
        (з as? [String: Any]) ?? [:]
    }
}

// MARK: - Части сделки

/// Точка {lat, lon}: оба числа и не 0,0 (clcYaMapMarks сайта).
struct ТочкаEDS: Equatable {
    let широта: Double
    let долгота: Double

    static func из(_ з: Any?) -> ТочкаEDS? {
        guard let d = з as? [String: Any],
              let ш = СделкиAPI.координата(d["lat"]), let д = СделкиAPI.координата(d["lon"]),
              ш.isFinite, д.isFinite, ш != 0 || д != 0 else { return nil }
        return ТочкаEDS(широта: ш, долгота: д)
    }
}

/// Дверь (ship.to.door): {out} — у подъезда, иначе {flat, porch, floor, code, note}.
struct ДверьEDS: Equatable {
    var уПодъезда = false
    var квартира = ""
    var подъезд = ""
    var этаж = ""
    var домофон = ""
    var заметка = ""

    init() {}

    init(_ з: Any?) {
        let d = РазборEDS.словарь(з)
        уПодъезда = РазборEDS.да(d["out"])
        квартира = РазборEDS.строка(d["flat"])
        подъезд = РазборEDS.строка(d["porch"])
        этаж = РазборEDS.строка(d["floor"])
        домофон = РазборEDS.строка(d["code"])
        заметка = РазборEDS.строка(d["note"])
    }

    /// _apkDoorVal сайта: у подъезда — {out:true, note?}; иначе {flat, porch, floor, code, note?}.
    var значение: [String: Any] {
        let з = String(заметка.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if уПодъезда {
            var д: [String: Any] = ["out": true]
            if !з.isEmpty { д["note"] = з }
            return д
        }
        var д: [String: Any] = [
            "flat": квартира.trimmingCharacters(in: .whitespaces),
            "porch": подъезд.trimmingCharacters(in: .whitespaces),
            "floor": этаж.trimmingCharacters(in: .whitespaces),
            "code": домофон.trimmingCharacters(in: .whitespaces)
        ]
        if !з.isEmpty { д["note"] = з }
        return д
    }
}

/// Реквизиты продавца (ship.pay_to): тип, маска, открыты ли покупателю и сами реквизиты.
struct РеквизитыEDS: Equatable {
    var тип = ""
    var маска = ""
    var открыты = false
    var значение = ""

    init(_ з: Any?) {
        let d = РазборEDS.словарь(з)
        тип = РазборEDS.строка(d["type"])
        маска = РазборEDS.строка(d["mask"])
        открыты = РазборEDS.да(d["open"])
        значение = РазборEDS.строка(d["value"])
    }

    var есть: Bool { !маска.isEmpty }

    /// o.open ? _edsPtFmt(type, value) : mask.
    var показ: String { открыты ? ФорматEDS.реквизиты(тип, значение) : маска }
}

/// Курьер Яндекса по сделке (ship.courier).
struct КурьерEDS: Equatable {
    var сорвался = false
    var снят = false
    var статус = ""
    var этап = ""
    var имя = ""
    var машина = ""
    var где: ТочкаEDS? = nil
    var откуда: ТочкаEDS? = nil
    var куда: ТочкаEDS? = nil
    var етаА: Double = 0
    var етаБ: Double = 0
    var етаВ: Double = 0
    var звонок = false
    var отслеживание = ""

    init(_ d: [String: Any]) {
        сорвался = РазборEDS.да(d["failed"])
        снят = РазборEDS.да(d["cancelled"])
        статус = РазборEDS.строка(d["status"]).lowercased()
        этап = РазборEDS.строка(d["seg"])
        имя = РазборEDS.строка(d["name"])
        машина = РазборEDS.строка(d["car"])
        где = ТочкаEDS.из(d["pos"])
        откуда = ТочкаEDS.из(d["from"])
        куда = ТочкаEDS.из(d["to"])
        етаА = РазборEDS.число(d["eta_a"])
        етаБ = РазборEDS.число(d["eta_b"])
        етаВ = РазборEDS.число(d["eta_r"])
        звонок = РазборEDS.есть(d["call"])
        отслеживание = РазборEDS.строка(d["share"])
    }
}

/// Отправка почтой (ship.post): перевозчик, трек, ссылка «Где посылка».
struct ПочтаEDS: Equatable {
    var название = ""
    var трек = ""
    var адрес = ""
}

/// ship сделки: способ передачи и всё, что к нему.
struct ДоставкаEDS: Equatable {
    var способ = "meet"
    var курьерВозможен = false
    var кудаАдрес = ""
    var кудаДверь = ДверьEDS()
    var платит = ""
    var стоимость = 0
    var оплачена = false
    var возвращена = false
    var реквизиты = РеквизитыEDS(nil)
    var заборАдрес = ""
    var курьер: КурьерEDS? = nil
    var ошибкаВызова = false
    var почта: ПочтаEDS? = nil
    var часовНаОплату = 0
    var оплатитьДо = ""
    var оплатаОтмечена = false

    init() {}

    init(_ d: [String: Any]) {
        let м = РазборEDS.строка(d["method"])
        способ = м.isEmpty ? "meet" : м
        курьерВозможен = РазборEDS.да(d["courier_on"])
        let куда = РазборEDS.словарь(d["to"])
        кудаАдрес = РазборEDS.строка(куда["addr"])
        кудаДверь = ДверьEDS(куда["door"])
        платит = РазборEDS.строка(d["payer"])
        стоимость = РазборEDS.целое(d["fee"])
        оплачена = РазборEDS.есть(d["paid"])
        возвращена = РазборEDS.есть(d["refunded"])
        реквизиты = РеквизитыEDS(d["pay_to"])
        заборАдрес = РазборEDS.строка(РазборEDS.словарь(d["pickup"])["addr"])
        if let к = d["courier"] as? [String: Any] { курьер = КурьерEDS(к) }
        ошибкаВызова = РазборEDS.есть(d["courier_err"])
        if let п = d["post"] as? [String: Any] {
            почта = ПочтаEDS(название: РазборEDS.строка(п["name"]), трек: РазборEDS.строка(п["track"]),
                             адрес: РазборEDS.строка(п["url"]))
        }
        часовНаОплату = РазборEDS.целое(d["pay_after_h"])
        оплатитьДо = РазборEDS.строка(d["pay_due"])
        оплатаОтмечена = РазборEDS.есть(d["paid_mark"])
    }

    /// Всё, кроме живых полей курьера (pos, eta_*): их смена не перерисовывает окно заново (_edsStateSig).
    var безЖивого: ДоставкаEDS {
        var копия = self
        копия.курьер?.где = nil
        копия.курьер?.етаА = 0
        копия.курьер?.етаБ = 0
        копия.курьер?.етаВ = 0
        return копия
    }
}

/// Флаги deal.can.* — что человеку можно сейчас.
struct МожноEDS: Equatable {
    var подписатьДоговор = false
    var подписатьАкт = false
    var реквизиты = false
    var выбратьДоставку = false
    var оплатитьДоставку = false
    var вызватьКурьера = false
    var показатьКод = false
    var ввестиКод = false
    var кодКурьеру = false
    var кодПосылки = false
    var отправитьПочтой = false
    var отметитьОплату = false
    var отменить = false
    var сообщить = false

    init() {}

    init(_ з: Any?) {
        let d = РазборEDS.словарь(з)
        func ф(_ имя: String) -> Bool { РазборEDS.есть(d[имя]) }
        подписатьДоговор = ф("sign_contract")
        подписатьАкт = ф("sign_act")
        реквизиты = ф("pay_to")
        выбратьДоставку = ф("ship_set")
        оплатитьДоставку = ф("ship_pay")
        вызватьКурьера = ф("ship_call")
        показатьКод = ф("handover")
        ввестиКод = ф("enter_code")
        кодКурьеру = ф("courier_code")
        кодПосылки = ф("parcel_code")
        отправитьПочтой = ф("post_send")
        отметитьОплату = ф("paid_mark")
        отменить = ф("cancel")
        сообщить = ф("report")
    }
}

/// Решение поддержки по спору (dispute.resolved).
struct РешениеEDS: Equatable {
    var итог = ""
    var когда = ""
    var заметка = ""
}

/// Спор (dispute).
struct СпорEDS: Equatable {
    var кто = ""
    var причина = ""
    var фото = 0
    var обращение = ""
    var решение: РешениеEDS? = nil
}

/// Запись протокола (events[]).
struct СобытиеEDS: Equatable, Identifiable {
    let id: Int
    var когда = ""
    var кто = ""
    var что = ""
    var место = false
}

// MARK: - Сделка

struct СделкаEDS: Equatable {
    let id: String
    var статус = ""
    /// "seller" | "buyer".
    var роль = ""
    var цена = 0
    var срок = ""
    var товарИд = ""
    var фото = ""
    var название = ""
    var имяПродавца = ""
    var телефонПродавца = ""
    var имяПокупателя = ""
    var телефонПокупателя = ""
    var договорПродавец: String? = nil
    var договорПокупатель: String? = nil
    var актПродавец: String? = nil
    var актПокупатель: String? = nil
    var можно = МожноEDS()
    var платаОплачена = false
    var платаМоя = 0
    var доставка: ДоставкаEDS? = nil
    var спор: СпорEDS? = nil
    var отменил = ""
    var причинаОтмены = ""
    var естьОтмена = false
    var документДоговора = ""
    var документАкта = ""
    var события: [СобытиеEDS] = []

    init?(_ j: [String: Any]) {
        typealias Р = РазборEDS
        let номер = Р.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        статус = Р.строка(j["status"])
        роль = Р.строка(j["role"])
        цена = Р.целое(j["price"])
        срок = Р.строка(j["expires_at"])
        let товар = Р.словарь(j["product"])
        товарИд = Р.строка(товар["id"])
        фото = Р.строка(товар["img"]).trimmingCharacters(in: .whitespaces)
        название = Р.строка(товар["title"])
        let продавец = Р.словарь(j["seller"])
        имяПродавца = Р.строка(продавец["name"])
        телефонПродавца = Р.строка(продавец["phone"])
        let покупатель = Р.словарь(j["buyer"])
        имяПокупателя = Р.строка(покупатель["name"])
        телефонПокупателя = Р.строка(покупатель["phone"])
        let договор = Р.словарь(j["contract"])
        договорПродавец = Р.подпись(договор["seller"])
        договорПокупатель = Р.подпись(договор["buyer"])
        let акт = Р.словарь(j["act"])
        актПродавец = Р.подпись(акт["seller"])
        актПокупатель = Р.подпись(акт["buyer"])
        можно = МожноEDS(j["can"])
        let плата = Р.словарь(j["fee"])
        платаОплачена = Р.есть(плата["paid"])
        платаМоя = Р.целое(плата["me"])
        if let д = j["ship"] as? [String: Any] { доставка = ДоставкаEDS(д) }
        if let с = j["dispute"] as? [String: Any] {
            var спор = СпорEDS(кто: Р.строка(с["by"]), причина: Р.строка(с["reason"]), фото: Р.целое(с["photos"]),
                               обращение: Р.строка(с["ticket"]))
            if let р = с["resolved"] as? [String: Any] {
                спор.решение = РешениеEDS(итог: Р.строка(р["outcome"]), когда: Р.строка(р["at"]),
                                          заметка: Р.строка(р["note"]))
            }
            self.спор = спор
        }
        if let о = j["cancel"] as? [String: Any] {
            естьОтмена = true
            отменил = Р.строка(о["by"])
            причинаОтмены = Р.строка(о["reason"])
        }
        let документы = Р.словарь(j["docs"])
        документДоговора = Р.строка(документы["contract"])
        документАкта = Р.строка(документы["act"])
        let сырые = (j["events"] as? [Any]) ?? []
        события = сырые.enumerated().compactMap { пара -> СобытиеEDS? in
            guard let e = пара.element as? [String: Any] else { return nil }
            return СобытиеEDS(id: пара.offset, когда: Р.строка(e["at"]), кто: Р.строка(e["who"]), что: Р.строка(e["what"]),
                              место: Р.есть(e["geo"]))
        }
    }

    var покупатель: Bool { роль == "buyer" }
    var продавец: Bool { роль == "seller" }
    /// (e.ship && e.ship.method) || "meet".
    var способ: String { доставка?.способ ?? "meet" }
    var встреча: Bool { способ == "meet" }
    /// Плата за подпись договора с меня: (fee && !fee.paid && +fee.me) || 0.
    var плата: Int { платаОплачена ? 0 : платаМоя }
    /// e.act[role].
    var мойАкт: String? { продавец ? актПродавец : актПокупатель }
    /// Вторая сторона (a): покупателю — продавец, продавцу — покупатель.
    var другаяИмя: String { покупатель ? имяПродавца : имяПокупателя }
    var другаяТелефон: String { покупатель ? телефонПродавца : телефонПокупателя }

    /// Шаг полосы: signing 0, signed/shipping 1, met/disputed 2, completed 3; прочее — полосы нет.
    var шаг: Int? {
        switch статус {
        case "signing": return 0
        case "signed", "shipping": return 1
        case "met", "disputed": return 2
        case "completed": return 3
        default: return nil
        }
    }

    /// Опрос раз в 5 с (_edsRender): встреча или доставка идут, либо акт ждёт подписи.
    var нуженОпрос: Bool {
        if статус == "signed" || статус == "shipping" { return true }
        guard статус == "met" else { return false }
        let ждёмМеня = мойАкт == nil
        let ждёмПродавца = способ == "courier" && актПродавец == nil
        return ждёмМеня || ждёмПродавца
    }

    /// _edsStateSig: смена этого перерисовывает окно; живые поля курьера — нет.
    var подписьСостояния: СделкаEDS {
        var копия = self
        копия.доставка = доставка?.безЖивого
        копия.события = []
        return копия
    }
}

/// Строка списка «Сделки с подписью eGov» (my).
struct КраткоEDS: Identifiable, Equatable {
    let id: String
    var статус = ""
    var способ = ""
    var фото = ""
    var название = ""
    var цена = 0
    var продавец = false

    init?(_ j: [String: Any]) {
        typealias Р = РазборEDS
        let номер = Р.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        статус = Р.строка(j["status"])
        способ = Р.строка(Р.словарь(j["ship"])["method"])
        let товар = Р.словарь(j["product"])
        фото = Р.строка(товар["img"]).trimmingCharacters(in: .whitespaces)
        название = Р.строка(товар["title"])
        цена = Р.целое(j["price"])
        продавец = Р.строка(j["role"]) == "seller"
    }
}

// MARK: - Статус (_edsSt)

enum ВидПлашкиEDS {
    case инфо
    case внимание
    case хорошо
    case плохо
    case нет
}

enum СтатусEDS {
    /// _edsSt(status, ship): вид плашки и текст. Не встреча — доставка (t у сайта).
    static func плашка(_ статус: String, способ: String) -> (вид: ВидПлашкиEDS, текст: String) {
        let доставка = !способ.isEmpty && способ != "meet"
        let т: (String) -> String = { EDSText.т($0) }
        switch статус {
        case "signing":   return (.инфо, т("eds_st_signing"))
        case "signed":    return (.внимание, т(доставка ? "eds_st_signed_ship" : "eds_st_signed"))
        case "shipping":  return (.инфо, т("eds_st_shipping"))
        case "met":       return (.внимание, т(доставка ? "eds_st_met_ship" : "eds_st_met"))
        case "completed": return (.хорошо, т("eds_st_completed"))
        case "disputed":  return (.плохо, т("eds_st_disputed"))
        case "cancelled": return (.нет, т("eds_st_cancelled"))
        case "expired":   return (.нет, т("eds_st_expired"))
        default:          return (.нет, статус)
        }
    }
}

// MARK: - Форматы

enum ФорматEDS {
    /// _edsMoney: целое ru-RU.
    static func деньги(_ n: Int) -> String { СделкиФормат.деньги(n) }

    /// «12 345 ₸».
    static func тенге(_ n: Int) -> String { СделкиФормат.деньги(n) + " ₸" }

    /// _edsWhen: «25 сент., 14:03». Строка ISO или число (секунды, миллисекунды) — как new Date(e) сайта.
    static func когда(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Double(t), n > 0 {
            let ф = DateFormatter()
            ф.locale = СделкиText.локаль
            ф.setLocalizedDateFormatFromTemplate("ddMMMHHmm")
            return ф.string(from: Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n))
        }
        return СделкиФормат.сВременем(t)
    }

    /// _edsPtFmt: Kaspi 11 цифр — «+7 777 123 45 67»; карта — группами по 4.
    static func реквизиты(_ тип: String, _ значение: String) -> String {
        let d = цифры(значение)
        if тип == "kaspi" && d.count == 11 {
            let м = Array(d)
            func ч(_ от: Int, _ до: Int) -> String { String(м[от..<до]) }
            let части: [String] = [ч(0, 1), ч(1, 4), ч(4, 7), ч(7, 9), ч(9, 11)]
            return "+" + части.joined(separator: " ")
        }
        if тип == "card" && d.count >= 16 { return группы(d) }
        return значение
    }

    /// _edsPtCopy: Kaspi — 10 цифр без семёрки; карта — цифры; прочее как есть.
    static func копия(_ тип: String, _ значение: String) -> String {
        let d = цифры(значение)
        if тип == "kaspi" && d.count == 11 { return String(d.dropFirst()) }
        if тип == "card" { return d }
        return значение
    }

    /// \D сайта: только ASCII-цифры.
    static func цифры(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.map { Character($0) })
    }

    /// «0000 0000 0000 0000».
    static func группы(_ d: String) -> String {
        var итог = ""
        for (i, c) in d.enumerated() {
            if i > 0 && i % 4 == 0 { итог.append(" ") }
            итог.append(c)
        }
        return итог
    }

    /// _edsCardMax: Visa, Mastercard, Мир — 16 цифр, прочие — до 19.
    static func длинаКарты(_ d: String) -> Int {
        guard let первая = d.first else { return 19 }
        return (первая == "4" || первая == "5" || первая == "2") ? 16 : 19
    }

    /// _edsLuhn.
    static func луна(_ d: String) -> Bool {
        guard !d.isEmpty else { return false }
        var сумма = 0
        var удвоить = false
        for c in d.reversed() {
            guard var n = c.wholeNumberValue else { return false }
            if удвоить {
                n *= 2
                if n > 9 { n -= 9 }
            }
            сумма += n
            удвоить.toggle()
        }
        return сумма % 10 == 0
    }

    /// _edsCardMask: цифры, не длиннее длины карты, группами по 4.
    static func маскаКарты(_ ввод: String) -> String {
        var d = цифры(ввод)
        d = String(d.prefix(длинаКарты(d)))
        return группы(d)
    }

    /// Ошибка у поля карты при вводе: номер полный, а Луна не сошлась.
    static func ошибкаКарты(_ ввод: String) -> String? {
        let d = String(цифры(ввод).prefix(длинаКарты(цифры(ввод))))
        if d.count == длинаКарты(d) && !луна(d) { return EDSText.т("eds_card_bad") }
        return nil
    }

    /**
     _edsPanFind: строки распознанного текста → номера карт. Строка 16–21 цифр — кандидат; две короткие строки подряд
     (≤10 цифр каждая), вместе 16–19, — тоже. Из кандидата — все отрезки 16–19 цифр, что начинаются с 2–6, не длиннее
     длины карты и проходят Луну.
     */
    static func номераКарт(_ строки: [String]) -> [String] {
        let чистые = строки.map { цифры($0) }.filter { $0.count >= 4 }
        var кандидаты: [String] = []
        for (i, s) in чистые.enumerated() {
            if s.count >= 16 && s.count <= 21 { кандидаты.append(s) }
            if i + 1 < чистые.count && s.count <= 10 && чистые[i + 1].count <= 10 {
                let вместе = s + чистые[i + 1]
                if вместе.count >= 16 && вместе.count <= 19 { кандидаты.append(вместе) }
            }
        }
        var итог: [String] = []
        for к in кандидаты {
            let м = Array(к)
            for длина in 16...19 {
                guard длина <= м.count else { break }
                for начало in 0...(м.count - длина) {
                    let отрезок = String(м[начало..<(начало + длина)])
                    guard let первая = отрезок.first, "23456".contains(первая) else { continue }
                    if длина <= длинаКарты(отрезок) && луна(отрезок) && !итог.contains(отрезок) {
                        итог.append(отрезок)
                    }
                }
            }
        }
        return итог
    }

    /// clocalEtaTxt: «вот-вот» (≤ 90 с), «через ~N мин · 14:05» или «к 15:30». сейчас — время сервера.
    static func эта(_ когда: Double, сейчас: Double) -> String {
        guard когда > 0 else { return "" }
        let осталось = когда - сейчас
        if осталось <= 90 { return EDSText.т("yac_eta_now") }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "HH:mm"
        let время = ф.string(from: Date(timeIntervalSince1970: когда))
        let минут = Int((осталось / 60).rounded())
        if минут < 60 {
            return EDSText.т("yac_eta_min", ["n": String(минут)]) + " · " + время
        }
        return EDSText.т("yac_eta_at", ["t": время])
    }
}

// MARK: - Модель окна

@MainActor
final class МодельСделкиEDS: ObservableObject {
    enum Загрузка: Equatable {
        case идёт
        case готово
        case ошибка(String)
        case нуженВход
        /// Ссылку QR (eds.php?action=go) не разобрали.
        case ссылкаНеВедёт
    }

    /// Код передачи на встрече (edsShowCode): код, ссылка для QR, когда истечёт, сколько минут действует.
    struct КодПередачи: Equatable {
        let код: String
        let ссылка: String
        let истекает: Date
        let минут: Int
    }

    /// Код для посылки (_edsParcelShow).
    struct КодПосылки: Equatable {
        let код: String
        let ссылка: String
    }

    /// Заказ курьера после расчёта (ship_set courier).
    struct ЗаказКурьера: Equatable {
        let q: String
        let точка: ТочкаEDS
        let адрес: String
        let дверь: ДверьEDS
    }

    /// Вопросы окна (cabConfirm сайта).
    enum Вопрос: Equatable {
        /// edsOpen с t: «Подтвердить встречу» / «Посылка у вас».
        case ссылка(посылка: Bool)
        /// _edsFeeShort: плата за подпись, нехватка, сколько предложить пополнить.
        case плата(плата: Int, нехватка: Int, пополнить: Int)
        /// edsShipPay / edsShipCall: short.
        case нехватка(текст: String)
        /// _edsShipCourier: цена курьера — «Выбрать курьера».
        case курьер(текст: String, заказ: ЗаказКурьера)
        /// edsCourierCode.
        case кодКурьеру(String)
        /// edsPaidMark.
        case оплачено
        /// edsCourierCall: подменный номер курьера.
        case звонок(номер: String, добавочный: String, минут: Int, ttl: Bool)
    }

    /// Листы окна.
    enum Лист: String, Identifiable {
        case пополнение
        case карта
        case отмена
        case проблема
        case сканер

        var id: String { rawValue }
    }

    @Published private(set) var id: String
    @Published private(set) var сделка: СделкаEDS? = nil
    @Published private(set) var загрузка: Загрузка = .идёт
    /// Ключ нажатой кнопки, пока идёт её запрос (_edsBusy): «…» на ней, остальные ждут.
    @Published private(set) var идёт: String? = nil
    @Published var тост: String? = nil
    @Published var вопрос: Вопрос? = nil
    @Published var лист: Лист? = nil
    @Published private(set) var кодПередачи: КодПередачи? = nil
    @Published private(set) var кодПосылки: КодПосылки? = nil
    /// Номер обращения, открытого поверх (edsTicket → openTicket).
    @Published var обращение: String? = nil

    // Поля окна (значения id полей сайта).
    /// #eds-code.
    @Published var кодВвод = ""
    /// #eds-geo: записать место встречи в протокол.
    @Published var гео = true
    /// #eds-pt-type и поля реквизитов.
    @Published var типРеквизитов = "kaspi"
    @Published var kaspi = ""
    @Published var карта = "" {
        didSet {
            let маска = ФорматEDS.маскаКарты(карта)
            if маска != карта { карта = маска }
            ошибкаКарты = ФорматEDS.ошибкаКарты(маска)
        }
    }
    @Published var счёт = ""
    @Published var ошибкаКарты: String? = nil
    /// Форма реквизитов раскрыта (edsPayToEdit); реквизитов ещё нет — раскрыта всегда.
    @Published var правимРеквизиты = false
    /// #eds-pk-addr, #eds-pk-flat.
    @Published var заборАдрес = ""
    @Published var заборДверь = ""
    /// #eds-po-car, #eds-po-name, #eds-po-track.
    @Published var перевозчик = "kazpost"
    @Published var названиеПеревозчика = ""
    @Published var трек = ""

    /// t из ссылки: покупателю — вопрос о встрече/посылке после первой загрузки.
    private var токен: String
    private let переход: Bool
    private var первыйРаз = true
    private var опрос: Task<Void, Never>? = nil
    private var задачаТоста: Task<Void, Never>? = nil
    /// Сдвиг часов сервера (_edsSkew): now сервера минус свои часы, секунды.
    private(set) var сдвиг: Double = 0
    /// Пополнение кошелька (_edsFeeShort, showTopup): модель листа и подписка на её итог.
    private(set) var пополнение: ПополнениеМодель? = nil
    private var пополнено = false
    private var подписки: Set<AnyCancellable> = []

    init(id: String, токен: String) {
        self.id = id
        self.токен = токен
        self.переход = false
    }

    /// Ссылка QR: номер сделки узнаём у сервера.
    init(переход токен: String) {
        self.id = ""
        self.токен = токен
        self.переход = true
    }

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    /// Время сервера, секунды (clcSrvNow).
    var сейчасСервера: Double { Date().timeIntervalSince1970 + сдвиг }

    // MARK: - Появление и опрос

    func появилась() async {
        if первыйРаз {
            первыйРаз = false
            await начать()
        }
        запуститьОпрос()
    }

    func исчезла() {
        опрос?.cancel()
        опрос = nil
    }

    /// Окно снова на экране (после сканера во весь экран): опрос дальше.
    func продолжить() {
        guard !первыйРаз, опрос == nil else { return }
        запуститьОпрос()
    }

    /// Лист окна закрылся (свайпом или кнопкой): после пополнения — сделка заново.
    func листЗакрыт() {
        if пополнение != nil { пополнениеЗакрыто() }
    }

    private func начать() async {
        if переход {
            guard let найдено = await EDSAPI.разобратьПереход(токен) else {
                загрузка = .ссылкаНеВедёт
                return
            }
            id = найдено.id
            токен = найдено.токен
        }
        await загрузить()
        guard let с = сделка, !токен.isEmpty, с.покупатель, с.можно.ввестиКод else { return }
        вопрос = .ссылка(посылка: !с.встреча)
    }

    /// edsOpen / _edsReload: сделка заново.
    func загрузить() async {
        guard !id.isEmpty else { return }
        if сделка == nil { загрузка = .идёт }
        do {
            guard let j = try await EDSAPI.сделка(id) else { throw КабинетСайта.Сбой.приложение }
            if РазборEDS.да(j["ok"]), let d = j["deal"] as? [String: Any], let новая = СделкаEDS(d) {
                принять(новая, ответ: j)
                загрузка = .готово
                return
            }
            if МоиОбъявленияAPI.нетСессии(j) {
                if сделка == nil { загрузка = .нуженВход }
                return
            }
            let сообщение = РазборEDS.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if сделка == nil {
                загрузка = .ошибка(сообщение.isEmpty ? т("eds_not_found") : сообщение)
            }
        } catch {
            if сделка == nil {
                загрузка = .ошибка(т((error as? КабинетСайта.Сбой) == .сеть ? "no_conn" : "eds_not_found"))
            } else {
                показать(т("no_conn"))
            }
        }
    }

    private func принять(_ новая: СделкаEDS, ответ j: [String: Any]) {
        let сейчас = РазборEDS.число(j["now"])
        if сейчас > 0 { сдвиг = сейчас - Date().timeIntervalSince1970 }
        let прежняя = сделка
        сделка = новая
        if прежняя == nil || прежняя?.доставка?.реквизиты.тип != новая.доставка?.реквизиты.тип {
            let тип = новая.доставка?.реквизиты.тип ?? ""
            типРеквизитов = ["kaspi", "card", "account"].contains(тип) ? тип : "kaspi"
        }
        if заборАдрес.isEmpty, let адрес = новая.доставка?.заборАдрес, !адрес.isEmpty { заборАдрес = адрес }
        if новая.доставка?.реквизиты.есть != true { правимРеквизиты = false }
    }

    /// _edsPoll: раз в 5 с (при коде передачи — раз в 3 с), пока окно на экране и приложение активно.
    private func запуститьОпрос() {
        опрос?.cancel()
        опрос = Task { [weak self] in
            while !Task.isCancelled {
                let пауза: UInt64 = (self?.кодПередачи != nil) ? 3_000_000_000 : 5_000_000_000
                try? await Task.sleep(nanoseconds: пауза)
                guard !Task.isCancelled, let модель = self else { return }
                await модель.тихо()
            }
        }
    }

    /// _edsQuiet и опрос у кода передачи.
    private func тихо() async {
        guard UIApplication.shared.applicationState == .active, идёт == nil, лист == nil, вопрос == nil,
              кодПосылки == nil, let прежняя = сделка else { return }
        if let код = кодПередачи {
            guard код.истекает > Date() else { return }
        } else if !прежняя.нуженОпрос {
            return
        }
        guard let j = try? await EDSAPI.сделкаВФоне(id), РазборEDS.да(j["ok"]),
              let d = j["deal"] as? [String: Any], let новая = СделкаEDS(d), новая.id == id else { return }
        if кодПередачи != nil {
            guard новая.статус != "signed" else { return }
            кодПередачи = nil
            принять(новая, ответ: j)
            показать(т("eds_meet_ok_seller"))
            return
        }
        guard новая != прежняя else { return }
        let смена = новая.подписьСостояния != прежняя.подписьСостояния
        принять(новая, ответ: j)
        if смена && новая.статус == "met" && новая.продавец && прежняя.статус != "met" {
            показать(т("eds_meet_ok_seller"))
        }
    }

    // MARK: - Тост и занятость

    func показать(_ текст: String, секунд: Double = 2.6) {
        тост = текст
        задачаТоста?.cancel()
        задачаТоста = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(секунд * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.тост = nil
        }
    }

    /// Текст ответа сервера или «Не получилось».
    private func ошибка(_ j: [String: Any]) -> String {
        let m = РазборEDS.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        let e = РазборEDS.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if e == "auth" { return т("login_t") }
        if !e.isEmpty && !КабинетСайта.машинныйКод(e) { return e }
        return т("app_err")
    }

    /// Одно нажатие за раз: ключ кнопки занят, пока идёт её запрос.
    private func занять(_ ключ: String) -> Bool {
        guard идёт == nil, сделка != nil else { return false }
        идёт = ключ
        return true
    }

    private func освободить() { идёт = nil }

    // MARK: - Подпись договора и акта (edsSign)

    func подписать(_ документ: String) {
        guard let с = сделка else { return }
        /* Плата за подпись идёт с баланса кошелька — денежное нажатие. */
        if документ == "contract" && с.плата > 0 && !Config.деньгиСделок {
            БезСайта.сообщить(заголовок: БезСайтаText.т("deal_t"), текст: БезСайтаText.т("deal_s"))
            return
        }
        guard занять("sign_" + документ) else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправитьОдинРаз("sign", id: с.id, тело: ["doc": документ])
                if РазборEDS.да(j["ok"]) {
                    let ключ: String
                    if РазборEDS.строка(j["status"]) == "completed" {
                        ключ = "eds_done_t"
                    } else if РазборEDS.да(j["both"]) {
                        ключ = "eds_signed_both"
                    } else {
                        ключ = "eds_signed_you"
                    }
                    показать(т(ключ))
                    await загрузить()
                    return
                }
                if РазборEDS.строка(j["error"]) == "fee_short" {
                    let нехватка = max(РазборEDS.целое(j["short"]), 1)
                    let пополнить = max(500, 100 * Int((Double(нехватка) / 100).rounded(.up)))
                    вопрос = .плата(плата: РазборEDS.целое(j["fee"]), нехватка: нехватка, пополнить: пополнить)
                    return
                }
                if РазборEDS.есть(j["need_otp"]) {
                    let акт = документ == "act"
                    ПотокEgov.шаг(назначение: РазборEDS.строка(j["purpose"]), ссылка: РазборEDS.строка(j["ref"]),
                                  заголовок: т(акт ? "eds_otp_act_t" : "eds_otp_contract_t"),
                                  подсказка: т(акт ? "eds_otp_act_h" : "eds_otp_contract_h"),
                                  готово: { [weak self] in self?.подписать(документ) })
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    ВходПоверх.показать(готово: { [weak self] in Task { await self?.загрузить() } })
                    return
                }
                показать(ошибка(j))
                await загрузить()
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    // MARK: - Пополнение кошелька (_edsFeeShort, showTopup)

    /// Лист «Пополнить кошелёк» поверх окна сделки; сумма — своя сумма листа (topupCustom), 0 — без суммы.
    func пополнить(_ сумма: Int) {
        guard Config.деньгиКошелька else {
            БезСайта.сообщить(заголовок: БезСайтаText.т("deal_t"), текст: БезСайтаText.т("deal_s"))
            return
        }
        let модель = ПополнениеМодель()
        if сумма > 0 { модель.своя = String(сумма) }
        подписки.removeAll()
        пополнено = false
        модель.$итог
            .sink { [weak self] итог in
                if case .пополнен? = итог { self?.пополнено = true }
            }
            .store(in: &подписки)
        пополнение = модель
        лист = .пополнение
    }

    /// Лист пополнения закрылся: сделка заново; пополнили — «Баланс пополнен — подпишите договор».
    func пополнениеЗакрыто() {
        let было = пополнено
        пополнено = false
        подписки.removeAll()
        пополнение = nil
        if было { показать(т("eds_fee_back_sign")) }
        Task { await загрузить() }
    }

    // MARK: - Встреча: код передачи (edsShowCode, edsEnterCode, _edsEnter)

    func показатьКод() {
        guard let с = сделка, занять("show_code") else { return }
        let сГео = гео
        Task {
            defer { освободить() }
            var тело: [String: Any] = [:]
            if сГео, let место = await ГеоEDS.одноМесто() { тело["geo"] = место }
            do {
                let j = try await EDSAPI.отправить("handover_start", id: с.id, тело: тело)
                if РазборEDS.да(j["ok"]) {
                    let секунд = РазборEDS.число(j["exp_in"])
                    let срок = секунд > 0 ? секунд : 600
                    let ссылка = СделкиEDS.абсолютная(РазборEDS.строка(j["link"]))
                    кодПередачи = КодПередачи(код: РазборEDS.строка(j["code"]), ссылка: ссылка,
                                               истекает: Date().addingTimeInterval(срок),
                                               минут: max(1, Int((срок / 60).rounded())))
                    запуститьОпрос()
                    return
                }
                показать(ошибка(j))
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// «Назад к сделке» (_edsReload из окна кода).
    func закрытьКод() {
        кодПередачи = nil
        кодПосылки = nil
        запуститьОпрос()
        Task { await загрузить() }
    }

    /// edsEnterCode: 6 цифр из поля.
    func ввестиКод() {
        let код = ФорматEDS.цифры(кодВвод)
        guard код.count == 6 else {
            показать(т("eds_code_need"))
            return
        }
        войти(код, поСсылке: false)
    }

    /// _edsEnter: handover_enter {code} или {token}; место — если флажок есть на экране и включён.
    func войти(_ значение: String, поСсылке: Bool) {
        guard let с = сделка, занять("enter") else { return }
        let сГео = гео && с.статус == "signed" && с.встреча
        Task {
            defer { освободить() }
            var тело: [String: Any] = поСсылке ? ["token": значение] : ["code": значение]
            if сГео, let место = await ГеоEDS.одноМесто() { тело["geo"] = место }
            do {
                let j = try await EDSAPI.отправить("handover_enter", id: с.id, тело: тело)
                if РазборEDS.да(j["ok"]) {
                    кодВвод = ""
                    показать(т("eds_meet_ok"))
                    await загрузить()
                    return
                }
                показать(ошибка(j))
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// Ответ на вопрос ссылки (edsOpen с t).
    func подтвердитьПоСсылке() {
        guard !токен.isEmpty else { return }
        войти(токен, поСсылке: true)
    }

    // MARK: - Способ передачи (edsShipPick, _edsShipCourier)

    func выбратьСпособ(_ способ: String) {
        guard let с = сделка else { return }
        if способ == "courier" {
            лист = .карта
            return
        }
        guard занять("ship_" + способ) else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("ship_set", id: с.id, тело: ["ship": способ])
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_ship_saved"))
                    await загрузить()
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// Точка покупателя из окна карты (hovAddrOpen «to»): расчёт курьера и вопрос с ценой.
    func точкаКурьера(адрес: String, точка: ТочкаEDS?, дверь: ДверьEDS) {
        guard let с = сделка else { return }
        guard let точка else {
            показать(т("eds_ship_need_pt"))
            return
        }
        guard занять("ship_courier") else { return }
        Task {
            defer { освободить() }
            do {
                let ответ = try await EDSAPI.расчётКурьера(товар: с.товарИд, точка: точка, уПодъезда: дверь.уПодъезда,
                                                          адрес: адрес)
                let j = ответ ?? [:]
                let q = РазборEDS.строка(j["q"])
                if РазборEDS.да(j["ok"]) && !q.isEmpty {
                    let бесплатно = РазборEDS.есть(j["free"])
                    let первая = бесплатно
                        ? т("eds_ship_q_free", ["a": адрес])
                        : т("eds_ship_q", ["a": адрес, "f": ФорматEDS.тенге(РазборEDS.целое(j["price"]))])
                    вопрос = .курьер(текст: первая + " " + т("eds_ship_q2"),
                                     заказ: ЗаказКурьера(q: q, точка: точка, адрес: адрес, дверь: дверь))
                    return
                }
                let причина = РазборEDS.строка(j["reason"])
                let ключ: String
                if причина == "intercity" || РазборEDS.строка(j["mode"]) == "carriers" {
                    ключ = "eds_ship_intercity"
                } else if причина == "no_from" {
                    ключ = "eds_ship_no_from"
                } else if причина == "no_courier" {
                    ключ = "eds_ship_bulky"
                } else if причина == "slow_down" {
                    ключ = "eds_ship_slow"
                } else {
                    ключ = "eds_ship_na"
                }
                показать(т(ключ))
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// «Выбрать курьера»: ship_set {ship:"courier", q, lat, lon, addr, door}.
    func выбратьКурьера(_ заказ: ЗаказКурьера) {
        guard let с = сделка, занять("ship_courier") else { return }
        Task {
            defer { освободить() }
            let тело: [String: Any] = ["ship": "courier", "q": заказ.q, "lat": заказ.точка.широта,
                                       "lon": заказ.точка.долгота, "addr": заказ.адрес, "door": заказ.дверь.значение]
            do {
                let j = try await EDSAPI.отправить("ship_set", id: с.id, тело: тело)
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_ship_saved"))
                    await загрузить()
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    // MARK: - Реквизиты продавца (edsPayToSave)

    func сохранитьРеквизиты() {
        guard let с = сделка else { return }
        let тип = типРеквизитов
        var значение = ""
        switch тип {
        case "card":
            let d = ФорматEDS.цифры(карта)
            if d.count < 16 {
                ошибкаКарты = т("eds_card_short")
                return
            }
            if !ФорматEDS.луна(d) {
                ошибкаКарты = т("eds_card_bad")
                return
            }
            значение = d
        case "account":
            значение = счёт.trimmingCharacters(in: .whitespacesAndNewlines)
            if значение.count < 10 {
                показать(т("eds_payto_need"))
                return
            }
        default:
            if let текст = НомерКЗ.ошибка(kaspi) {
                показать(текст)
                return
            }
            значение = kaspi
            if ФорматEDS.цифры(значение).count < 11 {
                показать(т("eds_payto_need"))
                return
            }
        }
        guard занять("pay_to") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("pay_to", id: с.id, тело: ["type": тип, "value": значение])
                if РазборEDS.да(j["ok"]) {
                    правимРеквизиты = false
                    показать(т("eds_payto_ok"))
                    await загрузить()
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// edsPayToCopy.
    func скопироватьРеквизиты() {
        guard let р = сделка?.доставка?.реквизиты, р.открыты else { return }
        UIPasteboard.general.string = ФорматEDS.копия(р.тип, р.значение)
        показать(т("copied_value"))
    }

    /// Номер карты со сканера (_edsScanDone).
    func картаСоСканера(_ номер: String) {
        типРеквизитов = "card"
        карта = номер
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        показать(т("eds_scan_ok"))
    }

    // MARK: - Курьер (edsShipPay, edsShipCall, edsCourierCode, edsCourierCall)

    func оплатитьДоставку() {
        guard let с = сделка else { return }
        guard Config.деньгиСделок else {
            БезСайта.сообщить(заголовок: БезСайтаText.т("deal_t"), текст: БезСайтаText.т("deal_s"))
            return
        }
        guard занять("ship_pay") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправитьОдинРаз("ship_pay", id: с.id)
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_ship_paid_t"))
                    await загрузить()
                    return
                }
                if РазборEDS.строка(j["error"]) == "short" {
                    вопрос = .нехватка(текст: т("eds_short", ["n": ФорматEDS.деньги(РазборEDS.целое(j["short"]))]))
                    return
                }
                показать(ошибка(j))
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    func вызватьКурьера() {
        guard let с = сделка else { return }
        let адрес = заборАдрес.trimmingCharacters(in: .whitespacesAndNewlines)
        let дверь = заборДверь.trimmingCharacters(in: .whitespacesAndNewlines)
        guard адрес.count >= 5 else {
            показать(т("eds_ship_pickup_need"))
            return
        }
        guard Config.деньгиСделок else {
            БезСайта.сообщить(заголовок: БезСайтаText.т("deal_t"), текст: БезСайтаText.т("deal_s"))
            return
        }
        guard занять("ship_call") else { return }
        Task {
            defer { освободить() }
            let двериЗначение: [String: Any] = дверь.isEmpty ? [:] : ["flat": String(дверь.prefix(40))]
            let тело: [String: Any] = ["addr": String(адрес.prefix(300)), "door": двериЗначение]
            do {
                let j = try await EDSAPI.отправитьОдинРаз("ship_call", id: с.id, тело: тело)
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_ship_called"))
                    if let посылка = j["parcel"] as? [String: Any] {
                        показатьПосылку(код: РазборEDS.строка(посылка["code"]), токен: РазборEDS.строка(посылка["token"]))
                    } else {
                        await загрузить()
                    }
                    return
                }
                if РазборEDS.строка(j["error"]) == "short" {
                    вопрос = .нехватка(текст: т("eds_short_s", ["n": ФорматEDS.деньги(РазборEDS.целое(j["short"]))]))
                    return
                }
                показать(ошибка(j), секунд: 5)
                await загрузить()
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    func кодКурьеру() {
        guard let с = сделка, занять("courier_code") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("courier_code", id: с.id)
                if РазборEDS.да(j["ok"]) {
                    вопрос = .кодКурьеру(РазборEDS.строка(j["code"]))
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    func позвонитьКурьеру() {
        guard let с = сделка, занять("courier_phone") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("courier_phone", id: с.id)
                if РазборEDS.да(j["ok"]) {
                    let ttl = РазборEDS.число(j["ttl"])
                    вопрос = .звонок(номер: РазборEDS.строка(j["phone"]),
                                     добавочный: ФорматEDS.цифры(РазборEDS.строка(j["ext"])),
                                     минут: max(1, Int((ttl / 60).rounded())), ttl: ttl > 0)
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// tel: подменного номера с добавочным через запятую.
    func набрать(_ номер: String, добавочный: String) {
        let чистый = номер.filter { $0 == "+" || ($0.isASCII && $0.isNumber) }
        guard !чистый.isEmpty else { return }
        var строка = "tel:" + чистый
        if !добавочный.isEmpty { строка += "," + добавочный }
        guard let адрес = URL(string: строка) else { return }
        UIApplication.shared.open(адрес)
    }

    // MARK: - Почта и код посылки (edsPostSend, edsParcelCode, _edsParcelShow)

    func отправитьПочтой() {
        guard let с = сделка else { return }
        let номер = трек.trimmingCharacters(in: .whitespacesAndNewlines)
        guard номер.count >= 5 else {
            показать(т("eds_post_track_need"))
            return
        }
        guard занять("post_send") else { return }
        let тело: [String: Any] = ["carrier": перевозчик,
                                   "name": названиеПеревозчика.trimmingCharacters(in: .whitespacesAndNewlines),
                                   "track": номер]
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("post_send", id: с.id, тело: тело)
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_post_saved"))
                    if let посылка = j["parcel"] as? [String: Any] {
                        показатьПосылку(код: РазборEDS.строка(посылка["code"]), токен: РазборEDS.строка(посылка["token"]))
                    } else {
                        await загрузить()
                    }
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    func кодПосылкиПоказать() {
        guard let с = сделка, занять("parcel_code") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("parcel_code", id: с.id)
                if РазборEDS.да(j["ok"]) {
                    показатьПосылку(код: РазборEDS.строка(j["code"]), токен: РазборEDS.строка(j["token"]))
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    private func показатьПосылку(код: String, токен: String) {
        кодПосылки = КодПосылки(код: код, ссылка: СделкиEDS.ссылкаПосылки(токен))
    }

    // MARK: - Оплата после получения (edsPaidMark)

    func отметитьОплату() {
        guard let с = сделка, занять("paid_mark") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("paid_mark", id: с.id)
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_paid_t"))
                    await загрузить()
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    // MARK: - Отмена, проблема, фото спора

    /// _edsCancelGo: при отмене сервер возвращает плату и доставку — ровно один раз.
    func отменить(_ причина: String) {
        guard let с = сделка, занять("cancel") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправитьОдинРаз("cancel", id: с.id, тело: ["reason": причина])
                показать(РазборEDS.да(j["ok"]) ? т("eds_cancelled_t") : ошибка(j))
                await загрузить()
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// _edsReportGo.
    func сообщить(_ причина: String) {
        guard let с = сделка else { return }
        guard !причина.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            показать(т("eds_report_need"))
            return
        }
        guard занять("report") else { return }
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("report", id: с.id, тело: ["reason": причина])
                показать(РазборEDS.да(j["ok"]) ? т("eds_report_done2") : ошибка(j), секунд: 3.5)
                await загрузить()
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// edsDisputePhoto: снимок не больше 1600 по большей стороне, JPEG 0,85, dataURL.
    func фотоСпора(_ данные: Data) {
        guard let с = сделка else { return }
        guard let картинка = UIImage(data: данные) else {
            показать(т("eds_disp_photo_bad"))
            return
        }
        guard занять("dispute_photo") else { return }
        let готовая = ФотоEDS.уменьшить(картинка, до: 1600)
        guard let jpeg = готовая.jpegData(compressionQuality: 0.85) else {
            освободить()
            показать(т("eds_disp_photo_bad"))
            return
        }
        let адрес = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        Task {
            defer { освободить() }
            do {
                let j = try await EDSAPI.отправить("dispute_photo", id: с.id, тело: ["img": адрес])
                if РазборEDS.да(j["ok"]) {
                    показать(т("eds_disp_photo_ok"))
                    await загрузить()
                } else {
                    показать(ошибка(j))
                }
            } catch {
                показать(т("no_conn"))
            }
        }
    }

    /// edsTicket: обращение по спору — переписка поверх окна.
    func открытьОбращение() {
        guard let номер = сделка?.спор?.обращение, !номер.isEmpty else {
            показать(т("app_err"))
            return
        }
        обращение = номер
    }

    /// Документ сделки (docs.contract | docs.act) — своё окно PDF, не страница сайта.
    func открытьДокумент(_ адрес: String, заголовок: String) {
        let чистый = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty, чистый != "#" else { return }
        var путь = чистый
        if let url = URL(string: чистый), url.scheme != nil {
            guard Config.deepLink(url) != nil,
                  let части = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                БезСайта.внешняя(url)
                return
            }
            путь = части.percentEncodedPath + (части.percentEncodedQuery.map { "?" + $0 } ?? "")
        }
        if !путь.hasPrefix("/") { путь = "/" + путь }
        ОкнаДокументов.показать(ДокументКабинета(заголовок: заголовок, источник: .путь(путь)))
    }

    /// Вход: после него сделка заново.
    func войтиВКабинет() {
        ВходПоверх.показать(готово: { [weak self] in
            Task { await self?.загрузить() }
        })
    }
}

// MARK: - Снимок для спора

enum ФотоEDS {
    /// Уменьшить так, чтобы большая сторона была не больше предела (как canvas сайта).
    static func уменьшить(_ картинка: UIImage, до предел: CGFloat) -> UIImage {
        let размер = картинка.size
        let большая = max(размер.width, размер.height, 1)
        let доля = min(1, предел / большая)
        let новый = CGSize(width: max(1, (размер.width * доля).rounded()), height: max(1, (размер.height * доля).rounded()))
        let формат = UIGraphicsImageRendererFormat.default()
        формат.scale = 1
        формат.opaque = true
        return UIGraphicsImageRenderer(size: новый, format: формат).image { _ in
            картинка.draw(in: CGRect(origin: .zero, size: новый))
        }
    }
}
