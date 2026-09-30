import Foundation

/**
 СООБЩЕНИЯ КАБИНЕТА — ЗАПРОСЫ, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Всё по карте кабинета (§6.3, §6.4, §6.8, §6.9.1, §8.7) и по коду сайта (js/cabinet.min.js: loadMessages, _msgRow*,
 msgPin/msgHide/msgRestore/msgPurge, dmSetLabel/lcmSetLabel, openLeadChat и _lcm*, loadRequests/requestRespond/_reqDo*,
 checkPendingFeedback/fbSubmit, markAllRead, openTicket/supSend, dataReqSend; модуль deals: msgFilter, msgSearchInput).
 Транспорт — КабинетСайта.вызвать (этап 40): fetch изнутри страницы сайта под слоем — те же куки, Origin и Referer
 (dm.php проверяет источник: error "origin", §6.0.2).

 🔴 КАК У САЙТА — БЕЗ CSRF, С me_id. Многие запросы чатов идут без токена (карта §6.10, колонка «csrf»): dm.php (list,
 set_label), chat.php (leads, buyer_chats, seller_chat, seller_join, seller_reply, typing, presence_event, set_label,
 request_unblock), api/chat_hide.php, support.php?action=create, списки my_requests и my_pending_feedback. Их тела — ровно
 сайта (отправитьБезТокена). С токеном — chat_pin, subs.php block/unblock, report.php, offer_*, request_action,
 request_feedback, mark_notif_read, sup_my_reply (отправить: токен страницы кабинета, «csrf» — страница заново и один
 повтор, §8.0.3). me_id — KlikoUser.id вошедшего (_dmMe сайта = localStorage.ulx_me_id).

 Только чтение: dm.php list, chat.php leads / buyer_chats / seller_chat (и long-poll wait=1&since=) / search, my_requests,
 my_pending_feedback, sup_my_get, страница кабинета (колокольчик, CHAT_PINS). Всё остальное — только по нажатию.
 🔴 ДЕНЬГИ: offer_decline (продавец отказывается — обеспечение возвращается покупателю) — только за Config.деньгиСделок
 (false): иначе кнопка открывает этот лид-чат на странице кабинета сайта.
 */
@MainActor
enum ИнбоксAPI {
    typealias З = МоиОбъявленияAPI

    // MARK: - Кто я (me_id)

    /// Номер вошедшего, найденный последним. Сбрасывается при выходе и когда страница говорит «гость».
    private static var запомненный = ""

    /**
     Номер без лишних запросов: страница под слоем (KlikoUser.id или ulx_me_id) или уже известный. Зовётся из опроса
     переписки каждые три секунды — страницу кабинета ради него не качает.
     */
    static func номерБыстро() async -> String {
        let сессия = await SiteSession.состояние()
        if let п = сессия.пользователь, !п.isEmpty {
            запомненный = п
            return п
        }
        if сессия.вошёл == false {
            запомненный = ""
            return ""
        }
        return запомненный
    }

    /// Номер для запроса, которому он обязателен (list, my_requests): быстро, иначе — со страницы кабинета.
    static func мойНомер(ждать: Bool) async -> String {
        let быстро = await номерБыстро()
        if !быстро.isEmpty { return быстро }
        /* Владелец 26.09.2026: гость известен по странице под слоем — страницу кабинета (сотни КБ) не качаем.
           Иначе счётчик ленты каждые 12 с тянул бы cabinet.php у каждого невошедшего ради «нужен вход». */
        if await SiteSession.состояние().вошёл == false {
            запомненный = ""
            return ""
        }
        guard let страница = try? await КабинетСайта.состояние(ждать: ждать) else { return "" }
        if страница.вошёл == true && !страница.uid.isEmpty {
            запомненный = страница.uid
            З.запомнитьТокен(страница.csrf)
        }
        return запомненный
    }

    static func забыть() {
        запомненный = ""
    }

    /// encodeURIComponent сайта.
    nonisolated static func вАдрес(_ значение: String) -> String {
        значение.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? значение
    }

    // MARK: - Транспорт

    /// GET без токена. nil — ответ не JSON. ждать = false — фоновый запрос: страницу под слоем не трогает.
    static func получить(_ хвост: String, ждать: Bool = true) async throws -> [String: Any]? {
        try await КабинетСайта.вызвать(хвост, ждать: ждать).json
    }

