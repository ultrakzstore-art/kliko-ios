import Foundation

/**
 ФИЛЬТРЫ И СОРТИРОВКА НА СЕРВЕРЕ — ЭТАП 33 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «приложение должно быть почти 100%
 похоже на сайт, только нативное SwiftUI»).

 Уточнение этапа 18 отбирало только уже загруженное: какие фильтры понимает api/listings.php, приложению было неизвестно.
 Теперь известно — из самого сайта: строитель запроса ленты _mkApiQS (js/marketplace-feed.min.js) и разбор адреса
 страницы (js/marketplace.min.js). Поэтому отбирает сервер, по всему сайту, теми же параметрами, что шлёт сайт:

   · sort — reco, price (дешевле), price_d (дороже): карта сайта {reco:"reco", price_asc:"price",
     price_desc:"price_d", date_*:"new"}; «Новые» по умолчанию (value="date") в карте нет — уходят как reco, а порядок
     «новые + ТОП» ставит лента (Feed/FeedRhythm.swift). «Старые» и «По рейтингу» сайт сортирует у себя на странице —
     у нас их нет;
   · cond — new или used, пусто — не шлём;
   · verified=1, photo=1;
   · pmin, pmax — целые ₸;
   · ymin, ymax — год выпуска; у сайта они в мастере транспорта (_mkAfDomFor: transport и его разделы);
   · rooms — комнаты через «,», значения MK_AF_ROOMS сайта: "0" — студия, "1"…"4", "5" — «5 и больше»; у сайта — в мастере
     недвижимости, у нас — у жилья (без участков, коммерческой и гаражей: комнат там нет).
 Прочие параметры раздела 8 карты API (фасеты, пробег, площадь, этаж, марки) — не здесь: их значения или смысл сайт в
 скачанном коде не показывает до конца.

 Сменили раздел — цена, год и комнаты сбрасываются, как mkResetCatFilters сайта (шкала цен у разделов разная); сортировка,
 состояние, «Проверенные» и «Только с фото» остаются. Новый поиск и смена города фильтры не трогают. Сохранённый поиск
 (этап 12) несёт цену и состояние — то же, что сайт кладёт в subs.php?action=add (pmin, pmax, cond).
 */

/// «Сначала показывать» — значение <select id="mk-sort"> сайта; что уходит в sort= у api/listings.php — `параметр`.
/// Порядок вариантов — как у сайта: «Новые» (по умолчанию, selected), «Рекомендуемые», «Дешевле», «Дороже».
enum СортировкаЛенты: String, CaseIterable, Hashable, Sendable {
    case новые = "date"
    case рекомендуемые = "reco"
    case дешевле = "price_asc"
    case дороже = "price_desc"

    /// sort= запроса — карта _mkApiQS сайта {reco:"reco", price_asc:"price", price_desc:"price_d", date_*:"new"}[sort]
    /// || "reco". Значения "date" в ней нет: «Новые» уходят как reco, а порядок «новые + ТОП через десять» ставит лента
    /// у себя (ЗолотойРитм, Feed/FeedRhythm.swift), как mkRender сайта.
    var параметр: String {
        switch self {
        case .новые, .рекомендуемые: return "reco"
        case .дешевле:              return "price"
        case .дороже:               return "price_d"
        }
    }

    /// Подпись — sort_reco, sort_new, sort_cheap, sort_expensive сайта.
    var подпись: String {
        switch self {
        case .рекомендуемые: return FilterText.т("sort_reco")
        case .новые:         return FilterText.т("sort_new")
        case .дешевле:       return FilterText.т("sort_cheap")
        case .дороже:        return FilterText.т("sort_expensive")
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
        let транспорт = РазделыСайта.корень(раздел) == "transport"
        switch self {
        case .новое: return FilterText.т(транспорт ? "cond_new_auto" : "cond_new")
        case .бу:    return FilterText.т(транспорт ? "cond_used_auto" : "cond_used")
        }
    }
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

    /// Страница ленты у сайта — per=48 (mkApiNext).
    static let наСтранице = 48
    /// Комнаты в порядке MK_AF_ROOMS сайта: "0" — студия, "5" — «5 и больше».
    static let всеКомнаты = ["0", "1", "2", "3", "4", "5"]

    /// Ничего не отбирает (сортировка не в счёт: она меняет порядок, а не выдачу).
    var пустые: Bool {
        ценаОт == nil && ценаДо == nil && состояние == nil && !толькоПроверенные && !сФото
            && годОт == nil && годДо == nil && комнаты.isEmpty
    }

    /// Сколько выбрано — число на кнопке «Фильтры» (.mk-fc, mkAC сайта): каждая граница и каждый переключатель по одному.
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
        return n
    }

