import Foundation

/**
 ФИЛЬТРЫ И СОРТИРОВКА НА СЕРВЕРЕ — ЭТАП 33 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «приложение должно быть почти 100%
 похоже на сайт, только нативное SwiftUI»).

 Уточнение этапа 18 отбирало только уже загруженное: какие фильтры понимает api/listings.php, приложению было неизвестно.
 Теперь известно — из самого сайта: строитель запроса ленты _mkApiQS (js/marketplace-feed.min.js) и разбор адреса
 страницы (js/marketplace.min.js). Поэтому отбирает сервер, по всему сайту, теми же параметрами, что шлёт сайт:

   · sort — reco, price (дешевле), price_d (дороже): карта сайта {reco:"reco", price_asc:"price",
     price_desc:"price_d", date_*:"new"}; «Новые» по умолчанию (value="date") в карте нет — уходят как reco, а порядок
     «новые + ТОП» ставит лента (Feed/FeedRhythm.swift). «Старые» (sort=new) и «По рейтингу» (sort=reco) сайт
     сортирует у себя на странице по загруженному — лента тоже (FeedModel.порядокНаТелефоне);
   · cond — new или used, пусто — не шлём;
   · verified=1, photo=1;
   · pmin, pmax — целые ₸;
   · ymin, ymax — год выпуска; у сайта они в мастере транспорта (_mkAfDomFor: transport и его разделы);
   · rooms — комнаты через «,», значения MK_AF_ROOMS сайта: "0" — студия, "1"…"4", "5" — «5 и больше»; у сайта — в мастере
     недвижимости, у нас — у жилья (без участков, коммерческой и гаражей: комнат там нет);
   · brands, models, gear, fuel — марки через «,», модель строкой, коробка и топливо через «,» (mkSt.brands, mkSt.model,
     mkSt.gear, mkSt.fuel — мастер авто сайта). Приходят ссылкой ленты (?brands=Toyota&models=Camry&gear=Автомат, разбор
     адреса mkSt — СсылкиЛенты); коробку и топливо у транспорта можно выбрать и в листе «Фильтры» (MK_AF_GEAR, MK_AF_FUEL).
     Марку и модель — тоже, у всего транспорта (домен «auto» сайта, _mkAfDomFor: transport, cars-*, auto-parts): марок
     несколько, модель одна и только у одной марки (af_model_many сайта); справочник — /api/auto_models.php, тот же, что у
     мастера авто подачи (ПодачаМодель.загрузитьМарки, моделиМарки). Сайт шлёт их при любом разделе — и мы (годные(для:)
     их не отсекает).
 У КАЖДОГО РАЗДЕЛА СВОИ ФИЛЬТРЫ (владелец 30.09.2026: «в каждом разделе свои фильтры поиска») — как панель и мастер
 подбора сайта, и только то, что api/listings.php действительно применяет:
   · транспорт — марка, модель, год, пробег (kmin/kmax), объём двигателя (emin/emax), коробка, топливо (MKF_SPECS.cars,
     ступени MK_AF_STEPS_NUM); запчасти — «Для какой марки/модели» и тип детали (ptype, /api/parts_types.php);
   · недвижимость — сделка (intent sale/rent), комнаты, площадь (amin/amax), участок (lmin/lmax), этаж (flmin/flmax), год
     постройки (ymin/ymax), размещение коммерции (place, MK_AF_PLACE) и признаки жилья (rt, MK_AF_RT_TAGS) — по виду, как
     _afRtTagGroups мастера;
   · компьютеры и телефоны — процессор (cpuv), ОЗУ от (kmin), накопитель от (emin), дискретная видеокарта (dgpu): группы
     #mkf-cpu, #mkf-ram, #mkf-sto, #mkf-gpu панели сайта, только по mkTechKind;
   · одежда, спорт, дом, детское, хобби, еда, красота, животные, смартфоны — фасеты MKF_SPECS из значений загруженных
     карточек (kind:'text'), только на колонках, что отбирает сервер (MKF_SRV_LIST: cpu→gear, gpu→fuel, ram→ramv,
     storage→stov, значения через «|», как _mkApiQS);
   · услуги — без состояния (cat_condition_mode 'none': сервер cond у них не применяет).
   · прочая электроника (ТВ, мониторы, принтеры, наушники, фото и видео, приставки, часы, комплектующие, оргтехника…) —
     набор раздела из inc/e_specs.php (Filters/ElectronicsSpecs.swift): значения чипами (gear, fuel, ramv, stov через «|»),
     числа на ram и storage — «от — до» (kmin/kmax, emin/emax), год выпуска — ymin/ymax.

 Сменили раздел — фильтры раздела (всё, кроме порядка, состояния, «Проверенных» и «Только с фото») уходят в память ленты
 (FeedModel), а у нового раздела возвращаются те, что были выбраны в нём прежде. Новый поиск и смена города фильтры не
 трогают. Сохранённый поиск (этап 12) несёт цену и состояние — то же, что сайт кладёт в subs.php?action=add (pmin, pmax,
 cond).
 */

/// «Сначала показывать» — значение <select id="mk-sort"> сайта; что уходит в sort= у api/listings.php — `параметр`.
/// Порядок вариантов — как у сайта: «Новые» (по умолчанию, selected), «Рекомендуемые», «Старые», «Дешевле», «Дороже»,
/// «По рейтингу». Седьмой — «date_desc»: его ставит только ссылка ?sort=new (разбор адреса mkSt сайта), в списке его нет.
enum СортировкаЛенты: String, CaseIterable, Hashable, Sendable {
    case новые = "date"
    case рекомендуемые = "reco"
    case старые = "date_asc"
    case дешевле = "price_asc"
    case дороже = "price_desc"
    case поРейтингу = "rating"
    /// ?sort=new ссылки — date_desc сайта: новые подряд, без золотого ритма ТОП (mkRender: «date» !== sort — _top=false
    /// у всех и всё загруженное по created_ts от новых к старым), запрос — sort=new.
    case новыеПодряд = "date_desc"

    /// Варианты списка «Сначала показывать» — <option> сайта, без date_desc (его выбирает только ссылка).
    static let вМеню: [СортировкаЛенты] = [.новые, .рекомендуемые, .старые, .дешевле, .дороже, .поРейтингу]

    /// Пункт списка, отмеченный галочкой: date_desc — это «Новые».
    var пунктМеню: СортировкаЛенты { self == .новыеПодряд ? .новые : self }

