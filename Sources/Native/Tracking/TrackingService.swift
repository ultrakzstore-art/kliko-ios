import Foundation
import UIKit

/**
 ОТСЛЕЖИВАНИЕ ДОСТАВКИ — СЛУЖБА (модель — TrackingModel.swift, экраны — TrackingViews.swift, контракт сервера —
 docs/SERVER_TRACKING.md).

 Откуда берутся статусы, по порядку:
   1. Сервер kliko.kz: GET escrow.php?action=track&id=<сделка> → {ok, track{…}} — уже нормализованная запись. Сервер
      сам ходит в СДЭК (OAuth), Яндекс Доставку (B2B-токен), Казпочту и кэширует ответы. Ключи — только там.
      Пока сервер этого действия не знает (ответ не JSON или незнакомая ошибка), приложение до перезапуска его не
      спрашивает и идёт дальше.
   2. Сама сделка (escrow.php?action=deal, то же, что читает карточка): живые поля курьера Яндекса в clocal.delivery
      (yandex_status, курьер, машина и цвет, сроки yandex_eta_a/b/r, код, звонок, где он), этап перевозчика ship_car_*
      (СДЭК, Exline, Avis — их статусы сервер уже кладёт в сделку), ссылка track_url.
   3. Публичный API без ключа прямо с телефона — только Казпочта (КазпочтаТрека).
   4. Ничего нет — СостояниеТрека.нетДанных; если известна ссылка службы или страница перевозчика — её можно открыть
      листом Safari ВНУТРИ приложения (последний выход).

 Опрос: пока курьер Яндекса в пути и карточка на экране — каждые 30 с, иначе раз в 10 мин (конечный статус — раз в 30);
 фоновые круги — только когда нативный слой на экране и приложение активно (СделкиAPI.опросМожно). Последний результат
 по сделке — в памяти и в UserDefaults (КэшТрека, до 20 сделок, до 30 событий в каждой).

 Транспорт — СделкиAPI (КабинетСайта.вызвать: запрос изнутри страницы сайта, с её куками); запись (set_track) — с
 токеном csrf, как у сайта (dealTrackSave).
 */

// MARK: - Рубильники

enum НастройкиОтслеживания {
    /// Спрашивать публичный API Казпочты прямо с телефона (ключ не нужен). false — только сервер и сделка.
    static let казпочтаНапрямую = true
    /// Спрашивать escrow.php?action=track. false — сразу сделка (пока сервер не готов, это просто один лишний запрос).
    static let маршрутСервера = true
    /// Опрос: курьер в пути и карточка на экране / обычный / статус конечный (секунды).
    static let опросЖивой: TimeInterval = 30
    static let опросОбычный: TimeInterval = 600
    static let опросКонечный: TimeInterval = 1800
}

// MARK: - Разбор ответов

enum РазборТрека {
    typealias A = СделкиAPI

    // MARK: Даты

    /// Unix-секунды (или миллисекунды), ISO 8601, «2026-09-28 14:35:00», «28.09.2026 14:35». Наивное время — Алматы.
    static func дата(_ з: Any?) -> Date? {
        if let n = з as? NSNumber { return изЧисла(n.doubleValue) }
        guard let сырое = з as? String else { return nil }
        let s = сырое.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "0" { return nil }
        if let n = Double(s) { return изЧисла(n) }
        if let d = isoПолный.date(from: s) { return d }
        if let d = isoПростой.date(from: s) { return d }
        for ф in форматы {
            if let d = ф.date(from: s) { return d }
        }
        return nil
    }

    private static func изЧисла(_ n: Double) -> Date? {
        guard n.isFinite, n > 0 else { return nil }
        return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
    }

    private static let isoПолный: ISO8601DateFormatter = {
        let ф = ISO8601DateFormatter()
        ф.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ф
    }()

    private static let isoПростой = ISO8601DateFormatter()

