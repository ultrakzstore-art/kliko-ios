import Foundation

/**
 ЧАТ ПО ОБЪЯВЛЕНИЮ — ЗАПРОСЫ К САЙТУ (этап 38, владелец 25.09.2026: «почти 100% похоже на сайт»).

 У объявления сайта свой чат — chat.php (Kliko AI-ассистент продавца, потом сам продавец), отдельно от личных сообщений
 dm.php (этап 3). Витрина (js/marketplace.min.js: mkChatOpen, mkChatSendNow, mkChatLongPoll, mkChatReload, mkChatRefetch,
 mkOfferSend, mkChatCallSeller, mkChatBlockAction) ходит так — адрес от _MKB = "/", куки веб-сессии, тело JSON:
   · GET  chat.php?action=widget_data&pid=<объявление> → {ok, seller{id, name, verified}, product{title, img, price, kind,
     listing_status, gone, seller_id}, messages[], status, chat_id, blocked, blocked_by_me, deal_live, deal_id,
     agreed_price, no_escrow, seller_presence, seller_read_at, seller_online};
   · POST chat.php?action=send {pid, text[, offer][, force_escalate: true]} — БЕЗ csrf, как у сайта → {ok, ai_reply,
     status, chat_id, escalated}; {blocked, msg}; {need: "auth" | "verify" | "paid", msg}; {error};
   · GET  chat.php?action=poll&cid=<chat_id>&since=<count> → {ok, chat{messages, status, agreed_price, seller_read_at},
     count, typing}; {error: "access"} — опрос прекращается;
   · GET  chat.php?action=history&cid= → {ok, chat{messages, status}} — «потяни — обновится»;
   · POST chat.php?action=request_unblock {peer_id} — без csrf → {ok} | {error};
   · GET  chat.php?action=leads → {ok, leads[{chat_id, unread}]} — лиды (чаты по моим объявлениям) для числа на «Чате»
     рядом с dm.php list, как ulxBBChatBadge нижней панели сайта (13-bottombar).
 Сообщение (mkChatBubble, mkChatRender): role — buyer (я) | seller | ai | system; text; at; kind — offer (offer{price,
 method, term, funded, withdrawn, accepted, countered}), counter (counter{price, base, pct, accepted, declined,
 superseded}), offer_ok / offer_funded / offer_unfunded / offer_no (строка .kc-sys); type — geo (lat, lon), image (url);
 via — "telegram".

 Предложение цены — ровно mkOfferSend: text с суммой и offer {price, method: "cash", term: 0, pickup, ship_by_buyer},
 force_escalate: true. Подкрепить деньгами (offer_fund / offer_unfund) здесь НЕТ: они держат и возвращают деньги — это
 остаётся на сайте. Ответ на встречную цену продавца (offer_counter_accept / offer_counter_decline, _mkCounterGo) денег не
 двигает — только соглашается о цене или отказывается (оплата потом, оформлением сделки): он здесь, ответНаВстречную.
 Отзыв предложения (offer_withdraw) — OfferWithdraw.swift.

 Разбор терпимый, как у ленты (Listing): числа строкой или числом, массив — иногда объектом {"0":…}, чего нет — пусто.
 Здесь только запросы: когда слать, решает МодельЧатаОбъявления. Повторов нет: одно нажатие — один запрос.
 */
enum ЧатОбъявленияAPI {

    // MARK: - Что приходит

    struct Продавец: Equatable, Sendable {
        let id: String
        let имя: String
        let проверен: Bool
    }

    /// product ответа widget_data — шапка чата (mkChatHeaderRender).
    struct Товар: Equatable, Sendable {
        let id: String
        let название: String
        let фото: String?
        let цена: Double?
        /// kind: goods | service | rent — от него надпись у снятого («Продано», «Услуга больше не актуальна», «Объект сдан»).
        let вид: String
        /// Снято, продано, удалено: gone или listing_status из gone, deleted, deleted_permanent, sold, inactive.
        let снято: Bool
        let продавец: String
    }