    /// sort= запроса — карта _mkApiQS сайта {reco:"reco", price_asc:"price", price_desc:"price_d", date_asc:"new",
    /// date_desc:"new"}[sort] || "reco". Значения "date" в ней нет: «Новые» уходят как reco, а порядок «новые + ТОП через
    /// десять» ставит лента у себя (ЗолотойРитм, Feed/FeedRhythm.swift), как mkRender сайта. «Старые» (date_asc) и
    /// «новые подряд» (date_desc) — "new"; «По рейтингу» в карте нет — reco. Эти три порядка сайт ставит у себя на странице
    /// по загруженному (FeedModel.порядокНаТелефоне).
    var параметр: String {
        switch self {
        case .новые, .рекомендуемые, .поРейтингу: return "reco"
        case .старые, .новыеПодряд:              return "new"
        case .дешевле:                           return "price"
        case .дороже:                            return "price_d"
        }
    }

    /// Подпись — sort_reco, sort_new, sort_old, sort_cheap, sort_expensive, sort_rating сайта; date_desc — тоже «Новые».
    var подпись: String {
        switch self {
        case .рекомендуемые:         return FilterText.т("sort_reco")
        case .новые, .новыеПодряд:   return FilterText.т("sort_new")
        case .старые:                return FilterText.т("sort_old")
        case .дешевле:               return FilterText.т("sort_cheap")
        case .дороже:                return FilterText.т("sort_expensive")
        case .поРейтингу:            return FilterText.т("sort_rating")
        }
    }
}

/// Состояние — cond= у api/listings.php.
enum СостояниеТовара: String, CaseIterable, Hashable, Sendable {
    case новое = "new"
    case бу = "used"

    /// «Новое» и «Б/У» (cond_new, cond_used); у транспорта — «Новая» и «С пробегом», как в мастере авто сайта
    /// (af_cond_new, af_cond_used в mkAfChipsList).
    func подпись(раздел: String) -> String {
        let корень = РазделыСайта.корень(раздел)
        /* Запчасти — обычный товар (cat_condition_mode 'goods'); у жилья — «Новостройка» и «Вторичка» (af_rt_new). */
        let транспорт = корень == "transport" && !ФильтрыЛенты.маркаДляЗапчастей(раздел)
        let жильё = корень == "realty"
        switch self {
        case .новое: return FilterText.т(жильё ? "cond_new_realty" : (транспорт ? "cond_new_auto" : "cond_new"))
        case .бу:    return FilterText.т(жильё ? "cond_used_realty" : (транспорт ? "cond_used_auto" : "cond_used"))
        }
    }
}

/// Числовой отбор ступенями — MK_AF_STEPS_NUM мастера сайта («один выбор для всех числовых полей»): пара параметров.
enum ДиапазонФильтра: String, CaseIterable, Hashable, Sendable {
    case пробег
    case двигатель
    case площадь
    case участок
    case этаж

    /// Параметры api/listings.php: «от» и «до».
    var параметрОт: String {
        switch self {
        case .пробег:    return "kmin"
        case .двигатель: return "emin"
        case .площадь:   return "amin"
        case .участок:   return "lmin"
        case .этаж:      return "flmin"
        }
    }

    var параметрДо: String {
        switch self {
        case .пробег:    return "kmax"
        case .двигатель: return "emax"
        case .площадь:   return "amax"
        case .участок:   return "lmax"
        case .этаж:      return "flmax"
        }
    }

    /// Ступени — MK_AF_STEPS_NUM: km, eng, area, land, floor.
    var ступени: [Double] {
        switch self {
        case .пробег:
            return [10000, 20000, 30000, 50000, 75000, 100000, 130000, 150000, 200000, 250000, 300000, 400000, 500000]
        case .двигатель:
            return [0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.5, 2.7, 3.0, 3.5, 4.0, 4.4, 5.0, 6.0]
        case .площадь:
            return [20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90, 100, 120, 150, 200, 300, 500]
        case .участок:
            return [3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25, 30, 50, 100]
        case .этаж:
            return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30]
        }
    }

    /// Заголовок группы — fac_mileage, af_eng, af_area, af_land, af_floor сайта.
    var подпись: String {
        switch self {
        case .пробег:    return FilterText.т("mileage")
        case .двигатель: return FilterText.т("engine")
        case .площадь:   return FilterText.т("area")
        case .участок:   return FilterText.т("land")
        case .этаж:      return FilterText.т("floor")
        }
    }

    /// Ступень словами: «150 000», «1.6».
    func запись(_ значение: Double) -> String {
        if self == .двигатель { return String(format: "%.1f", значение) }
        return DesignText.число(Int(значение.rounded()))
    }

    /// Значение в запрос: целое — без дробной части («150000»), объём — «1.6».
    static func вЗапрос(_ значение: Double) -> String {
        if значение == значение.rounded() { return String(Int(значение)) }
        return String(format: "%.1f", значение)
    }
}

/// Тип детали (ptype) — ключ справочника /api/parts_types.php и его название для чипа.
struct ТипДеталиФильтра: Hashable, Sendable {
    let ключ: String
    let название: String
}

/// Фасет MKF_SPECS сайта со значениями из загруженных карточек (kind:'text'): колонка и ключ подписи.
struct ФасетРаздела: Hashable, Sendable {
    /// cpu, gpu, ram, storage — колонка объявления.
    let колонка: String
    /// Ключ FilterText подписи («Размер», «Цвет», …).
    let ключПодписи: String
    /// Электроника (inc/e_specs.php): значения справочника вместо «частых из карточек» и готовая подпись.
    var значения: [String] = []
    var заголовок: String = ""

    var подпись: String { заголовок.isEmpty ? FilterText.т(ключПодписи) : заголовок }

    /// Набор из справочника электроники: значения показываем на языке телефона (ev_).
    var электроника: Bool { !значения.isEmpty }

    /// MKF_SRV_LIST сайта: какой параметр отбирает эту колонку списком.
    var параметр: String { ФасетРаздела.параметрКолонки(колонка) }

    static func параметрКолонки(_ колонка: String) -> String {
        switch колонка {
        case "cpu": return "gear"
        case "gpu": return "fuel"
        case "ram": return "ramv"
        default:    return "stov"
        }
    }
}

/// Группа признаков жилья (MK_AF_RT_TAGS): ключ заголовка и значения rt.
struct ГруппаПризнаковЖилья: Hashable, Sendable {
    let ключ: String
    let признаки: [String]
}