    /// POST JSON без csrf — тело ровно сайта. Не JSON — «ошибка приложения». Повторов нет: запись могла дойти.
    static func отправитьБезТокена(_ хвост: String, тело: [String: Any], ждать: Bool = true) async throws -> [String: Any] {
        let ответ = try await КабинетСайта.вызвать(хвост, метод: "POST", тело: тело, ждать: ждать)
        guard let j = ответ.json else { throw КабинетСайта.Сбой.приложение }
        return j
    }

    /// POST {csrf, …}: токен и один повтор на «csrf» — общие с «Моими объявлениями». Только не денежные запросы.
    static func отправить(_ хвост: String, тело: [String: Any]) async throws -> [String: Any] {
        try await З.отправить(хвост, тело: тело)
    }

    /**
     ulxErr сайта: error показывается, только если это не короткий латинский код (§6.0.3); иначе — запасной текст.
     */
    nonisolated static func текстОшибки(_ j: [String: Any]?, запасной: String) -> String {
        guard let j else { return запасной }
        let текст = З.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if текст.isEmpty || КабинетСайта.машинныйКодБезГлавной(текст) { return запасной }
        return текст
    }

    /// «Нет соединения» / «Ошибка» — как сайт по виду сбоя fetch.
    nonisolated static func текстСбоя(_ ошибка: Error) -> String {
        if let сбой = ошибка as? КабинетСайта.Сбой, сбой == .сеть { return ИнбоксText.т("err_no_conn") }
        return ИнбоксText.т("err_generic")
    }

    // MARK: - Инбокс: три источника и склейка (loadMessages)

    enum Итог: Equatable, Sendable {
        case готово
        case нуженВход
        case сбой
    }

    struct Сборка {
        var итог: Итог
        var строки: [СтрокаИнбокса] = []
        /// me_id, на чьих куках собрано (для копии на диске); пусто — неизвестно.
        var номер: String = ""
    }

    /**
     loadMessages сайта: три запроса по очереди, каждый сам по себе (не ответил один — остальные всё равно показываются):
       GET dm.php?action=list&me_id=<me> → threads[] (dm);
       GET chat.php?action=leads          → leads[]   (lead);
       GET chat.php?action=buyer_chats    → chats[]   (buyer).
     Склейка по tid (dm) или chat_id (lead, buyer): приоритет lead > buyer > dm, kinds — с записи-победителя, если они там
     есть, иначе с другой; unread — большее. Строка без номера у сайта остаётся отдельной — здесь её нет: ни открыть, ни
     убрать её нельзя (все действия сайта идут по номеру). Порядок: сначала с непрочитанными, потом новые сверху
     (упорядочить). Превью и время склеенной строки — той записи, где сообщение новее (см. склеить).
     */
    static func собрать(ждать: Bool) async -> Сборка {
        let я = await мойНомер(ждать: ждать)
        if я.isEmpty {
            let сессия = await SiteSession.состояние()
            if сессия.вошёл == false { return Сборка(итог: .нуженВход) }
        }
        var записи: [СтрокаИнбокса] = []
        var ответили = 0
        var безВхода = 0

        if let j = try? await получить("dm.php?action=list&me_id=" + вАдрес(я), ждать: ждать) {
            ответили += 1
            if З.да(j["ok"]) {
                for t in (j["threads"] as? [[String: Any]]) ?? [] {
                    if let строка = СтрокаИнбокса(dm: t) { записи.append(строка) }
                }
            } else if З.нетСессии(j) {
                безВхода += 1
            }
        }
        if let j = try? await получить("chat.php?action=leads", ждать: ждать) {
            ответили += 1
            if З.да(j["ok"]) {
                for t in (j["leads"] as? [[String: Any]]) ?? [] {
                    if let строка = СтрокаИнбокса(лид: t) { записи.append(строка) }
                }
            } else if З.нетСессии(j) {
                безВхода += 1
            }
        }
        if let j = try? await получить("chat.php?action=buyer_chats", ждать: ждать) {
            ответили += 1
            if З.да(j["ok"]) {
                for t in (j["chats"] as? [[String: Any]]) ?? [] {
                    if let строка = СтрокаИнбокса(покупка: t) { записи.append(строка) }
                }
            } else if З.нетСессии(j) {
                безВхода += 1
            }
        }
        if ответили == 0 { return Сборка(итог: .сбой) }
        if безВхода == ответили { return Сборка(итог: .нуженВход) }
        return Сборка(итог: .готово, строки: склеить(записи), номер: я)
    }