    private static let форматы: [DateFormatter] = {
        let шаблоны = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "dd.MM.yyyy HH:mm:ss",
                       "dd.MM.yyyy HH:mm", "yyyy-MM-dd", "dd.MM.yyyy"]
        return шаблоны.map { шаблон in
            let ф = DateFormatter()
            ф.locale = Locale(identifier: "en_US_POSIX")
            ф.timeZone = TimeZone(identifier: "Asia/Almaty")
            ф.dateFormat = шаблон
            return ф
        }
    }()

    // MARK: Строки

    private static func чистая(_ з: Any?) -> String {
        A.строка(з).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ссылку показываем, только если это https и хост известной службы (как проверяет сервер в set_track).
    static func безопаснаяСсылка(_ ссылка: String) -> Bool {
        guard ссылка.hasPrefix("https://"), ссылка.count <= 500, let адрес = URL(string: ссылка),
              let хост = адрес.host else { return false }
        return ОпределениеПеревозчика.поХосту(хост) != nil
    }

    // MARK: 1. Ответ сервера (контракт docs/SERVER_TRACKING.md)

    static func изСервера(_ t: [String: Any], роль: String) -> ДанныеТрека {
        var д = ДанныеТрека(перевозчик: ПеревозчикТрека(код: A.строка(t["carrier"])))
        д.имяПеревозчика = чистая(t["carrier_name"])
        д.номер = чистая(t["track_no"])
        д.статус = СтатусТрека(код: A.строка(t["status"]))
        д.текстСтатуса = чистая(t["status_text"])
        д.кодПеревозчика = чистая(t["carrier_status"]).lowercased()
        if д.статус == .неизвестно && !д.текстСтатуса.isEmpty {
            д.статус = СтатусТрека.поТексту(д.текстСтатуса)
        }
        var сроки: [СрокТрека] = []
        if let когда = дата(t["eta"]) {
            сроки.append(СрокТрека(цель: .доставка, когда: когда, до: дата(t["eta_to"])))
        }
        for з in (t["etas"] as? [Any]) ?? [] {
            guard let d = з as? [String: Any], let когда = дата(d["at"]) else { continue }
            let цель = ЦельСрокаТрека(rawValue: A.строка(d["target"])) ?? .доставка
            сроки.append(СрокТрека(цель: цель, когда: когда, до: дата(d["to"])))
        }
        д.сроки = сроки
        if let к = t["courier"] as? [String: Any] {
            let курьер = курьерСервера(к)
            if !курьер.пусто { д.курьер = курьер }
        }
        д.события = события(t["events"])
        д.обновлено = дата(t["updated_at"]) ?? Date()
        let ссылка = чистая(t["public_url"])
        if безопаснаяСсылка(ссылка) { д.ссылка = ссылка }
        д.живой = A.да(t["live"])
        д.источник = .сервер
        д.роль = роль.isEmpty ? A.строка(t["role"]) : роль
        let опрос = A.число(t["next_poll"])
        if опрос > 0 { д.следующийОпрос = опрос }
        if д.статус == .неизвестно, let первое = д.события.first { д.статус = первое.статус }
        return д
    }

    private static func курьерСервера(_ d: [String: Any]) -> КурьерТрека {
        var к = КурьерТрека()
        к.имя = чистая(d["name"])
        к.машина = чистая(d["car"])
        к.цветМашины = чистая(d["car_color"])
        к.номерМашины = чистая(d["plate"])
        к.телефон = чистая(d["phone"])
        к.добавочный = чистая(d["ext"]).filter { $0.isNumber }
        к.звонок = A.да(d["call"]) || !к.телефон.isEmpty
        к.код = чистая(d["code"])
        к.кодДля = чистая(d["code_for"])
        к.попыток = max(0, A.целое(d["code_left"]))
        к.кодВСМС = A.да(d["code_sms"])
        к.широта = A.координата(d["lat"])
        к.долгота = A.координата(d["lon"])
        return к
    }

    /// events[] сервера: {at, status, text, place}; статуса нет — по словам.
    static func события(_ з: Any?) -> [СобытиеТрека] {
        var итог: [СобытиеТрека] = []
        for элемент in (з as? [Any]) ?? [] {
            guard let d = элемент as? [String: Any] else { continue }
            let текст = чистая(d["text"])
            var статус = СтатусТрека(код: A.строка(d["status"]))
            if статус == .неизвестно { статус = СтатусТрека.поТексту(текст) }
            guard !текст.isEmpty || статус != .неизвестно else { continue }
            итог.append(СобытиеТрека(когда: дата(d["at"]), статус: статус, текст: текст, место: чистая(d["place"])))
        }
        return поВремени(итог)
    }

    /// Новые сверху; без времени — в конец.
    static func поВремени(_ список: [СобытиеТрека]) -> [СобытиеТрека] {
        список.sorted { ($0.когда ?? .distantPast) > ($1.когда ?? .distantPast) }
    }

    // MARK: 2. Сделка (escrow.php?action=deal → deal)

    /**
     Всё, что сделка уже знает о доставке. Порядок: готовая запись сервера внутри сделки (deal.track), курьер Яндекса
     (clocal.delivery), отправка перевозчиком (ship_car_*), межгород (deal.carrier), ссылка track_url, номер
     carrier_track_no. Ничего — nil.
     */
    static func изСделки(_ j: [String: Any]) -> ДанныеТрека? {
        let роль = A.строка(j["my_role"])
        if let t = j["track"] as? [String: Any], !t.isEmpty {
            return изСервера(t, роль: роль)
        }
        if let я = изЯндекса(j, роль: роль) { return я }
        if let п = изПеревозчика(j, роль: роль) { return п }
        if let м = j["carrier"] as? [String: Any] {
            let номер = ОпределениеПеревозчика.чистый(A.строка(м["track"]))
            if !номер.isEmpty {
                let поИмени = ПеревозчикТрека(код: A.строка(м["code"]).isEmpty ? A.строка(м["name"]) : A.строка(м["code"]))
                let п = поИмени != .другой ? поИмени : (ОпределениеПеревозчика.поНомеру(номер) ?? .другой)
                var д = ДанныеТрека(перевозчик: п)
                д.имяПеревозчика = чистая(м["name"])
                д.номер = номер
                д.роль = роль
                return д
            }
        }
        let ссылка = чистая(j["track_url"])
        if !ссылка.isEmpty, let найден = ОпределениеПеревозчика.изТекста(ссылка) {
            var д = ДанныеТрека(перевозчик: найден.перевозчик)
            д.номер = найден.номер
            if безопаснаяСсылка(найден.ссылка) { д.ссылка = найден.ссылка }
            д.роль = роль
            return д
        }
        for ключ in ["carrier_track_no", "track_no"] {
            let номер = ОпределениеПеревозчика.чистый(A.строка(j[ключ]))
            if let п = ОпределениеПеревозчика.поНомеру(номер) {
                var д = ДанныеТрека(перевозчик: п)
                д.номер = номер
                д.роль = роль
                return д
            }
        }
        return nil
    }

    /**
     Живые поля курьера Яндекса (clocalYandexPanel, clocalEtaHtml сайта). Принимает сделку целиком, clocal или
     clocal.delivery — что есть под рукой.
     */
    static func изЯндекса(_ j: [String: Any], роль: String = "") -> ДанныеТрека? {
        let блок: [String: Any]
        if let c = j["clocal"] as? [String: Any], let d = c["delivery"] as? [String: Any] {
            блок = d
        } else if let d = j["delivery"] as? [String: Any] {
            блок = d
        } else {
            блок = j
        }
        let код = A.строка(блок["yandex_status"]).lowercased()
        let сбой = A.да(блок["yandex_failed"])
        guard !код.isEmpty || сбой else { return nil }
        var д = ДанныеТрека(перевозчик: .yandex)
        д.роль = роль.isEmpty ? A.строка(j["my_role"]) : роль
        д.кодПеревозчика = код
        if сбой {
            д.статус = .проблема
            д.текстСтатуса = ТрекText.т("ya_failed")
        } else {
            д.статус = СтатусТрека.изЯндекса(код)
            д.текстСтатуса = подписьЯндекса(код)
        }
        var к = КурьерТрека()
        к.имя = чистая(блок["yandex_courier"])
        к.машина = чистая(блок["yandex_courier_car"])
        к.цветМашины = чистая(блок["yandex_car_color"])
        к.звонок = A.да(блок["yandex_call"])
        к.код = чистая(блок["yandex_code"])
        к.кодДля = чистая(блок["yandex_code_for"])
        к.попыток = max(0, A.целое(блок["yandex_code_left"]))
        к.кодВСМС = к.код.isEmpty && A.да(блок["yandex_code_sms"])
        if let место = блок["yandex_pos"] as? [String: Any] {
            к.широта = A.координата(место["lat"])
            к.долгота = A.координата(место["lon"])
        }
        if !к.пусто && !сбой { д.курьер = к }
        д.сроки = срокиЯндекса(блок, код: код)
        let ссылка = чистая(блок["yandex_share_url"])
        if безопаснаяСсылка(ссылка) { д.ссылка = ссылка }
        let вПути: Set<String> = ["performer_found", "pickup_arrived", "ready_for_pickup_confirmation", "pickuped",
                                  "delivery_arrived", "ready_for_delivery_confirmation", "returning", "return_arrived",
                                  "ready_for_return_confirmation"]
        д.живой = !сбой && вПути.contains(код)
        if let забрал = дата(блок["picked_up_at"]) {
            д.события = [СобытиеТрека(когда: забрал, статус: .вПути, текст: подписьЯндекса("pickuped"))]
        }
        д.источник = .сделка
        return д
    }

    /// clocalEtaHtml: при возврате — eta_r; после забора — только eta_b; до забора — eta_a и eta_b.
    private static func срокиЯндекса(_ блок: [String: Any], код: String) -> [СрокТрека] {
        let возврат: Set<String> = ["returning", "return_arrived", "ready_for_return_confirmation"]
        let забрал: Set<String> = ["pickuped", "delivery_arrived", "ready_for_delivery_confirmation"]
        var итог: [СрокТрека] = []
        if возврат.contains(код) {
            if let r = дата(блок["yandex_eta_r"]) { итог.append(СрокТрека(цель: .обратно, когда: r, до: nil)) }
            return итог
        }
        if !забрал.contains(код), let a = дата(блок["yandex_eta_a"]) {
            итог.append(СрокТрека(цель: .кПродавцу, когда: a, до: nil))
        }
        if let b = дата(блок["yandex_eta_b"]) { итог.append(СрокТрека(цель: .кПокупателю, когда: b, до: nil)) }
        return итог
    }

    /// clocalYaLabel сайта.
    static func подписьЯндекса(_ код: String) -> String {
        let ключи: [String: String] = [
            "new": "yastat_new", "estimating": "yastat_est", "ready_for_approval": "yastat_ready",
            "accepted": "yastat_accepted", "performer_lookup": "yastat_lookup", "performer_draft": "yastat_lookup",
            "performer_found": "yastat_found", "pickup_arrived": "yastat_atseller",
            "ready_for_pickup_confirmation": "yastat_atseller", "pickuped": "yastat_picked",
            "delivery_arrived": "yastat_atbuyer", "ready_for_delivery_confirmation": "yastat_atbuyer",
            "pay_waiting": "yastat_handed", "delivered": "yastat_delivered", "delivered_finish": "yastat_delivered",
            "returning": "yastat_returning", "return_arrived": "yastat_atseller_ret",
            "returned": "yastat_returned_seller", "returned_finish": "yastat_returned", "cancelled": "yastat_cancelled",
            "cancelled_by_taxi": "yastat_cancelled_taxi", "failed": "yastat_nocourier",
            "performer_not_found": "yastat_nocourier"
        ]
        if let ключ = ключи[код.lowercased()] { return ТрекText.т(ключ) }
        return ""
    }

    /**
     Отправка перевозчиком (dealCarrierHtml сайта): ship_carrier, ship_car{name, kind, days_min, days_max, pvz_addr},
     ship_car_number, ship_car_stage, ship_car_cancelled, ship_car_at, ship_car_track_url. Статусы СДЭК сервер уже
     переводит в ship_car_stage — это и есть «СДЭК внутри приложения», пока нет action=track.
     */
    static func изПеревозчика(_ j: [String: Any], роль: String) -> ДанныеТрека? {
        let номер = чистая(j["ship_car_number"])
        let заказ = чистая(j["ship_car_order"])
        guard A.строка(j["ship_mode"]) == "carrier" || !номер.isEmpty || !заказ.isEmpty else { return nil }
        var этап = A.да(j["ship_car_cancelled"]) ? "cancelled" : A.строка(j["ship_car_stage"])
        if этап.isEmpty && (!номер.isEmpty || !заказ.isEmpty) { этап = "created" }
        guard !этап.isEmpty else { return nil }
        let машина = (j["ship_car"] as? [String: Any]) ?? [:]
        var д = ДанныеТрека(перевозчик: ПеревозчикТрека(код: A.строка(j["ship_carrier"])))
        д.имяПеревозчика = чистая(машина["name"])
        д.номер = номер
        д.роль = роль
        д.кодПеревозчика = этап
        д.статус = СтатусТрека.изЭтапа(этап, доДвери: A.строка(машина["kind"]) == "door")
        let ссылка = чистая(j["ship_car_track_url"])
        if безопаснаяСсылка(ссылка) { д.ссылка = ссылка }
        let оформлено = дата(j["ship_car_at"])
        if let оформлено {
            д.события = [СобытиеТрека(когда: оформлено, статус: .создан, текст: СтатусТрека.создан.текст)]
        }
        let от = A.целое(машина["days_min"])
        let до = A.целое(машина["days_max"])
        if let оформлено, max(от, до) > 0, !д.статус.конечный {
            let день: TimeInterval = 86_400
            let начало = оформлено.addingTimeInterval(Double(от > 0 ? от : до) * день)
            let конец = оформлено.addingTimeInterval(Double(max(от, до)) * день)
            д.сроки = [СрокТрека(цель: .доставка, когда: начало, до: конец > начало ? конец : nil)]
        }
        д.источник = .сделка
        return д
    }

    // MARK: 3. Любой JSON перевозчика (публичный API) — события по ключам

    /**
     Обход ответа без жёсткой схемы: публичные API меняются без предупреждения. Узнаёт форму Казпочты
     ({date, activity:[{time, status:[…], city, name}]}) и плоские события ({date|time|datetime, status|description|
     name, city|place}). Глубже 7 уровней не идёт.
     */
    static func событияИзЛюбого(_ з: Any, глубина: Int = 0) -> [СобытиеТрека] {
        guard глубина < 7 else { return [] }
        if let список = з as? [Any] {
            return список.flatMap { событияИзЛюбого($0, глубина: глубина + 1) }
        }
        guard let d = з as? [String: Any] else { return [] }
        if let действия = d["activity"] as? [Any] {
            let день = A.строка(d["date"])
            var итог: [СобытиеТрека] = []
            for элемент in действия {
                guard let a = элемент as? [String: Any] else { continue }
                let время = A.строка(a["time"])
                let когда = дата(время.isEmpty ? день : день + " " + время) ?? датаСобытия(a) ?? дата(день)
                if let с = событие(a, когда: когда) { итог.append(с) }
            }
            if !итог.isEmpty { return итог }
        }
        if let с = событие(d, когда: nil) { return [с] }
        return d.values.flatMap { событияИзЛюбого($0, глубина: глубина + 1) }
    }

    private static let ключиТекста = ["status", "description", "status_name", "operation", "event", "title", "message",
                                      "text", "state", "name"]
    private static let ключиМеста = ["city", "place", "location", "dep_name", "office", "point", "address", "name"]
    private static let ключиДаты = ["datetime", "date", "time", "dt", "timestamp", "at", "created_at", "date_time"]

    private static func датаСобытия(_ d: [String: Any]) -> Date? {
        for ключ in ключиДаты {
            if let когда = дата(d[ключ]) { return когда }
        }
        return nil
    }

    private static func событие(_ d: [String: Any], когда: Date?) -> СобытиеТрека? {
        var текст = ""
        var ключТекста = ""
        for ключ in ключиТекста {
            if let s = d[ключ] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty {
                текст = s.trimmingCharacters(in: .whitespacesAndNewlines)
                ключТекста = ключ
                break
            }
            if let список = d[ключ] as? [Any] {
                let строки = список.compactMap { $0 as? String }.filter { !$0.isEmpty }
                if !строки.isEmpty {
                    текст = строки.joined(separator: ", ")
                    ключТекста = ключ
                    break
                }
            }
        }
        guard !текст.isEmpty, текст.count <= 300 else { return nil }
        guard let время = когда ?? датаСобытия(d) else { return nil }
        var место = ""
        for ключ in ключиМеста where ключ != ключТекста {
            let s = чистая(d[ключ])
            if !s.isEmpty && s.count <= 200 {
                место = s
                break
            }
        }
        return СобытиеТрека(когда: время, статус: СтатусТрека.поТексту(текст), текст: текст, место: место)
    }

    // MARK: 4. Слияние с прежней записью

    /**
     Сервер и перевозчик отдают ленту целиком — она и остаётся. У сделки ленты нет, есть только текущий статус: ленту
     собираем сами — к прежним событиям (тот же перевозчик и номер) добавляем новый статус, когда он сменился.
     */
    static func слить(прежние: ДанныеТрека?, новые: ДанныеТрека) -> ДанныеТрека {
        var д = новые
        if д.источник != .сделка && !д.события.isEmpty { return д }
        var лента = д.события
        if let п = прежние, п.перевозчик == д.перевозчик, п.номер == д.номер {
            for старое in п.события where !лента.contains(where: { $0.статус == старое.статус && $0.текст == старое.текст }) {
                лента.append(старое)
            }
        }
        лента = поВремени(лента)
        if д.статус != .неизвестно {
            let подпись = д.подпись
            let первое = лента.first
            if первое == nil || первое?.статус != д.статус || первое?.текст != подпись {
                лента.insert(СобытиеТрека(когда: Date(), статус: д.статус, текст: подпись), at: 0)
            }
        }
        д.события = Array(лента.prefix(30))
        return д
    }
}

