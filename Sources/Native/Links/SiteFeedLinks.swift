import Foundation

/**
 ССЫЛКИ ЛЕНТЫ САЙТА — СВОИМИ ЭКРАНАМИ (владелец: «главное, чтобы на сайт не прыгал с приложения»).

 Раньше эти адреса из справки, историй, чата, пушей и универсальных ссылок падали в окно «Страница недоступна в
 приложении»: NativeRouter знал только ?item=, ?cat=, ?q=, ?all=1 и ?fav=1. Теперь — как разбор адреса страницы ленты
 сайта (mkSt и немедленная функция после него, js/marketplace.min.js; MK_SEO; _mkSellerCtx):
   · /kz/<язык>/marketplace, /marketplace/, /marketplace.php, /index.php без параметров — лента, как «Главная»
     (логотип и «Все объявления» home.html и item.html, запасной адрес mkItemUrl, mkGoneSimilar без cat и q);
   · /kz/<язык>/kupit/<раздел>/ и /kz/<язык>/uslugi/<раздел>/ — SEO-разделы плиток главной (a.mh-tile href, onclick
     mkHomeGo(раздел) → _mhPush({cat}) + mkVertical): лента раздела, язык в пути не важен;
   · /kupit/<раздел>/<город>/[<район>/] (и uslugi, kupit-bu, novye, arenda) — раздел в этом городе (местоSEO): слаг
     города — как seo_cities сайта, района — как seo_districts. Сайт кладёт город страницы только в отбор выдачи
     (mkSt.city = MK_SEO.city), выбор человека (ulx_city) не пишет — у нас так же: место ссылки только у этой выдачи
     ленты (ВыборГорода.местоСсылки), сохранённый город прежний. Слаг не наш — раздел без города. /rabota/<раздел>/<город>/
     — список вакансий этого места (ОкноВакансий, место ссылки — только этому окну);
   · ?vs=goods — плитка «Товары» (mkHomeGo('goods') → _mhPush({vs:"goods"}), MK_VSETS): набор «goods»
     (ListingsAPI.параметрыРаздела);
   · /kz/<язык>/jobs — «Работа» боковой колонки (a.mk-side-jobs); /?cat=jobs&q=<должность> — чипы главной: список
     вакансий с этим запросом (ОкноВакансий);
   · фильтры в адресе — q (80 знаков, строчными, как mkSt.q), cat, pmin, pmax, cond — в ИскомоеЛенты; city и region —
     выбор места ленты (СинхронПодписок.перейтиВ, как у сохранённого поиска); sort (reco | price | price_d | new),
     verified=1, photo=1, ymin, ymax, brands, models, gear, fuel — в ФильтрыЛенты через ДобавкаЛенты
     (NativeFeedView.применитьСнаружи); марки, коробка и топливо — через «,», модель строкой, как mkSt сайта; в ленте —
     чипами над выдачей и параметрами запроса (ФильтрыЛенты.параметры);
   · ?s=<продавец> — контекст продавца (window._mkSellerCtx: лента только его объявлений, «назад» — seller.php?id=):
     его витрина ОкноПродавца, как ?order_seller кабинета (WebBridge.продавецКабинета).
 */
enum СсылкиЛенты {
    /// Путь ленты: /, /index.php, /marketplace(/), /marketplace.php — с /kz/<язык> впереди или без.
    static let путьЛенты = "^(/[a-z]{2}/[a-z]{2})?(/|/index\\.php|/marketplace/?|/marketplace\\.php)?$"
    /// «Работа» боковой колонки ленты: /kz/<язык>/jobs.
    static let путьРаботы = "^(/[a-z]{2}/[a-z]{2})?/jobs(\\.php)?/?$"
    /// Главная без параметров — её ведёт Config.главная (лента и перезагрузка страницы под слоем), не этот разбор.
    private static let путьГлавной = "^(/[a-z]{2}/[a-z]{2})?/?$"

    /// sort= адреса → «Сначала показывать» (карта сайта {reco:"reco", price:"price_asc", price_d:"price_desc",
    /// new:"date_desc"}). «date_desc» — новые подряд без золотого ритма ТОП, запрос sort=new (.новыеПодряд).
    private static let порядки: [String: СортировкаЛенты] = [
        "reco": .рекомендуемые, "price": .дешевле, "price_d": .дороже, "new": .новыеПодряд
    ]

