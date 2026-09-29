import Foundation
import SwiftUI
import UIKit

/**
 СДЕЛКИ С ПОДПИСЬЮ eGov (БЕЗ ГАРАНТА) — ЗАПРОСЫ И ССЫЛКИ (владелец: «на сайт не прыгать, всё своими экранами»).

 Всё — как у модуля сайта js/cabinet-eds.min.js (edsOpen, _edsReload, _edsPost, edsListInject). APP_BASE кабинета
 пустой, поэтому пути от корня, без /kz/<язык>/:
   · GET  /eds.php?action=deal&id=<id>          → {ok, deal, now} | {ok:false, msg};
   · GET  /eds.php?action=my&role=<seller|buyer> → {ok, deals[]} — блок «Сделки с подписью eGov» в «Моих сделках»;
   · POST /eds.php?action=<действие>            — JSON {csrf, id, …} (_edsPost): sign, handover_start, handover_enter,
     ship_set, ship_pay, ship_call, courier_code, courier_phone, parcel_code, post_send, pay_to, paid_mark, cancel,
     report, dispute_photo;
   · GET  /api/ship_quote.php?item=&lat=&lon=[&dd=out]&a= — цена курьера Яндекса перед выбором доставки.
 Транспорт — тот же, что у «Моих сделок» (СделкиAPI → КабинетСайта.вызвать, токен страницы кабинета). То, за чем
 деньги (подпись с платой с баланса, оплата и вызов курьера, отмена с возвратом платы), — ДеньгиСделкиAPI.отправитьОдинРаз:
 ровно один раз, без повторов.

 Ссылки, которые ведут в сделку (ПереходыКабинета.своимЭкраном — раньше NativeRouter):
   · /cabinet.php?eds=<id>[&t=<токен>] — mkEdsShow и create сайта, пуш; у сайта showDeals() и edsOpen(id, t);
   · /eds.php?action=go&t=<токен>       — QR кода посылки или встречи. Сервер отвечает переходом на
     /cabinet.php?eds=<id>&t=<токен>; номер сделки берём из этого ответа (адрес печатается в LANG_OPTS страницы).
 Своё окно сделки встаёт поверх всего (ПоверхВсего), под ним — «Мои сделки», как showDeals() сайта.
 */
@MainActor
enum EDSAPI {

    /// Путь сделки: /eds.php?action=deal&id=<id>.
    static func путьСделки(_ id: String) -> String {
        "/eds.php?action=deal&id=" + вАдрес(id)
    }

    /// GET сделки (edsOpen, _edsReload). nil — ответ не JSON.
    static func сделка(_ id: String) async throws -> [String: Any]? {
        try await СделкиAPI.получить(путьСделки(id), отКорня: true)
    }

    /// Тихий опрос (_edsQuiet): не ждёт страницу сайта и не уводит её (шлюз банка, eGov).
    static func сделкаВФоне(_ id: String) async throws -> [String: Any]? {
        try await КабинетСайта.вызвать(путьСделки(id), отКорня: true, ждать: false).json
    }

    /// edsListInject: сделки роли вкладки.
    static func мои(_ роль: String) async throws -> [String: Any]? {
        try await СделкиAPI.получить("/eds.php?action=my&role=" + вАдрес(роль), отКорня: true)
    }

    /// _edsPost без денег: {csrf, id, …}; «csrf» — свежий токен и один повтор (СделкиAPI.отправить).
    static func отправить(_ действие: String, id: String, тело: [String: Any] = [:]) async throws -> [String: Any] {
        var полное = тело
        if полное["id"] == nil { полное["id"] = id }
        return try await СделкиAPI.отправить("/eds.php?action=" + действие, тело: полное, отКорня: true)
    }

    /// _edsPost, за которым деньги (плата за подпись, доставка, возврат при отмене): ровно один раз.
    static func отправитьОдинРаз(_ действие: String, id: String, тело: [String: Any] = [:]) async throws -> [String: Any] {
        var полное = тело
        if полное["id"] == nil { полное["id"] = id }
        return try await ДеньгиСделкиAPI.отправитьОдинРаз("/eds.php?action=" + действие, тело: полное, отКорня: true)
    }