// MARK: - Казпочта: публичный API без ключа

enum КазпочтаТрека {
    /// S10 ВПС: две буквы, девять цифр, две буквы.
    static func годится(_ номер: String) -> Bool {
        ОпределениеПеревозчика.чистый(номер).range(of: "^[A-Z]{2}[0-9]{9}[A-Z]{2}$", options: .regularExpression) != nil
    }

    /**
     ⚠️ Публичный адрес, которым пользуется сама страница track.kazpost.kz (без ключа, без входа). Официального
     описания нет — проверить на устройстве; изменится форма ответа — разбор (РазборТрека.событияИзЛюбого) просто не
     найдёт событий, и служба покажет то, что знает сервер и сделка. Сеть или сбой — nil.
     */
    static func события(_ номер: String) async -> [СобытиеТрека]? {
        let н = ОпределениеПеревозчика.чистый(номер)
        guard годится(н), let адрес = URL(string: "https://track.kazpost.kz/api/v2/" + н + "/events") else { return nil }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        let ответ: (Data, URLResponse)
        do {
            ответ = try await URLSession.shared.data(for: запрос)
        } catch {
            return nil
        }
        guard let http = ответ.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              ответ.0.count < 2_000_000,
              let json = try? JSONSerialization.jsonObject(with: ответ.0) else { return nil }
        let список = РазборТрека.поВремени(РазборТрека.событияИзЛюбого(json))
        return список.isEmpty ? nil : Array(список.prefix(50))
    }
}