    /// Склейка и порядок loadMessages (см. выше). nonisolated — чистая функция над данными.
    nonisolated static func склеить(_ записи: [СтрокаИнбокса]) -> [СтрокаИнбокса] {
        var поНомеру: [String: СтрокаИнбокса] = [:]
        var порядокНомеров: [String] = []
        for запись in записи {
            guard let была = поНомеру[запись.номер] else {
                поНомеру[запись.номер] = запись
                порядокНомеров.append(запись.номер)
                continue
            }
            let новаяВыше = запись.источник.приоритет < была.источник.приоритет
            var победитель = новаяВыше ? запись : была
            let другая = новаяВыше ? была : запись
            if победитель.видыИзОтвета == nil { победитель.виды = другая.виды }
            победитель.непрочитано = max(победитель.непрочитано, другая.непрочитано)
            /* TestFlight, владелец: «последние сообщения в чате не отразились в общем списке». Сайт оставляет запись
               источника-победителя целиком (lead > buyer > dm), а переписку покупки (openBuyerChat → openDM с
               tid = chat_id) пишет dm.php: у buyer_chats last_msg и updated отстают, свежие — у записи dm.php. Тип,
               теги, куда вести — по-прежнему победителя; превью и время — той записи, где сообщение новее. */
            победитель.взятьПоследнее(у: другая)
            поНомеру[запись.номер] = победитель
        }
        let склеенные: [СтрокаИнбокса] = порядокНомеров.compactMap { поНомеру[$0] }
        let упорядоченные = упорядочить(склеенные)
        /* window._acwMeta сайта: после сортировки meta каждой записи кладётся в общую карту по номеру товара
           (product_id || listing_id), и _msgAv / _msgSubline берут её ОТТУДА, а не из своей записи. Одна покупка часто
           приходит только из dm.php list без meta, а её товар — ещё и в buyer_chats с meta: у сайта у обеих строк фото
           и раздел, у приложения до этого фото было лишь у той записи, где пришла своя meta. Позже в порядке —
           главнее (JS перезаписывает ключ); без номера товара у сайта меты нет вовсе. */
        var метаПоТовару: [String: МетаИнбокса] = [:]
        for строка in упорядоченные {
            let товар = строка.объявлениеID
            if !товар.isEmpty, let мета = строка.своиМета { метаПоТовару[товар] = мета }
        }
        return упорядоченные.map { исходная in
            var строка = исходная
            строка.применить(строка.объявлениеID.isEmpty ? nil : метаПоТовару[строка.объявлениеID])
            return строка
        }
    }

    /**
     Порядок loadMessages: сначала с непрочитанными, потом новые сверху. Сайт сравнивает строки updated; здесь — время
     последнего сообщения (большее из updated и времени строки), разобранное в дату: у dm.php last.at бывает новее
     updated, а время, известное из открытой переписки, может прийти в другом виде, чем updated списка. Не разобралось —
     строки updated, как у сайта. Array.sort в Swift не обязан быть устойчивым, а сайт (Array.prototype.sort) устойчив:
     одинаковые остаются в порядке прихода. Закреплённые поднимает наверх ИнбоксМодель.видимые.
     */
    nonisolated static func упорядочить(_ строки: [СтрокаИнбокса]) -> [СтрокаИнбокса] {
        let ключи: [(строка: СтрокаИнбокса, место: Int, время: Date?)] = строки.enumerated().map { пара in
            (строка: пара.element, место: пара.offset, время: пара.element.свежесть)
        }
        let упорядоченные = ключи.sorted { a, b in
            let aНов = a.строка.непрочитано > 0 ? 1 : 0
            let bНов = b.строка.непрочитано > 0 ? 1 : 0
            if aНов != bНов { return aНов > bНов }
            if let aВ = a.время, let bВ = b.время {
                if aВ != bВ { return aВ > bВ }
            } else if a.строка.порядок != b.строка.порядок {
                return a.строка.порядок > b.строка.порядок
            }
            return a.место < b.место
        }
        return упорядоченные.map { $0.строка }
    }

    // MARK: - Действия со строкой

    enum ИтогДействия: Equatable {
        case готово
        case ошибка(String)
    }

