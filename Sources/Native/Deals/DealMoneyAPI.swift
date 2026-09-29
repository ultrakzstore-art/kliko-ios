import Foundation

/**
 ДЕНЬГИ СДЕЛОК — ЗАПРОСЫ, ДАННЫЕ, ЗАДАНИЯ ИЗ ССЫЛОК (этап 44, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 🔴 ВСЁ ЗДЕСЬ — ТОЛЬКО ЗА Config.деньгиСделок (стоит false). Пока рубильник выключен, ни одна функция этого файла не
 вызывается: денежные кнопки карточки открывают страницу сделки сайта (cabinet.php?deal=<id>), ссылки ?start_deal=,
 ?start_service=, ?topup=, ?meet=, ?parcel= — страницу кабинета сайта, как на этапе 43.

 Денежные запросы (карта кабинета §4.6–§4.11, §4.9.5–§4.9.10, §8.6) — те же тела, что у js/cabinet.min.js:
   · escrow.php?action=create {product_id, hold_type:"full", amount?, pay_method?, pay_term?} / услуга {kind:"service", …};
   · escrow.php?action=pay {deal_id, use_points} · pay_card {deal_id} · ship_add / ship_add_card {deal_id, ship_q, to_lat,
     to_lon, to_addr} · ship_drop {deal_id, accept_paid};
   · escrow.php?action=cancel {deal_id, reason[, accept_fault]} · buyer_confirm {deal_id, rating, review} ·
     seller_confirm {deal_id, note} · pin_enter {deal_id, pin};
   · chat.php?action=meet_scan|parcel_open {token} · chat.php?action=clocal_return_confirm {deal_id};
   · pay.php?action=confirm — тело "{}", без csrf (так шлёт сайт после возврата со шлюза).
 Правило (§8.0.2): денежный POST уходит РОВНО ОДИН РАЗ и только после нажатия человека. Ни повтора на «csrf», ни повтора
 при обрыве сети или таймауте: ответ мог не дойти, а деньги — уйти. На «csrf» токен забывается — следующее НАЖАТИЕ
 возьмёт свежий. Только чтение (без токена): escrow.php?action=points, chat.php?action=widget_data, api/ship_quote.php.
 */
@MainActor
enum ДеньгиСделкиAPI {

    /// Денежный POST {csrf, …}: один раз, без повторов (см. шапку). Сессии нет — {ok:false, error:"auth"}.
    static func отправитьОдинРаз(_ хвост: String, тело: [String: Any], отКорня: Bool = false) async throws -> [String: Any] {
        let токен = try await МоиОбъявленияAPI.токенСейчас()
        guard !токен.isEmpty else { return ["ok": false, "error": "auth"] }
        var полное = тело
        полное["csrf"] = токен
        let ответ = try await КабинетСайта.вызвать(хвост, метод: "POST", тело: полное, отКорня: отКорня)
        guard let j = ответ.json else { throw КабинетСайта.Сбой.приложение }
        if МоиОбъявленияAPI.строка(j["error"]) == "csrf" { МоиОбъявленияAPI.забыть() }
        return j
    }

    /**
     POST pay.php?action=confirm с телом "{}" — без csrf, как у сайта (карта §4.0, §4.7). Сервер сверяет оплату картой,
     которую человек уже провёл на странице банка, и зачисляет её на кошелёк; сам ничего не списывает. Сайт шлёт его до
     пяти раз с шагом 3 с после ?topup=ok — натив тоже (ВозвратСоШлюза в модели), и только после возврата со шлюза.
     */
    static func сверитьОплату() async throws -> [String: Any]? {
        try await КабинетСайта.вызвать("pay.php?action=confirm", метод: "POST", тело: [:]).json
    }

    /// GET без токена (points, widget_data, ship_quote).
    static func получить(_ хвост: String) async throws -> [String: Any]? {
        try await МоиОбъявленияAPI.получить(хвост)
    }

    /// «Ошибка: <e>» сайта.
    static func ошибка(_ e: String) -> String {
        ДеньгиСделкиText.т("err_pfx").replacingOccurrences(of: "{e}", with: e)
    }
}