// MARK: - Кэш

extension Notification.Name {
    /// КэшТрека записал новый статус доставки; userInfo["deal"] — номер сделки.
    static let klikoТрекИзменился = Notification.Name("kliko.tracking.changed")
}

/// Последний результат по сделке: в памяти и в UserDefaults (до 20 сделок). Выход из аккаунта — забыть().
@MainActor
enum КэшТрека {
    private static var память: [String: ДанныеТрека] = [:]
    private static var прочитан = false
    private static let ключХранения = "kliko.tracking.cache.v1"
    private static let пределСделок = 20

    static func прочитать(_ сделка: String) -> ДанныеТрека? {
        загрузить()
        return память[сделка]
    }

    static func записать(_ данные: ДанныеТрека, для сделка: String) {
        загрузить()
        var д = данные
        if д.события.count > 30 { д.события = Array(д.события.prefix(30)) }
        if память[сделка] == д { return }
        память[сделка] = д
        if память.count > пределСделок {
            let старые = память.sorted { $0.value.обновлено < $1.value.обновлено }.prefix(память.count - пределСделок)
            for пара in старые { память[пара.key] = nil }
        }
        сохранить()
        /* Экран сделки обновит плашку на экране блокировки (ЖиваяСделка). */
        NotificationCenter.default.post(name: .klikoТрекИзменился, object: nil, userInfo: ["deal": сделка])
    }