    /**
     msgPin: POST cabinet.php?action=chat_pin {csrf, id, on} → ok, pins[] (новый список). Больше пяти — сайт отказывает
     сам, до запроса («Можно закрепить максимум 5 чатов»); это проверяет модель.
     */
    static func закрепить(_ номер: String, да включить: Bool) async -> (ИтогДействия, [String]?) {
        do {
            let j = try await отправить("cabinet.php?action=chat_pin", тело: ["id": номер, "on": включить])
            if З.да(j["ok"]) {
                let список = ((j["pins"] as? [Any]) ?? []).map { З.строка($0) }
                return (.готово, список)
            }
            return (.ошибка(текстОшибки(j, запасной: ИнбоксText.т("err_generic"))), nil)
        } catch {
            return (.ошибка(ИнбоксText.т("err_no_conn")), nil)
        }
    }

    /// msgHide / msgRestore / msgPurge: POST api/chat_hide.php {type, id, op} — без токена, путь относительный
    /// (/kz/<язык>/api/chat_hide.php, §6.0.2). purge — только после вопроса (его задаёт экран).
    static func корзина(_ строка: СтрокаИнбокса, оп: String) async -> ИтогДействия {
        do {
            let j = try await отправитьБезТокена("api/chat_hide.php",
                                                 тело: ["type": строка.тип, "id": строка.номер, "op": оп])
            if З.да(j["ok"]) { return .готово }
            return .ошибка(текстОшибки(j, запасной: ИнбоксText.т("err_generic")))
        } catch {
            return .ошибка(ИнбоксText.т("err_no_conn"))
        }
    }

    /**
     Метка диалога: dmSetLabel — POST dm.php {action: "set_label", me_id, thread_id, label}; lcmSetLabel — POST
     chat.php?action=set_label {chat_id, label}. Оба без токена. ok → «Метка сохранена ✓», иначе error или «Ошибка».
     */
    static func метка(_ ключ: String, лид: Bool, номер: String) async -> ИтогДействия {
        do {
            let j: [String: Any]
            if лид {
                j = try await отправитьБезТокена("chat.php?action=set_label", тело: ["chat_id": номер, "label": ключ])
            } else {
                let я = await мойНомер(ждать: true)
                j = try await отправитьБезТокена("dm.php", тело: ["action": "set_label", "me_id": я,
                                                                  "thread_id": номер, "label": ключ])
            }
            if З.да(j["ok"]) { return .готово }
            let текст = З.строка(j["error"])
            return .ошибка(текст.isEmpty ? ИнбоксText.т("err_generic") : текст)
        } catch {
            return .ошибка(ИнбоксText.т("err_no_conn"))
        }
    }

    /**
     Серверный поиск по переписке (msgSearchInput модуля deals): GET chat.php?action=search&q=<запрос> → results[{id,
     snip}] или ids[]. Только чтение; не ответил — остаётся поиск по строкам.
     */
    static func найти(_ запрос: String) async -> [String: String]? {
        guard let j = try? await получить("chat.php?action=search&q=" + вАдрес(запрос), ждать: false),
              З.да(j["ok"]) else { return nil }
        var найдено: [String: String] = [:]
        if let результаты = j["results"] as? [[String: Any]] {
            for р in результаты {
                let номер = З.строка(р["id"])
                if !номер.isEmpty { найдено[номер] = З.строка(р["snip"]) }
            }
        } else {
            for номер in (j["ids"] as? [Any]) ?? [] {
                let н = З.строка(номер)
                if !н.isEmpty { найдено[н] = "" }
            }
        }
        return найдено
    }

    // MARK: - Со страницы кабинета

    /// const CHAT_PINS = [...] — закреплённые чаты, как их напечатал сервер.
    nonisolated static func закреплённые(_ html: String) -> [String]? {
        guard let r = html.range(of: "CHAT_PINS\\s*=\\s*\\[[^\\]]*\\]", options: .regularExpression) else { return nil }
        let кусок = String(html[r])
        guard let начало = кусок.firstIndex(of: "[") else { return nil }
        let массив = String(кусок[начало...])
        guard let данные = массив.data(using: .utf8),
              let список = (try? JSONSerialization.jsonObject(with: данные)) as? [Any] else { return nil }
        return список.map { З.строка($0) }
    }

    /// const HELP_URL = "\/kz\/ru\/help" — «Справочный центр».
    nonisolated static func справка(_ html: String) -> String? {
        guard let r = html.range(of: "HELP_URL\\s*=\\s*\"[^\"]*\"", options: .regularExpression) else { return nil }
        let кусок = String(html[r])
        guard let первая = кусок.firstIndex(of: "\"") else { return nil }
        var путь = String(кусок[кусок.index(after: первая)...])
        if путь.hasSuffix("\"") { путь.removeLast() }
        путь = путь.replacingOccurrences(of: "\\/", with: "/")
        return путь.isEmpty ? nil : путь
    }
}

