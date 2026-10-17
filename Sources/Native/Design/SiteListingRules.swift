import Foundation

/**
 ПРАВИЛА СТРАНИЦЫ ОБЪЯВЛЕНИЯ САЙТА (этап 28, владелец 25.09.2026: «почти 100% похоже на сайт»).

 Что показать и как назвать — так же, как решает js/marketplace.min.js сайта, по тем же полям ответа api/listings.php:
 mkCond (метка на фото), mkPriceHTML (цена), mkHoursText/mkHoursOpen/mkHoursState (режим работы), mkTrustBlock
 («Продавец утверждает»), mkBuyTipsKey (совет «… — на что смотреть»), mkDate («Добавлено сегодня»). Правила собраны
 здесь, отдельно от вида, чтобы страница была просто разметкой, а расхождение с сайтом искалось в одном месте.
 */
extension Listing {
    /// Услуга или вакансия (mkIsService): «от» перед ценой, подпись «Режим работы», «Связаться» внизу.
    var услуга: Bool { РазделыСайта.услуга(категория) }

    /// Корень раздела: «transport», «services»… — пусто, если раздела нет.
    var корень: String { РазделыСайта.корень(категория) }

    // MARK: - Метка на фото (mkCond)

    struct МеткаСостояния: Hashable {
        let текст: String
        /// Новое — зелёная метка, б/у и «С пробегом» — оранжевая.
        let новое: Bool
    }

    /// «Б/У», «Новое», «С пробегом», «Без пробега», «Новостройка», «Вторичный рынок». nil — сайт метку не ставит:
    /// у услуг, вакансий и нежилой недвижимости.
    var меткаСостояния: МеткаСостояния? {
        let новое = состояние.map { $0 == "new" } ?? isNew
        if let раздел = категория, let класс = РазделыСайта.дерево[раздел]?.класс {
            guard класс == "residential" && !forRent else { return nil }
            return МеткаСостояния(текст: ListingPageText.т(новое ? "realty_new" : "realty_used"), новое: новое)
        }
        switch корень {
        case "services", "jobs":
            return nil
        case "transport" where !РазделыСайта.внутри(категория, ["auto-parts"]):
            return МеткаСостояния(текст: ListingPageText.т(новое ? "no_mileage" : "with_mileage"), новое: новое)
        default:
            return МеткаСостояния(текст: ListingPageText.т(новое ? "cond_new" : "cond_used"), новое: новое)
        }
    }

    // MARK: - Цена (mkPriceHTML)

    /// Показывать ли цену: у услуги без цены и без «договорной» сайт строку цены не рисует.
    var ценаВидна: Bool {
        !услуга || (price ?? 0) > 0 || negotiable
    }

    /// «от» перед ценой — у услуг с ценой.
    var ценаОт: Bool { услуга && (price ?? 0) > 0 }

    /// Аренда посуточно без цены продажи: «5 000 ₸/сут».
    var ценаАренды: Double? {
        guard forRent, let день = rentPriceDay, день > 0, negotiable || (price ?? 0) <= 0 else { return nil }
        return день
    }

    /// «/сут» или «/М».
    var единицаАренды: String {
        "/" + ListingPageText.т(периодАренды == "month" ? "unit_month" : "unit_day")
    }

    /// Старая цена выше нынешней — сайт красит цену красным и пишет «↓ N%».
    var скидкаПроцентов: Int? {
        guard ценаАренды == nil, let старая = oldPrice, let цена = price, цена > 0, старая > цена else { return nil }
        return Int(((старая - цена) / старая * 100).rounded())
    }

    // MARK: - Режим работы (mkHoursText, mkHoursOpen)

    /// «09:00–18:00» или «Круглосуточно»; nil — режим не задан.
    var текстЧасов: String? {
        if часыРежим == "247" { return ListingPageText.т("hours_247") }
        guard часыРежим == "range", let с = часыС, let до = часыДо else { return nil }
        return с + "–" + до
    }

    /// Открыто ли сейчас по времени сайта: Казахстан, UTC+5 (MK_HOURS_TZ_OFFSET = 300). Без расписания — открыто.
    func открытоСейчас(_ сейчас: Date = Date()) -> Bool {
        guard часыРежим == "range", let с = Self.минуты(часыС), let до = Self.минуты(часыДо) else { return true }
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = TimeZone(secondsFromGMT: 5 * 3600) ?? .current
        let ч = календарь.component(.hour, from: сейчас)
        let м = календарь.component(.minute, from: сейчас)
        let теперь = ч * 60 + м
        if с == до { return true }
        return с < до ? (теперь >= с && теперь < до) : (теперь >= с || теперь < до)
    }

    /// «09:30» → 570 (_hm2m сайта).
    private static func минуты(_ строка: String?) -> Int? {
        guard let части = строка?.split(separator: ":"), let ч = части.first.flatMap({ Int($0) }) else { return nil }
        let м = части.count > 1 ? (Int(части[1]) ?? 0) : 0
        return ч * 60 + м
    }

    // MARK: - «Продавец утверждает» (mkTrustBlock)