/// Какой фильтр — у чипа над выдачей и у его «×».
enum ВидФильтра: Hashable, Sendable {
    case проверенные
    case сФото
    case комнаты
    case год
    case состояние
    case ценаОт
    case ценаДо
    /// Марка, коробка и топливо — чип на каждое значение (mkAfChipsList сайта: {k:"brand", v}), модель — один.
    case марка(String)
    case модель
    case коробка(String)
    case топливо(String)
    /// Фильтры разделов (у каждого — свои): ступени, сделка, признаки и размещение жилья, тип детали, техника, фасеты.
    case диапазон(ДиапазонФильтра)
    case сделка
    case признакЖилья(String)
    case размещение(String)
    case типДетали(String)
    case процессор
    case озу
    case накопитель
    case дискретная
    /// «От — до» характеристики электроники (колонка ram или storage).
    case характеристика(String)
    /// Колонка и значение фасета MKF_SPECS.
    case фасет(String, String)
    /// Поиск, раздел и «Рядом со мной» — чипы mkRenderActive тоже, но живут не в фильтрах: их «×» — в FeedModel.
    case запрос
    case раздел
    case рядом
}

/// Чип выбранного фильтра над выдачей (.mk-achip).
struct АктивныйФильтр: Identifiable, Hashable {
    let вид: ВидФильтра
    let текст: String

    var id: ВидФильтра { вид }
}

/// Что отбирает сервер. По умолчанию — ничего и порядок «Новые» (mkSt.sort:"date" сайта; запрос — sort=reco, как до
/// этапа 33).
struct ФильтрыЛенты: Equatable, Hashable, Sendable {
    var сортировка: СортировкаЛенты = .новые
    /// pmin и pmax — целые ₸; nil — границы нет.
    var ценаОт: Int?
    var ценаДо: Int?
    /// cond; nil — любое.
    var состояние: СостояниеТовара?
    /// verified=1 — только проверенные продавцы.
    var толькоПроверенные = false
    /// photo=1 — только с фото.
    var сФото = false
    /// ymin и ymax — год выпуска (транспорт).
    var годОт: Int?
    var годДо: Int?
    /// rooms — значения MK_AF_ROOMS ("0"…"5"), жильё.
    var комнаты: Set<String> = []
    /// brands — марки в порядке выбора (mkSt.brands сайта); у запчастей это «Для какой марки».
    var марки: [String] = []
    /// models — модель одной строкой (mkSt.model; «Для какой модели» у запчастей); "" — любая.
    var модель = ""
    /// gear — коробка: значения MK_AF_GEAR сайта («Автомат», «Механика», «Робот», «Вариатор»).
    var коробка: [String] = []
    /// fuel — топливо: значения MK_AF_FUEL сайта («Бензин», «Дизель», «Газ», «Гибрид», «Электро»).
    var топливо: [String] = []
    /// Ступени раздела (пробег, объём, площадь, участок, этаж): «от» и «до»; нет ключа — границы нет.
    var ступениОт: [ДиапазонФильтра: Double] = [:]
    var ступениДо: [ДиапазонФильтра: Double] = [:]
    /// intent — сделка у недвижимости: "sale" или "rent"; "" — любая (в режиме «Аренда» не шлём: там intent=rent).
    var сделка = ""
    /// rt — признаки жилья (MK_AF_RT_TAGS), в порядке выбора.
    var признакиЖилья: [String] = []
    /// place — размещение коммерции (MK_AF_PLACE).
    var размещение: [String] = []
    /// ptype — типы детали у запчастей.
    var типыДеталей: [ТипДеталиФильтра] = []
    /// cpuv — производитель процессора (intel, amd, apple; mkSt.fcpu сайта — один).
    var процессор = ""
    /// kmin и emin у техники — «ОЗУ от» и «Накопитель от», ГБ (mkSt.fram, mkSt.fsto).
    var озуОт: Int?
    var накопительОт: Int?
    /// dgpu=1 — только с дискретной видеокартой.
    var дискретная = false
    /// Фасеты MKF_SPECS: колонка → выбранные значения (уходят списком через «|»).
    var фасеты: [String: [String]] = [:]
    /// Электроника (inc/e_specs.php): «от» и «до» числовой характеристики — колонка (ram, storage) → значение
    /// справочника («27», «512GB»); в запрос — числом (kmin/kmax, emin/emax).
    var характеристикиОт: [String: String] = [:]
    var характеристикиДо: [String: String] = [:]

    /// Страница ленты у сайта — per=48 (mkApiNext).
    static let наСтранице = 48
    /// Комнаты в порядке MK_AF_ROOMS сайта: "0" — студия, "5" — «5 и больше».
    static let всеКомнаты = ["0", "1", "2", "3", "4", "5"]
    /// MK_AF_GEAR сайта — значения уходят в gear= как есть, по-русски.
    static let всеКоробки = ["Автомат", "Механика", "Робот", "Вариатор"]
    /// MK_AF_FUEL сайта — значения уходят в fuel= как есть, по-русски.
    static let всеВидыТоплива = ["Бензин", "Дизель", "Газ", "Гибрид", "Электро"]

    /// Ничего не отбирает (сортировка не в счёт: она меняет порядок, а не выдачу).
    var пустые: Bool {
        ценаОт == nil && ценаДо == nil && состояние == nil && !толькоПроверенные && !сФото
            && годОт == nil && годДо == nil && комнаты.isEmpty && безАвто && безРазделов
    }

    /// Ничего из фильтров разделов этапа «у каждого раздела свои» (ступени, сделка, жильё, детали, техника, фасеты).
    var безРазделов: Bool {
        ступениОт.isEmpty && ступениДо.isEmpty && сделка.isEmpty && признакиЖилья.isEmpty && размещение.isEmpty
            && типыДеталей.isEmpty && процессор.isEmpty && озуОт == nil && накопительОт == nil && !дискретная
            && фасеты.values.allSatisfy { $0.isEmpty } && характеристикиОт.isEmpty && характеристикиДо.isEmpty
    }

    /// Ни марки, ни модели, ни коробки, ни топлива.
    var безАвто: Bool { марки.isEmpty && модель.isEmpty && коробка.isEmpty && топливо.isEmpty }

    /// Сколько выбрано — число на кнопке «Фильтры» (.mk-fc, mkAC сайта): каждая граница и каждый переключатель по одному;
    /// марки, модель, коробка и топливо — по одному на группу, как комнаты.
    var число: Int {
        var n = 0
        if ценаОт != nil { n += 1 }
        if ценаДо != nil { n += 1 }
        if состояние != nil { n += 1 }
        if толькоПроверенные { n += 1 }
        if сФото { n += 1 }
        if годОт != nil { n += 1 }
        if годДо != nil { n += 1 }
        if !комнаты.isEmpty { n += 1 }
        if !марки.isEmpty { n += 1 }
        if !модель.isEmpty { n += 1 }
        if !коробка.isEmpty { n += 1 }
        if !топливо.isEmpty { n += 1 }
        n += ступениОт.count + ступениДо.count
        if !сделка.isEmpty { n += 1 }
        if !признакиЖилья.isEmpty { n += 1 }
        if !размещение.isEmpty { n += 1 }
        if !типыДеталей.isEmpty { n += 1 }
        if !процессор.isEmpty { n += 1 }
        if озуОт != nil { n += 1 }
        if накопительОт != nil { n += 1 }
        if дискретная { n += 1 }
        n += фасеты.values.filter { !$0.isEmpty }.count
        n += характеристикиОт.count + характеристикиДо.count
        return n
    }