extension КабинетСайта {
    /// Этап 45: то же правило «машинный код», что у машинныйКод, — для nonisolated разбора (регулярное выражение сайта).
    nonisolated static func машинныйКодБезГлавной(_ ошибка: String) -> Bool {
        ошибка.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil
    }
}

// MARK: - Строка инбокса

/// meta{img, catIcon, catName, catColor} записи инбокса — то, что сайт кладёт в window._acwMeta.
struct МетаИнбокса: Equatable {
    var обложка: String
    var значок: String
    var раздел: String
    var цвет: String
}

/// Последнее сообщение, известное по открытой переписке (время — сервера, из самой переписки): им строка списка
/// обновляется сразу, не дожидаясь ответа списка (ИнбоксМодель.вПереписке).
struct ПоследнееВПереписке: Equatable {
    var текст: String
    var моё: Bool
    /// Значок превью: календарь (аренда) или «повтор» (обмен), как у init(dm:).
    var значок: String?
    var когда: String
}

/// Одна строка «Чата» кабинета — диалог dm.php, лид chat.php или покупка chat.php (_msgRowDm / _msgRowLead / _msgRowBuyer).
struct СтрокаИнбокса: Identifiable, Equatable {
    enum Источник: String, Equatable {
        case dm, lead, buyer

        /// {lead:0, buyer:1, dm:2} сайта: меньше — главнее при склейке.
        var приоритет: Int {
            switch self {
            case .lead: return 0
            case .buyer: return 1
            case .dm: return 2
            }
        }
    }

    let источник: Источник
    /// tid (dm) или chat_id (lead, buyer).
    let номер: String
    var id: String { номер }
    var имя: String = ""
    /// Время в строке (_msgTimeTag).
    var когда: String = ""
    /// updated — порядок списка.
    var порядок: String = ""
    /// created_at — «с какого числа» (msg-since).
    var начат: String = ""
    var объявлениеID: String = ""
    /// Третья часть подстроки: название объявления (dm, buyer) или состояние лида.
    var подпись: String = ""
    var статусОбъявления: String = ""
    /// Превью последнего сообщения.
    var превью: String = ""
    /// Превью — «Вы: …» (своё не-служебное сообщение dm).
    var превьюМоё: Bool = false
    /// Значок превью: календарь (запрос аренды) или «повтор» (обмен).
    var значокПревью: String? = nil
    var непрочитано: Int = 0
    var скрыт: Bool = false
    var виды: [String] = []
    /// kinds пришли в ответе этого источника (JS: a.data.kinds — массив, даже пустой, считается «есть»).
    var видыИзОтвета: [String]? = nil
    var метка: String = ""
    /// status лида: ai | hot_lead | seller_active | closed.
    var статусЛида: String = ""
    /// peer_id (dm, buyer); у лида — buyer_id, если список его прислал (шапка чата ведёт на витрину собеседника).
    var собеседник: String = ""
    var собеседникУдалён: Bool = false
    /// meta.img / meta.catIcon / meta.catName / meta.catColor (_msgAv, _msgSubline) — уже после общей карты сайта
    /// (_acwMeta, см. ИнбоксAPI.склеить): у строки то, что сайт нарисовал бы для её товара.
    var обложка: String = ""
    /// meta.catIcon — SVG значка корневого раздела (MK_CATS[].icon); что рисовать — ЗначокРаздела.
    var значокРаздела: String = ""
    var раздел: String = ""
    var цветРаздела: String = ""
    /// meta своей записи, как пришла (nil — поля meta не было). Из них склейка собирает карту по товару.
    var своиМета: МетаИнбокса? = nil
    /// Весь текст строки для поиска (_msgHay), в нижнем регистре.
    var стог: String = ""

    /// Время последнего сообщения строки: большее из времени строки (last.at у dm) и updated. nil — не разобралось.
    var свежесть: Date? {
        let a = ИнбоксВремя.дата(когда)
        let b = ИнбоксВремя.дата(порядок)
        switch (a, b) {
        case let (.some(x), .some(y)): return max(x, y)
        case let (.some(x), .none): return x
        case let (.none, .some(y)): return y
        case (.none, .none): return nil
        }
    }

