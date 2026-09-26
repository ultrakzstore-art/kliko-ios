import Foundation

/**
 БИЗНЕС-РАЗДЕЛЫ КАБИНЕТА — ЗАПРОСЫ И ДАННЫЕ (этап 50, владелец: «всё приложение нативным»).

 Раньше «Счета», «Журнал», «Коммерческие предложения», «Аналитика» и «Разделы магазина» открывали кабинет сайта. Теперь
 это свои экраны на тех же вызовах, что у докачанного модуля js/cabinet-business.min.js (и shopSecLoad в
 js/cabinet.min.js). Транспорт — КабинетСайта через МоиОбъявленияAPI (fetch изнутри страницы сайта, её куки и токен):
   · GET  cabinet.php?action=analytics                          → {ok, stats{views, active, deals_done, in_progress,
                                                                     deals_total, revenue, conversion, rating, reviews,
                                                                     top[{title, views, wholesale}]}} (showAnalytics);
   · POST b2b_journal {csrf, period}                            → {ok, totals{count, sum, paid, paid_sum, vat, cancelled},
                                                                     rows[{id, no, at, paid_at, buyer, guest, bin, total,
                                                                     vat, status, doc_url}]} (jrnLoad);
   · POST b2b_ledger {csrf, period, scope: ""|"stock"}         → {ok, rows[{at, event, data{…}}]} (jrnLogLoad);
   · POST invoice_list {csrf, role: "buyer"}                    → {ok, invoices[{type, no, date, total, company{name},
                                                                     seller_name}]} (invLoad — «Полученные счета»);
   · POST kp_list {csrf, role: "seller"|"buyer"}                → {ok, requests[…], quota{left, lim}} (kpLoad);
   · POST b2b_orders_list {csrf}                                — уже в БизнесМодель (этап 48).
 Запись — только по нажатию и, где сайт спрашивает, после того же вопроса:
   · b2b_order_status {csrf, id, status} (b2bStatus: confirmed · paid · shipped · done · cancelled);
   · kp_generate {csrf, kp_id, mode: "template"|"ai", tpl: "formal"|"short"|""} → {ok, text, quota} | no_company | need_pro;
   · kp_send {csrf, kp_id, text, tpl, accent, size, foot} — оформление по умолчанию сайта (bar, #16a34a, m, req);
   · kp_decline {csrf, kp_id};
   · shop_sections_list {csrf} / shop_sections_save {csrf, sections[{id, name}]} (shopSecLoad / shopSecSave).
 Денег здесь нет: «Оплата пришла» — отметка продавца о безналичной оплате счёта B2B, а не платёж в приложении.
 Печать документов (счёт, накладная, акт, счёт-фактура, КП в PDF), печать и подпись с eGov, прайс-лист, налоговый модуль
 и интеграции — страницей кабинета сайта.
 */
@MainActor
enum БизнесРазделыAPI {
    typealias A = МоиОбъявленияAPI

    /// Сбой раздела: текст для человека и признак «нужен вход».
    struct Сбой: Error {
        let текст: String
        var нуженВход = false
        var нуженПРО = false
    }