    struct ПунктДоверия: Hashable {
        let текст: String
        /// Гарантия и доставка — «ключевые»: зелёный пункт, как .is-key сайта.
        let ключевой: Bool
        let значок: String
    }

    var пунктыДоверия: [ПунктДоверия] {
        собратьПунктыДоверия(безЗаявленияГаранта: false)
    }

    /// Сборка 84 (окно v2, владелец 17.10.2026): «Продавец утверждает» под описанием. Когда в карточке решения стоит
    /// строка гаранта (СтрокаГарантаСводки), пункт «Безопасная сделка» (guarantor) не повторяется — одно обещание в одном
    /// месте. строкаГаранта = false — те же пункты, что пунктыДоверия.
    func пунктыДоверияОкна(строкаГаранта: Bool) -> [ПунктДоверия] {
        собратьПунктыДоверия(безЗаявленияГаранта: строкаГаранта)
    }

    private func собратьПунктыДоверия(безЗаявленияГаранта: Bool) -> [ПунктДоверия] {
        var пункты: [ПунктДоверия] = []
        let к = корень
        if !услуга && !["services", "jobs", "realty"].contains(к) {
            let дни = гарантияВыключена ? 0 : (гарантияДней ?? 0)
            if дни > 0 {
                пункты.append(ПунктДоверия(текст: String(format: ListingPageText.т("warranty"), Self.срокГарантии(дни)),
                                           ключевой: true, значок: "checkmark.shield"))
            }
        }
        /* mkIsDeliverable: доставка бывает у всего, кроме недвижимости, транспорта, услуг и вакансий. */
        if !["realty", "transport", "services", "jobs"].contains(к) {
            if доставкаБесплатно {
                пункты.append(ПунктДоверия(текст: ListingPageText.т("ship_free"), ключевой: true, значок: "shippingbox"))
            }
            if let дни = доставкаДней {
                пункты.append(ПунктДоверия(текст: String(format: ListingPageText.т("ship_days"), дни),
                                           ключевой: true, значок: "clock"))
            }
        }
        /* «Безопасная сделка» (guarantor) продавца — только пока гарант не на паузе. */
        let пауза = ПаузаГаранта.наПаузеСейчас
        let безГарантаВСписке = пауза || безЗаявленияГаранта
        for ключ in заявления where !(безГарантаВСписке && ключ == "guarantor") {
            пункты.append(ПунктДоверия(текст: ListingPageText.т("t_" + ключ), ключевой: false, значок: "checkmark"))
        }
        return пункты
    }

    /// mkWarrTerm: 365 дней — «12 месяцев», кратное 30 — месяцы, иначе дни.
    static func срокГарантии(_ дни: Int) -> String {
        let месяцы = дни == 365 ? 12 : (дни >= 30 && дни % 30 == 0 ? дни / 30 : 0)
        let основа = месяцы > 0 ? "month" : "day"
        let n = месяцы > 0 ? месяцы : дни
        /* Арабский: 1 · 2–10 (أشهر, أيام) · 11 и больше (شهرًا, يومًا) — как warrTerm кабинета сайта. */
        if ListingPageText.язык == "ar" {
            let форма = n == 1 ? "_1" : (n >= 2 && n <= 10 ? "_2" : "_5")
            return String(n) + " " + ListingPageText.т(основа + форма)
        }
        return ListingPageText.число(n, основа)
    }

    // MARK: - Совет «… — на что смотреть» (mkBuyTipsKey)

    /// auto, tech, realty, rent, service — или nil, совета нет.
    /// Сборка 84 (разбор окна 17.10.2026): у запчастей и шин с дисками совета «Авто» нет — пункты про VIN, пробег и
    /// осмотр машины к колёсам и деталям не относятся (раньше «auto» отдавался всему корню transport).
    var ключСовета: String? {
        if forRent { return "rent" }
        switch корень {
        case "transport" where РазделыСайта.внутри(категория, Self.разделыБезСоветаАвто):
            return nil
        case "transport": return "auto"
        case "electronics": return "tech"
        case "realty": return "realty"
        case "services", "jobs": return "service"
        default: return nil
        }
    }

    /// Запчасти и шины с дисками — внутри transport, но совет «Авто» не про них.
    private static let разделыБезСоветаАвто: Set<String> = ["auto-parts", "tires-wheels"]

    // MARK: - Суть объявления (карточка решения, сборка 84)

    /// Сколько штук в наличии — mkStockLine сайта: только у новых товаров, не у услуг, работы, жилья и аренды.
    var штукВНаличии: Int? {
        guard let штук = поляВида.наличие, состояние == "new", !forRent,
              !["services", "jobs", "realty"].contains(корень) else { return nil }
        return штук
    }

    /// Открыто ли сейчас по режиму работы: круглосуточно или по часам сайта (UTC+5). Режима нет — nil.
    var открытоПоЧасам: Bool? {
        guard текстЧасов != nil else { return nil }
        return часыРежим == "247" || открытоСейчас()
    }