    /**
     Склейка: у другой записи того же диалога сообщение новее — её превью и время (тип и теги остаются свои).

     TestFlight, владелец: «последние сообщения не видны в общих сообщениях, которые я присылал». Запись dm.php знает
     само последнее сообщение (last{text, mine, at}), а buyer_chats и leads — только last_msg и время чата updated, без
     автора. При одном и том же времени (одно сообщение в двух ответах) склейка оставляла запись-победителя: превью без
     «Вы: », а при updated, сдвинутом на секунду-другую позже last.at, — ещё и прежний текст. Теперь запись dm.php
     главнее, если её сообщение не старше времени победителя больше чем на запас (секунды записи одного сообщения).
     */
    mutating func взятьПоследнее(у другая: СтрокаИнбокса) {
        guard let её = другая.свежесть else { return }
        let изПереписки = другая.источник == .dm && источник != .dm && !другая.превью.isEmpty
        if let моя = свежесть {
            let запас: TimeInterval = изПереписки ? Self.запасСклейки : 0
            if моя > её.addingTimeInterval(запас) {
                /* Тот же текст у записи dm.php — её «Вы: » (у buyer_chats и leads признака автора нет). */
                if изПереписки && другая.превью == превью { превьюМоё = другая.превьюМоё && источник != .lead }
                return
            }
            if моя == её && !изПереписки { return }
        }
        превью = другая.превью
        превьюМоё = другая.превьюМоё && источник != .lead
        значокПревью = другая.значокПревью
        let время = другая.когда.isEmpty ? другая.порядок : другая.когда
        /* Время строки не уходит назад: у победителя updated мог быть на секунды позже last.at записи dm.php. */
        if let моя = свежесть, моя > её {
            if когда.isEmpty { когда = время }
        } else {
            когда = время
            порядок = другая.порядок.isEmpty ? когда : другая.порядок
        }
        стог += " " + другая.превью.lowercased()
    }

    /// Секунды между last.at сообщения (dm.php) и updated того же чата (buyer_chats, leads), которые считаются одним
    /// событием: сервер ставит их двумя записями одного запроса.
    static let запасСклейки: TimeInterval = 5

    /**
     Последнее из открытой переписки. true — применено; false — строка уже показывает то же.

     сейчасНаЭкране = true — зовёт открытая переписка: её снимок только что пришёл от сервера и главнее строки списка
     (строка могла прийти с updated, сдвинутым позже самого сообщения, — прежде такое обновление отбрасывалось, и своё
     только что отправленное сообщение не попадало в превью). false — ответ списка сверяется с запомненным: список
     прислал сообщение новее — запомненное забывается.
     */
    mutating func принять(_ последнее: ПоследнееВПереписке, сейчасНаЭкране: Bool = false) -> Bool {
        guard let его = ИнбоксВремя.дата(последнее.когда) else { return false }
        /* Лид сайт показывает без «Вы: » (_msgRowLead: last_msg как есть). */
        let моё = последнее.моё && источник != .lead
        let тоЖе = превью == последнее.текст && превьюМоё == моё && значокПревью == последнее.значок
        if тоЖе { return false }
        /* Список новее запомненного больше чем на запас склейки — это уже другое сообщение (ответ собеседника). */
        if !сейчасНаЭкране, let моя = свежесть, моя > его.addingTimeInterval(Self.запасСклейки) { return false }
        превью = последнее.текст
        превьюМоё = моё
        значокПревью = последнее.значок
        когда = последнее.когда
        порядок = последнее.когда
        стог += " " + последнее.текст.lowercased()
        return true
    }

    /// Тип для chat_hide (_msgHideMeta): dm, buychat, lead.
    var тип: String {
        switch источник {
        case .dm: return "dm"
        case .buyer: return "buychat"
        case .lead: return "lead"
        }
    }

    private typealias З = МоиОбъявленияAPI