    static func забыть() {
        память = [:]
        прочитан = true
        UserDefaults.standard.removeObject(forKey: ключХранения)
    }

    private static func загрузить() {
        guard !прочитан else { return }
        прочитан = true
        guard let данные = UserDefaults.standard.data(forKey: ключХранения),
              let словарь = try? JSONDecoder().decode([String: ДанныеТрека].self, from: данные) else { return }
        память = словарь
    }

    private static func сохранить() {
        guard let данные = try? JSONEncoder().encode(память) else { return }
        UserDefaults.standard.set(данные, forKey: ключХранения)
    }
}

// MARK: - Звонок курьеру

/// Ответ clocal_courier_phone (подменный номер и добавочный) или готовый номер сервера.
struct ЗвонокКурьеруТрека: Equatable {
    let номер: String
    let добавочный: String
    let минут: Int

    /// tel:+77001234567,123 — запятая набирает добавочный после соединения (как у сайта).
    var адрес: URL? {
        let цифры = номер.filter { $0.isNumber || $0 == "+" }
        guard !цифры.isEmpty else { return nil }
        return URL(string: "tel:" + цифры + (добавочный.isEmpty ? "" : "," + добавочный))
    }

    var пояснение: String {
        var части: [String] = [String(format: ТрекText.т("call_num"), номер.слеваНаправо)]
        if !добавочный.isEmpty { части.append(String(format: ТрекText.т("call_ext"), добавочный.слеваНаправо)) }
        части.append(ТрекText.т("call_hint"))
        if минут > 0 { части.append(String(format: ТрекText.т("call_ttl"), минут)) }
        return части.joined(separator: "\n")
    }
}

