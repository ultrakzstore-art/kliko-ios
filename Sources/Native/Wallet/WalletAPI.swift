import Foundation

/**
 КОШЕЛЁК И БАЛЛЫ — ЗАПРОСЫ И ДАННЫЕ, ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Карта кабинета §5 и §8.9; код — js/cabinet.min.js (loadWalletInfo, frozenRender, payoutBannerHTML, payoutOpenLink,
 payoutBackCheck, tpmOpen) и докачанный модуль js/cabinet-wallet.min.js (doTopup, showWithdraw, wdLadderCard, wdCalcFee,
 wdAmountOk, wdUpdateBtn, wdAutoToggle, doWithdraw, wdResultModal). Транспорт — КабинетСайта.вызвать (этап 40): fetch
 изнутри страницы сайта под слоем, с её куками, Origin и Referer; пути относительные, как у сайта (/kz/<язык>/…).

 Только чтение (GET без токена, как у сайта):
   · cabinet.php?action=wallet_info   → баланс, доступно, удержано, история, готовые выплаты, ставки вывода, ступень;
   · cabinet.php?action=frozen_funds  → «Заморожено сейчас»;
   · cabinet.php?action=payout_outcome → итог выплаты после возврата со страницы банка (?payout=back);
   · escrow.php?action=points         → баллы, уровень, кэшбэк, история начислений (showPoints модуля deals);
   · escrow.php?action=deal&id=       → чек сделки из истории (showReceipt; разбор — Сделка этапа 43).

 🔴 ДЕНЬГИ — только за рубильниками, только по нажатию человека, ровно один раз (ДеньгиСделкиAPI.отправитьОдинРаз:
 ни повтора на «csrf», ни повтора при обрыве сети — ответ мог не дойти, а деньги уйти):
   · Config.деньгиКошелька (false): pay.php?action=create {amount, fresh} → redirect_url страницы банка;
     cabinet.php?action=topup {amount, fresh} (ответ payments_off первого); cabinet.php?action=withdraw
     {amount, method, details}; cabinet.php?action=wd_autopay {enabled[, method, details]};
     GET cabinet.php?action=payout_link&wid= (страница банка для карты выплаты);
   · Config.деньгиСделок (false, этап 44): cabinet.php?action=offer_unfund {listing_id} — возврат обеспечения
     предложения из «Заморожено сейчас» (§8.9: «возврат обеспечения → деньгиСделок»).
 pay.php?action=confirm (тело "{}", без csrf) — ДеньгиСделкиAPI.сверитьОплату этапа 44: только после возврата со шлюза.
 */
@MainActor
enum КошелёкAPI {
    /// GET без токена. ждать = false — фоновое чтение вкладки «Кабинет»: не ждёт страницу и не уводит её на главную.
    static func получить(_ хвост: String, ждать: Bool = true) async throws -> [String: Any]? {
        try await КабинетСайта.вызвать(хвост, ждать: ждать).json
    }

    /// Денежный POST (см. шапку): один раз, только по нажатию.
    static func отправитьОдинРаз(_ хвост: String, тело: [String: Any]) async throws -> [String: Any] {
        try await ДеньгиСделкиAPI.отправитьОдинРаз(хвост, тело: тело)
    }

    // Разбор — как +x||0 и x||"" сайта. nonisolated: зовут разборы вне главной нити.
    nonisolated static func строка(_ з: Any?) -> String { МоиОбъявленияAPI.строка(з) }
    nonisolated static func да(_ з: Any?) -> Bool { МоиОбъявленияAPI.да(з) }
    nonisolated static func число(_ з: Any?) -> Double {
        let n = МоиОбъявленияAPI.число(з)
        return n.isFinite ? n : 0
    }
    /// Сумма в тенге целым: сервер шлёт целые, дробь (если придёт) округляется, как toLocaleString без копеек.
    nonisolated static func тенге(_ з: Any?) -> Int {
        let n = число(з)
        guard abs(n) < 1e15 else { return 0 }
        return Int(n.rounded())
    }
}

// MARK: - wallet_info

/// holds[] — удержание: секунды до освобождения (left), сумма и почему (у сайта — «Срок безопасности»).
struct УдержаниеКошелька: Equatable {
    let секунд: Int
    let сумма: Int
    let почему: String
}

/// payout_ready[] — выплата подтверждена, ждёт карту на странице банка.
struct ГотоваяВыплата: Equatable, Identifiable {
    let wid: String
    let сумма: Int
    /// expires_at — строка для new Date(): до когда действует ссылка.
    let до: String
    var id: String { wid }
}