    /// Только то, что умеет сохранённый поиск (цена и состояние — как subs.php сайта), и порядок по умолчанию. Тогда
    /// выдача ленты — та же, что проверит фоновая проверка (этап 12), и её номера годятся ей точкой отсчёта.
    var какУСохранённого: Bool {
        сортировка.параметр == "reco" && !толькоПроверенные && !сФото && годОт == nil && годДо == nil && комнаты.isEmpty
            && безАвто && безРазделов
    }

    /**
     Параметры отбора для api/listings.php — как _mkApiQS сайта, в его порядке: cond, verified, photo, pmin, pmax, brands,
     models, gear, fuel, ymin, ymax, rooms. sort ListingsAPI ставит сам, первым полем. Пустое не шлём, как и сайт (r()
     пропускает "").
     */
    var параметры: [URLQueryItem] {
        var поля: [URLQueryItem] = []
        if let с = состояние { поля.append(URLQueryItem(name: "cond", value: с.rawValue)) }
        if толькоПроверенные { поля.append(URLQueryItem(name: "verified", value: "1")) }
        if сФото { поля.append(URLQueryItem(name: "photo", value: "1")) }
        if let n = ценаОт { поля.append(URLQueryItem(name: "pmin", value: String(n))) }
        if let n = ценаДо { поля.append(URLQueryItem(name: "pmax", value: String(n))) }
        /* e.brands.join(","), String(e.model).trim(), e.gear.join(","), e.fuel.join(",") — как _mkApiQS. */
        if !марки.isEmpty { поля.append(URLQueryItem(name: "brands", value: марки.joined(separator: ","))) }
        let модельСтрокой = модель.trimmingCharacters(in: .whitespacesAndNewlines)
        if !модельСтрокой.isEmpty { поля.append(URLQueryItem(name: "models", value: модельСтрокой)) }
        if !коробка.isEmpty { поля.append(URLQueryItem(name: "gear", value: коробка.joined(separator: ","))) }
        if !топливо.isEmpty { поля.append(URLQueryItem(name: "fuel", value: топливо.joined(separator: ","))) }
        if let n = годОт { поля.append(URLQueryItem(name: "ymin", value: String(n))) }
        if let n = годДо { поля.append(URLQueryItem(name: "ymax", value: String(n))) }
        if !комнаты.isEmpty {
            поля.append(URLQueryItem(name: "rooms", value: Self.комнатыПоПорядку(комнаты).joined(separator: ",")))
        }
        поля.append(contentsOf: параметрыРазделов)
        return поля
    }

    /**
     Фильтры разделов — те же имена, что у _mkApiQS: place, rt, ptype, intent, ступени (kmin/kmax, emin/emax, amin/amax,
     lmin/lmax, flmin/flmax), техника (kmin, emin, cpuv, dgpu) и фасеты списком через «|» (gear, fuel, ramv, stov).
     */
    private var параметрыРазделов: [URLQueryItem] {
        var поля: [URLQueryItem] = []
        if !размещение.isEmpty { поля.append(URLQueryItem(name: "place", value: размещение.joined(separator: ","))) }
        if !признакиЖилья.isEmpty { поля.append(URLQueryItem(name: "rt", value: признакиЖилья.joined(separator: ","))) }
        if !типыДеталей.isEmpty {
            поля.append(URLQueryItem(name: "ptype", value: типыДеталей.map { $0.ключ }.joined(separator: ",")))
        }
        if сделка == "sale" || сделка == "rent" { поля.append(URLQueryItem(name: "intent", value: сделка)) }
        for д in ДиапазонФильтра.allCases {
            if let v = ступениОт[д], v > 0 { поля.append(URLQueryItem(name: д.параметрОт, value: ДиапазонФильтра.вЗапрос(v))) }
            if let v = ступениДо[д], v > 0 { поля.append(URLQueryItem(name: д.параметрДо, value: ДиапазонФильтра.вЗапрос(v))) }
        }
        if let n = озуОт, n > 0 { поля.append(URLQueryItem(name: "kmin", value: String(n))) }
        if let n = накопительОт, n > 0 { поля.append(URLQueryItem(name: "emin", value: String(n))) }
        if !процессор.isEmpty { поля.append(URLQueryItem(name: "cpuv", value: процессор)) }
        if дискретная { поля.append(URLQueryItem(name: "dgpu", value: "1")) }
        for колонка in ["cpu", "gpu", "ram", "storage"] {
            guard let значения = фасеты[колонка], !значения.isEmpty else { continue }
            поля.append(URLQueryItem(name: ФасетРаздела.параметрКолонки(колонка),
                                     value: значения.joined(separator: "|")))
        }
        /* Числа электроники — MKF_SRV_RANGE сайта: ram → kmin/kmax, storage → emin/emax. */
        for колонка in ["ram", "storage"] {
            let имяОт = колонка == "ram" ? "kmin" : "emin"
            let имяДо = колонка == "ram" ? "kmax" : "emax"
            if let v = характеристикиОт[колонка], let n = ХарактеристикиЭлектроники.вЧисло(v) {
                поля.append(URLQueryItem(name: имяОт, value: n))
            }
            if let v = характеристикиДо[колонка], let n = ХарактеристикиЭлектроники.вЧисло(v) {
                поля.append(URLQueryItem(name: имяДо, value: n))
            }
        }
        return поля
    }

    // MARK: - Раздел

    /// Транспорт без запчастей: у детали года выпуска, пробега и двигателя нет.
    static func машины(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "transport" && !РазделыСайта.внутри(раздел, ["auto-parts"])
    }

    /// Год — у транспорта (мастер авто сайта) и у построенного жилья: год постройки (фасет r_year, ymin/ymax — та же
    /// колонка year); у участка его нет.
    static func годДоступен(_ раздел: String) -> Bool {
        машины(раздел) || (РазделыСайта.корень(раздел) == "realty" && !РазделыСайта.внутри(раздел, ["land"]))
            || ХарактеристикиЭлектроники.набор(раздел).contains { $0.колонка == "year" }
    }

    /// «Год выпуска» у транспорта, «Год постройки» у жилья (fac_build_year).
    static func подписьГода(_ раздел: String) -> String {
        FilterText.т(РазделыСайта.корень(раздел) == "realty" ? "build_year" : "year")
    }

