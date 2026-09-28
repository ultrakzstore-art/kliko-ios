import Foundation

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ЗАПРОСЫ И ДАННЫЕ, ЭТАП 41 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Всё по карте кабинета (§3, §8.3): те же вызовы, те же тела, что у js/cabinet.min.js на главном экране кабинета.
 Транспорт — КабинетСайта.вызвать (этап 40): fetch изнутри страницы сайта под слоем, с её куками, Origin и Referer.

 Только чтение (без токена, как у сайта):
   · GET /kz/<язык>/cabinet.php?action=my_items          → {ok, items[], slots} — все объявления разом, без страниц;
   · GET /kz/<язык>/cabinet.php?action=item_status&id=   → {ok, status, reason, ai_issues[]} — опрос после «Активировать»;
   · GET /api/jobs.php?action=mine                        → {jobs[]} — блок «Работа».
 Запись — только по нажатию, с тем же вопросом, что у сайта (вопрос задаёт экран), тело {csrf, …} JSON:
   · deactivate_item {id} · activate_item {id} (он же «Восстановить») · delete_item {id, reason:"Удалено пользователем"}
   · delete_permanent {id} · toggle_autorenew {item_id, on} · stock_adjust {id, stock} · mod_recheck {id}
   · send_to_manual {id} · /api/jobs.php?action=delete|restore {id}.
 Денег здесь нет: продвижение, слоты, пакеты Kliko AI и «В ТОП» резюме в приложении не продаются.

 🔴 ТОКЕН. Отдельного API нет, токен печатает страница кабинета (§0.2). Каждый раз качать её ради нажатия — лишние сотни
 килобайт, поэтому токен запоминается при загрузке списка (там страница читается всё равно — IS_SHOP, CAB_AI). Ответ
 «csrf» — токен устарел: страница заново и один повтор (не денежный запрос, §8.0.3). Ответ «auth» — сессии нет.
 */
@MainActor
enum МоиОбъявленияAPI {

    /// Токен последней прочитанной страницы кабинета. Пусто — прочитать перед записью.
    private static var токен: String = ""

    static func запомнитьТокен(_ новый: String) {
        if !новый.isEmpty { токен = новый }
    }

    /// Выход: токен ушедшего не годится следующему.
    static func забыть() {
        токен = ""
    }

    /**
     Этап 42: токен для запроса, который кладёт его не в JSON (multipart загрузки фото подачи, КабинетСайта.загрузитьФото).
     Пусто — прочитать страницу кабинета; пусто и после неё — сессии нет.
     */
    static func токенСейчас() async throws -> String {
        if токен.isEmpty {
            let страница = try await КабинетСайта.состояние()
            if страница.вошёл == false { return "" }
            токен = страница.csrf
        }
        return токен
    }

    /// GET без токена. nil — ответ не JSON (страница ошибки, обрыв посреди ответа).
    static func получить(_ хвост: String, отКорня: Bool = false) async throws -> [String: Any]? {
        let ответ = try await КабинетСайта.вызвать(хвост, отКорня: отКорня)
        return ответ.json
    }