    private static func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Ответ сервера → словарь или Сбой со словами сервера (ulxErr сайта), «Ошибка», «Нет соединения».
    private static func проверить(_ j: [String: Any]?) throws -> [String: Any] {
        guard let j else { throw Сбой(текст: т("err_generic")) }
        if A.нетСессии(j) { throw Сбой(текст: CabinetText.т("signed_out"), нуженВход: true) }
        guard A.да(j["ok"]) else {
            let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let про = A.да(j["need_pro"]) || A.да(j["need_tier"])
            if ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) {
                throw Сбой(текст: про ? БизнесРазделыText.т("pro_need") : т("err_generic"), нуженПРО: про)
            }
            throw Сбой(текст: ошибка, нуженПРО: про)
        }
        return j
    }

    private static func получить(_ хвост: String) async throws -> [String: Any] {
        do {
            return try проверить(try await A.получить(хвост))
        } catch let с as Сбой {
            throw с
        } catch {
            throw Сбой(текст: т("no_conn"))
        }
    }

    private static func отправить(_ хвост: String, _ тело: [String: Any]) async throws -> [String: Any] {
        do {
            return try проверить(try await A.отправить(хвост, тело: тело))
        } catch let с as Сбой {
            throw с
        } catch {
            throw Сбой(текст: т("no_conn"))
        }
    }

    // MARK: - Аналитика

    static func аналитика() async throws -> АналитикаМагазина {
        let j = try await получить("cabinet.php?action=analytics")
        return АналитикаМагазина((j["stats"] as? [String: Any]) ?? [:])
    }

    // MARK: - Журнал

    static func журнал(период: String) async throws -> ЖурналСчетов {
        let j = try await отправить("cabinet.php?action=b2b_journal", ["period": период])
        return ЖурналСчетов(j)
    }

    static func действия(период: String, склад: Bool) async throws -> [СобытиеЖурнала] {
        let j = try await отправить("cabinet.php?action=b2b_ledger", ["period": период, "scope": склад ? "stock" : ""])
        let строки: [Any] = (j["rows"] as? [Any]) ?? []
        var итог: [СобытиеЖурнала] = []
        for (номер, запись) in строки.enumerated() {
            if let с = запись as? [String: Any] { итог.append(СобытиеЖурнала(с, номер: номер)) }
        }
        return итог
    }

    // MARK: - Счета

    static func полученныеСчета() async throws -> [ПолученныйДокумент] {
        let j = try await отправить("cabinet.php?action=invoice_list", ["role": "buyer"])
        let строки: [Any] = (j["invoices"] as? [Any]) ?? []
        var итог: [ПолученныйДокумент] = []
        for (номер, запись) in строки.enumerated() {
            if let с = запись as? [String: Any] { итог.append(ПолученныйДокумент(с, номер: номер)) }
        }
        return итог
    }

    /// b2bStatus сайта. nil — готово; иначе текст ошибки.
    static func статусЗаказа(_ id: String, _ статус: String) async -> String? {
        do {
            _ = try await отправить("cabinet.php?action=b2b_order_status", ["id": id, "status": статус])
            return nil
        } catch let с as Сбой {
            return с.текст
        } catch {
            return т("no_conn")
        }
    }

    // MARK: - Коммерческие предложения

    static func запросыКП(роль: String) async throws -> (запросы: [ЗапросКП], квота: КвотаКП?) {
        let j = try await отправить("cabinet.php?action=kp_list", ["role": роль])
        let строки: [Any] = (j["requests"] as? [Any]) ?? []
        let запросы = строки.compactMap { запись -> ЗапросКП? in
            guard let с = запись as? [String: Any] else { return nil }
            return ЗапросКП(с)
        }.filter { !$0.id.isEmpty }
        return (запросы, КвотаКП(j["quota"]))
    }

    enum ИтогКП {
        case текст(String, КвотаКП?)
        case нужныРеквизиты
        case нуженПРО
        case ошибка(String, КвотаКП?)
    }

    /// kpGen сайта.
    static func сформироватьКП(_ id: String, ии: Bool, шаблон: String) async -> ИтогКП {
        do {
            let тело: [String: Any] = ["kp_id": id, "mode": ии ? "ai" : "template", "tpl": шаблон]
            let j = try await A.отправить("cabinet.php?action=kp_generate", тело: тело)
            if A.нетСессии(j) { return .ошибка(CabinetText.т("signed_out"), nil) }
            let квота = КвотаКП(j["quota"])
            if A.да(j["ok"]) { return .текст(A.строка(j["text"]), квота) }
            if A.да(j["no_company"]) { return .нужныРеквизиты }
            if A.да(j["need_pro"]) { return .нуженПРО }
            let ошибка = A.строка(j["error"])
            return .ошибка(ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? т("err_generic") : ошибка, квота)
        } catch {
            return .ошибка(т("no_conn"), nil)
        }
    }

    /// kpSend сайта с оформлением по умолчанию. nil — отправлено.
    static func отправитьКП(_ id: String, текст: String) async -> String? {
        do {
            _ = try await отправить("cabinet.php?action=kp_send",
                                    ["kp_id": id, "text": текст, "tpl": "bar", "accent": "#16a34a", "size": "m",
                                     "foot": "req"])
            return nil
        } catch let с as Сбой {
            return с.текст
        } catch {
            return т("no_conn")
        }
    }

    static func отклонитьКП(_ id: String) async -> String? {
        do {
            _ = try await отправить("cabinet.php?action=kp_decline", ["kp_id": id])
            return nil
        } catch let с as Сбой {
            return с.текст
        } catch {
            return т("no_conn")
        }
    }

    // MARK: - Разделы магазина

    static func разделы() async throws -> [РазделМагазина] {
        let j = try await отправить("cabinet.php?action=shop_sections_list", [:])
        let строки: [Any] = (j["sections"] as? [Any]) ?? []
        return строки.compactMap { запись -> РазделМагазина? in
            guard let с = запись as? [String: Any] else { return nil }
            return РазделМагазина(id: A.строка(с["id"]), название: A.строка(с["name"]))
        }
    }

    static func сохранитьРазделы(_ разделы: [РазделМагазина]) async throws -> [РазделМагазина] {
        let тело: [[String: Any]] = разделы.compactMap { р in
            let имя = р.название.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !имя.isEmpty else { return nil }
            return ["id": р.id, "name": имя]
        }
        let j = try await отправить("cabinet.php?action=shop_sections_save", ["sections": тело])
        let строки: [Any] = (j["sections"] as? [Any]) ?? []
        return строки.compactMap { запись -> РазделМагазина? in
            guard let с = запись as? [String: Any] else { return nil }
            return РазделМагазина(id: A.строка(с["id"]), название: A.строка(с["name"]))
        }
    }
}