    /// Снимок чата: widget_data, poll или history. nil у поля — его в ответе не было, прежнее значение не трогаем
    /// (как `void 0 !== t.blocked` в mkChatMeta сайта).
    struct Снимок: Sendable {
        var сообщения: [СообщениеЧатаОбъявления]? = nil
        var статус: String? = nil
        var чат: String? = nil
        var продавец: Продавец? = nil
        var товар: Товар? = nil
        var заблокирован: Bool? = nil
        var заблокировалЯ: Bool? = nil
        var сделкаИдёт: Bool? = nil
        var сделка: String? = nil
        var согласовано: Int? = nil
        var безГаранта: Bool? = nil
        var присутствие: String? = nil
        var прочитано: String? = nil
        var онлайн: Bool? = nil
        /// count опроса — since следующего.
        var счёт: Int? = nil
        var печатает = false
        /// Помощник продавца включён (флаг ответа, если сервер его прислал; нет флага — nil, решает переписка).
        var помощник: Bool? = nil
    }

    enum ИтогЗагрузки: Sendable {
        case готово(Снимок)
        /// need / error «auth» — чат только после входа.
        case нуженВход
        case отказ
        case сеть
    }

    enum ИтогОпроса: Sendable {
        case готово(Снимок)
        /// error «access» — у сайта опрос на этом прекращается.
        case закрыт
        case отказ
        case сеть
    }

    /// Ответ send с ok: true.
    struct ОтветОтправки: Sendable {
        let ответИИ: String?
        let статус: String?
        let чат: String?
        /// escalated — ассистент позвал продавца.
        let позвали: Bool
    }

    enum ИтогОтправки: Sendable {
        case готово(ОтветОтправки)
        /// blocked + msg — общение закрыто блокировкой.
        case заблокирован(String?)
        case нуженВход(String?)
        case нужнаВерификация(String?)
        /// need «paid» — лимит ассистента исчерпан.
        case лимит(String?)
        /// Иной отказ: код или текст сайта (error), «HTTP 500», «format» — под полем, как у этапа 3.
        case отказ(String)
        case сеть
    }

    /// Предложение цены — поля offer у mkOfferSend. Способ оплаты — всегда «cash», как выбран по умолчанию в окне сайта:
    /// рассрочка и кредит у сайта считаются по данным объявления (payment), которых у приложения нет.
    struct Предложение: Sendable {
        let цена: Int
        /// pickup — «Заберу сам» (или «Заберу или оплачу доставку сам» при бесплатной доставке).
        let забрать: Bool
        /// ship_by_buyer = pickup && ship_free.
        let доставкаСам: Bool
    }

    struct Лид: Equatable, Sendable {
        let id: String
        let непрочитано: Int
    }

    enum ИтогЛидов: Sendable {
        case список([Лид])
        case нуженВход
        /// Не ответил или ответ не того вида — число оставляем прежним.
        case нет
    }

    enum ИтогПросьбы: Sendable {
        case готово
        /// Текст сайта для человека (правило ulxErr) или nil.
        case отказ(String?)
        case сеть
    }

    // MARK: - Запросы

    /// GET widget_data — открыть чат объявления (mkChatOpen) или перечитать его (mkChatReload).
    static func загрузить(_ объявление: String) async -> ИтогЗагрузки {
        guard let адрес = адресЧата("widget_data", [URLQueryItem(name: "pid", value: объявление)]) else { return .отказ }
        return загрузка(await получить(адрес))
    }

    /// GET history — вся переписка по номеру чата (mkChatRefetch).
    static func история(_ чат: String) async -> ИтогЗагрузки {
        guard let адрес = адресЧата("history", [URLQueryItem(name: "cid", value: чат)]) else { return .отказ }
        return загрузка(await получить(адрес))
    }

    /// GET poll — новое после since (первый раз -1: у сайта _mkChatMsgCount = -1, и сервер отдаёт всё сразу).
    static func опрос(_ чат: String, после счёт: Int) async -> ИтогОпроса {
        guard let адрес = адресЧата("poll", [URLQueryItem(name: "cid", value: чат),
                                          URLQueryItem(name: "since", value: String(счёт))]) else { return .отказ }
        switch await получить(адрес) {
        case .сеть:
            return .сеть
        case .неJSON:
            return .отказ
        case .поля(let поля, _):
            guard да(поля["ok"]) else {
                return строка(поля["error"]) == "access" ? .закрыт : .отказ
            }
            return .готово(снимок(поля))
        }
    }