    /**
     POST JSON с полем csrf, как у сайта. На «csrf» — свежая страница и один повтор; сессии нет — ответ с error «auth»
     (его разбирает модель). Автоматических повторов при сбое сети нет: запись могла дойти, второй раз её не шлём.
     */
    static func отправить(_ хвост: String, тело: [String: Any], отКорня: Bool = false) async throws -> [String: Any] {
        var повторили = false
        while true {
            if токен.isEmpty {
                let страница = try await КабинетСайта.состояние()
                if страница.вошёл == false { return ["ok": false, "error": "auth"] }
                токен = страница.csrf
            }
            guard !токен.isEmpty else { throw КабинетСайта.Сбой.приложение }
            var полное = тело
            полное["csrf"] = токен
            let ответ = try await КабинетСайта.вызвать(хвост, метод: "POST", тело: полное, отКорня: отКорня)
            guard let j = ответ.json else { throw КабинетСайта.Сбой.приложение }
            if строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                токен = ""
                continue
            }
            return j
        }
    }

    // MARK: - Разбор значений (как JS: 1, "1", true — да). nonisolated — их зовут и разборы данных вне главной нити.

    nonisolated static func да(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue != 0 }
        if let текст = значение as? String { return текст == "1" || текст == "true" }
        return false
    }

    nonisolated static func строка(_ значение: Any?) -> String {
        if let текст = значение as? String { return текст }
        if let число = значение as? NSNumber { return число.stringValue }
        return ""
    }

    /// +e||0 сайта: число или строка с числом; прочее — 0.
    nonisolated static func число(_ значение: Any?) -> Double {
        if let число = значение as? NSNumber { return число.doubleValue }
        if let текст = значение as? String { return Double(текст.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return 0
    }

    nonisolated static func целое(_ значение: Any?) -> Int {
        let n = число(значение)
        guard n.isFinite else { return 0 }
        /* Int(Double) падает на числах за пределами Int (от 9,2e18) — такое с сервера не ждём, но и не роняем приложение. */
        return Int(exactly: n.rounded(.towardZero)) ?? 0
    }

    /// Ошибка сервера: сессии нет.
    nonisolated static func нетСессии(_ j: [String: Any]) -> Bool {
        строка(j["error"]) == "auth" || строка(j["need"]) == "auth"
    }
}

// MARK: - Вкладки

/// Вкладки «Опубликованные» / «Неактивные» / «Удалённые» (#adv-tabs). rawValue — как в localStorage.kliko_adv_tab сайта.
enum ВкладкаОбъявлений: String, CaseIterable, Hashable {
    case published
    case inactive
    case deleted

    var название: String {
        switch self {
        case .published: return МоиОбъявленияText.т("tab_published")
        case .inactive:  return МоиОбъявленияText.т("tab_inactive")
        case .deleted:   return МоиОбъявленияText.т("tab_deleted")
        }
    }

    var пусто: String {
        switch self {
        case .published: return МоиОбъявленияText.т("empty_published")
        case .inactive:  return МоиОбъявленияText.т("empty_inactive")
        case .deleted:   return МоиОбъявленияText.т("empty_deleted")
        }
    }
}

// MARK: - Объявление из my_items

/// Кто лайкнул, написал, позвонил, поделился (stats.who.*[]): {name, at}.
struct КтоОбъявления: Hashable {
    let имя: String
    let когда: String
}

/// stats объявления (advStatsHTML): счётчики и списки «кто». Отдельного API статистики у кабинета нет (§3.4).
struct СтатистикаОбъявления: Equatable {
    var просмотры: Int = 0
    var избранное: Int = 0
    var сообщения: Int = 0
    var звонки: Int = 0
    var поделились: Int = 0
    var ждут: Int = 0
    /// Ключи — like / msg / call / share, как у сайта.
    var кто: [String: [КтоОбъявления]] = [:]
}

/// Одно объявление items[] ответа my_items — только поля, которые читает экран (карта §3.1.2).
struct МоёОбъявление: Identifiable, Equatable {
    let id: String
    var название: String = ""
    var бренд: String = ""
    var фото: String = ""
    var создано: String = ""
    var раздел: String = ""
    var цена: Double = 0
    var торг: Bool = false
    var аренда: Bool = false
    var ценаАренды: Double = 0
    var периодАренды: String = ""
    var статус: String = ""
    var причина: String = ""
    var отклонений: Int = 0
    var причинаРучной: String = ""
    var скрываемНомера: Bool = false
    /// held_no_phone: ждёт верификации владельца — лежит в «Опубликованных» с жёлтым значком.
    var ждётВерификации: Bool = false
    var сверхЛимита: Bool = false
    var сверхЛимитаСамо: Bool = false
    var проданоСлот: Bool = false
    var пауза: Bool = false
    var черновикИмпорта: Bool = false
    /// sched_at, unix-секунды: в очереди публикаций.
    var вОчереди: Double = 0
    var ждётСлот: Bool = false
    /// life_end, unix-секунды: конец 30-дневного срока.
    var конецСрока: Double = 0
    var автоПродление: Bool = false
    var топ: Bool = false
    var топДо: String = ""
    /// next_free_bump, unix-секунды: следующее бесплатное авто-поднятие.
    var следующееПоднятие: Double = 0
    var статистика = СтатистикаОбъявления()
    var склад: Int = 0
    /// sample: демо-объявление — другой набор кнопок.
    var образец: Bool = false
    /// Для масс-редактора («Таблицей», _ADVT_F сайта): condition ("new" / иное — б/у), city, warranty_days.
    var состояние: String = ""
    var город: String = ""
    var гарантия: Int = 0

    init(id: String) {
        self.id = id
    }

    /// Разбор записи items[]. Без id запись бесполезна — nil.
    init?(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        self.init(id: номер)
        название = A.строка(j["title"])
        бренд = A.строка(j["brand"])
        фото = A.строка(j["img"])
        создано = A.строка(j["created_at"])
        раздел = A.строка(j["category"])
        цена = A.число(j["price"])
        торг = A.да(j["price_negotiable"])
        аренда = A.да(j["for_rent"])
        ценаАренды = A.число(j["rent_price_day"])
        периодАренды = A.строка(j["rent_period"])
        статус = A.строка(j["status"])
        причина = A.строка(j["reason"])
        отклонений = A.целое(j["reject_count"])
        причинаРучной = A.строка(j["manual_review_reason"])
        скрываемНомера = A.да(j["redacting"])
        ждётВерификации = A.да(j["held_no_phone"])
        сверхЛимита = A.да(j["held_over_limit"])
        сверхЛимитаСамо = A.да(j["held_over_limit_auto"])
        проданоСлот = A.да(j["sold_deactivated"])
        пауза = A.да(j["paused"])
        черновикИмпорта = A.да(j["import_draft"])
        вОчереди = A.число(j["sched_at"])
        ждётСлот = A.да(j["sched_wait"])
        конецСрока = A.число(j["life_end"])
        автоПродление = A.да(j["auto_renew"])
        топ = A.да(j["top"])
        топДо = A.строка(j["top_until"])
        следующееПоднятие = A.число(j["next_free_bump"])
        склад = A.целое(j["stock"])
        образец = A.да(j["sample"])
        состояние = A.строка(j["condition"])
        город = A.строка(j["city"])
        гарантия = A.целое(j["warranty_days"])
        if let с = j["stats"] as? [String: Any] {
            статистика = Self.статистика(с)
        }
    }

    private static func статистика(_ с: [String: Any]) -> СтатистикаОбъявления {
        typealias A = МоиОбъявленияAPI
        var итог = СтатистикаОбъявления()
        итог.просмотры = A.целое(с["views"])
        итог.избранное = A.целое(с["likes"])
        итог.сообщения = A.целое(с["msgs"])
        итог.звонки = A.целое(с["calls"])
        итог.поделились = A.целое(с["shares"])
        итог.ждут = A.целое(с["wait"])
        if let кто = с["who"] as? [String: Any] {
            for ключ in ["like", "msg", "call", "share"] {
                let список = (кто[ключ] as? [Any]) ?? []
                итог.кто[ключ] = список.compactMap { запись -> КтоОбъявления? in
                    guard let з = запись as? [String: Any] else { return nil }
                    return КтоОбъявления(имя: A.строка(з["name"]), когда: A.строка(з["at"]))
                }
            }
        }
        return итог
    }

    // MARK: Правила сайта

    /// _advExpired: одобрено, не ждёт верификации, без авто-продления, срок вышел.
    func истёк(_ сейчас: Double) -> Bool {
        статус == "approved" && !ждётВерификации && !автоПродление && конецСрока > 0 && конецСрока <= сейчас
    }

    /**
     _advTabFilter сайта. Одно отличие: статус ai_check сайт не кладёт ни в одну вкладку (карта §3.1.3, риск §8.3) — такое
     объявление пропадало бы с экрана, хотя его, как и pending, проверяет Kliko AI. Здесь оно в «Неактивных», рядом с
     pending, с тем же значком «Проверяется Kliko AI…». Запросы от этого не меняются.
     */
    func во(_ вкладка: ВкладкаОбъявлений, сейчас: Double) -> Bool {
        switch вкладка {
        case .published:
            return (статус == "approved" && !истёк(сейчас)) || ждётВерификации
        case .deleted:
            return статус == "deleted" || статус == "deleted_permanent"
        case .inactive:
            let неактивные: Set<String> = ["pending", "ai_check", "rejected", "pending_manual", "inactive", "sold"]
            return !ждётВерификации && (истёк(сейчас) || неактивные.contains(статус))
        }
    }

    /// _advMatchQ: подстрока в «название бренд id» без учёта регистра.
    func подходит(_ запрос: String) -> Bool {
        let q = запрос.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return (название + " " + бренд + " " + id).lowercased().contains(q)
    }

    /// _advTechManual: ручная проверка по технической причине — у такой есть «Проверить сейчас».
    var техническаяРучная: Bool {
        let п = причинаРучной.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !п.isEmpty && (п.hasPrefix("авто-проверка") || п.hasPrefix("ответ kliko ai не разобран"))
    }
}

// MARK: - Слоты из my_items

/// slots ответа my_items (карта §3.3.9): лимит активных объявлений.
struct СлотыОбъявлений: Equatable {
    var лимит: Int = 0
    var занято: Int = 0
    var бесплатно: Int = 0
    var тариф: Int = 0
    var до: String = ""

    init?(_ j: [String: Any]?) {
        guard let j else { return nil }
        typealias A = МоиОбъявленияAPI
        лимит = A.целое(j["limit"])
        занято = A.целое(j["used"])
        бесплатно = A.целое(j["free"])
        тариф = A.целое(j["plan"])
        до = A.строка(j["until"])
    }
}

// MARK: - «Работа»: вакансии и резюме

/// Запись jobs[] ответа /api/jobs.php?action=mine (jobsMineDraw / _jbRow сайта).
struct МояРабота: Identifiable, Equatable {
    let id: String
    var вакансия: Bool = false
    var название: String = ""
    var имя: String = ""
    var компания: String = ""
    var зарплатаОт: Double = 0
    var зарплатаДо: Double = 0
    var город: String = ""
    var топ: Bool = false
    var истёк: Bool = false

    init?(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        вакансия = A.строка(j["kind"]) == "vacancy"
        название = A.строка(j["title"])
        имя = A.строка(j["name"])
        компания = A.строка(j["company"])
        зарплатаОт = A.число(j["salary_min"])
        зарплатаДо = A.число(j["salary_max"])
        город = A.строка(j["city"])
        топ = A.да(j["top"])
        истёк = A.да(j["expired"])
    }
}