// MARK: - Данные

/// stats ответа analytics (renderAnalytics сайта).
struct АналитикаМагазина: Equatable {
    struct Товар: Equatable, Identifiable {
        let id: Int
        let название: String
        let просмотры: Int
        let опт: Bool
    }

    let просмотры: Int
    let активных: Int
    let сделокЗавершено: Int
    let вПроцессе: Int
    let сделокВсего: Int
    let выручка: Int
    let конверсия: String
    let рейтинг: String
    let отзывов: Int
    let топ: [Товар]

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        просмотры = A.целое(j["views"])
        активных = A.целое(j["active"])
        сделокЗавершено = A.целое(j["deals_done"])
        вПроцессе = A.целое(j["in_progress"])
        сделокВсего = A.целое(j["deals_total"])
        выручка = A.целое(j["revenue"])
        let к = A.строка(j["conversion"])
        конверсия = к.isEmpty ? "0" : к
        let р = A.строка(j["rating"])
        рейтинг = (р.isEmpty || р == "0") ? "—" : р
        отзывов = A.целое(j["reviews"])
        let сырые: [Any] = (j["top"] as? [Any]) ?? []
        var товары: [Товар] = []
        for (номер, запись) in сырые.enumerated() {
            guard let т = запись as? [String: Any] else { continue }
            let имя = A.строка(т["title"])
            товары.append(Товар(id: номер, название: имя.isEmpty ? "—" : имя, просмотры: A.целое(т["views"]),
                                опт: A.да(т["wholesale"])))
        }
        топ = товары
    }
}

/// Строка журнала счетов (jrnRender).
struct СчётЖурнала: Equatable, Identifiable {
    let id: String
    let номер: String
    let дата: String
    let оплачен: String
    let покупатель: String
    let гость: Bool
    let бин: String
    let сумма: Int
    let ндс: Int
    let статус: String
    let документ: String