    /**
     Цель для адреса ленты, SEO-раздела или «Работы»; nil — адрес не отсюда (или его ведёт другой разбор: объявление
     ?item= — NativeRouter.распознать и БезСайта.ближайший, продавец ?s= — WebBridge, главная без параметров —
     Config.главная).
     */
    static func цель(_ части: URLComponents) -> NativeRouter.Цель? {
        let путь = части.path
        let все = части.queryItems ?? []
        func значение(_ имя: String) -> String {
            let v = все.first(where: { $0.name == имя })?.value ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let страницаКаталога = страницаSEO(путь)
        let seo = страницаКаталога?.раздел
        let намерение = страницаКаталога?.намерение ?? ""
        /* /q/<запрос>/ — SEO-страница поиска (MK_SEO.q перекрывает q адреса). */
        let запросSEO = seo == nil ? запросПоискаSEO(путь) : nil
        let работа = путь.range(of: путьРаботы, options: .regularExpression) != nil
        let лента = seo == nil && запросSEO == nil && !работа
            && путь.range(of: путьЛенты, options: .regularExpression) != nil
        guard seo != nil || запросSEO != nil || работа || лента else { return nil }

        let товар = значение("item")
        if лента {
            guard товар.isEmpty else { return nil }
            if (части.query ?? "").isEmpty, путь.range(of: путьГлавной, options: .regularExpression) != nil {
                return nil
            }
            /* Нижняя панель сайта: /kz/ru/marketplace?fav=1 — избранное. */
            if значение("fav") == "1" && Config.избранное { return .избранное }
            /* ?s=<продавец> — его витрина (WebBridge.продавецКабинета), а не вся лента. */
            if ВитринаПродавцаAPI.годный(значение("s")) { return nil }
        } else if !товар.isEmpty, Config.нативнаяКарточка,
                  товар.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            /* SEO-страница с открытым объявлением (?item=) — его карточка. */
            return .объявление(id: товар)
        }

        /* mkSt.q: slice(0, 80).toLowerCase(). */
        let текст = String((запросSEO ?? значение("q")).prefix(80)).lowercased()
        /* MK_SEO.cat перекрывает cat адреса; набор ?vs= (MK_VSETS) — раздел выше обоих (_mhUrlSync: cat только без vs). */
        var раздел = seo ?? значение("cat")
        if значение("vs") == "goods" { раздел = "goods" }

        /* /rabota/<раздел>/ — вакансии (SEO_INTENTS: sections jobs). /rabota/<раздел>/<город>/[<район>/] — вакансии этого
           места: сайт кладёт город страницы в отбор выдачи (mkSt.city = MK_SEO.city), выбор человека не трогает. */
        if работа || намерение == "rabota" || раздел.lowercased() == "jobs" {
            let место = намерение == "rabota" ? местоSEO(путь) : nil
            return .вакансии(номер: номерВакансии(части.fragment), запрос: текст, место: место)
        }
        if раздел.range(of: "^[A-Za-z0-9_-]{1,60}$", options: .regularExpression) == nil { раздел = "" }

        /* MK_SEO.cond: /kupit-bu/ — б/у, /novye/ — новые (перекрывают cond адреса). */
        var состояние = значение("cond")
        if намерение == "kupit-bu" { состояние = "used" }
        if намерение == "novye" { состояние = "new" }
        let искомое = ИскомоеЛенты(текст: текст, раздел: раздел, ценаОт: целое(значение("pmin")),
                                   ценаДо: целое(значение("pmax")), состояние: состояние)
        var добавка = ДобавкаЛенты()
        if let место = местоSEO(путь) {
            /* MK_SEO.city перекрывает city адреса, а region без города в запрос не идёт (_mkApiQS) — место адреса ни
               выдаче, ни выбору человека уже не нужно. */
            добавка.городКаталога = место.город
            добавка.районКаталога = место.район
        } else {
            добавка.город = String(значение("city").prefix(80))
            добавка.регион = String(значение("region").prefix(60))
        }
        добавка.сортировка = порядки[значение("sort")]
        /* "1" === t.get("verified") и photo — без обрезки пробелов, как у сайта. */
        добавка.проверенные = все.first(where: { $0.name == "verified" })?.value == "1"
        добавка.сФото = все.first(where: { $0.name == "photo" })?.value == "1"
        добавка.годОт = целое(значение("ymin"))
        добавка.годДо = целое(значение("ymax"))
        /* Мастер авто: n("brands") — trim().split(",").filter(Boolean); models — trim(); gear и fuel — как brands. */
        добавка.марки = список(значение("brands"))
        добавка.модель = String(значение("models").prefix(80))
        добавка.коробка = список(значение("gear"))
        добавка.топливо = список(значение("fuel"))
        /* MK_SEO.rent: /arenda/<раздел>/ — режим «Аренда» ленты с этим разделом. */
        добавка.аренда = намерение == "arenda"
        return .найти(искомое, добавка: добавка.пустая ? nil : добавка)
    }