    /// Коробка и топливо в листе «Фильтры» — транспорт без запчастей (шаги «Коробка» и «Топливо» мастера авто сайта).
    /// Пришедшие ссылкой при другом разделе не отсекаются — сайт их шлёт.
    static func автоДоступно(_ раздел: String) -> Bool {
        машины(раздел)
    }

    /// Ступени раздела: у машин — пробег и объём (MKF_SPECS.cars), у жилья — как мастер _afxRange по виду: площадь (не у
    /// участка), участок (дом, земля), этаж (квартира, коммерция).
    static func ступени(_ раздел: String) -> [ДиапазонФильтра] {
        if машины(раздел) { return [.пробег, .двигатель] }
        guard РазделыСайта.корень(раздел) == "realty" else { return [] }
        if РазделыСайта.внутри(раздел, ["land"]) { return [.участок] }
        if РазделыСайта.внутри(раздел, ["houses"]) { return [.площадь, .участок] }
        if РазделыСайта.внутри(раздел, ["apartments", "commercial-realty"]) { return [.площадь, .этаж] }
        return [.площадь]
    }

    /// Состояние — не у услуг и работы: cat_condition_mode 'none', сервер cond там не применяет (cond_free).
    static func состояниеДоступно(_ раздел: String) -> Bool {
        let корень = РазделыСайта.корень(раздел)
        return корень != "services" && корень != "jobs"
    }

    /// Сделка (intent) — у недвижимости: «Купить» или «Снять» (шаг «Сделка» мастера жилья).
    static func сделкаДоступна(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "realty"
    }

    /// Размещение (place) — только у коммерции (af_rt_place мастера).
    static func размещениеДоступно(_ раздел: String) -> Bool {
        РазделыСайта.внутри(раздел, ["commercial-realty"])
    }

    /// MK_AF_PLACE сайта — ключи те же, что у формы подачи.
    static let всеРазмещения = ["bc", "mall", "house", "standalone", "warehouse", "basement"]