// MARK: - Что приложение знает о деньгах сделки сверх этапа 43

/**
 Поля deal, которые читают только денежные блоки сайта: код продавца (dealPinBlock), застой (stale_left), возврат товара
 (clocalReturnPanel: причина, чья вина, заявка курьера и обратная доставка).
 */
struct ДанныеДенегСделки: Equatable {
    /// my_pin — код продавца (4 цифры, меняется раз в минуту); pin_left — через сколько секунд новый.
    var пин: String = ""
    var пинСек: Int = 0
    /// stale_left — сколько секунд до ухода к модератору (показ, если ≤ 6 ч).
    var застойСек: Int = 0
    /// clocal.delivery.return_reason / return_fault / yandex_on.
    var причинаВозврата: String = ""
    var винаВозврата: String = ""
    var яндексВключён: Bool = false
    /// ship_claim_id, ship_claim_cancel ("free" — бесплатная отмена), ship_claim_failed, ship_return_fee.
    var заявкаКурьера: String = ""
    var отменаЗаявки: String = ""
    var заявкаСорвалась: Bool = false
    var обратнаяДоставка: Int = 0
    /// to_door.out — «Встречу у подъезда» (ship_quote &dd=out).
    var уПодъезда: Bool = false
    /// Итог возврата (refunded): кто оплатил доставку туда и обратно — ship_payer ("seller", "platform", иначе
    /// покупатель) и сколько списали — ship_seller_charge / ship_buyer_charge.
    var платилДоставку: String = ""
    var доставкаСПродавца: Int = 0
    var доставкаСПокупателя: Int = 0

    init() {}

    init(_ j: [String: Any]) {
        typealias A = СделкиAPI
        пин = A.строка(j["my_pin"]).trimmingCharacters(in: .whitespaces)
        пинСек = A.целое(j["pin_left"])
        застойСек = A.целое(j["stale_left"])
        заявкаКурьера = A.строка(j["ship_claim_id"]).trimmingCharacters(in: .whitespaces)
        отменаЗаявки = A.строка(j["ship_claim_cancel"])
        заявкаСорвалась = A.да(j["ship_claim_failed"])
        обратнаяДоставка = A.целое(j["ship_return_fee"])
        if let дверь = j["to_door"] as? [String: Any] { уПодъезда = A.да(дверь["out"]) }
        платилДоставку = A.строка(j["ship_payer"])
        доставкаСПродавца = A.целое(j["ship_seller_charge"])
        доставкаСПокупателя = A.целое(j["ship_buyer_charge"])
        if let блок = j["clocal"] as? [String: Any], let д = блок["delivery"] as? [String: Any] {
            причинаВозврата = A.строка(д["return_reason"])
            винаВозврата = A.строка(д["return_fault"])
            яндексВключён = A.да(д["yandex_on"])
        }
    }
}

// MARK: - Сбор гаранта (mkDealFee страницы кабинета)

/**
 mkDealFee: b = ceil(base·MK_COMM_RATE_B), s = round(base·MK_COMM_RATE), b += max(0, MK_FEE_MIN − (b+s)). Ставки
 сервер печатает в страницу кабинета; нет их на странице — значения из снимка (карта §4.1). Показ до создания сделки;
 после создания сумму считает сервер (total_pay).
 */
struct СтавкиСделки: Equatable {
    var покупатель: Double = 0.036269429999999998
    var продавец: Double = 0.035000000000000003
    var минимум: Int = 620