    /// Значения через «,» — n() разбора mkSt: пустые между запятыми выпадают. Пробелы вокруг значения и повторы убираем
    /// (у чипа своё значение — два одинаковых ему не нужны); не больше 20 значений по 60 знаков.
    static func список(_ v: String) -> [String] {
        var итог: [String] = []
        for кусок in v.split(separator: ",") {
            let значение = String(кусок.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            if значение.isEmpty || итог.contains(значение) { continue }
            итог.append(значение)
            if итог.count >= 20 { break }
        }
        return итог
    }

    /// Номер продавца из /marketplace?s=<продавец> (и прочих путей ленты, без ?item=); иначе nil.
    static func продавец(_ части: URLComponents) -> String? {
        guard части.path.range(of: путьЛенты, options: .regularExpression) != nil else { return nil }
        let все = части.queryItems ?? []
        let товар = (все.first(where: { $0.name == "item" })?.value ?? "").trimmingCharacters(in: .whitespaces)
        guard товар.isEmpty else { return nil }
        /* window._mkSellerCtx = String(s).trim(). */
        let номер = (все.first(where: { $0.name == "s" })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ВитринаПродавцаAPI.годный(номер) ? номер : nil
    }

    /// Раздел SEO-страницы каталога (/kupit/<раздел>/, /uslugi/<раздел>/ и прочие намерения — страницаSEO); без раздела —
    /// "" (вся лента); не SEO-страница — nil.
    static func разделSEO(_ путь: String) -> String? {
        страницаSEO(путь)?.раздел
    }

    /// Намерения каталога сайта (SEO_INTENTS, inc/seo_catalog.php; правило .htaccess): kupit, kupit-bu (б/у), novye
    /// (новые), arenda (аренда), uslugi (услуги), rabota (вакансии).
    private static let намеренияSEO: Set<String> = ["kupit", "kupit-bu", "novye", "arenda", "uslugi", "rabota"]

    /// Путь без языка впереди (/kz/<язык>/…) — сегментами.
    private static func сегментыБезЯзыка(_ путь: String) -> [String] {
        var сегменты = путь.split(separator: "/").map(String.init)
        func язык(_ s: String) -> Bool { s.count == 2 && s.allSatisfy { $0.isASCII && $0.isLowercase } }
        if сегменты.count >= 2, язык(сегменты[0]), язык(сегменты[1]) { сегменты.removeFirst(2) }
        return сегменты
    }

    /// SEO-страница каталога: /<намерение>/<раздел>/[<город>/[<район>/]] с /kz/<язык> впереди или без. Раздел негодный
    /// или его нет — "" (вся лента). Город и район — местоSEO.
    static func страницаSEO(_ путь: String) -> (намерение: String, раздел: String)? {
        let сегменты = сегментыБезЯзыка(путь)
        guard let первый = сегменты.first?.lowercased(), намеренияSEO.contains(первый) else { return nil }
        guard сегменты.count >= 2 else { return (первый, "") }
        let раздел = сегменты[1].lowercased()
        return (первый, раздел.range(of: "^[a-z0-9-]{1,60}$", options: .regularExpression) != nil ? раздел : "")
    }

    /**
     Место SEO-страницы каталога: /<намерение>/<раздел>/<город>/[<район>/] (правила .htaccess — не больше четырёх
     сегментов). Город — по слагу справочника, как seo_city_name сайта; район — только своего города (seo_district).
     Раздела нет (у сайта такой страницы нет — 404), города нет или слаг не наш — nil: раздел без города. Район чужой
     или неизвестный — только город (сайт отдал бы 404, у нас — ближайшее).
     */
    static func местоSEO(_ путь: String) -> ГдеИскать? {
        let сегменты = сегментыБезЯзыка(путь)
        guard (3...4).contains(сегменты.count), let страница = страницаSEO(путь), !страница.раздел.isEmpty,
              let город = городаSEO[сегменты[2].lowercased()] else { return nil }
        var место = ГдеИскать(город: город)
        if сегменты.count == 4, let район = районыSEO[сегменты[3].lowercased()], район.город == город {
            место.район = район.ключ
        }
        return место
    }

    /// seo_cities сайта (inc/seo_catalog.php): слаг города → название. Город-регион (Астана, Алматы, Шымкент) — своим
    /// ключом («astana»), города областей — ulx_slug(название, 40) («ust-kamenogorsk»); совпал слаг — первый по
    /// справочнику. Справочник тот же, что у сайта (data/geo_kz.json и MK_GEO — одни и те же 426 мест).
    private static let городаSEO: [String: String] = {
        var итог: [String: String] = [:]
        for регион in ГеоДанные.регионы {
            if регион.город { итог[регион.ключ] = регион.название }
            for город in регион.города {
                let слаг = ПоделитьсяСайта.чпу(город, предел: 40)
                if итог[слаг] == nil { итог[слаг] = город }
            }
        }
        return итог
    }()

    /// seo_districts сайта: слаг района — ulx_slug(название без слова «район», 40): «baykonurskiy», «al-farabiyskiy».
    private static let районыSEO: [String: ГеоРайон] = {
        var итог: [String: ГеоРайон] = [:]
        for район in ГеоДанные.районы {
            let имя = район.название.replacingOccurrences(of: "\\s*район\\s*$", with: "",
                                                           options: [.regularExpression, .caseInsensitive])
            итог[ПоделитьсяСайта.чпу(имя.trimmingCharacters(in: .whitespaces), предел: 40)] = район
        }
        return итог
    }()

    /// /q/<запрос>/ — SEO-страница поиска (seo_q_route сайта): «-», «_», «+» — пробелы, всё, кроме букв и цифр, — прочь,
    /// строчными. Не она или запрос пустой — nil.
    static func запросПоискаSEO(_ путь: String) -> String? {
        let сегменты = сегментыБезЯзыка(путь)
        guard сегменты.count == 2, сегменты[0] == "q" else { return nil }
        let сырой = сегменты[1].removingPercentEncoding ?? сегменты[1]
        let пробелы = сырой.replacingOccurrences(of: "[-_+]", with: " ", options: .regularExpression)
        let буквы = пробелы.replacingOccurrences(of: "[^\\p{L}\\p{N} ]+", with: " ", options: .regularExpression)
        let запрос = буквы.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).lowercased()
        return запрос.isEmpty ? nil : запрос
    }

    /// #vac=<номер> — карточка вакансии; иначе nil (список).
    private static func номерВакансии(_ якорь: String?) -> String? {
        let якорь = якорь ?? ""
        guard якорь.hasPrefix("vac=") else { return nil }
        let номер = String(якорь.dropFirst(4)).removingPercentEncoding ?? ""
        return номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil ? номер : nil
    }

    /// parseInt(v, 10) сайта: цифры в начале; больше нуля — число, иначе nil (как e() у разбора mkSt).
    static func целое(_ v: String) -> Int? {
        let цифры = v.prefix(while: { $0.isASCII && $0.isNumber })
        guard !цифры.isEmpty, let n = Int(String(цифры.prefix(12))), n > 0 else { return nil }
        return n
    }

    /**
     Место из ссылки — ленте до выдачи: город (mkSt.city) — как у сохранённого поиска (СинхронПодписок.перейтиВ), без
     города — регион (mkSt.region). Чего нет в справочнике, не ставим: выбор человека опечаткой не стираем. Город
     SEO-страницы каталога сюда не идёт — его ставит сама лента, только своей выдаче (NativeFeedView.применитьСнаружи).
     */
    @MainActor
    static func поставитьМесто(_ добавка: ДобавкаЛенты) {
        guard Config.выборГорода else { return }
        if !добавка.город.isEmpty && ГеоДанные.естьГород(добавка.город) {
            СинхронПодписок.перейтиВ(добавка.город)
        } else if !добавка.регион.isEmpty {
            let место = НедавнееМесто(вид: .регион, значение: добавка.регион)
            if let где = место.где { ВыборГорода.shared.выбрать(где, запомнить: место) }
        }
    }
}

/// Что ссылка ленты несёт сверх ИскомоеЛенты: место (city, region; город и район SEO-страницы каталога) и фильтры,
/// которых сохранённый поиск не хранит (sort, verified, photo, ymin, ymax, brands, models, gear, fuel). NativeFeedView
/// ставит их поверх фильтров искомого (применитьСнаружи).
struct ДобавкаЛенты: Hashable, Sendable {
    /// city= адреса — выбор места человека (поставитьМесто).
    var город = ""
    var регион = ""
    /// Город SEO-страницы каталога названием (/kupit/<раздел>/<город>/) — только этой выдаче, выбор не меняет
    /// (ВыборГорода.местоСсылки).
    var городКаталога = ""
    /// Ключ района SEO-страницы (/kupit/<раздел>/<город>/<район>/) — вместе с городом каталога.
    var районКаталога = ""
    var сортировка: СортировкаЛенты? = nil
    var проверенные = false
    var сФото = false
    var годОт: Int? = nil
    var годДо: Int? = nil
    /// brands — марки (mkSt.brands).
    var марки: [String] = []
    /// models — модель строкой (mkSt.model).
    var модель = ""
    /// gear — коробка (mkSt.gear).
    var коробка: [String] = []
    /// fuel — топливо (mkSt.fuel).
    var топливо: [String] = []
    /// Режим «Аренда» ленты (MK_SEO.rent страницы /arenda/<раздел>/).
    var аренда = false