    init(_ j: [String: Any], запасной: Int) {
        typealias A = МоиОбъявленияAPI
        let свой = A.строка(j["id"])
        id = свой.isEmpty ? "row-" + String(запасной) : свой
        номер = A.строка(j["no"])
        дата = A.строка(j["at"])
        оплачен = A.строка(j["paid_at"])
        покупатель = A.строка(j["buyer"])
        гость = A.да(j["guest"])
        бин = A.строка(j["bin"])
        сумма = КошелёкAPI.тенге(j["total"])
        ндс = КошелёкAPI.тенге(j["vat"])
        let с = A.строка(j["status"])
        статус = с.isEmpty ? "new" : с
        документ = A.строка(j["doc_url"])
    }

    /// Месяц счёта «2026-03» для графика: из «2026-03-14 …» или «14.03.2026».
    var месяц: String? { ЖурналСчетов.месяц(дата) }
}

/// Ответ b2b_journal.
struct ЖурналСчетов: Equatable {
    let выписано: Int
    let выписаноСумма: Int
    let проведено: Int
    let проведеноСумма: Int
    let ндс: Int
    let отменено: Int
    let строки: [СчётЖурнала]

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let итоги = (j["totals"] as? [String: Any]) ?? [:]
        выписано = A.целое(итоги["count"])
        выписаноСумма = КошелёкAPI.тенге(итоги["sum"])
        проведено = A.целое(итоги["paid"])
        проведеноСумма = КошелёкAPI.тенге(итоги["paid_sum"])
        ндс = КошелёкAPI.тенге(итоги["vat"])
        отменено = A.целое(итоги["cancelled"])
        let сырые: [Any] = (j["rows"] as? [Any]) ?? []
        var итог: [СчётЖурнала] = []
        for (номер, запись) in сырые.enumerated() {
            if let с = запись as? [String: Any] { итог.append(СчётЖурнала(с, запасной: номер)) }
        }
        строки = итог
    }

    /// Сумма по месяцам: выписано (без отменённых) и оплачено — для графика.
    struct Месяц: Identifiable, Equatable {
        let месяц: String
        let вид: String
        let сумма: Int
        var id: String { месяц + "|" + вид }
    }

    func поМесяцам(выписано подписьВыписано: String, оплачено подписьОплачено: String) -> [Месяц] {
        var выписано: [String: Int] = [:]
        var оплачено: [String: Int] = [:]
        for строка in строки where строка.статус != "cancelled" {
            guard let м = строка.месяц else { continue }
            выписано[м, default: 0] += строка.сумма
            if ["paid", "shipped", "done"].contains(строка.статус) {
                оплачено[м, default: 0] += строка.сумма
            }
        }
        var итог: [Месяц] = []
        for м in выписано.keys.sorted() {
            итог.append(Месяц(месяц: м, вид: подписьВыписано, сумма: выписано[м] ?? 0))
            итог.append(Месяц(месяц: м, вид: подписьОплачено, сумма: оплачено[м] ?? 0))
        }
        return итог
    }

    static func месяц(_ дата: String) -> String? {
        let d = дата.trimmingCharacters(in: .whitespaces)
        if let r = d.range(of: "^\\d{4}-\\d{2}", options: .regularExpression) { return String(d[r]) }
        if let r = d.range(of: "\\d{2}\\.\\d{2}\\.\\d{4}", options: .regularExpression) {
            let части = d[r].split(separator: ".")
            if части.count == 3 { return String(части[2]) + "-" + String(части[1]) }
        }
        return nil
    }
}

/// Строка «Склад» / «Действия» (jrnLogRender).
struct СобытиеЖурнала: Equatable, Identifiable {
    let id: Int
    let время: String
    let событие: String
    let название: String
    let было: String
    let стало: String
    let изменение: Int
    let номер: String
    let покупатель: String
    let сумма: Int