/// walletInfo.ladder — ступень доверия: потолки вывода и что нужно до следующей (wdLadderCard).
struct СтупеньДоверия: Equatable {
    let название: String
    let снижена: Bool
    let нужноСделок: Int
    let нужноОборота: Int
    let нужноСуток: Int
    let естьСледующая: Bool
    let следующая: String
    let заОперацию: Int
    let заМесяц: Int

    init?(_ j: [String: Any]?) {
        guard let j else { return nil }
        typealias A = КошелёкAPI
        название = A.строка(j["label"])
        снижена = A.число(j["penalty"]) > 0
        нужноСделок = A.тенге(j["need_deals"])
        нужноОборота = A.тенге(j["need_sum"])
        нужноСуток = A.тенге(j["need_days"])
        /* t.next у сайта — «истинно ли»: пустая строка, 0, null — верхняя ступень. */
        let след = j["next"]
        if let s = след as? String {
            естьСледующая = !s.isEmpty
        } else if let n = след as? NSNumber {
            естьСледующая = n.doubleValue != 0
        } else {
            естьСледующая = след != nil && !(след is NSNull)
        }
        следующая = A.строка(j["next_label"])
        заОперацию = A.тенге(j["op"])
        заМесяц = A.тенге(j["month"])
    }
}

/// Строка истории операций (#tx-list).
struct ОперацияКошелька: Identifiable, Equatable {
    let id: Int
    let тип: String
    /// delta (если есть и не null) иначе amount — со знаком: >0 — зачисление.
    let сумма: Double
    let когда: String
    /// note || product — вторая строка.
    let заметка: String
    let сделка: String

    /// Строки escrow_* подсвечены и ведут в сделку.
    var гарант: Bool { тип.hasPrefix("escrow_") }
    /// «чек» — только у escrow_release и escrow_hold.
    var естьЧек: Bool { (тип == "escrow_release" || тип == "escrow_hold") && !сделка.isEmpty }
}

/**
 Ответ wallet_info (карта §5.1.1) и ключи, которые читает модуль wallet (wd_*, acq_*, ladder, saved_method,
 auto_withdraw…). Значения по умолчанию — как `let walletInfo={…}` страницы до первого ответа.
 */
struct СведенияКошелька: Equatable {
    var баланс: Int = 0
    /// available; нет — равно balance (null!=d.available ? … : balance).
    var доступно: Int = 0
    var удержано: Int = 0
    var удержания: [УдержаниеКошелька] = []
    /// topup_locked — пополнение с карты, которое тратится только на услуги Kliko.
    var пополнениеКартой: Int = 0
    var операции: [ОперацияКошелька] = []
    var выплаты: [ГотоваяВыплата] = []
    // Ставки вывода (wdCalcFee, wdAmountOk, showWithdraw)
    var комиссияПроц: Double = 0
    var минимум: Double = 0
    var максимум: Double = 0
    var остатокМин: Double = 0
    var безКомиссии: Double = 0
    var эквайрВыводПроц: Double = 0
    var эквайрВыводМин: Double = 0
    var эквайрВводПроц: Double = 0
    var эквайрВводМин: Double = 0
    var наценка: Double = 1
    var ступень: СтупеньДоверия? = nil
    var сохранённыйСпособ: String = ""
    var автоВывод: Bool = false
    var автоСпособ: String = ""
    var автоМаска: String = ""

    init() {}

