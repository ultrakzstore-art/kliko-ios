import SwiftUI

/**
 «КАРТОЧКА РЕШЕНИЯ» ПОД ЦЕНОЙ ОКНА ОБЪЯВЛЕНИЯ — СБОРКА 84 (владелец 17.10.2026: «Модалку товаров надо упростить, так
 как фокус сбивается… сначала покажи вариант»; на макет «Окно товара — упрощение» — «Собирай 84»). План и замеры —
 docs/LISTING_MODAL_V2.md, рубильник modal_summary (Config.окноРешения, ListingWindowV2.swift).

 Вместо 4–8 разных блоков под ценой (часы, наличие, «Продавец утверждает», крошки, «Подходит», большая кнопка
 примерки) — одна спокойная карточка из 2–4 строк по 44 pt. Строки отвечают на вопросы покупателя:
   · что за вещь — состояние словом и до трёх главных характеристик (Listing.сутьОбъявления, SiteListingRules.swift);
     у услуг — «Открыто до 21:00 · 09:00–21:00». Не нажимается;
   · подойдёт ли — компактная строка «Подходит моему» / «Подойдут ли?» (ПлашкаПодходитМоему и СтрокаПодойдутЛи с
     параметром вСводке): они сами наблюдают «Моё», корень страницы — нет (правило b644caf);
   · кто продаёт — аватар 28 pt с буквой, имя, печать «Проверен», оценка и сделки (нет — «с 2026 г.» или «Новый
     продавец»), город; нажатие — витрина продавца (ОкноПродавца), как у карточки продавца внизу;
   · безопасно ли платить — «Деньги у Kliko до получения товара ›» строго при тех же условиях, что подпись главной
     кнопки панели (ГлавноеДействиеОкна, ПаузаГаранта.работаетПоСверке — App Review 2.3.1). Нажатие — весть
     klikoОткрытьГарантОкна: окно «Безопасная сделка» открывает панель связи (вход, проверка и сверка живут там).
 Вид: Theme.поверхность2, рамка-линия 1 pt, Радиус.md, без тени; колонка значка 24 pt, текст 14 pt (растёт с
 «Размером текста»), первая часть жирная цветом текста, остальное вторым цветом через « · »; тонкие линии между
 строками с отступом 48 pt от ведущего края. Ничего не движется само; без GeometryReader и записи состояния из замера.
 */

// MARK: - Строка карточки

/// Где строке, которая сама решает, видна ли она («подходит»), рисовать тонкую линию: сверху (над ней есть строка),
/// снизу (она первая, а под ней строки есть) или нигде.
enum ЛинияСтрокиСводки: Equatable {
    case нет, сверху, снизу
}

/// Тонкая линия между строками карточки: 1 pt цвета линии, отступ 48 pt от ведущего края (под текстом, не под значком).
struct ЛинияСводки: View {
    init() {}

    var body: some View {
        Theme.линия
            .frame(height: 1)
            .padding(.leading, КаркасСтрокиСводки<EmptyView>.отступТекста)
            .accessibilityHidden(true)
    }
}

/// Значок строки: символ SF в колонке 24 pt или аватар продавца 28 pt (буква, фото — если есть).
enum ЗначокСтрокиСводки {
    case символ(String, Color)
    case аватар(буква: String, адрес: URL?)
}

/// Нажатие строки карточки: подсветка фоном на всю строку, без сжатия (строка — часть карточки, а не кнопка).
struct НажатиеСтрокиСводки: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.линия.opacity(0.6) : Color.clear)
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}

/**
 Каркас строки: колонка значка 24 pt, текст, шеврон «›» (если нажимается), высота не меньше 44 pt, поля 12 pt.
 Нажимается — кнопка во всю строку с подсказкой VoiceOver; нет — один элемент VoiceOver из значка и текста.
 */
struct КаркасСтрокиСводки<Текст: View>: View {
    /// Поле 12 + колонка значка 24 + промежуток 12: отсюда начинается текст и тонкие линии.
    static var отступТекста: CGFloat { 48 }

    let значок: ЗначокСтрокиСводки
    let шеврон: Bool
    let подсказка: String?
    let нажать: (() -> Void)?
    let текст: Текст

    init(значок: ЗначокСтрокиСводки, шеврон: Bool, подсказка: String? = nil, нажать: (() -> Void)? = nil,
         @ViewBuilder текст: () -> Текст) {
        self.значок = значок
        self.шеврон = шеврон
        self.подсказка = подсказка
        self.нажать = нажать
        self.текст = текст()
    }