    /**
     Группы признаков жилья — _afRtTagGroups мастера: аренде — срок и условия, покупке — документы; ремонт — всем, кроме
     участка; тип дома и санузел — только квартире и дому; «Кто сдаёт» — только аренде.
     */
    static func группыПризнаков(_ раздел: String, сделка: String, аренда: Bool) -> [ГруппаПризнаковЖилья] {
        guard РазделыСайта.корень(раздел) == "realty" else { return [] }
        let снять = аренда || сделка == "rent"
        let квартираИлиДом = РазделыСайта.внутри(раздел, ["apartments", "houses"])
        let участок = РазделыСайта.внутри(раздел, ["land"])
        var итог: [ГруппаПризнаковЖилья] = []
        if снять {
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_term", признаки: ["term:long", "term:daily"]))
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_cond",
                                             признаки: ["furniture", "utilities", "parking", "kids", "pets"]))
        }
        if сделка == "sale" && !аренда {
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_docs", признаки: ["docs:private", "mortgage_ok"]))
        }
        if !участок {
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_reno", признаки: ["reno:euro", "reno:design", "reno:cosmetic"]))
        }
        if квартираИлиДом {
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_bld", признаки: ["bld:brick", "bld:monolith", "bld:panel"]))
            итог.append(ГруппаПризнаковЖилья(ключ: "rtg_bath", признаки: ["bath:separate", "bath:combined"]))
        }
        if снять { итог.append(ГруппаПризнаковЖилья(ключ: "rtg_owner", признаки: ["owner:owner"])) }
        return итог
    }

    /// Признак жилья словами: ключ FilterText — «rt_» и значение с «_» вместо «:» (rt_term_long, rt_reno_euro).
    static func подписьПризнака(_ значение: String) -> String {
        FilterText.т("rt_" + значение.replacingOccurrences(of: ":", with: "_"))
    }

    /// Тип детали (ptype) — у запчастей, шаг «Тип запчасти» мастера сайта.
    static func типДеталиДоступен(_ раздел: String) -> Bool {
        маркаДляЗапчастей(раздел)
    }

    /// mkTechKind сайта — ТОЧНО по разделу, не по предкам: "pc" (компьютеры, ноутбуки, настольные, моноблоки), "phone"
    /// (телефоны и планшеты), "" — отборов техники нет (у машины те же kmin/emin значат пробег и объём).
    static func видТехники(_ раздел: String) -> String {
        if ["phones-tablets", "smartphones", "tablets"].contains(раздел) { return "phone" }
        if ["computers", "laptops", "desktops", "all-in-one"].contains(раздел) { return "pc" }
        return ""
    }

    /// Чипы #mk-d-ram и #mk-d-sto панели сайта: «8+», «16+», «32+»; «256 ГБ+», «512 ГБ+», «1 ТБ+».
    static let ступениОЗУ = [8, 16, 32]
    static let ступениНакопителя = [256, 512, 1024]
    /// #mk-d-cpu: Intel, AMD, Apple — значения cpuv.
    static let производители = ["intel", "amd", "apple"]

    static func подписьПроизводителя(_ ключ: String) -> String {
        switch ключ {
        case "intel": return "Intel"
        case "amd":   return "AMD"
        case "apple": return "Apple"
        default:      return ключ
        }
    }

    static func подписьНакопителя(_ гб: Int) -> String {
        гб >= 1024 ? String(format: FilterText.т("tb_plus"), String(гб / 1024))
            : String(format: FilterText.т("gb_plus"), String(гб))
    }

    /**
     Фасеты MKF_SPECS сайта со значениями из карточек — только на колонках MKF_SRV_LIST (их отбирает сервер). Смартфоны и
     планшеты — «Чипсет» (ОЗУ и память у них — чипами техники); прочие — по корню. «Возраст» животных (колонка year)
     сервер списком не отбирает — его нет.
     */
    static func фасеты(_ раздел: String) -> [ФасетРаздела] {
        /* Электроника — из справочника (mkFacetSet сайта: _mkESpecFacets раньше MKF_SPECS). */
        let электроника = ХарактеристикиЭлектроники.набор(раздел).filter { $0.чипами }
        if !электроника.isEmpty {
            return электроника.map { х in
                ФасетРаздела(колонка: х.колонка, ключПодписи: "", значения: х.значения, заголовок: х.подпись)
            }
        }
        if РазделыСайта.внутри(раздел, ["smartphones", "tablets"]) {
            return [ФасетРаздела(колонка: "cpu", ключПодписи: "fs_chipset")]
        }
        switch РазделыСайта.корень(раздел) {
        case "clothing":
            return [ФасетРаздела(колонка: "storage", ключПодписи: "fs_size"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_color"),
                    ФасетРаздела(колонка: "ram", ключПодписи: "fs_material")]
        case "sport":
            return [ФасетРаздела(колонка: "storage", ключПодписи: "fs_size"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_material"),
                    ФасетРаздела(колонка: "gpu", ключПодписи: "fs_type")]
        case "home-garden":
            return [ФасетРаздела(колонка: "ram", ключПодписи: "fs_material"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_color"),
                    ФасетРаздела(колонка: "storage", ключПодписи: "fs_size")]
        case "kids":
            return [ФасетРаздела(колонка: "storage", ключПодписи: "fs_age"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_gender"),
                    ФасетРаздела(колонка: "ram", ключПодписи: "fs_material")]
        case "hobby":
            return [ФасетРаздела(колонка: "cpu", ключПодписи: "fs_type"),
                    ФасетРаздела(колонка: "ram", ключПодписи: "fs_material")]
        case "food-farm":
            return [ФасетРаздела(колонка: "storage", ключПодписи: "fs_weight"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_sort")]
        case "beauty":
            return [ФасетРаздела(колонка: "storage", ключПодписи: "fs_volume"),
                    ФасетРаздела(колонка: "cpu", ключПодписи: "fs_type")]
        case "animals":
            return [ФасетРаздела(колонка: "cpu", ключПодписи: "fs_species"),
                    ФасетРаздела(колонка: "ram", ключПодписи: "fs_breed")]
        default:
            return []
        }
    }

    /// Числовые характеристики электроники «от — до» (ram, storage) — в порядке справочника.
    static func диапазоныХарактеристик(_ раздел: String) -> [ХарактеристикаЭлектроники] {
        ХарактеристикиЭлектроники.набор(раздел).filter { $0.диапазоном }
    }

    /// Значения фасета — «топ по частоте» из загруженных карточек, как чипы kind:'text' сайта (до 12), и всегда
    /// выбранные: иначе снять их было бы нечем. Одинаковые без учёта регистра — одно (mkFacetStr).
    static func значенияФасета(_ колонка: String, из товары: [Listing], выбранные: [String]) -> [String] {
        var счёт: [String: Int] = [:]
        var показ: [String: String] = [:]
        for товар in товары {
            let сырое: String?
            switch колонка {
            case "cpu": сырое = товар.cpuСтрокой
            case "gpu": сырое = товар.gpuСтрокой
            case "ram": сырое = товар.ramСтрокой
            default:    сырое = товар.storageСтрокой
            }
            let значение = (сырое ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !значение.isEmpty, значение.count <= 40, !значение.contains("|") else { continue }
            let ключ = значение.lowercased()
            счёт[ключ, default: 0] += 1
            if показ[ключ] == nil { показ[ключ] = значение }
        }
        let частые = счёт.sorted { а, б in а.value != б.value ? а.value > б.value : а.key < б.key }
            .prefix(12)
            .compactMap { показ[$0.key] }
        var итог = выбранные
        for значение in частые where !итог.contains(where: { $0.lowercased() == значение.lowercased() }) {
            итог.append(значение)
        }
        return итог
    }

    /// Марка и модель в листе «Фильтры» — у всего транспорта, как шаги brand и model мастера авто сайта (_mkAfDomFor →
    /// "auto": transport и все его разделы, запчасти тоже — у них это «Для какой марки»).
    static func маркаДоступна(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "transport"
    }

    /// Запчасти: марка и модель — «Для какой марки», «Для какой модели» (af_brand_for, af_model_for сайта).
    static func маркаДляЗапчастей(_ раздел: String) -> Bool {
        РазделыСайта.внутри(раздел, ["auto-parts"])
    }

    /// Марки сменились — модель прочь: она бывает только у одной марки (af_model_many сайта).
    static func переключитьМарку(_ марка: String, в ф: inout ФильтрыЛенты) {
        переключить(марка, в: &ф.марки)
        ф.модель = ""
    }

    /// Комнаты — у жилья: недвижимость без участков, коммерческой и гаражей.
    static func комнатыДоступны(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "realty"
            && !РазделыСайта.внутри(раздел, ["land", "commercial-realty", "garages-parking"])
    }

    /// Без того, чего у раздела нет: год — не у транспорта, комнаты — не у жилья. Сервер не получит параметр, который к
    /// этой выдаче не относится и молча оставил бы её пустой.
    func годные(для раздел: String, аренда: Bool = false) -> ФильтрыЛенты {
        var итог = self
        if !Self.годДоступен(раздел) {
            итог.годОт = nil
            итог.годДо = nil
        }
        if !Self.комнатыДоступны(раздел) { итог.комнаты = [] }
        /* Фильтры разделов — только свои: чужой пробег или «Евроремонт» молча оставили бы выдачу пустой. */
        let ступени = Set(Self.ступени(раздел))
        итог.ступениОт = итог.ступениОт.filter { ступени.contains($0.key) }
        итог.ступениДо = итог.ступениДо.filter { ступени.contains($0.key) }
        if !Self.сделкаДоступна(раздел) || аренда { итог.сделка = "" }
        let признаки = Set(Self.группыПризнаков(раздел, сделка: итог.сделка, аренда: аренда).flatMap { $0.признаки })
        итог.признакиЖилья = итог.признакиЖилья.filter { признаки.contains($0) }
        if !Self.размещениеДоступно(раздел) { итог.размещение = [] }
        if !Self.типДеталиДоступен(раздел) { итог.типыДеталей = [] }
        let техника = Self.видТехники(раздел)
        if техника.isEmpty {
            итог.озуОт = nil
            итог.накопительОт = nil
        }
        if техника != "pc" {
            итог.процессор = ""
            итог.дискретная = false
        }
        let колонки = Set(Self.фасеты(раздел).map { $0.колонка })
        итог.фасеты = итог.фасеты.filter { колонки.contains($0.key) && !$0.value.isEmpty }
        let числа = Set(Self.диапазоныХарактеристик(раздел).map { $0.колонка })
        итог.характеристикиОт = итог.характеристикиОт.filter { числа.contains($0.key) }
        итог.характеристикиДо = итог.характеристикиДо.filter { числа.contains($0.key) }
        return итог
    }

    /// Фильтры раздела, в который перешли: сохранённые прежде (память ленты) или пустые — а порядок, состояние,
    /// «Проверенные» и «Только с фото» остаются нынешними: они общие для всей ленты.
    func дляРаздела(сохранённые: ФильтрыЛенты?) -> ФильтрыЛенты {
        guard var итог = сохранённые else { return дляНовогоРаздела() }
        итог.сортировка = сортировка
        итог.состояние = состояние
        итог.толькоПроверенные = толькоПроверенные
        итог.сФото = сФото
        return итог
    }

    /// Сменили раздел — mkResetCatFilters сайта: цена, год, комнаты, марки, модель, коробка и топливо сбрасываются,
    /// остальное остаётся.
    func дляНовогоРаздела() -> ФильтрыЛенты {
        var итог = self
        итог.ценаОт = nil
        итог.ценаДо = nil
        итог.годОт = nil
        итог.годДо = nil
        итог.комнаты = []
        итог.марки = []
        итог.модель = ""
        итог.коробка = []
        итог.топливо = []
        итог.ступениОт = [:]
        итог.ступениДо = [:]
        итог.сделка = ""
        итог.признакиЖилья = []
        итог.размещение = []
        итог.типыДеталей = []
        итог.процессор = ""
        итог.озуОт = nil
        итог.накопительОт = nil
        итог.дискретная = false
        итог.фасеты = [:]
        итог.характеристикиОт = [:]
        итог.характеристикиДо = [:]
        return итог
    }

    /// Убрать один фильтр — «×» на чипе (mkRemove сайта; марка, коробка и топливо — одно значение, как чип мастера авто).
    mutating func убрать(_ вид: ВидФильтра) {
        switch вид {
        case .проверенные: толькоПроверенные = false
        case .сФото:       сФото = false
        case .комнаты:     комнаты = []
        case .год:
            годОт = nil
            годДо = nil
        case .состояние:   состояние = nil
        case .ценаОт:      ценаОт = nil
        case .ценаДо:      ценаДо = nil
        case .марка(let значение):   марки.removeAll { $0 == значение }
        case .модель:                модель = ""
        case .коробка(let значение): коробка.removeAll { $0 == значение }
        case .топливо(let значение): топливо.removeAll { $0 == значение }
        case .диапазон(let д):
            ступениОт[д] = nil
            ступениДо[д] = nil
        case .сделка:                сделка = ""
        case .признакЖилья(let значение): признакиЖилья.removeAll { $0 == значение }
        case .размещение(let значение):   размещение.removeAll { $0 == значение }
        case .типДетали(let ключ):        типыДеталей.removeAll { $0.ключ == ключ }
        case .процессор:             процессор = ""
        case .озу:                   озуОт = nil
        case .накопитель:            накопительОт = nil
        case .дискретная:            дискретная = false
        case .характеристика(let колонка):
            характеристикиОт[колонка] = nil
            характеристикиДо[колонка] = nil
        case .фасет(let колонка, let значение):
            var список = фасеты[колонка] ?? []
            список.removeAll { $0 == значение }
            фасеты[колонка] = список.isEmpty ? nil : список
        case .запрос, .раздел, .рядом:
            break               // не фильтры — их убирает FeedModel.убратьФильтр
        }
    }

    /// Вариант коробки или топлива в листе — выбрать или снять (у сайта это чипы мастера авто, несколько сразу).
    static func переключить(_ значение: String, в список: inout [String]) {
        if список.contains(значение) {
            список.removeAll { $0 == значение }
        } else {
            список.append(значение)
        }
    }

    // MARK: - Чипы (.mk-active)

    /**
     Чипы над выдачей — mkRenderActive сайта, в его порядке: «Проверенные продавцы», «С фото», комнаты и год — как фасет
     («Комнаты: Студия, 2»), состояние, «от 10 000 ₸», «до 50 000 ₸». Сортировка — не чип: её видно на кнопке
     «Сначала показывать», как у сайта. Впереди — чипы мастера авто (mkAfChipsList, полоса #mk-afbar): каждая марка и
     модель как есть («Toyota», «Camry»), каждая коробка и топливо — словом на языке телефона («Автомат», «Бензин»).
     */
    func чипы(раздела раздел: String) -> [АктивныйФильтр] {
        var итог: [АктивныйФильтр] = []
        for марка in марки {
            итог.append(АктивныйФильтр(вид: .марка(марка), текст: марка))
        }
        if !модель.isEmpty {
            итог.append(АктивныйФильтр(вид: .модель, текст: модель))
        }
        for значение in коробка {
            итог.append(АктивныйФильтр(вид: .коробка(значение), текст: Self.подписьАвто(значение)))
        }
        for значение in топливо {
            итог.append(АктивныйФильтр(вид: .топливо(значение), текст: Self.подписьАвто(значение)))
        }
        итог.append(contentsOf: чипыРазделов(раздел))
        if толькоПроверенные {
            итог.append(АктивныйФильтр(вид: .проверенные, текст: FilterText.т("verified_chip")))
        }
        if сФото {
            итог.append(АктивныйФильтр(вид: .сФото, текст: FilterText.т("photo_chip")))
        }
        if !комнаты.isEmpty {
            let список = Self.комнатыПоПорядку(комнаты).map { Self.подписьКомнат($0) }.joined(separator: ", ")
            итог.append(АктивныйФильтр(вид: .комнаты,
                                       текст: String(format: FilterText.т("facet"), FilterText.т("rooms"), список)))
        }
        if let годы = Self.диапазон(годОт, годДо, { String($0) }) {
            итог.append(АктивныйФильтр(вид: .год,
                                       текст: String(format: FilterText.т("facet"), Self.подписьГода(раздел), годы)))
        }
        if let с = состояние {
            итог.append(АктивныйФильтр(вид: .состояние, текст: с.подпись(раздел: раздел)))
        }
        if let n = ценаОт {
            итог.append(АктивныйФильтр(вид: .ценаОт, текст: String(format: FilterText.т("from_x"), Self.тенге(n))))
        }
        if let n = ценаДо {
            итог.append(АктивныйФильтр(вид: .ценаДо, текст: String(format: FilterText.т("to_x"), Self.тенге(n))))
        }
        return итог
    }

    /// Чипы фильтров раздела: сделка, тип детали, размещение, признаки жилья, ступени («Пробег, км: до 150 000»),
    /// техника и фасеты («Размер: M»).
    private func чипыРазделов(_ раздел: String) -> [АктивныйФильтр] {
        var итог: [АктивныйФильтр] = []
        let формат = FilterText.т("facet")
        if !сделка.isEmpty {
            итог.append(АктивныйФильтр(вид: .сделка, текст: FilterText.т(сделка == "rent" ? "deal_rent" : "deal_sale")))
        }
        for тип in типыДеталей {
            итог.append(АктивныйФильтр(вид: .типДетали(тип.ключ), текст: тип.название))
        }
        for значение in размещение {
            итог.append(АктивныйФильтр(вид: .размещение(значение), текст: FilterText.т("pl_" + значение)))
        }
        for значение in признакиЖилья {
            итог.append(АктивныйФильтр(вид: .признакЖилья(значение), текст: Self.подписьПризнака(значение)))
        }
        for д in ДиапазонФильтра.allCases {
            guard let строка = Self.диапазонСтупеней(д, ступениОт[д], ступениДо[д]) else { continue }
            итог.append(АктивныйФильтр(вид: .диапазон(д), текст: String(format: формат, д.подпись, строка)))
        }
        if !процессор.isEmpty {
            итог.append(АктивныйФильтр(вид: .процессор, текст: Self.подписьПроизводителя(процессор)))
        }
        if let n = озуОт {
            итог.append(АктивныйФильтр(вид: .озу, текст: String(format: формат, FilterText.т("ram"), String(n) + "+")))
        }
        if let n = накопительОт {
            итог.append(АктивныйФильтр(вид: .накопитель, текст: Self.подписьНакопителя(n)))
        }
        if дискретная {
            итог.append(АктивныйФильтр(вид: .дискретная, текст: FilterText.т("discrete")))
        }
        let наборФасетов = Self.фасеты(раздел)
        let подписи = Dictionary(наборФасетов.map { ($0.колонка, $0.подпись) }, uniquingKeysWith: { а, _ in а })
        let электроника = наборФасетов.contains { $0.электроника }
        for колонка in ["cpu", "gpu", "ram", "storage"] {
            for значение in фасеты[колонка] ?? [] {
                let показ = электроника ? ХарактеристикиЭлектроники.показ(значение) : значение
                let текст = подписи[колонка].map { String(format: формат, $0, показ) } ?? показ
                итог.append(АктивныйФильтр(вид: .фасет(колонка, значение), текст: текст))
            }
        }
        for х in Self.диапазоныХарактеристик(раздел) {
            guard let строка = Self.диапазонХарактеристики(характеристикиОт[х.колонка], характеристикиДо[х.колонка])
            else { continue }
            итог.append(АктивныйФильтр(вид: .характеристика(х.колонка), текст: String(format: формат, х.подпись, строка)))
        }
        return итог
    }

    /// «от 1.6», «до 150 000» или «50–100» — _afRange сайта для ступеней.
    static func диапазонСтупеней(_ д: ДиапазонФильтра, _ от: Double?, _ до: Double?) -> String? {
        switch (от, до) {
        case let (.some(а), .some(б)): return д.запись(а) + "–" + д.запись(б)
        case let (.some(а), .none):    return String(format: FilterText.т("from_x"), д.запись(а))
        case let (.none, .some(б)):    return String(format: FilterText.т("to_x"), д.запись(б))
        case (.none, .none):           return nil
        }
    }

    /// «от 27», «до 1TB» или «27–32» — значения справочника электроники как есть.
    static func диапазонХарактеристики(_ от: String?, _ до: String?) -> String? {
        switch (от, до) {
        case let (.some(а), .some(б)): return а + "–" + б
        case let (.some(а), .none):    return String(format: FilterText.т("from_x"), а)
        case let (.none, .some(б)):    return String(format: FilterText.т("to_x"), б)
        case (.none, .none):           return nil
        }
    }

    // MARK: - Подписи

    /// «Студия», «2», «5 и больше» — MK_AF_ROOMS сайта.
    static func подписьКомнат(_ значение: String) -> String {
        switch значение {
        case "0": return FilterText.т("studio")
        case "5": return FilterText.т("rooms_5")
        default:  return значение
        }
    }

    /// Коробка и топливо словом на языке телефона — MKF_TR сайта (fac_auto, fac_petrol, …); незнакомое — как есть.
    static func подписьАвто(_ значение: String) -> String {
        let ключи: [String: String] = [
            "Автомат": "fac_auto", "Механика": "fac_manual", "Робот": "fac_robot", "Вариатор": "fac_cvt",
            "Бензин": "fac_petrol", "Дизель": "fac_diesel", "Газ": "fac_gas", "Гибрид": "fac_hybrid",
            "Электро": "fac_electric"
        ]
        guard let ключ = ключи[значение] else { return значение }
        return FilterText.т(ключ)
    }

    /// Выбранные комнаты в порядке MK_AF_ROOMS; чужие значения отбрасываем.
    static func комнатыПоПорядку(_ выбранные: Set<String>) -> [String] {
        всеКомнаты.filter { выбранные.contains($0) }
    }

    /// «10 000 ₸» — fmt() сайта: разряды неразрывным пробелом.
    static func тенге(_ n: Int) -> String {
        (DesignText.число(n) + "\u{00A0}₸").слеваНаправо
    }

    /// _afRange сайта: «от A», «до B» или «A–B»; нет ни одной границы — nil.
    static func диапазон(_ от: Int?, _ до: Int?, _ запись: (Int) -> String) -> String? {
        switch (от, до) {
        case let (.some(а), .some(б)): return запись(а) + "–" + запись(б)
        case let (.some(а), .none):    return String(format: FilterText.т("from_x"), запись(а))
        case let (.none, .some(б)):    return String(format: FilterText.т("to_x"), запись(б))
        case (.none, .none):           return nil
        }
    }

    /// Цена одной строкой — название сохранённого поиска: «10 000–50 000 ₸», «от 10 000 ₸», «до 50 000 ₸».
    static func подписьЦены(от: Int?, до: Int?) -> String? {
        guard let строка = диапазон(от, до, { DesignText.число($0) }) else { return nil }
        return строка + "\u{00A0}₸"
    }

    // MARK: - Набранное

    /// Число из поля: только цифры, не длиннее `цифр`; пусто или ноль — границы нет.
    static func числоИз(_ текст: String, цифр: Int) -> Int? {
        let цифры = String(текст.filter { $0.isASCII && $0.isNumber }.prefix(цифр))
        guard let n = Int(цифры), n > 0 else { return nil }
        return n
    }

    /// Год из поля — только правдоподобный (1900…2100): недонабранное «20» ленту не перезапрашивает.
    static func год(_ текст: String) -> Int? {
        guard let n = числоИз(текст, цифр: 4), (1900...2100).contains(n) else { return nil }
        return n
    }
}

extension ФильтрыЛенты {
    /// Фильтры сохранённого поиска (этап 12): цена и состояние — всё, что он несёт; остальное — по умолчанию.
    init(искомое: ИскомоеЛенты) {
        self.init()
        ценаОт = искомое.ценаОт
        ценаДо = искомое.ценаДо
        состояние = СостояниеТовара(rawValue: искомое.состояние)
    }
}

extension ИскомоеЛенты {
    /// Цена и состояние словами — к названию сохранённого поиска: «от 10 000 ₸», «Б/У».
    var подписиФильтров: [String] {
        var итог: [String] = []
        if let цена = ФильтрыЛенты.подписьЦены(от: ценаОт, до: ценаДо) { итог.append(цена) }
        if let с = СостояниеТовара(rawValue: состояние) { итог.append(с.подпись(раздел: раздел)) }
        return итог
    }
}