    init(_ j: [String: Any], номер порядковый: Int) {
        typealias A = МоиОбъявленияAPI
        id = порядковый
        /* (t.at||"").replace("T"," ").slice(0,16).replace(/-/g,".") */
        let сырое = A.строка(j["at"]).replacingOccurrences(of: "T", with: " ")
        время = String(сырое.prefix(16)).replacingOccurrences(of: "-", with: ".")
        событие = A.строка(j["event"])
        let д = (j["data"] as? [String: Any]) ?? [:]
        let имя = A.строка(д["title"])
        название = имя.isEmpty ? A.строка(д["item_id"]) : имя
        было = д["was"] == nil || д["was"] is NSNull ? "" : A.строка(д["was"])
        стало = A.строка(д["now"])
        изменение = A.целое(д["delta"])
        номер = A.строка(д["no"])
        let кто = A.строка(д["buyer"])
        покупатель = кто.isEmpty ? A.строка(д["id"]) : кто
        сумма = КошелёкAPI.тенге(д["total"])
    }
}

/// Полученный счёт или документ (invLoad).
struct ПолученныйДокумент: Equatable, Identifiable {
    let id: Int
    let вид: String
    let номер: String
    let дата: String
    let сумма: Int
    let продавец: String

    init(_ j: [String: Any], номер порядковый: Int) {
        typealias A = МоиОбъявленияAPI
        id = порядковый
        вид = A.строка(j["type"])
        номер = A.строка(j["no"])
        дата = A.строка(j["date"])
        сумма = КошелёкAPI.тенге(j["total"])
        let компания = (j["company"] as? [String: Any]) ?? [:]
        let имя = A.строка(компания["name"])
        продавец = имя.isEmpty ? A.строка(j["seller_name"]) : имя
    }
}

/// quota ответа kp_list / kp_generate: сколько Kliko AI-генераций осталось сегодня.
struct КвотаКП: Equatable {
    let осталось: Int
    let лимит: Int

    init?(_ сырое: Any?) {
        guard let j = сырое as? [String: Any] else { return nil }
        осталось = МоиОбъявленияAPI.целое(j["left"])
        лимит = МоиОбъявленияAPI.целое(j["lim"])
    }
}

/// Запрос коммерческого предложения (kp_list).
struct ЗапросКП: Equatable, Identifiable {
    struct Позиция: Equatable, Identifiable {
        let id: Int
        let название: String
        let количество: Int
        let цена: Int
    }

    let id: String
    let статус: String
    let покупатель: String
    let продавец: String
    let создан: String
    let отправлен: String
    let позиции: [Позиция]
    let заметка: String
    let текст: String

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        id = A.строка(j["id"])
        статус = A.строка(j["status"])
        покупатель = A.строка(j["buyer_name"])
        let компания = (j["seller_company"] as? [String: Any]) ?? [:]
        продавец = A.строка(компания["name"])
        создан = A.строка(j["created_at"])
        отправлен = A.строка(j["sent_at"])
        let сырые: [Any] = (j["items"] as? [Any]) ?? []
        var итог: [Позиция] = []
        for (номер, запись) in сырые.enumerated() {
            guard let п = запись as? [String: Any] else { continue }
            /* parseInt(t.qty)||1 сайта. */
            let кол = A.целое(п["qty"])
            итог.append(Позиция(id: номер, название: A.строка(п["title"]), количество: кол > 0 ? кол : 1,
                                цена: A.целое(п["price"])))
        }
        позиции = итог
        заметка = A.строка(j["note"])
        текст = A.строка(j["kp_text"])
    }

    /// kpItemsSum сайта.
    var сумма: Int { позиции.reduce(0) { $0 + $1.цена * $1.количество } }
}

/// Раздел витрины магазина (shop_sections_*).
struct РазделМагазина: Equatable, Identifiable {
    var id: String
    var название: String
    /// Свой ключ строки на экране: у нового раздела id сервера пустой.
    var строка: UUID = UUID()

    init(id: String, название: String) {
        self.id = id
        self.название = название
    }
}