    /// Место SEO-страницы каталога; nil — у ссылки его нет.
    var местоКаталога: ГдеИскать? {
        guard !городКаталога.isEmpty else { return nil }
        return ГдеИскать(город: городКаталога, район: районКаталога)
    }

    var пустая: Bool {
        let безМеста = город.isEmpty && регион.isEmpty && городКаталога.isEmpty
        let безФильтров = сортировка == nil && !проверенные && !сФото && годОт == nil && годДо == nil
        let безАвто = марки.isEmpty && модель.isEmpty && коробка.isEmpty && топливо.isEmpty
        return безМеста && безФильтров && безАвто && !аренда
    }

    /// Фильтры ленты с добавкой поверх: цену и состояние уже поставило искомое, остальное — отсюда.
    func поверх(_ фильтры: ФильтрыЛенты) -> ФильтрыЛенты {
        var итог = фильтры
        if let сортировка { итог.сортировка = сортировка }
        if проверенные { итог.толькоПроверенные = true }
        if сФото { итог.сФото = true }
        if let годОт { итог.годОт = годОт }
        if let годДо { итог.годДо = годДо }
        if !марки.isEmpty { итог.марки = марки }
        if !модель.isEmpty { итог.модель = модель }
        if !коробка.isEmpty { итог.коробка = коробка }
        if !топливо.isEmpty { итог.топливо = топливо }
        return итог
    }
}

/**
 Ссылки кабинета, которые сначала просят войти или стать продавцом (экран гостя сайта):
   · /cabinet?add=1 — баннер главной «Продавайте на Kliko» (a.mh-bn-s data-k="sell"): как кнопка продажи главной
     (SiteHome.путьПродажи) — проверенному продавцу мастер подачи, вошедшему без проверки — верификация eGov
     (?go=egov), гостю — регистрация продавца через eGov (?egov=1);
   · /cabinet?after=import|add|deals (и с ?egov=1 — окно mkRegGate) — _AFTER_OK экрана гостя: после входа или
     регистрации — cabinet?go=import | go=add | go=deals, то есть перенос объявлений, мастер подачи, «Мои сделки». Вошёл
     уже — сразу туда.
 */
@MainActor
enum ВходПоСсылке {
    /// /cabinet?add=1.
    static func продать() {
        switch СессияПриложения.shared.роль {
        case .продавец:
            _ = ПодачаОкно.shared.открыть(.новое)
        case .вошёл:
            ОкноEgov.открыть(Config.страницаСайта("cabinet?go=egov"))
        case .гость:
            ОкноEgov.открыть(Config.страницаСайта("cabinet?egov=1"))
        }
    }

    /// /cabinet?after=<куда>[&egov=1]: адрес — cabinet?go=… своего экрана.
    static func войтиЗатем(_ адрес: URL, egov: Bool) {
        Task { @MainActor in
            var вошёл = СессияПриложения.shared.вошёл
            if вошёл == nil { вошёл = await SiteSession.состояние().вошёл }
            if вошёл == true {
                WebBridge.shared.перейти(адрес)
                return
            }
            let дальше: () -> Void = {
                /* Лист входа или eGov ещё уезжает — свой экран после него. */
                _ = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    WebBridge.shared.перейти(адрес)
                }
            }
            if egov {
                ОкноEgov.открыть(Config.страницаСайта("cabinet?egov=1"), готово: дальше)
            } else {
                ВходПоверх.показать(готово: дальше)
            }
        }
    }
}