    var body: some View {
        if let нажать {
            Button(action: нажать) { содержимое }
                .buttonStyle(НажатиеСтрокиСводки())
                .accessibilityHint(подсказка ?? "")
        } else {
            содержимое
                .accessibilityElement(children: .combine)
        }
    }

    private var содержимое: some View {
        HStack(spacing: 12) {
            значокВид
                .frame(width: 24)
            /* Текст берёт всю ширину между значком и шевроном: варианты ViewThatFits меряются по ней. */
            текст
                .frame(maxWidth: .infinity, alignment: .leading)
            if шеврон {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var значокВид: some View {
        switch значок {
        case .символ(let имя, let краска):
            Image(systemName: имя)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(краска)
                .accessibilityHidden(true)
        case .аватар(let буква, let адрес):
            АватарСводки(буква: буква, адрес: адрес)
        }
    }
}

/// Аватар продавца 28 pt: буква имени на спокойной подложке; есть фото — фото (из памяти ленты, без AsyncImage).
struct АватарСводки: View {
    let буква: String
    let адрес: URL?

    init(буква: String, адрес: URL?) {
        self.буква = буква
        self.адрес = адрес
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
        return форма
            .fill(Theme.линия)
            .frame(width: 28, height: 28)
            .overlay {
                Text(буква)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текст)
            }
            .overlay {
                if let адрес {
                    КартинкаЛенты(адрес, пунктов: 28) {
                        Color.clear
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(форма)
                }
            }
            .accessibilityHidden(true)
    }
}

/**
 Строка из частей через « · »: первая — жирная цветом текста, остальные — вторым цветом (краска — весь текст одним
 цветом: гарант — акцент, пауза — второй). Не влезает в строку — сначала уходят последние части (ViewThatFits по
 вариантам, без замера), последний вариант — первые три части в две строки.
 */
struct СтрокаСводки: View {
    let значок: ЗначокСтрокиСводки
    let части: [String]
    let краска: Color?
    let шеврон: Bool
    let подсказка: String?
    let нажать: (() -> Void)?
    @ScaledMetric(relativeTo: .subheadline) private var кегль: CGFloat = 14

    init(значок: ЗначокСтрокиСводки, части: [String], краска: Color? = nil, шеврон: Bool = false,
         подсказка: String? = nil, нажать: (() -> Void)? = nil) {
        self.значок = значок
        self.части = части.filter { !$0.isEmpty }
        self.краска = краска
        self.шеврон = шеврон
        self.подсказка = подсказка
        self.нажать = нажать
    }

    var body: some View {
        КаркасСтрокиСводки(значок: значок, шеврон: шеврон, подсказка: подсказка, нажать: нажать) {
            надпись
        }
    }

    private var надпись: some View {
        let все: [String] = части
        let безОдной: [String] = все.count > 2 ? Array(все.dropLast()) : все
        let безДвух: [String] = все.count > 3 ? Array(все.dropLast(2)) : безОдной
        let начало: [String] = Array(все.prefix(3))
        return ViewThatFits(in: .horizontal) {
            строка(все, строк: 1)
            строка(безОдной, строк: 1)
            строка(безДвух, строк: 1)
            строка(начало, строк: 2)
        }
    }

    private func строка(_ список: [String], строк: Int) -> some View {
        Text(Self.текст(список, краска: краска, кегль: кегль))
            .lineLimit(строк)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Части одной строкой: первая — semibold, остальные — обычные, через « · ».
    static func текст(_ список: [String], краска: Color?, кегль: CGFloat) -> AttributedString {
        var итог = AttributedString()
        let главная: Color = краска ?? Theme.текст
        let вторая: Color = краска ?? Theme.текстВторой
        for (номер, часть) in список.enumerated() {
            if номер > 0 {
                var точка = AttributedString(" · ")
                точка.font = Font.system(size: кегль)
                точка.foregroundColor = вторая
                итог.append(точка)
            }
            var кусок = AttributedString(часть)
            кусок.font = Font.system(size: кегль, weight: номер == 0 ? .semibold : .regular)
            кусок.foregroundColor = номер == 0 ? главная : вторая
            итог.append(кусок)
        }
        return итог
    }
}

// MARK: - Карточка

/**
 Карточка решения. Строки по порядку: суть, подходит, продавец, гарант. Линии между строками рисуют сами строки: у
 постоянных (суть, продавец, гарант) — сверху, если выше уже есть постоянная строка; у «подходит», которая появляется
 по «Моему», — сверху после сути или снизу, если она первая и ниже есть строки. Постоянных строк нет — карточки нет
 (страница ставит прежнюю плашку «Подходит моему»).
 */
struct СводкаРешения: View {
    let товар: Listing
    let магазин: Bool
    /// Строка гаранта стоит (СтрокаГарантаСводки.стоит) — посчитано страницей: по тому же признаку «Продавец утверждает»
    /// под описанием не повторяет «Безопасную сделку».
    let строкаГаранта: Bool

    init(товар: Listing, магазин: Bool, строкаГаранта: Bool) {
        self.товар = товар
        self.магазин = магазин
        self.строкаГаранта = строкаГаранта
    }

    /// Какая строка «подходит» может стоять у объявления — так же, как прежде под ценой (SiteListing.swift).
    enum Подходит {
        case нет, моё, шины
    }

    @MainActor
    static func подходит(_ т: Listing) -> Подходит {
        guard Config.моё else { return .нет }
        return ПодойдутЛиОбъявления.стоит(т) ? .шины : .моё
    }

    /// Есть ли у карточки постоянные строки. Нет — карточки нет.
    @MainActor
    static func есть(_ т: Listing, строкаГаранта: Bool) -> Bool {
        !т.сутьОбъявления.isEmpty || СтрокаПродавцаСводки.есть(т) || строкаГаранта
    }

    var body: some View {
        let суть: [String] = товар.сутьОбъявления
        let естьСуть = !суть.isEmpty
        let продавец: Bool = СтрокаПродавцаСводки.есть(товар)
        let нижеЕсть = продавец || строкаГаранта
        let линияПодходит: ЛинияСтрокиСводки = естьСуть ? .сверху : (нижеЕсть ? .снизу : .нет)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(spacing: 0) {
            if естьСуть {
                строкаСути(суть)
            }
            строкаПодходит(линияПодходит)
            if продавец {
                СтрокаПродавцаСводки(товар: товар, магазин: магазин, линияСверху: естьСуть)
            }
            if строкаГаранта {
                СтрокаГарантаСводки(товар: товар, линияСверху: естьСуть || продавец)
            }
        }
        .background(Theme.поверхность2, in: форма)
        .clipShape(форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ListingSummaryText.т("sum_a11y"))
    }

    /// «Б/У · Apple M2 · 8 ГБ ОЗУ» (значок tag) или у услуг «Открыто до 21:00 · 09:00–21:00» (часы: открыто — зелёный
    /// значок, иначе второй цвет). Не нажимается.
    private func строкаСути(_ суть: [String]) -> some View {
        let часы: Bool = товар.услуга && товар.текстЧасов != nil
        let открыто: Bool = товар.открытоПоЧасам ?? false
        let краска: Color = часы && открыто ? Theme.зелёный2 : Theme.текстВторой
        let символ: String = часы ? "clock" : "tag"
        return СтрокаСводки(значок: .символ(символ, краска), части: суть)
    }

    @ViewBuilder
    private func строкаПодходит(_ линия: ЛинияСтрокиСводки) -> some View {
        switch Self.подходит(товар) {
        case .шины:
            СтрокаПодойдутЛи(товар: товар, вСводке: линия)
        case .моё:
            ПлашкаПодходитМоему(товар: товар, вСводке: линия)
        case .нет:
            EmptyView()
        }
    }
}

// MARK: - Кто продаёт

/**
 «Kana ✓ · ★ 4.8 · 14 сделок · Астана ›»: аватар 28 pt, имя жирным, печать «Проверен» (checkmark.seal.fill цветом
 Theme.проверен), потом то, что действительно есть: «Магазин», у товаров с часами — «Открыто до 19:00», оценка и
 сделки; нет ни того, ни другого — «с 2026 г.» или «Новый продавец»; город. Не влезает — уходят последние части.
 Нажатие — витрина продавца поверх объявления (ОкноПродавца), как у карточки продавца внизу (БлокПродавца).
 Имени продавца нет — строки нет.
 */
struct СтрокаПродавцаСводки: View {
    let товар: Listing
    let магазин: Bool
    let линияСверху: Bool
    @ScaledMetric(relativeTo: .subheadline) private var кегль: CGFloat = 14

    init(товар: Listing, магазин: Bool, линияСверху: Bool) {
        self.товар = товар
        self.магазин = магазин
        self.линияСверху = линияСверху
    }

    static func есть(_ т: Listing) -> Bool {
        !(т.продавец ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var имя: String { (товар.продавец ?? "").trimmingCharacters(in: .whitespaces) }

    private var буква: String { String(имя.prefix(1)).uppercased() }

    private var номер: String { (товар.продавецID ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Витрину можно открыть: номер продавца годится в адрес.
    private var витрина: Bool { ВитринаПродавцаAPI.годный(номер) }

    /// Части после имени — в порядке макета.
    private var части: [String] {
        var итог: [String] = []
        if магазин { итог.append(ListingPageText.т("shop")) }
        if !товар.услуга, let часы = товар.частиЧасов.first { итог.append(часы) }
        var известно = false
        if let оценка = товар.рейтингПродавца {
            итог.append("★ " + String(format: "%.1f", оценка))
            известно = true
        }
        if let сделки = товар.сделкиПродавца, сделки > 0 {
            итог.append(ListingSummaryText.сделок(сделки))
            известно = true
        }
        if !известно {
            if let год = товар.продавецС {
                итог.append(String(format: ListingPageText.т("since"), год))
            } else {
                итог.append(ListingPageText.т("new_seller"))
            }
        }
        let город = товар.city.trimmingCharacters(in: .whitespaces)
        if !город.isEmpty { итог.append(город) }
        return итог
    }

    var body: some View {
        let адрес: URL? = товар.аватарПродавца.flatMap { Config.url($0) }
        var открыть: (() -> Void)? = nil
        if витрина {
            открыть = { открытьВитрину() }
        }
        let подсказка: String? = витрина ? StorefrontText.т("all_goods") : nil
        return VStack(spacing: 0) {
            if линияСверху {
                ЛинияСводки()
            }
            КаркасСтрокиСводки(значок: .аватар(буква: буква, адрес: адрес), шеврон: витрина, подсказка: подсказка,
                               нажать: открыть) {
                надпись
            }
        }
    }

    private var надпись: some View {
        let остальное: [String] = части
        return HStack(spacing: 4) {
            Text(имя)
                .font(.system(size: кегль, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .layoutPriority(1)
            if товар.продавецПроверен {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: кегль - 1))
                    .foregroundStyle(Theme.проверен)
                    .accessibilityLabel(ListingPageText.т("verified"))
            }
            if !остальное.isEmpty {
                ViewThatFits(in: .horizontal) {
                    вторые(остальное)
                    вторые(Array(остальное.prefix(max(1, остальное.count - 1))))
                    вторые(Array(остальное.prefix(max(1, остальное.count - 2))))
                    вторые(Array(остальное.prefix(1)))
                }
            }
        }
    }

    private func вторые(_ список: [String]) -> some View {
        Text("· " + список.joined(separator: " · "))
            .font(.system(size: кегль))
            .foregroundStyle(Theme.текстВторой)
            .lineLimit(1)
    }

    private func открытьВитрину() {
        ОткликСайта.выбор()
        ОкноПродавца.открыть(id: номер, имя: имя)
    }
}

// MARK: - Безопасно ли платить

/**
 Строка гаранта — только при тех же условиях, что подпись главной кнопки панели сегодня (ГлавноеДействиеОкна.для и
 его подпись, ListingActions.swift; App Review 2.3.1 — не обещать того, чего нет):
   · «Купить безопасно» и гарант работает ПО СВЕРКЕ (ПаузаГаранта.работаетПоСверке) — зелёный щит и «Деньги у Kliko до
     получения товара ›» цветом акцента; сверки ещё не было — «Безопасная сделка Kliko ›», после сверки текст
     меняется проявлением на месте;
   · «Внести задаток» (авто, жильё) — «Бронь через Безопасную сделку ›»; «Заказать безопасно» — «Оплата исполнителю
     после приёмки ›»;
   · гарант на паузе у объявления, где он был бы (ГарантОбъявления.наПаузеУОбъявления), — серая «Безопасная сделка
     сейчас на паузе» без шеврона и не нажимается.
 Строки нет: цифровое объявление (Apple 3.1.1), своё (номер вошедшего — СессияПриложения.id, синхронно), в резерве или
 снято (Listing.вРезерве, Listing.активно), режим сделок с подписью eGov, аренда и «Связаться» без гаранта.
 Нажатие — весть klikoОткрытьГарантОкна с номером объявления: окно «Безопасная сделка» (ЛистГарантСделки) открывает
 панель связи — у неё вход, проверка и сверка. Строка сама наблюдает ПаузаГаранта и РежимСделокСайта — корень
 страницы их не наблюдает (правило b644caf).
 */
struct СтрокаГарантаСводки: View {
    let товар: Listing
    let линияСверху: Bool
    @ObservedObject private var пауза = ПаузаГаранта.shared
    @ObservedObject private var режим = РежимСделокСайта.shared
    /// Сверка гаранта была и паузы нет — снимок для показа; меняется после своей сверки (не из тела).
    @State private var поСверке = ПаузаГаранта.работаетПоСверке

    init(товар: Listing, линияСверху: Bool) {
        self.товар = товар
        self.линияСверху = линияСверху
    }

    enum Вид: Equatable {
        /// «Деньги у Kliko до получения товара» — гарант работает по сверке.
        case деньги
        /// «Безопасная сделка Kliko» — сверки ещё не было.
        case сделка
        case бронь
        case услуга
        case пауза
    }

    /// Стоит ли строка у объявления — по последнему известному режиму сделок и паузе (без наблюдения).
    @MainActor
    static func стоит(_ т: Listing) -> Bool {
        вид(т, eds: РежимСделокСайта.edsСейчас, поСверке: ПаузаГаранта.работаетПоСверке) != nil
    }

    @MainActor
    static func вид(_ т: Listing, eds: Bool, поСверке: Bool) -> Вид? {
        guard !т.цифровое, т.активно, !т.вРезерве, !своё(т) else { return nil }
        let главное: ГлавноеДействиеОкна = ГлавноеДействиеОкна.для(т, eds: eds)
        switch главное {
        case .купить:
            return поСверке ? .деньги : .сделка
        case .задаток:
            return .бронь
        case .заказать:
            return .услуга
        case .связаться:
            return ГарантОбъявления.наПаузеУОбъявления(т) ? .пауза : nil
        default:
            /* Аренда, сделка с подписью eGov и новые состояния панели — гаранта в карточке нет. */
            return nil
        }
    }

    /// Своё объявление — сразу по номеру вошедшего, без ожидания страницы сайта.
    @MainActor
    private static func своё(_ т: Listing) -> Bool {
        let я = СессияПриложения.shared.id
        return !я.isEmpty && я == т.продавецID
    }

    var body: some View {
        let вид: Вид? = Self.вид(товар, eds: режим.eds, поСверке: поСверке)
        return Group {
            if let вид {
                VStack(spacing: 0) {
                    if линияСверху {
                        ЛинияСводки()
                    }
                    строка(вид)
                }
            }
        }
        .task {
            /* Сверка паузы гаранта не чаще раза в 10 минут (обычно её уже сделала витрина); пришла — текст меняется
               проявлением на месте, высота строки та же. */
            await пауза.сверить()
            let стало = ПаузаГаранта.работаетПоСверке
            if стало != поСверке {
                withAnimation(ДвижениеСайта.смена) { поСверке = стало }
            }
        }
    }

    private func строка(_ вид: Вид) -> some View {
        let наПаузе = вид == .пауза
        let краска: Color = наПаузе ? Theme.текстВторой : Theme.акцент
        let символ: String = наПаузе ? "shield.slash" : "checkmark.shield.fill"
        var нажать: (() -> Void)? = nil
        if !наПаузе {
            нажать = { открытьГарант() }
        }
        let подсказка: String? = наПаузе ? nil : ListingSummaryText.т("esc_hint")
        return СтрокаСводки(значок: .символ(символ, краска), части: [Self.текст(вид)], краска: краска,
                            шеврон: !наПаузе, подсказка: подсказка, нажать: нажать)
    }

    static func текст(_ вид: Вид) -> String {
        switch вид {
        case .деньги: return ListingSummaryText.т("esc_money")
        case .сделка: return ListingSummaryText.т("esc_safe")
        case .бронь: return ListingSummaryText.т("esc_deposit")
        case .услуга: return ListingSummaryText.т("esc_service")
        case .пауза: return ListingSummaryText.т("esc_paused")
        }
    }

    private func открытьГарант() {
        ОткликСайта.выбор()
        NotificationCenter.default.post(name: .klikoОткрытьГарантОкна, object: товар.id)
    }
}