// MARK: - Служба одной сделки

@MainActor
final class СлужбаОтслеживания: ObservableObject {
    let сделка: String

    @Published private(set) var состояние: СостояниеТрека
    @Published private(set) var обновляется = false
    @Published private(set) var сохраняется = false
    /// Короткая плашка внизу карточки («Сохранено», «Нет связи»).
    @Published private(set) var плашка: String? = nil
    /// Ошибка правки трека — окно в листе правки.
    @Published var ошибкаПравки: (заголовок: String, текст: String)? = nil
    /// Номер курьера получен — окно «Звонок курьеру».
    @Published var звонок: ЗвонокКурьеруТрека? = nil

    /// Карточка на экране: живой курьер опрашивается каждые 30 с.
    private(set) var наЭкране = false
    private var сырая: [String: Any]? = nil
    private var сыраяКогда: Date? = nil
    private var задачаПлашки: Task<Void, Never>? = nil

    /// Сервер ответил, что action=track не знает, — до перезапуска не спрашиваем.
    private static var безСервера = false
    /// Отказы, которые сервер с action=track отдаёт осознанно (а не «такого действия нет»).
    private static let известныеОтказы: Set<String> = ["no_track", "not_found", "access", "rate", "csrf", "status",
                                                       "empty", "auth", "busy"]

    init(сделка: String, данные: [String: Any]? = nil) {
        self.сделка = сделка
        let начальное: СостояниеТрека
        if let к = КэшТрека.прочитать(сделка) {
            начальное = к.содержательно ? .данные(к) : .нетДанных(к)
        } else {
            начальное = .загрузка
        }
        _состояние = Published(initialValue: начальное)
        if let данные { принять(сделку: данные) }
    }

    private func т(_ ключ: String) -> String { ТрекText.т(ключ) }

    // MARK: Данные сделки из карточки

    /**
     Сделка, которую карточка уже прочитала (deal ответа escrow.php?action=deal): живые поля Яндекса видны сразу, без
     своего запроса. Сервер с action=track всё равно спросится на следующем круге — у него лента событий.
     */
    func принять(сделку j: [String: Any]) {
        сырая = j
        сыраяКогда = Date()
        guard let новая = РазборТрека.изСделки(j) else { return }
        if case .данные(let д) = состояние, д.источник != .сделка { return }
        применить(новая)
    }