    /// POST send — сообщение, «Позвать продавца» (позвать: force_escalate) или предложение цены (offer). Без csrf — тело
    /// ровно как у сайта.
    static func написать(объявление: String, текст: String, предложение: Предложение?, позвать: Bool) async -> ИтогОтправки {
        guard let адрес = адресЧата("send") else { return .отказ("format") }
        var тело: [String: Any] = ["pid": объявление, "text": текст]
        if let п = предложение {
            тело["offer"] = ["price": п.цена, "method": "cash", "term": 0, "pickup": п.забрать,
                             "ship_by_buyer": п.доставкаСам] as [String: Any]
        }
        if позвать || предложение != nil { тело["force_escalate"] = true }
        switch await отправить(адрес, тело: тело) {
        case .сеть:
            return .сеть
        case .неJSON(let код):
            if код == 401 || код == 403 { return .нуженВход(nil) }
            return .отказ((200..<300).contains(код) ? "format" : "HTTP \(код)")
        case .поля(let поля, let код):
            if да(поля["ok"]) {
                return .готово(ОтветОтправки(ответИИ: строка(поля["ai_reply"]), статус: строка(поля["status"]),
                                             чат: строка(поля["chat_id"]), позвали: да(поля["escalated"])))
            }
            let словаСайта = строка(поля["msg"])
            if да(поля["blocked"]) { return .заблокирован(словаСайта) }
            let нужно = (строка(поля["need"]) ?? "").lowercased()
            let ошибка = строка(поля["error"]) ?? ""
            if нужно == "auth" || ошибка == "auth" || да(поля["need_reg"]) { return .нуженВход(словаСайта) }
            if нужно == "verify" || ошибка == "verify" || ошибка == "need_verification" {
                return .нужнаВерификация(словаСайта)
            }
            if нужно == "paid" { return .лимит(словаСайта) }
            if !ошибка.isEmpty { return .отказ(ошибка) }
            if код == 401 || код == 403 { return .нуженВход(словаСайта) }
            return .отказ((200..<300).contains(код) ? (словаСайта ?? "refused") : "HTTP \(код)")
        }
    }

    /**
     «Принять · N ₸» / «Отказаться» у встречной цены продавца — POST chat.php?action=offer_counter_accept |
     offer_counter_decline {csrf, pid} (_mkCounterGo витрины). Токен — страницы кабинета, как у offer_withdraw
     (ИнбоксAPI.отправить: на «csrf» — свежая страница и один повтор). Ответ ok — {price} согласованной цены.
     */
    @MainActor
    static func ответНаВстречную(объявление: String, принять: Bool) async -> (ok: Bool, цена: Int, ошибка: String?) {
        guard !объявление.isEmpty else { return (false, 0, ListingChatText.т("failed")) }
        let действие = принять ? "offer_counter_accept" : "offer_counter_decline"
        do {
            let j = try await ИнбоксAPI.отправить("chat.php?action=" + действие, тело: ["pid": объявление])
            if да(j["ok"]) { return (true, max(0, целое(j["price"]) ?? 0), nil) }
            return (false, 0, ИнбоксAPI.текстОшибки(j, запасной: ListingChatText.т("failed")))
        } catch {
            if let сбой = error as? КабинетСайта.Сбой, сбой == .сеть { return (false, 0, ListingChatText.т("no_conn")) }
            return (false, 0, ListingChatText.т("failed"))
        }
    }

    /// GET leads — непрочитанные в чатах по моим объявлениям (ulxBBChatBadge сайта).
    static func лиды() async -> ИтогЛидов {
        guard let адрес = адресЧата("leads") else { return .нет }
        switch await получить(адрес) {
        case .сеть:
            return .нет
        case .неJSON(let код):
            return (код == 401 || код == 403) ? .нуженВход : .нет
        case .поля(let поля, let код):
            guard да(поля["ok"]) else {
                let нужно = строка(поля["need"]) ?? ""
                let ошибка = строка(поля["error"]) ?? ""
                return (нужно == "auth" || ошибка == "auth" || код == 401 || код == 403) ? .нуженВход : .нет
            }
            var итог: [Лид] = []
            for элемент in записи(поля["leads"]) {
                guard let запись = элемент as? [String: Any] else { continue }
                итог.append(Лид(id: строка(запись["chat_id"]) ?? строка(запись["id"]) ?? "",
                                непрочитано: max(0, целое(запись["unread"]) ?? 0)))
            }
            return .список(итог)
        }
    }

    /// POST request_unblock {peer_id} — «Запросить разблокировку» у продавца, который ограничил общение (mkChatBlockAction).
    static func попроситьРазблокировать(_ продавец: String) async -> ИтогПросьбы {
        guard let адрес = адресЧата("request_unblock") else { return .отказ(nil) }
        switch await отправить(адрес, тело: ["peer_id": продавец]) {
        case .сеть:
            return .сеть
        case .неJSON:
            return .отказ(nil)
        case .поля(let поля, _):
            return да(поля["ok"]) ? .готово : .отказ(текстДляЧеловека(поля["error"]))
        }
    }