    /// Только то, что умеет сохранённый поиск (цена и состояние — как subs.php сайта), и порядок по умолчанию. Тогда
    /// выдача ленты — та же, что проверит фоновая проверка (этап 12), и её номера годятся ей точкой отсчёта.
    var какУСохранённого: Bool {
        сортировка.параметр == "reco" && !толькоПроверенные && !сФото && годОт == nil && годДо == nil && комнаты.isEmpty
    }

    /**
     Параметры отбора для api/listings.php — как _mkApiQS сайта, в его порядке: cond, verified, photo, pmin, pmax, ymin,
     ymax, rooms. sort ListingsAPI ставит сам, первым полем. Пустое не шлём, как и сайт (r() пропускает "").
     */
    var параметры: [URLQueryItem] {
        var поля: [URLQueryItem] = []
        if let с = состояние { поля.append(URLQueryItem(name: "cond", value: с.rawValue)) }
        if толькоПроверенные { поля.append(URLQueryItem(name: "verified", value: "1")) }
        if сФото { поля.append(URLQueryItem(name: "photo", value: "1")) }
        if let n = ценаОт { поля.append(URLQueryItem(name: "pmin", value: String(n))) }
        if let n = ценаДо { поля.append(URLQueryItem(name: "pmax", value: String(n))) }
        if let n = годОт { поля.append(URLQueryItem(name: "ymin", value: String(n))) }
        if let n = годДо { поля.append(URLQueryItem(name: "ymax", value: String(n))) }
        if !комнаты.isEmpty {
            поля.append(URLQueryItem(name: "rooms", value: Self.комнатыПоПорядку(комнаты).joined(separator: ",")))
        }
        return поля
    }

    // MARK: - Раздел

    /// Год выпуска — у транспорта (мастер авто сайта), кроме запчастей: у детали года выпуска нет.
    static func годДоступен(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "transport" && !РазделыСайта.внутри(раздел, ["auto-parts"])
    }

    /// Комнаты — у жилья: недвижимость без участков, коммерческой и гаражей.
    static func комнатыДоступны(_ раздел: String) -> Bool {
        РазделыСайта.корень(раздел) == "realty"
            && !РазделыСайта.внутри(раздел, ["land", "commercial-realty", "garages-parking"])
    }

    /// Без того, чего у раздела нет: год — не у транспорта, комнаты — не у жилья. Сервер не получит параметр, который к
    /// этой выдаче не относится и молча оставил бы её пустой.
    func годные(для раздел: String) -> ФильтрыЛенты {
        var итог = self
        if !Self.годДоступен(раздел) {
            итог.годОт = nil
            итог.годДо = nil
        }
        if !Self.комнатыДоступны(раздел) { итог.комнаты = [] }
        return итог
    }

    /// Сменили раздел — mkResetCatFilters сайта: цена, год и комнаты сбрасываются, остальное остаётся.
    func дляНовогоРаздела() -> ФильтрыЛенты {
        var итог = self
        итог.ценаОт = nil
        итог.ценаДо = nil
        итог.годОт = nil
        итог.годДо = nil
        итог.комнаты = []
        return итог
    }

    /// Убрать один фильтр — «×» на чипе (mkRemove сайта).
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
        }
    }

    // MARK: - Чипы (.mk-active)

    /**
     Чипы над выдачей — mkRenderActive сайта, в его порядке: «Проверенные продавцы», «С фото», комнаты и год — как фасет
     («Комнаты: Студия, 2»), состояние, «от 10 000 ₸», «до 50 000 ₸». Сортировка — не чип: её видно на кнопке
     «Сначала показывать», как у сайта.
     */
    func чипы(раздела раздел: String) -> [АктивныйФильтр] {
        var итог: [АктивныйФильтр] = []
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
                                       текст: String(format: FilterText.т("facet"), FilterText.т("year"), годы)))
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

    // MARK: - Подписи

    /// «Студия», «2», «5 и больше» — MK_AF_ROOMS сайта.
    static func подписьКомнат(_ значение: String) -> String {
        switch значение {
        case "0": return FilterText.т("studio")
        case "5": return FilterText.т("rooms_5")
        default:  return значение
        }
    }

    /// Выбранные комнаты в порядке MK_AF_ROOMS; чужие значения отбрасываем.
    static func комнатыПоПорядку(_ выбранные: Set<String>) -> [String] {
        всеКомнаты.filter { выбранные.contains($0) }
    }

    /// «10 000 ₸» — fmt() сайта: разряды неразрывным пробелом.
    static func тенге(_ n: Int) -> String {
        DesignText.число(n) + "\u{00A0}₸"
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