    init(_ d: [String: Any]) {
        typealias A = КошелёкAPI
        баланс = A.тенге(d["balance"])
        if let есть = d["available"], !(есть is NSNull) {
            доступно = A.тенге(есть)
        } else {
            доступно = баланс
        }
        удержано = A.тенге(d["held"])
        удержания = ((d["holds"] as? [[String: Any]]) ?? []).map { h in
            УдержаниеКошелька(секунд: A.тенге(h["left"]), сумма: A.тенге(h["amount"]), почему: A.строка(h["why"]))
        }
        пополнениеКартой = A.тенге(d["topup_locked"])
        var список: [ОперацияКошелька] = []
        for (i, t) in ((d["transactions"] as? [[String: Any]]) ?? []).enumerated() {
            let дельта = t["delta"]
            let сумма: Double = (дельта != nil && !(дельта is NSNull)) ? A.число(дельта) : A.число(t["amount"])
            var заметка = A.строка(t["note"])
            if заметка.isEmpty { заметка = A.строка(t["product"]) }
            список.append(ОперацияКошелька(id: i, тип: A.строка(t["type"]), сумма: сумма, когда: A.строка(t["at"]),
                                           заметка: заметка, сделка: A.строка(t["deal_id"])))
        }
        операции = список
        выплаты = ((d["payout_ready"] as? [[String: Any]]) ?? []).compactMap { (p: [String: Any]) -> ГотоваяВыплата? in
            let wid = A.строка(p["wid"])
            guard !wid.isEmpty else { return nil }
            return ГотоваяВыплата(wid: wid, сумма: A.тенге(p["amount"]), до: A.строка(p["expires_at"]))
        }
        комиссияПроц = A.число(d["wd_fee_pct"])
        минимум = A.число(d["wd_min"])
        максимум = A.число(d["wd_max"])
        остатокМин = A.число(d["wd_tail_min"])
        безКомиссии = A.число(d["wd_free_left"])
        эквайрВыводПроц = A.число(d["acq_out_pct"])
        эквайрВыводМин = A.число(d["acq_out_min"])
        эквайрВводПроц = A.число(d["acq_in_pct"])
        эквайрВводМин = A.число(d["acq_in_min"])
        let н = A.число(d["wd_markup"])
        наценка = н == 0 ? 1 : н
        ступень = СтупеньДоверия(d["ladder"] as? [String: Any])
        сохранённыйСпособ = A.строка(d["saved_method"])
        автоВывод = A.да(d["auto_withdraw"])
        автоСпособ = A.строка(d["auto_method"])
        автоМаска = A.строка(d["auto_details_mask"])
    }
}

// MARK: - frozen_funds

struct ЗамороженоСтрока: Identifiable, Equatable {
    /// "deal" — деньги в гарант-сделке; иное — обеспечение предложения.
    let сделка: Bool
    let номер: String
    let сумма: Int
    let название: String
    let можноОтменить: Bool
    /// after_ship | meet_lock | stage | denied.
    let почему: String
    var id: String { (сделка ? "d:" : "o:") + номер }
}

struct ЗамороженоКошелька: Equatable {
    let всего: Int
    let строки: [ЗамороженоСтрока]

    /// !t.ok || !(t.items||[]).length — блока нет.
    init?(_ j: [String: Any]) {
        typealias A = КошелёкAPI
        guard A.да(j["ok"]) else { return nil }
        let список: [ЗамороженоСтрока] = ((j["items"] as? [[String: Any]]) ?? []).map { e in
            ЗамороженоСтрока(сделка: A.строка(e["kind"]) == "deal", номер: A.строка(e["id"]), сумма: A.тенге(e["amount"]),
                             название: A.строка(e["title"]), можноОтменить: A.да(e["can_cancel"]),
                             почему: A.строка(e["why"]))
        }
        guard !список.isEmpty else { return nil }
        всего = A.тенге(j["total"])
        строки = список
    }
}

// MARK: - escrow.php?action=points

struct ЗаписьБаллов: Identifiable, Equatable {
    let id: Int
    let баллы: Int
    let когда: String
    let причина: String
    let сделка: String
    /// earn | spend | иное.
    let тип: String
}

struct БаллыКошелька: Equatable {
    var баллы: Int = 0
    var уровень: String = ""
    var следующийУровень: String = ""
    var доСледующего: Int = 0
    /// cashback_pct ?? buyer_pct ?? 1.
    var кэшбэк: Double = 1
    /// max_spend ?? 10.
    var максимум: Double = 10
    /// seller_pct — только если сервер прислал.
    var продавцу: Double? = nil
    /// tiers[{min, cashback}].
    var ступени: [Int: Double] = [:]
    var история: [ЗаписьБаллов] = []

    init?(_ n: [String: Any]) {
        typealias A = КошелёкAPI
        guard A.да(n["ok"]) else { return nil }
        баллы = A.тенге(n["points"])
        уровень = A.строка(n["level"])
        следующийУровень = A.строка(n["next_level"])
        доСледующего = A.тенге(n["next_pts"])
        /* ?? сайта: берётся первое, что не null/undefined (0 — тоже значение). */
        func первое(_ ключи: [String], _ запас: Double) -> Double {
            for к in ключи {
                if let з = n[к], !(з is NSNull) { return A.число(з) }
            }
            return запас
        }
        кэшбэк = первое(["cashback_pct", "buyer_pct"], 1)
        максимум = первое(["max_spend"], 10)
        if let s = n["seller_pct"], !(s is NSNull) { продавцу = A.число(s) }
        var т: [Int: Double] = [:]
        for t in (n["tiers"] as? [[String: Any]]) ?? [] {
            т[A.тенге(t["min"])] = A.число(t["cashback"])
        }
        ступени = т
        история = ((n["log"] as? [[String: Any]]) ?? []).enumerated().map { (i, e) in
            ЗаписьБаллов(id: i, баллы: A.тенге(e["pts"]), когда: A.строка(e["at"]), причина: A.строка(e["reason"]),
                         сделка: A.строка(e["deal_id"]), тип: A.строка(e["type"]))
        }
    }
}