    // MARK: - Разбор

    private static func загрузка(_ сырое: Сырое) -> ИтогЗагрузки {
        switch сырое {
        case .сеть:
            return .сеть
        case .неJSON(let код):
            return (код == 401 || код == 403) ? .нуженВход : .отказ
        case .поля(let поля, _):
            guard да(поля["ok"]) else {
                let нужно = строка(поля["need"]) ?? ""
                let ошибка = строка(поля["error"]) ?? ""
                return (нужно == "auth" || ошибка == "auth") ? .нуженВход : .отказ
            }
            return .готово(снимок(поля))
        }
    }

    /// Поля ответа → снимок. Переписка и статус — в chat{} (poll, history) или сверху (widget_data); согласованная цена и
    /// «прочитано» — там же, как читает их mkChatMeta.
    private static func снимок(_ поля: [String: Any]) -> Снимок {
        let чат = поля["chat"] as? [String: Any]
        var с = Снимок()
        /* Без «??» между Any?: иначе компилятор вправе свернуть Optional в Any, и пустое поле пройдёт как значение. */
        var сырыеСообщения: Any? = поля["messages"]
        if let изЧата = чат?["messages"] { сырыеСообщения = изЧата }
        if let найденные = сырыеСообщения, !(найденные is NSNull) {
            с.сообщения = сообщения(найденные)
        }
        с.статус = строка(чат?["status"]) ?? строка(поля["status"])
        с.чат = строка(поля["chat_id"])
        if let п = поля["seller"] as? [String: Any] {
            с.продавец = Продавец(id: строка(п["id"]) ?? "", имя: строка(п["name"]) ?? "", проверен: да(п["verified"]))
        }
        if let т = поля["product"] as? [String: Any] {
            let состояние = (строка(т["listing_status"]) ?? "").lowercased()
            let снято = да(т["gone"]) || ["gone", "deleted", "deleted_permanent", "sold", "inactive"].contains(состояние)
            с.товар = Товар(id: строка(т["id"]) ?? "", название: строка(т["title"]) ?? "", фото: строка(т["img"]),
                            цена: дробное(т["price"]), вид: строка(т["kind"]) ?? "goods", снято: снято,
                            продавец: строка(т["seller_id"]) ?? "")
        }
        if есть(поля["blocked"]) {
            с.заблокирован = да(поля["blocked"])
            с.заблокировалЯ = да(поля["blocked_by_me"])
        }
        if есть(поля["deal_live"]) { с.сделкаИдёт = да(поля["deal_live"]) }
        if есть(поля["deal_id"]) { с.сделка = строка(поля["deal_id"]) ?? "" }
        if есть(чат?["agreed_price"]) {
            с.согласовано = max(0, целое(чат?["agreed_price"]) ?? 0)
        } else if есть(поля["agreed_price"]) {
            с.согласовано = max(0, целое(поля["agreed_price"]) ?? 0)
        }
        if есть(поля["no_escrow"]) { с.безГаранта = да(поля["no_escrow"]) }
        if есть(поля["seller_presence"]) { с.присутствие = строка(поля["seller_presence"]) ?? "" }
        с.прочитано = строка(чат?["seller_read_at"]) ?? строка(поля["seller_read_at"])
        if есть(поля["seller_online"]) { с.онлайн = да(поля["seller_online"]) }
        с.счёт = целое(поля["count"])
        с.печатает = да(поля["typing"])
        с.помощник = флагПомощника(поля, чат: чат)
        return с
    }

    /// Ключи, которыми сервер может сказать, включён ли помощник продавца (настройка «Kliko AI-помощник в чате»,
    /// save_pref_chat {ai}). Витрина сайта их не читает — поэтому только терпимо: нет ключа — nil.
    private static let ключиПомощника = ["ai_on", "ai_enabled", "ai_active", "seller_ai", "assistant", "ai"]