    /**
     Первая строка карточки решения (владелец 17.10.2026, макет «Окно товара — упрощение»): что за вещь — части для
     « · », первая жирная. Товар: состояние словом (меткаСостояния: «Б/У», «Новое», «С пробегом», «Вторичный рынок»)
     и «Аренда» — метки, которых в окне v2 на фото нет; у нового — «в наличии 5 шт», потом до трёх главных характеристик
     (характеристикиСтраницы — те же, что в описании).
     Услуга и вакансия: «Открыто до 21:00 · 09:00–21:00» (или «Откроется в 09:00», «Круглосуточно»), потом до двух
     характеристик. Сказать нечего — пусто, строки нет. Только чтение полей объявления: без сети и без состояния.
     */
    var сутьОбъявления: [String] {
        var части: [String] = []
        if услуга {
            части.append(contentsOf: частиЧасов)
        } else {
            if let метка = меткаСостояния { части.append(метка.текст) }
            /* Метки на фото в окне v2 нет — «Аренда» словом здесь, после состояния, как метки галереи. */
            if forRent { части.append(ListingPageText.т("rent")) }
        }
        if let штук = штукВНаличии {
            части.append(String(format: ListingSummaryText.т("sum_stock"), штук))
        }
        let предел = услуга ? 2 : 3
        let состояниеСловом = меткаСостояния?.текст ?? ""
        var взято = 0
        for пункт in характеристикиСтраницы where взято < предел {
            let текст = пункт.текст.trimmingCharacters(in: .whitespaces)
            if текст.isEmpty || части.contains(текст) { continue }
            /* «Состояние: Б/У» в характеристиках — то же, что первое слово строки. */
            if !состояниеСловом.isEmpty && текст.hasSuffix(": " + состояниеСловом) { continue }
            части.append(текст)
            взято += 1
        }
        return части
    }

    /// Часы услуги словами: «Открыто до 21:00», «09:00–21:00»; закрыто — «Откроется в 09:00»; круглосуточно — одно слово.
    var частиЧасов: [String] {
        guard let часы = текстЧасов else { return [] }
        if часыРежим == "247" { return [часы] }
        if открытоСейчас(), let до = часыДо {
            return [String(format: ListingSummaryText.т("sum_open_till"), до), часы]
        }
        if let с = часыС {
            return [String(format: ListingSummaryText.т("sum_opens_at"), с), часы]
        }
        return [часы]
    }

    // MARK: - «Добавлено …» (mkDate)

    /// Есть created_ts — точное время, как mkExactTime сайта: «22 сен 2026, 12:53». Нет — mkDate по created_at
    /// («2026-09-24»): «сегодня», «вчера», «3 дня назад», «24 сен» (и год, если не этот).
    var когдаДобавлено: String? {
        if созданоСекунд > 0 {
            let когда = Date(timeIntervalSince1970: TimeInterval(созданоСекунд))
            let к = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: когда)
            let месяцы = ListingPageText.т("months").split(separator: ",").map(String.init)
            let номер = (к.month ?? 1) - 1
            let месяц = месяцы.indices.contains(номер) ? месяцы[номер] : String(номер + 1)
            let время = String(format: "%02d:%02d", к.hour ?? 0, к.minute ?? 0)
            return [String(к.day ?? 0), месяц, String(к.year ?? 0) + ",", время].joined(separator: " ")
        }
        guard let строка = создано else { return nil }
        return Listing.датаСайта(строка)
    }

    /// mkDate сайта для даты «2026-09-24»: «сегодня», «вчера», «3 дня назад», «24 сен» (и год, если не этот); не такая
    /// строка — как пришла. Этап 37 (владелец 25.09.2026): тем же правилом сайт пишет дату отзыва о продавце
    /// (_mkSellerRevPaint: mkDate(t.date)), поэтому правило вынесено из «Добавлено …» и общее для обоих.
    /// Этап 49: `коротко` — mkDate(t, true) карточек главной: «3 дня» без «назад».
    static func датаСайта(_ строка: String, коротко: Bool = false) -> String {
        let части = строка.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard части.count == 3 else { return строка }
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = .current
        guard let день = календарь.date(from: DateComponents(year: части[0], month: части[1], day: части[2])) else {
            return строка
        }
        let сегодня = календарь.startOfDay(for: Date())
        let дней = календарь.dateComponents([.day], from: день, to: сегодня).day ?? 0
        if дней <= 0 { return ListingPageText.т("today") }
        if дней == 1 { return ListingPageText.т("yesterday") }
        if дней < 7 {
            let сколько = ListingPageText.число(дней, "day")
            return коротко ? сколько : String(format: ListingPageText.т("ago"), сколько)
        }
        let месяцы = ListingPageText.т("months").split(separator: ",").map(String.init)
        let месяц = месяцы.indices.contains(части[1] - 1) ? месяцы[части[1] - 1] : String(части[1])
        let этотГод = календарь.component(.year, from: Date())
        return "\(части[2]) \(месяц)" + (части[0] != этотГод ? " \(части[0])" : "")
    }
}