    /// _msgRowDm.
    init?(dm t: [String: Any]) {
        let tid = З.строка(t["tid"])
        guard !tid.isEmpty else { return nil }
        источник = .dm
        номер = tid
        let пир = З.строка(t["peer_name"])
        собеседникУдалён = З.да(t["peer_gone"])
        имя = пир.isEmpty ? ИнбоксText.т(собеседникУдалён ? "user_deleted" : "user") : пир
        let последнее = (t["last"] as? [String: Any]) ?? [:]
        let at = З.строка(последнее["at"])
        когда = at.isEmpty ? З.строка(t["updated"]) : at
        порядок = З.строка(t["updated"])
        начат = З.строка(t["created_at"])
        объявлениеID = З.строка(t["listing_id"])
        подпись = З.строка(t["listing_title"])
        статусОбъявления = З.строка(t["item_status"])
        непрочитано = max(0, З.целое(t["unread"]))
        скрыт = З.да(t["hidden"])
        видыИзОтвета = Self.виды(t["kinds"])
        виды = видыИзОтвета ?? []
        метка = З.строка(t["label"])
        собеседник = З.строка(t["peer_id"])
        let типПоследнего = З.строка(последнее["type"])
        let текст = З.строка(последнее["text"])
        switch типПоследнего {
        case "rental":
            значокПревью = "calendar"
            превью = ИнбоксText.т("rental_req")
        case "exchange":
            значокПревью = "arrow.2.squarepath"
            превью = ИнбоксText.т("exchange_offer")
        default:
            /* Служебное — без «Вы: » (сайт: type === "system"); правило то же, что у переписки (ЧатСообщение). */
            let служебное = ЧатСообщение.этоУведомление(роль: З.строка(последнее["role"]),
                                                        вид: З.строка(последнее["kind"]),
                                                        тип: типПоследнего.isEmpty ? "text" : типПоследнего,
                                                        текст: текст)
            превью = текст
            превьюМоё = З.да(последнее["mine"]) && !служебное
        }
        разобратьМета(t["meta"])
        стог = (пир + " " + подпись + " " + текст).lowercased()
    }

    /// _msgRowLead.
    init?(лид t: [String: Any]) {
        let cid = З.строка(t["chat_id"])
        guard !cid.isEmpty else { return nil }
        источник = .lead
        номер = cid
        let покупатель = З.строка(t["buyer_name"])
        имя = покупатель.isEmpty ? ИнбоксText.т("buyer") : покупатель
        let обновлён = З.строка(t["updated"])
        начат = З.строка(t["created_at"])
        когда = обновлён.isEmpty ? начат : обновлён
        порядок = когда
        объявлениеID = З.строка(t["product_id"])
        статусЛида = З.строка(t["status"])
        подпись = Self.состояниеЛида(статусЛида)
        статусОбъявления = З.строка(t["item_status"])
        непрочитано = max(0, З.целое(t["unread"]))
        скрыт = З.да(t["hidden"])
        видыИзОтвета = Self.виды(t["kinds"])
        виды = видыИзОтвета ?? []
        метка = З.строка(t["label"])
        /* _msgRowLead сайта номер покупателя не читает; пришёл в строке — берём, нет — его пришлёт seller_chat
           (buyer_id, _lcmApply). */
        let покупательID = З.строка(t["buyer_id"])
        собеседник = покупательID.isEmpty ? З.строка(t["peer_id"]) : покупательID
        let последнее = З.строка(t["last_msg"])
        превью = последнее.isEmpty ? подпись : последнее
        разобратьМета(t["meta"])
        стог = (покупатель + " " + З.строка(t["title"]) + " " + последнее).lowercased()
    }

    /// _msgRowBuyer.
    init?(покупка t: [String: Any]) {
        let cid = З.строка(t["chat_id"])
        guard !cid.isEmpty else { return nil }
        источник = .buyer
        номер = cid
        let продавец = З.строка(t["seller_name"])
        имя = продавец.isEmpty ? ИнбоксText.т("user") : продавец
        let обновлён = З.строка(t["updated"])
        начат = З.строка(t["created_at"])
        когда = обновлён.isEmpty ? начат : обновлён
        порядок = обновлён
        объявлениеID = З.строка(t["product_id"])
        собеседник = З.строка(t["peer_id"])
        подпись = З.строка(t["title"])
        статусОбъявления = З.строка(t["item_status"])
        непрочитано = max(0, З.целое(t["unread"]))
        скрыт = З.да(t["hidden"])
        видыИзОтвета = Self.виды(t["kinds"])
        виды = видыИзОтвета ?? []
        let последнее = З.строка(t["last_msg"])
        превью = последнее
        разобратьМета(t["meta"])
        стог = (продавец + " " + подпись + " " + последнее).lowercased()
    }

    /// kinds[] ответа; нет массива — nil (у склейки это «взять с другой записи»).
    private static func виды(_ значение: Any?) -> [String]? {
        guard let массив = значение as? [Any] else { return nil }
        return массив.map { элемент in З.строка(элемент) }
    }

    private mutating func разобратьМета(_ значение: Any?) {
        guard let m = значение as? [String: Any] else { return }
        let мета = МетаИнбокса(обложка: З.строка(m["img"]), значок: З.строка(m["catIcon"]),
                               раздел: З.строка(m["catName"]), цвет: З.строка(m["catColor"]))
        своиМета = мета
        применить(мета)
    }