    /// Флаг помощника сверху, в chat{} или в seller{}; только да/нет (число, логическое, строка), не объект.
    private static func флагПомощника(_ поля: [String: Any], чат: [String: Any]?) -> Bool? {
        var места: [[String: Any]] = [поля]
        if let чат { места.append(чат) }
        if let продавец = поля["seller"] as? [String: Any] { места.append(продавец) }
        for место in места {
            for ключ in ключиПомощника {
                guard let значение = место[ключ] else { continue }
                if let b = значение as? Bool { return b }
                if let n = значение as? NSNumber { return n.intValue != 0 }
                if let строкаЗначения = значение as? String {
                    switch строкаЗначения.lowercased() {
                    case "1", "true", "on", "yes": return true
                    case "0", "false", "off", "no", "": return false
                    default: continue
                    }
                }
            }
        }
        return nil
    }

    /// messages[] — по порядку; запись не словарём пропускаем. Номер — место в переписке: своего id у сообщения чата нет.
    static func сообщения(_ значение: Any?) -> [СообщениеЧатаОбъявления] {
        var итог: [СообщениеЧатаОбъявления] = []
        for (место, элемент) in записи(значение).enumerated() {
            guard let з = элемент as? [String: Any] else { continue }
            let роль = (строка(з["role"]) ?? "").lowercased()
            let вид = (строка(з["kind"]) ?? "").lowercased()
            let тип = (строка(з["type"]) ?? "").lowercased()
            let когда = строка(з["at"]) ?? ""
            var предложение: ПредложениеВЧате? = nil
            if let о = з["offer"] as? [String: Any] {
                предложение = ПредложениеВЧате(цена: max(0, целое(о["price"]) ?? 0),
                                               способ: (строка(о["method"]) ?? "").lowercased(),
                                               срок: max(0, целое(о["term"]) ?? 0),
                                               подкреплено: max(0, целое(о["funded"]) ?? 0),
                                               отозвано: да(о["withdrawn"]),
                                               принято: да(о["accepted"]),
                                               встречнаяПринята: max(0, целое(о["countered"]) ?? 0))
            }
            var встречная: ВстречнаяВЧате? = nil
            if let в = з["counter"] as? [String: Any] {
                встречная = ВстречнаяВЧате(цена: max(0, целое(в["price"]) ?? 0),
                                           база: max(0, целое(в["base"]) ?? 0),
                                           шаг: max(0, целое(в["pct"]) ?? 0),
                                           принята: да(в["accepted"]),
                                           отклонена: да(в["declined"]),
                                           устарела: да(в["superseded"]))
            }
            let номер = [String(место), роль, когда, вид].joined(separator: "|")
            итог.append(СообщениеЧатаОбъявления(id: номер, роль: роль, текст: строка(з["text"]) ?? "", вид: вид,
                                                 тип: тип, когда: когда,
                                                 изTelegram: (строка(з["via"]) ?? "").lowercased() == "telegram",
                                                 широта: дробное(з["lat"]), долгота: дробное(з["lon"]),
                                                 фото: тип == "image" ? строка(з["url"]) : nil,
                                                 предложение: предложение, встречная: встречная))
        }
        return итог
    }

    // MARK: - Транспорт

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        /* poll у сайта — долгий опрос: сервер держит запрос, пока не придёт новое (сайт после ответа спрашивает снова
           через 200 мс). Ждём с запасом, чтобы держащий запрос не обрывался как «нет связи». */
        c.timeoutIntervalForRequest = 45
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private enum Сырое {
        case поля([String: Any], Int)
        case неJSON(Int)
        case сеть
    }

    /// /chat.php?action=<действие> — от корня сайта, как _MKB + "chat.php" витрины.
    private static func адресЧата(_ действие: String, _ ещё: [URLQueryItem] = []) -> URL? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("chat.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: действие)] + ещё
        return ч?.url
    }

    private static func получить(_ адрес: URL) async -> Сырое {
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        return await выполнить(запрос)
    }

    private static func отправить(_ адрес: URL, тело: [String: Any]) async -> Сырое {
        guard let данные = try? JSONSerialization.data(withJSONObject: тело) else { return .неJSON(0) }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        /* Как fetch страницы: POST того же сайта несёт Origin сайта. */
        запрос.setValue(Config.apiBase.absoluteString, forHTTPHeaderField: "Origin")
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        запрос.httpBody = данные
        return await выполнить(запрос)
    }

    private static func выполнить(_ запрос: URLRequest) async -> Сырое {
        let пришло: (Data, URLResponse)
        do { пришло = try await сессия.data(for: запрос) } catch { return .сеть }
        let код = (пришло.1 as? HTTPURLResponse)?.statusCode ?? 200
        /* JSON разбираем и при 4xx: сайт объясняет отказ полями need/error, а не кодом. */
        guard let поля = (try? JSONSerialization.jsonObject(with: пришло.0)) as? [String: Any] else { return .неJSON(код) }
        return .поля(поля, код)
    }