    static func изСтраницы(_ html: String) -> СтавкиСделки {
        var с = СтавкиСделки()
        if let v = число(#"var MK_COMM_RATE_B\s*=\s*([0-9.]+)"#, html) { с.покупатель = v }
        if let v = число(#"var MK_COMM_RATE\s*=\s*([0-9.]+)"#, html) { с.продавец = v }
        if let v = число(#"var MK_FEE_MIN\s*=\s*([0-9.]+)"#, html) { с.минимум = тенгеБезПереполнения(v) }
        return с
    }

    private static func число(_ шаблон: String, _ html: String) -> Double? {
        guard let r = html.range(of: шаблон, options: .regularExpression) else { return nil }
        let кусок = String(html[r])
        guard let знак = кусок.firstIndex(of: "=") else { return nil }
        let значение = кусок[кусок.index(after: знак)...].trimmingCharacters(in: .whitespaces)
        return Double(значение)
    }

    /// Ставки — со страницы (изСтраницы): мусор или огромное число не роняет приложение — тенгеБезПереполнения
    /// держит каждое слагаемое в ±10¹⁵, и сумма двух-трёх таких не переполняет Int.
    func сбор(_ база: Int) -> Int {
        let b0 = max(0, база)
        var b = тенгеБезПереполнения((Double(b0) * покупатель).rounded(.up))
        let s = тенгеБезПереполнения(Double(b0) * продавец)
        b += max(0, тенгеБезПереполнения(Double(минимум)) - (b + s))
        return b
    }
}

// MARK: - Возврат со страницы банка (?topup=ok|fail&deal=<id>[&ship=1])

enum ВозвратСоШлюза {
    struct Итог: Equatable {
        let оплачено: Bool
        let сделка: String
        let курьер: Bool
    }

    /**
     Адрес, на который банк возвращает человека (его вписывает сервер в redirect_url — какой именно, в JS не видно, карта
     §4.19.6, §8.12.5): свой домен и параметр topup. Без deal — это пополнение кошелька (этап 47) — не наше.
     */
    static func разобрать(_ адрес: URL) -> Итог? {
        let хост = (адрес.host ?? "").lowercased()
        guard адрес.scheme?.lowercased() == "https", хост == "kliko.kz" || хост == "www.kliko.kz",
              let части = URLComponents(url: адрес, resolvingAgainstBaseURL: false) else { return nil }
        let параметры = части.queryItems ?? []
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        let итог = знач("topup")
        let номер = знач("deal")
        guard !итог.isEmpty, !номер.isEmpty, СделкиAPI.годныйНомер(номер) else { return nil }
        return Итог(оплачено: итог == "ok", сделка: номер, курьер: знач("ship") == "1")
    }
}

// MARK: - Задания из ссылок (?start_deal=, ?start_service=, ?meet=, ?parcel=, ?topup=)

/// Что попросила ссылка кабинета, когда деньги сделок в приложении включены.
enum ЗаданиеДенегСделки: Equatable {
    /// ?start_deal=<pid>[&pay=<метод>][&term=<мес>] — окно «Безопасная сделка».
    case сделка(товар: String, оплата: String, срок: Int)
    /// ?start_service=<pid> — «Заказать через гаранта».
    case услуга(товар: String)
    /// ?meet=<qr> (QR встречи с экрана продавца) или ?parcel=<token> (листок в коробке).
    case код(встреча: Bool, токен: String)
    /// Банк вернул человека: ?topup=ok|fail&deal=<id>[&ship=1].
    case шлюз(ВозвратСоШлюза.Итог)
}

/**
 Ящик на одно задание. Кладёт его разбор ссылки (АдресаКабинета — вне главного актора, поэтому здесь замок, а не
 @MainActor), забирает экран: «Мои сделки» — создание и коды, карточка сделки — возврат со шлюза своей сделки.
 Уведомление будит экран, который уже открыт; новый экран заберёт задание сам, появившись. Выход стирает ящик.
 */
final class ЗаданияДенегСделок: @unchecked Sendable {
    static let shared = ЗаданияДенегСделок()
    static let пришло = Notification.Name("kliko.deals.moneyTask")

    private let замок = NSLock()
    private var задание: ЗаданиеДенегСделки? = nil

    private init() {}

    func положить(_ новое: ЗаданиеДенегСделки) {
        замок.lock()
        задание = новое
        замок.unlock()
        NotificationCenter.default.post(name: Self.пришло, object: nil)
    }

    /// Забрать задание, если оно подходит этому экрану.
    func забрать(_ подходит: (ЗаданиеДенегСделки) -> Bool) -> ЗаданиеДенегСделки? {
        замок.lock()
        defer { замок.unlock() }
        guard let есть = задание, подходит(есть) else { return nil }
        задание = nil
        return есть
    }

    func стереть() {
        замок.lock()
        задание = nil
        замок.unlock()
    }
}