// MARK: - Формат

enum КошелёкФормат {
    /// toLocaleString("ru-RU") целого: «12 345».
    static func деньги(_ n: Int) -> String { СделкиФормат.деньги(n) }
    static func тенге(_ n: Int) -> String { СделкиФормат.тенге(n) }

    /// Число сайта как есть: 6 → «6», 0.5 → «0.5» (String(Number) — с точкой).
    static func процент(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e12 { return String(Int(x)) }
        return String(x)
    }

    /// «2 дн.» или «5ч»: часы = floor(left/3600); от 24 ч — round(часы/24) дней (loadWalletInfo, wdHeldCard).
    static func освободится(_ секунд: Int) -> String {
        let часы = max(0, секунд) / 3600
        if часы >= 24 {
            let дни = Int((Double(часы) / 24).rounded())
            return String(дни) + " " + КошелёкText.т("d_short")
        }
        return String(часы) + КошелёкText.т("h_short")
    }

    /// «26.09.2026, 18:30» — toLocaleDateString + toLocaleTimeString({hour, minute}) баннера выплаты.
    static func срокВыплаты(_ строка: String) -> String {
        guard let d = СделкиФормат.дата(строка) else { return "" }
        let дата = DateFormatter()
        дата.locale = Locale(identifier: "ru_RU")
        дата.dateFormat = "dd.MM.yyyy"
        let время = DateFormatter()
        время.locale = Locale(identifier: "ru_RU")
        время.dateFormat = "HH:mm"
        return дата.string(from: d) + ", " + время.string(from: d)
    }
}

// MARK: - Возврат со страницы банка и задания из ссылок

/// Куда банк вернул человека: пополнение (?topup=ok|fail без deal и pro) или выплата (?payout=back).
enum ВозвратКошелька: Equatable {
    case пополнение(оплачено: Bool)
    case выплата

    /**
     Адрес возврата вписывает сервер (в JS его не видно, карта §5.2.3, §5.3.6): свой домен и параметр topup или payout.
     С deal — это оплата сделки (этап 44, ВозвратСоШлюза), с pro — PRO (этап 48): не наше.
     */
    static func разобрать(_ адрес: URL) -> ВозвратКошелька? {
        let хост = (адрес.host ?? "").lowercased()
        guard адрес.scheme?.lowercased() == "https", хост == "kliko.kz" || хост == "www.kliko.kz",
              let части = URLComponents(url: адрес, resolvingAgainstBaseURL: false) else { return nil }
        let параметры = части.queryItems ?? []
        func знач(_ имя: String) -> String? {
            параметры.first(where: { $0.name == имя }).map { ($0.value ?? "").trimmingCharacters(in: .whitespaces) }
        }
        if знач("payout") == "back" { return .выплата }
        guard let итог = знач("topup"), !итог.isEmpty, знач("deal") == nil, знач("pro") == nil else { return nil }
        return .пополнение(оплачено: итог == "ok")
    }
}

/**
 Ящик на одно задание из ссылки кабинета (?payout=back, ?topup=ok|fail без deal). Кладёт разбор ссылки (АдресаКабинета —
 вне главного актора, поэтому замок, а не @MainActor), забирает экран кошелька. Уведомление будит уже открытый экран.
 Выход стирает ящик.
 */
final class ЗаданияКошелька: @unchecked Sendable {
    static let shared = ЗаданияКошелька()
    static let пришло = Notification.Name("kliko.wallet.task")

    private let замок = NSLock()
    private var задание: ВозвратКошелька? = nil

    private init() {}

    func положить(_ новое: ВозвратКошелька) {
        замок.lock()
        задание = новое
        замок.unlock()
        NotificationCenter.default.post(name: Self.пришло, object: nil)
    }

    func забрать() -> ВозвратКошелька? {
        замок.lock()
        defer { замок.unlock() }
        let есть = задание
        задание = nil
        return есть
    }

    func стереть() {
        замок.lock()
        задание = nil
        замок.unlock()
    }
}