    private func применить(_ новая: ДанныеТрека) {
        let д = РазборТрека.слить(прежние: состояние.запись, новые: новая)
        КэшТрека.записать(д, для: сделка)
        состояние = д.содержательно ? .данные(д) : .нетДанных(д)
    }

    // MARK: Обновление

    /// Пауза до следующего круга.
    var интервал: TimeInterval {
        guard let д = состояние.запись else { return НастройкиОтслеживания.опросОбычный }
        if д.живой && наЭкране { return НастройкиОтслеживания.опросЖивой }
        if let n = д.следующийОпрос { return min(3600, max(15, n)) }
        if д.статус.конечный { return НастройкиОтслеживания.опросКонечный }
        return НастройкиОтслеживания.опросОбычный
    }

    /// Круг опроса, пока жива задача экрана (.task карточки): отменили задачу — опрос кончился.
    func следить() async {
        наЭкране = true
        defer { наЭкране = false }
        await обновить()
        while !Task.isCancelled {
            let пауза = интервал
            try? await Task.sleep(nanoseconds: UInt64(пауза * 1_000_000_000))
            if Task.isCancelled { break }
            if !СделкиAPI.опросМожно { continue }
            await обновить(вФоне: true)
        }
    }

    private func получить(_ хвост: String, вФоне: Bool) async throws -> [String: Any]? {
        if вФоне {
            return try await СделкиAPI.получитьВФоне(хвост)
        }
        return try await СделкиAPI.получить(хвост)
    }

    /// Один круг: сервер → сделка → Казпочта напрямую. Сбой при известных данных — данные остаются.
    func обновить(вФоне: Bool = false) async {
        guard !обновляется else { return }
        обновляется = true
        defer { обновляется = false }
        let номерВАдресе = СделкиAPI.вАдрес(сделка)
        let прежние = состояние.запись
        var запись: ДанныеТрека? = nil
        var сбойСети = false
        var нетВхода = false
        var серверОтветилПусто = false

        /* 1. Сервер kliko.kz — нормализованная запись с лентой (docs/SERVER_TRACKING.md). */
        if НастройкиОтслеживания.маршрутСервера && !Self.безСервера {
            do {
                let j = try await получить("escrow.php?action=track&id=" + номерВАдресе, вФоне: вФоне)
                if let j {
                    if СделкиAPI.да(j["ok"]) {
                        if let t = j["track"] as? [String: Any], !t.isEmpty {
                            запись = РазборТрека.изСервера(t, роль: СделкиAPI.строка(j["role"]))
                        } else {
                            серверОтветилПусто = true
                        }
                    } else if МоиОбъявленияAPI.нетСессии(j) {
                        нетВхода = true
                    } else if !Self.известныеОтказы.contains(СделкиAPI.строка(j["error"])) {
                        Self.безСервера = true
                    }
                } else {
                    Self.безСервера = true
                }
            } catch {
                сбойСети = true
            }
        }

        /* 2. Сделка: clocal Яндекса, ship_car_* перевозчика, track_url. Свежую (из карточки) повторно не качаем. */
        if запись == nil && !нетВхода {
            let свежая = сыраяКогда.map { Date().timeIntervalSince($0) < 5 } ?? false
            if !свежая && !(серверОтветилПусто && сырая != nil) {
                do {
                    let j = try await получить("escrow.php?action=deal&id=" + номерВАдресе, вФоне: вФоне)
                    if let j, СделкиAPI.да(j["ok"]), let d = j["deal"] as? [String: Any] {
                        сырая = d
                        сыраяКогда = Date()
                        сбойСети = false
                    } else if let j, МоиОбъявленияAPI.нетСессии(j) {
                        нетВхода = true
                    }
                } catch {
                    сбойСети = true
                }
            }
            if let d = сырая { запись = РазборТрека.изСделки(d) }
        }

        /* 3. Казпочта напрямую — только если у сервера нет ленты. */
        if var д = запись, НастройкиОтслеживания.казпочтаНапрямую, д.перевозчик.открытыйAPI, !д.номер.isEmpty,
           д.источник != .сервер || д.события.isEmpty {
            if let события = await КазпочтаТрека.события(д.номер) {
                д.события = события
                if let первое = события.first {
                    if первое.статус != .неизвестно { д.статус = первое.статус }
                    д.текстСтатуса = первое.текст
                }
                д.источник = .перевозчик
                д.обновлено = Date()
                запись = д
            }
        }

        /* 4. Итог. */
        if let д = запись {
            применить(д)
        } else if нетВхода {
            if прежние == nil { состояние = .ошибка(т("e_auth")) }
        } else if сбойСети {
            if прежние == nil {
                состояние = .ошибка(т("e_conn"))
            } else if !вФоне {
                показать(т("e_conn"))
            }
        } else {
            состояние = .нетДанных(nil)
        }
    }