    /// _edsShipCourier: цена курьера Яндекса до точки покупателя (hovAddrOpen → ship_quote).
    static func расчётКурьера(товар: String, точка: ТочкаEDS, уПодъезда: Bool, адрес: String) async throws -> [String: Any]? {
        var хвост = "/api/ship_quote.php?item=" + вАдрес(товар)
        хвост += "&lat=" + String(точка.широта) + "&lon=" + String(точка.долгота)
        if уПодъезда { хвост += "&dd=out" }
        хвост += "&a=" + вАдрес(адрес)
        return try await СделкиAPI.получить(хвост, отКорня: true)
    }

    /**
     /eds.php?action=go&t=<токен> → номер сделки и токен. Сервер ведёт на /cabinet.php?eds=<id>&t=<токен>; fetch идёт
     следом за переходом и отдаёт страницу кабинета, а та печатает свой адрес в LANG_OPTS (и ссылках языков) — оттуда
     и берём eds. Ответ JSON с id — тоже годится. nil — не узнали (нет сессии, токен истёк).
     */
    static func разобратьПереход(_ токен: String) async -> (id: String, токен: String)? {
        guard let ответ = try? await КабинетСайта.вызвать("/eds.php?action=go&t=" + вАдрес(токен), отКорня: true) else {
            return nil
        }
        if let j = ответ.json {
            let вложенная = j["deal"] as? [String: Any]
            let номер = [СделкиAPI.строка(j["id"]), СделкиAPI.строка(j["eds"]), СделкиAPI.строка(вложенная?["id"])]
                .first(where: { годныйНомер($0) }) ?? ""
            if !номер.isEmpty {
                let т = СделкиAPI.строка(j["t"])
                return (номер, т.isEmpty ? токен : т)
            }
            let адрес = СделкиAPI.строка(j["url"])
            if let найдено = изАдресов(адрес) { return (найдено.id, найдено.токен.isEmpty ? токен : найдено.токен) }
        }
        guard let найдено = изАдресов(ответ.текст) else { return nil }
        return (найдено.id, найдено.токен.isEmpty ? токен : найдено.токен)
    }

    /// Первый адрес кабинета с eds= в тексте (разметка страницы или JSON): номер и t.
    nonisolated static func изАдресов(_ текст: String) -> (id: String, токен: String)? {
        guard !текст.isEmpty,
              let выражение = try? NSRegularExpression(pattern: "cabinet(?:\\.php)?\\?([^\"'\\s<>]{1,600})") else { return nil }
        let весь = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        for совпадение in выражение.matches(in: текст, range: весь) {
            guard let r = Range(совпадение.range(at: 1), in: текст) else { continue }
            var запрос = String(текст[r])
            запрос = запрос.replacingOccurrences(of: "\\u0026", with: "&")
            запрос = запрос.replacingOccurrences(of: "&amp;", with: "&")
            запрос = запрос.replacingOccurrences(of: "\\/", with: "/")
            if let решётка = запрос.firstIndex(of: "#") { запрос = String(запрос[..<решётка]) }
            let параметры = разобратьЗапрос(запрос)
            let номер = (параметры["eds"] ?? "").trimmingCharacters(in: .whitespaces)
            guard годныйНомер(номер) else { continue }
            let т = (параметры["t"] ?? "").trimmingCharacters(in: .whitespaces)
            return (номер, годныйТокен(т) ? т : "")
        }
        return nil
    }

    /// «a=1&b=2» → [a: 1, b: 2] без URLComponents (у него падение на кривом %XX): первое значение имени.
    nonisolated private static func разобратьЗапрос(_ запрос: String) -> [String: String] {
        var итог: [String: String] = [:]
        for пара in запрос.split(separator: "&", omittingEmptySubsequences: true) {
            let части = пара.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let имяСырое = части.first else { continue }
            let имя = String(имяСырое).removingPercentEncoding ?? String(имяСырое)
            let сырое = части.count > 1 ? String(части[1]).replacingOccurrences(of: "+", with: " ") : ""
            let значение = сырое.removingPercentEncoding ?? сырое
            if итог[имя] == nil { итог[имя] = значение }
        }
        return итог
    }

    // MARK: - Проверки и кодирование