    /// Поля аватара и подстроки из meta (или пусто, если у товара меты нет).
    mutating func применить(_ мета: МетаИнбокса?) {
        обложка = мета?.обложка ?? ""
        значокРаздела = мета?.значок ?? ""
        раздел = мета?.раздел ?? ""
        цветРаздела = мета?.цвет ?? ""
    }

    /// {ai, hot_lead, seller_active, closed} → подпись строки лида.
    static func состояниеЛида(_ статус: String) -> String {
        switch статус {
        case "ai": return ИнбоксText.т("lead_ai")
        case "hot_lead": return ИнбоксText.т("lead_hot")
        case "seller_active": return ИнбоксText.т("lead_active")
        case "closed": return ИнбоксText.т("lead_closed")
        default: return ""
        }
    }

    /// Куда ведёт нажатие (openDM / openLeadChat / openBuyerChat).
    var цель: ЧатЦель {
        switch источник {
        case .lead:
            return .лид(номер: номер, имя: имя, покупатель: собеседник)
        case .dm:
            return .переписка(номер: номер, собеседник: собеседник, имя: имя, объявление: объявлениеID)
        case .buyer:
            /* openBuyerChat: есть chat_id и peer_id — DM-окно с tid = chat_id; иначе — чат виджета витрины по товару
               (ulx_open_chat → /marketplace), у приложения это чат объявления этапа 38. */
            if !собеседник.isEmpty || объявлениеID.isEmpty {
                /* Без товара чата виджета нет — переписка по номеру (без собеседника ChatThreadModel читает её опросом). */
                return .переписка(номер: номер, собеседник: собеседник, имя: имя, объявление: объявлениеID)
            }
            return .объявление(Listing(номер: объявлениеID), предложить: false)
        }
    }
}

// MARK: - Время строк (_msgWhen, reqTimeAgo)

enum ИнбоксВремя {
    /// Сейчас — ISO 8601 с поясом (дата() разберёт его однозначно): время своего сообщения, если сервер его не прислал.
    static func сейчас() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: Date())
    }

    /// Разбор времени сервера: ISO 8601 (с поясом или без) и «yyyy-MM-dd HH:mm:ss». Без пояса — время телефона, как
    /// new Date(...) в браузере.
    static func дата(_ строка: String) -> Date? {
        let s = строка.trimmingCharacters(in: .whitespaces)
        guard s.count >= 10 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.timeZone = TimeZone.current
        for формат in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            ф.dateFormat = формат
            let длина = min(s.count, формат.replacingOccurrences(of: "'", with: "").count)
            if let d = ф.date(from: String(s.prefix(длина))) { return d }
        }
        return nil
    }

    /// _msgWhen: сегодня — «чч:мм», этот год — «d мес», иначе «дд.мм.гг».
    static func коротко(_ строка: String) -> String {
        guard let д = дата(строка) else { return "" }
        let календарь = Calendar.current
        let ф = DateFormatter()
        ф.locale = ИнбоксText.локаль
        if календарь.isDateInToday(д) {
            ф.dateFormat = "HH:mm"
        } else if календарь.component(.year, from: д) == календарь.component(.year, from: Date()) {
            ф.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            ф.dateFormat = "dd.MM.yy"
        }
        return ф.string(from: д)
    }

    /// Время сообщения «чч:мм» (toLocaleTimeString ru-RU).
    static func время(_ строка: String) -> String {
        guard let д = дата(строка) else { return "" }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "HH:mm"
        return ф.string(from: д)
    }

    /// reqTimeAgo: «только что», «N мин назад», «N ч назад», «N дней назад», дальше — дата «d мес».
    static func назад(_ строка: String) -> String {
        guard let д = дата(строка) else { return "" }
        let сек = max(0, Int(Date().timeIntervalSince(д)))
        if сек < 60 { return ИнбоксText.т("ago_now") }
        let мин = сек / 60
        if мин < 60 { return String(format: ИнбоксText.т("ago_min"), мин) }
        let ч = мин / 60
        if ч < 24 { return String(format: ИнбоксText.т("ago_h"), ч) }
        let дн = ч / 24
        if дн < 7 { return ИнбоксText.дней(дн) }
        let ф = DateFormatter()
        ф.locale = ИнбоксText.локаль
        ф.setLocalizedDateFormatFromTemplate("dMMM")
        return ф.string(from: д)
    }
}