    // MARK: Плашка

    func показать(_ текст: String) {
        плашка = текст
        задачаПлашки?.cancel()
        задачаПлашки = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.плашка = nil
        }
    }

    // MARK: Звонок курьеру

    /**
     Номер от сервера — сразу окно «Звонок курьеру». Нет номера, но звонок разрешён (yandex_call) — подменный номер
     спрашиваем, как сайт (clocalCourierCall): POST chat.php?action=clocal_courier_phone {deal_id} → {phone, ext, ttl}.
     */
    func позвонитьКурьеру() {
        guard let к = состояние.запись?.курьер else { return }
        if !к.телефон.isEmpty {
            звонок = ЗвонокКурьеруТрека(номер: к.телефон, добавочный: к.добавочный, минут: 0)
            return
        }
        guard к.звонок else { return }
        Task { @MainActor in
            do {
                let j = try await СделкиAPI.отправить("chat.php?action=clocal_courier_phone", тело: ["deal_id": self.сделка])
                if СделкиAPI.да(j["ok"]) {
                    let номер = СделкиAPI.строка(j["phone"]).trimmingCharacters(in: .whitespaces)
                    guard !номер.isEmpty else {
                        self.показать(self.т("e_failed"))
                        return
                    }
                    let добавочный = СделкиAPI.строка(j["ext"]).filter { $0.isNumber }
                    let минут = max(1, Int((СделкиAPI.число(j["ttl"]) / 60).rounded()))
                    self.звонок = ЗвонокКурьеруТрека(номер: номер, добавочный: добавочный,
                                                     минут: СделкиAPI.число(j["ttl"]) > 0 ? минут : 0)
                } else {
                    let m = СделкиAPI.строка(j["msg"]).trimmingCharacters(in: .whitespaces)
                    self.показать(m.isEmpty ? self.т("e_failed") : m)
                }
            } catch {
                self.показать(self.т("e_conn"))
            }
        }
    }

    // MARK: Правка трека

    /**
     «Изменить трек или ссылку». Ссылка службы — dealTrackSave сайта: POST escrow.php?action=set_track {deal_id, url}
     (пусто — убрать). Трек-номер без ссылки — POST escrow.php?action=set_track_no {deal_id, track_no, carrier}
     (новое действие, docs/SERVER_TRACKING.md §4): set_track с пустым url стёр бы прежнюю ссылку. Готово — true.
     */
    func сохранить(_ ввод: String) async -> Bool {
        guard !сохраняется else { return false }
        let t = ввод.trimmingCharacters(in: .whitespacesAndNewlines)
        let найден = ОпределениеПеревозчика.изТекста(t)
        let хвост: String
        var тело: [String: Any] = ["deal_id": сделка]
        if t.isEmpty {
            хвост = "escrow.php?action=set_track"
            тело["url"] = ""
        } else if let н = найден, !н.ссылка.isEmpty {
            хвост = "escrow.php?action=set_track"
            тело["url"] = н.ссылка
        } else if let н = найден, !н.номер.isEmpty {
            хвост = "escrow.php?action=set_track_no"
            тело["track_no"] = н.номер
            тело["carrier"] = н.перевозчик.rawValue
        } else if t.lowercased().hasPrefix("http") {
            /* Чужая ссылка — решает сервер (track_host), как у сайта. */
            хвост = "escrow.php?action=set_track"
            тело["url"] = t
        } else {
            ошибкаПравки = (т("edit_t"), т("detected_none"))
            return false
        }
        сохраняется = true
        defer { сохраняется = false }
        do {
            let j = try await СделкиAPI.отправить(хвост, тело: тело)
            if СделкиAPI.да(j["ok"]) {
                ОткликСайта.успех()
                показать(т(t.isEmpty ? "removed" : "saved"))
                сыраяКогда = nil
                Task { @MainActor [weak self] in await self?.обновить() }
                return true
            }
            ОткликСайта.предупреждение()
            let e = СделкиAPI.строка(j["error"])
            let сообщение = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch e {
            case "track_host":
                ошибкаПравки = (т("e_host_t"), т("e_host"))
            case "track_long":
                ошибкаПравки = (т("edit_t"), т("e_long"))
            default:
                if МоиОбъявленияAPI.нетСессии(j) {
                    ошибкаПравки = (т("edit_t"), т("e_auth"))
                } else if хвост.hasSuffix("set_track_no") && !Self.известныеОтказы.contains(e) {
                    ошибкаПравки = (т("edit_t"), т("e_no_srv"))
                } else {
                    ошибкаПравки = (т("edit_t"), сообщение.isEmpty ? (e.isEmpty ? т("e_failed") : e) : сообщение)
                }
            }
            return false
        } catch {
            ошибкаПравки = (т("edit_t"), т("e_conn"))
            return false
        }
    }
}