    /// Номер сделки из ссылки: буквы, цифры, дефис, подчёркивание (как ?deal=).
    nonisolated static func годныйНомер(_ номер: String) -> Bool {
        номер.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    /// Токен ссылки (t=): буквы, цифры и . _ - ; пусто — годится (ссылки без токена).
    nonisolated static func годныйТокен(_ токен: String) -> Bool {
        токен.isEmpty || токен.range(of: "^[A-Za-z0-9_.-]{1,256}$", options: .regularExpression) != nil
    }

    /// encodeURIComponent сайта: всё, кроме A–Z a–z 0–9 - _ . ! ~ * ' ( ).
    nonisolated static func вАдрес(_ значение: String) -> String {
        let можно = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return значение.addingPercentEncoding(withAllowedCharacters: можно) ?? ""
    }
}

// MARK: - Вход в сделку по ссылке

/// Уведомление: окно сделки с подписью eGov закрыли — «Мои сделки» перечитывают список (edsClose → loadDeals).
extension Notification.Name {
    static let klikoСделкаEDSЗакрыта = Notification.Name("kliko.eds.deal.closed")
}

@MainActor
enum СделкиEDS {
    /// Что за ссылка.
    enum Ссылка: Equatable {
        /// /cabinet.php?eds=<id>[&t=<токен>].
        case сделка(id: String, токен: String)
        /// /eds.php?action=go&t=<токен>.
        case переход(токен: String)
    }

    /// Ссылка сделки eGov или nil. Только наш домен (Config.deepLink).
    static func ссылка(_ адрес: URL) -> Ссылка? {
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return nil }
        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        let путь = части.path
        if АдресаКабинета.кабинет(путь) {
            let номер = знач("eds")
            guard EDSAPI.годныйНомер(номер) else { return nil }
            let токен = знач("t")
            return .сделка(id: номер, токен: EDSAPI.годныйТокен(токен) ? токен : "")
        }
        if путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/eds(\\.php)?/?$", options: .regularExpression) != nil {
            guard знач("action").lowercased() == "go" else { return nil }
            let токен = знач("t")
            guard !токен.isEmpty, EDSAPI.годныйТокен(токен) else { return nil }
            return .переход(токен: токен)
        }
        return nil
    }

    /**
     Для ПереходыКабинета.своимЭкраном: ссылка сделки eGov — «Мои сделки» под ней (showDeals сайта, если слой вкладок на
     месте) и своё окно сделки поверх. true — открыто.
     */
    static func перехватить(_ адрес: URL, подСписок: Bool) -> Bool {
        guard let с = ссылка(адрес) else { return false }
        if подСписок && NativeRouter.доступна(.сделки) {
            WebBridge.shared.лентаВидна = true
            NativeRouter.shared.цель = .сделки
        }
        switch с {
        case .сделка(let id, let токен):
            открыть(id: id, токен: токен)
        case .переход(let токен):
            открытьПереход(токен: токен)
        }
        return true
    }

    /// Окно сделки поверх верхнего экрана (edsOpen). токен — t из ссылки: покупателю сразу вопрос о встрече/посылке.
    static func открыть(id: String, токен: String = "") {
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранСделкиEDS(id: id, токен: токен, закрыть: закрыть)
        }
    }

    /// Ссылка из QR (eds.php?action=go): окно узнаёт номер сделки само, пока показывает «Загрузка…».
    static func открытьПереход(токен: String) {
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранСделкиEDS(переход: токен, закрыть: закрыть)
        }
    }

    /// Адрес ссылки QR посылки (_edsParcelShow): location.origin + "/eds.php?action=go&t=" + токен.
    static func ссылкаПосылки(_ токен: String) -> String {
        абсолютная("/eds.php?action=go&t=" + EDSAPI.вАдрес(токен))
    }

    /// Путь от корня («/eds.php?…») — полным адресом сайта, как location.origin + путь; полный — как есть.
    static func абсолютная(_ адрес: String) -> String {
        guard адрес.hasPrefix("/"), !адрес.hasPrefix("//") else { return адрес }
        var база = Config.apiBase.absoluteString
        while база.hasSuffix("/") { база.removeLast() }
        return база + адрес
    }
}