    // MARK: - Терпимое чтение полей

    private static func есть(_ значение: Any?) -> Bool {
        guard let значение else { return false }
        return !(значение is NSNull)
    }

    private static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private static func строка(_ значение: Any?) -> String? {
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = значение as? NSNumber { return n.stringValue }
        return nil
    }

    private static func целое(_ значение: Any?) -> Int? {
        if let n = значение as? NSNumber {
            let d = n.doubleValue
            return d.isFinite ? Int(exactly: d.rounded(.towardZero)) : nil
        }
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(t) ?? Double(t).flatMap { $0.isFinite ? Int(exactly: $0.rounded(.towardZero)) : nil }
        }
        return nil
    }

    private static func дробное(_ значение: Any?) -> Double? {
        if let n = значение as? NSNumber {
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        if let s = значение as? String, let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)), d.isFinite {
            return d
        }
        return nil
    }

    /// Массив или объект с номерами в ключах ({"0":…,"2":…} — так PHP отдаёт массив с дырами) — по порядку.
    private static func записи(_ значение: Any?) -> [Any] {
        if let массив = значение as? [Any] { return массив }
        if let словарь = значение as? [String: Any] {
            let ключи = словарь.keys.sorted { (Int($0) ?? Int.max) < (Int($1) ?? Int.max) }
            return ключи.compactMap { словарь[$0] }
        }
        return []
    }

    /// Правило ulxErr сайта: error показывается человеку, только если это не машинный код вида ^[a-z][a-z0-9_]{1,14}$.
    private static func текстДляЧеловека(_ значение: Any?) -> String? {
        guard let текст = строка(значение) else { return nil }
        let машинный = текст.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil
        return машинный ? nil : текст
    }
}

/// Сообщение чата объявления (mkChatBubble сайта).
struct СообщениеЧатаОбъявления: Identifiable, Equatable, Sendable {
    let id: String
    /// buyer — я (покупатель), seller — продавец, ai — Kliko AI-ассистент, system — служебная строка.
    let роль: String
    let текст: String
    /// kind: offer, counter, offer_ok, offer_funded, offer_unfunded, offer_no, contact.
    let вид: String
    /// type: geo, image, voice, video; пусто — текст.
    let тип: String
    let когда: String
    let изTelegram: Bool
    let широта: Double?
    let долгота: Double?
    /// Адрес картинки при type == image (у chat.php он сверху, а не в meta, как у dm.php).
    let фото: String?
    let предложение: ПредложениеВЧате?
    let встречная: ВстречнаяВЧате?
    /// Показано сразу после нажатия, сайт его ещё не вернул (как строка, которую mkChatSendNow дописывает до ответа).
    var местное = false

    var моё: Bool { роль == "buyer" }

    /// MK_CHAT_SYS_KINDS сайта: уведомления о предложении — строкой .kc-sys по центру.
    static let видыУведомлений: Set<String> = ["offer_funded", "offer_unfunded", "offer_no", "offer_ok"]

    /// Своё или служебное сообщение, показанное до ответа сайта. Номер — случайный: следующий снимок сайта его заменит.
    static func доОтвета(роль: String, текст: String) -> СообщениеЧатаОбъявления {
        СообщениеЧатаОбъявления(id: "local-" + UUID().uuidString, роль: роль, текст: текст, вид: "", тип: "",
                                когда: "", изTelegram: false, широта: nil, долгота: nil, фото: nil,
                                предложение: nil, встречная: nil, местное: true)
    }
}

/// offer{} своего предложения (mkOfferOwnCard).
struct ПредложениеВЧате: Hashable, Sendable {
    let цена: Int
    /// method: cash | inst | cred.
    let способ: String
    let срок: Int
    /// funded — сколько подкреплено деньгами.
    let подкреплено: Int
    let отозвано: Bool
    let принято: Bool
    /// countered — встречная цена, которую я принял.
    let встречнаяПринята: Int
}

/// counter{} встречной цены продавца (mkCounterCard).
struct ВстречнаяВЧате: Equatable, Sendable {
    let цена: Int
    /// base — моя сумма, к которой продавец прибавил шаг.
    let база: Int
    /// pct — шаг в процентах.
    let шаг: Int
    let принята: Bool
    let отклонена: Bool
    /// superseded — я предложил новую цену.
    let устарела: Bool
}
