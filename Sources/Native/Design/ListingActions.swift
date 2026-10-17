import SwiftUI
import UIKit

/**
 ОКНО ОБЪЯВЛЕНИЯ: НОВАЯ РАСКЛАДКА КНОПОК (ultra-site 13.10.2026: «Окно объявления: новая раскладка кнопок» и «кнопки
 называют то, что делают»; владелец: «всё что на сайте — и в iOS так же»).

 Нижняя панель — «[главная][Торг][Связаться]», как mkModalActions сайта на телефоне:
   · главная — действие этого объявления: «Купить безопасно» (товар с гарантом), «Внести задаток» (авто и недвижимость на
     продажу), «Арендовать» (объявление «сдаётся», даже с ценой продажи), «Заказать безопасно» (услуга), «Сделка с
     подписью eGov» (режим подписи, только товары). Где сделки нет (продавец не проверен, цена ниже порога, гарант выключен у
     объявления, пауза, режим «выключено») — главная «Связаться», и третьей кнопки нет: кнопки, которой нечего делать,
     нет вовсе;
   · «Торг» — предложение цены в чате (товар с ценой, не услуга, не своё);
   · «Связаться» — лист «Связаться с продавцом»: чат, WhatsApp, звонок; гостю строки под замком и одна «Войти или
     зарегистрироваться»; продавец «только чат» — вошедшему чат сразу.
 Своё объявление — одна «Редактировать». Продавец заблокирован — «Связь недоступна» и «Разблокировать». «Заблокировать» и
 «Пожаловаться» — в «Ещё» шапки окна (КнопкаЕщёОкна); гостю — «Войти, чтобы пожаловаться».
 Состояние, окна гаранта и чат держит ПанельСвязиСайта (SiteContactBar.swift): здесь — вид кнопок и правила.

 🔴 ДЕНЬГИ. Новых путей к оплате нет: главная кнопка жмёт тот же гарант панели (окно «Безопасная сделка», деньги — только за
 Config.деньгиСделок), цифровые услуги в приложении не продаются.

 СБОРКА 84 — ОКНО ОБЪЯВЛЕНИЯ V2 (владелец 17.10.2026: «Модалку товаров надо упростить, так как фокус сбивается»; на макет —
 «Собирай 84»; план и замеры — docs/LISTING_MODAL_V2.md, рубильник modal_summary — Config.окноРешения):
   · ряд всегда в одну строку: главная гибкая (не ниже 56 pt), «Торг» и «Связаться» — плитки 68×56 с нейтральными
     значками; столбиком — только при крупном «Размере текста» (accessibility), выбор по окружению, без ViewThatFits и
     без замера геометрии. Главная без квадрата 34 pt и без строки пояснения: значок 17 pt в строке, заголовок 15 pt до
     двух строк без ужатия; пояснение («Деньги у Kliko до получения товара») — подсказка VoiceOver, а на экране — строка
     карточки решения. Тень 6 / 20 % / 3, одно общее появление вместо каскада, блик — один раз за запуск приложения;
   · ошибки, найденные при разборе (исправлены и при выключенном рубильнике): задаток — только у машин и жилья (шины,
     диски и запчасти — «Купить безопасно»); вещь в резерве или продана — серая строка и одна «Связаться», гарант на
     занятой вещи не предлагается.
 Рубильник выключен — раскладка и движение прежние.
 */
extension Config {
    /// Новая раскладка окна объявления и «Ещё» в шапке (рубильник сайта modal_actions_v2, включён). Выключен — прежняя
    /// пилюля «Написать продавцу» со строкой «Купить безопасно» / «Предложить цену» и круглыми звонком и WhatsApp.
    static let кнопкиОкнаV2ВСборке = true
    static var кнопкиОкнаV2: Bool { НастройкиСервера.вклВыкл("modal_actions_v2", сборка: кнопкиОкнаV2ВСборке) }
    /// «Разбор объявления» (api/brief.php, рубильник сайта item_brief): кнопка под ценой и метка «Ниже рынка». Сервер
    /// выключил — отвечает off, кнопки и метки нет; здесь можно только выключить.
    static let разборОбъявленияВСборке = true
    static var разборОбъявления: Bool { НастройкиСервера.стопКран("item_brief", сборка: разборОбъявленияВСборке) }
    /// Доводы Kliko AI в «Разборе» (chat.php?action=brief_ai, рубильник сайта item_brief_ai, на сайте пока выключен):
    /// запрос — только по нажатию; ответ off — раздела нет до перезапуска. В сборке выключено, как на сайте: раздел
    /// появится, когда сервер пришлёт item_brief_ai = true в api/app_config.php.
    static let доводыИИРазбораВСборке = false
    static var доводыИИРазбора: Bool { НастройкиСервера.вклВыкл("item_brief_ai", сборка: доводыИИРазбораВСборке) }
}

// MARK: - Главное действие объявления

/// Что делает главная кнопка нижней панели — правило mkModalActions сайта.
enum ГлавноеДействиеОкна: Equatable {
    case купить
    case задаток
    case аренда
    case заказать
    case подписьEDS
    case связаться

    /// eds — режим сделок с подписью (MK_DEAL_MODE = "eds", РежимСделокСайта).
    static func для(_ т: Listing, eds: Bool) -> ГлавноеДействиеОкна {
        /* Сборка 84 (владелец 17.10.2026, «Найденные ошибки» окна v2): вещь в резерве или продана — гарант не
           предлагается, главная — «Связаться» (над ней панель пишет «В резерве — идёт сделка» или «Продано»). */
        if занятость(т) != nil { return .связаться }
        /* «Сдаётся» — «Арендовать», даже когда есть цена продажи: сделка у такого объявления — залог аренды. */
        if т.forRent { return .аренда }
        /* Аренда жилья без галочки «Сдаю» (непроверенный продавец до 13.10.2026 — realty.deal = "rent"): заявку через
           rentals.php не принять, задаток за «продажу» неверен — главная «Связаться». */
        if т.корень == "realty" && т.жильё["deal"] == "rent" { return .связаться }
        if eds { return СделкаEDSОбъявления.подходит(т) ? .подписьEDS : .связаться }
        /* Гарант: продавец проверен, не ниже порога, не no_escrow, не пауза (ГарантОбъявления.кнопка). Без цены
           оформлять нечего — «Связаться». */
        guard (т.price ?? 0) > 0, ГарантОбъявления.кнопка(т) == .купить else { return .связаться }
        if т.услуга { return т.корень == "services" ? .заказать : .связаться }
        if т.корень == "realty" { return .задаток }
        /* Сборка 84: задаток — бронь машины; шины, диски и запчасти (внутри transport) — обычный товар, «Купить
           безопасно» (раньше у колёс выходил «Внести задаток»). */
        if т.корень == "transport" && !РазделыСайта.внутри(т.категория, разделыБезЗадатка) { return .задаток }
        return .купить
    }

    /// Разделы transport, где задатка нет: запчасти и шины с дисками (tires-wheels лежит внутри auto-parts — названы
    /// оба, чтобы правило не зависело от дерева разделов).
    static let разделыБезЗадатка: Set<String> = ["auto-parts", "tires-wheels"]

    /// Вещь занята: в резерве (status = "reserved") или продана (status = "sold" или снята — is_active = false).
    enum Занятость: Equatable {
        case резерв
        case продано

        /// Серая строка панели над «Связаться».
        var текст: String {
            switch self {
            case .резерв: return ТекстыДействийОкна.т("ma_reserved")
            case .продано: return ТекстыДействийОкна.т("ma_sold")
            }
        }

        var значок: String {
            switch self {
            case .резерв: return "hourglass"
            case .продано: return "checkmark.circle"
            }
        }
    }

    /// Занята ли вещь (Listing.вРезерве, статус выдачи и Listing.активно); nil — свободна.
    static func занятость(_ т: Listing) -> Занятость? {
        if т.вРезерве { return .резерв }
        if !т.активно || т.статусВыдачи == "sold" { return .продано }
        return nil
    }

    var заголовок: String {
        switch self {
        case .купить: return ТекстыДействийОкна.т("ma_buy")
        case .задаток: return ТекстыДействийОкна.т("ma_deposit")
        case .аренда: return ТекстыДействийОкна.т("ma_rent")
        case .заказать: return ТекстыДействийОкна.т("ma_order")
        case .подписьEDS: return ТекстыДействийОкна.т("ma_eds")
        case .связаться: return ТекстыДействийОкна.т("ma_contact")
        }
    }

    var значок: String {
        switch self {
        case .купить, .задаток, .заказать: return "checkmark.shield"
        case .аренда: return "calendar"
        case .подписьEDS: return "pencil.line"
        case .связаться: return "bubble.left.and.bubble.right"
        }
    }

    /// Вторая строка главной кнопки. Связаться — каналы продавца; гарант на паузе — об этом.
    func подпись(_ т: Listing) -> String {
        switch self {
        case .купить:
            /* Обещание «деньги у Kliko» — только когда гарант работает по сверке (App Review 2.3.1). */
            return ПаузаГаранта.работаетПоСверке ? ТекстыДействийОкна.т("ma_buy_sub") : ""
        case .задаток: return ТекстыДействийОкна.т("ma_deposit_sub")
        case .аренда: return ТекстыДействийОкна.т("ma_rent_sub")
        case .заказать: return ТекстыДействийОкна.т("ma_order_sub")
        case .подписьEDS: return ТекстыДействийОкна.т("ma_eds_sub")
        case .связаться:
            /* Занятой вещи пауза гаранта ни при чём — о ней не пишем. */
            if занятость(т) == nil && ГарантОбъявления.наПаузеУОбъявления(т) {
                return ТекстыДействийОкна.т("ma_hold_sub")
            }
            return т.звонок || т.whatsApp ? ТекстыДействийОкна.т("ma_contact_sub") : ТекстыДействийОкна.т("ma_contact_chat")
        }
    }
}

// MARK: - Вести между частями окна

/**
 Части окна объявления зовут панель (у неё чат, гарант и листы): блок аренды — «Арендовать», «Разбор объявления» —
 вопрос в чат или главную кнопку, «Попросить настоящие фото» — чат с готовой фразой. object — номер объявления: панель
 другого объявления в том же стеке весть не берёт.
 */
enum ВестиОкнаОбъявления {
    /// Чат с продавцом; userInfo[ключТекста] — текст в строку ввода (не уходит сам).
    static let чат = Notification.Name("kliko.listing.ma.chat")
    /// Лист «Арендовать».
    static let аренда = Notification.Name("kliko.listing.ma.rent")
    /// Нажать главную кнопку.
    static let главное = Notification.Name("kliko.listing.ma.main")
    /// «Связаться».
    static let связаться = Notification.Name("kliko.listing.ma.contact")
    static let ключТекста = "text"

    static func послать(_ имя: Notification.Name, товар: String, текст: String = "") {
        NotificationCenter.default.post(name: имя, object: товар,
                                        userInfo: текст.isEmpty ? nil : [ключТекста: текст])
    }

    /// Текст из вести (пусто — нет).
    static func текст(_ весть: Notification) -> String {
        (весть.userInfo?[ключТекста] as? String) ?? ""
    }
}

/// Что сделать панели, когда её лист («Связаться», «Арендовать») уедет: лист поверх листа не открывается.
enum ПослеЛистаОкна: Equatable {
    case чат(текст: String)
    case звонок
    case whatsApp
    case вход
    case верификация
    /// «Открыть мои аренды» — номер аренды из ответа (пусто — раздел без карточки).
    case мояАренда(String)
}

/// Лист нижней панели.
enum ЛистОкнаОбъявления: String, Identifiable {
    case связь, аренда

    var id: String { rawValue }
}

// MARK: - Ряд кнопок

/**
 «[главная][Торг][Связаться]»: главная — зелёная, во всю оставшуюся ширину, «Торг» и «Связаться» — квадратные плитки
 одной высоты с ней. Не влезло в строку (длинный язык, «Сделка с подписью eGov», крупный текст) — главная сверху во всю
 ширину, плитки под ней поровну: подпись не обрезается многоточием. Появляются снизу лёгким каскадом.

 компактно (сборка 84, Config.окноРешения — снимок панели): всегда одна строка HStack(spacing 8) — главная гибкая, плитки
 68×56; столбиком — только при крупном «Размере текста» (dynamicTypeSize.isAccessibilitySize, окружение уже ограничено
 панелью до accessibility1). ViewThatFits сравнивал идеальную ширину ≈431 pt с 357 pt и всегда выбирал два ряда (178 pt),
 а на Pro Max ряд прыгал из одного в два, когда приходила сверка гаранта. Без замера геометрии и без записи состояния из
 тела; .fixedSize(vertical) остаётся — без него повторится растяжение из TestFlight 74. Появление — одно общее
 (прозрачность и 8 pt), без каскада.
 */
struct РядДействийОкна: View {
    let главное: ГлавноеДействиеОкна
    let подпись: String
    let ждём: Bool
    let торг: Bool
    let связаться: Bool
    let нажатьГлавное: () -> Void
    let нажатьТорг: () -> Void
    let нажатьСвязаться: () -> Void
    /// Окно объявления v2: одна строка, компактная главная, нейтральные плитки (решает панель — снимок рубильника).
    let компактно: Bool
    @State private var видно = false
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(главное: ГлавноеДействиеОкна, подпись: String, ждём: Bool, торг: Bool, связаться: Bool,
         нажатьГлавное: @escaping () -> Void, нажатьТорг: @escaping () -> Void,
         нажатьСвязаться: @escaping () -> Void, компактно: Bool = false) {
        self.главное = главное
        self.подпись = подпись
        self.ждём = ждём
        self.торг = торг
        self.связаться = связаться
        self.нажатьГлавное = нажатьГлавное
        self.нажатьТорг = нажатьТорг
        self.нажатьСвязаться = нажатьСвязаться
        self.компактно = компактно
    }

    var body: some View {
        if компактно {
            рядКомпактно
        } else {
            рядПрежний
        }
    }

    // MARK: Окно v2 (сборка 84)

    /// Одна строка; столбиком — только при крупном тексте. Одно общее появление снизу на 8 pt.
    private var рядКомпактно: some View {
        Group {
            if размерТекста.isAccessibilitySize {
                VStack(spacing: 8) {
                    главнаяКомпактно
                    if торг || связаться {
                        HStack(spacing: 8) { малыеКомпактно(растянуть: true) }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    главнаяКомпактно
                    малыеКомпактно(растянуть: false)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(видно ? 1 : 0)
        .offset(y: видно ? 0 : 8)
        .animation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.8)), value: видно)
        .onAppear { видно = true }
    }

    private var главнаяКомпактно: some View {
        ГлавнаяКнопкаОкна(значок: главное.значок, заголовок: главное.заголовок, подпись: подпись, ждём: ждём,
                          компактно: true, нажать: нажатьГлавное)
    }

    @ViewBuilder
    private func малыеКомпактно(растянуть: Bool) -> some View {
        if торг {
            МалаяКнопкаОкна(значок: "tag", заголовок: ТекстыДействийОкна.т("ma_offer"),
                            голос: ТекстыДействийОкна.т("ma_offer_a11y"), растянуть: растянуть, компактно: true,
                            нажать: нажатьТорг)
        }
        if связаться {
            МалаяКнопкаОкна(значок: "bubble.left.and.bubble.right", заголовок: ТекстыДействийОкна.т("ma_contact"),
                            голос: ТекстыДействийОкна.т("ma_cc_title"), растянуть: растянуть, компактно: true,
                            нажать: нажатьСвязаться)
        }
    }

    // MARK: Как до сборки 84

    private var рядПрежний: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                главная
                малые(растянуть: false)
            }
            VStack(spacing: 8) {
                главная
                if торг || связаться {
                    HStack(spacing: 8) { малые(растянуть: true) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { видно = true }
    }

    private var главная: some View {
        ГлавнаяКнопкаОкна(значок: главное.значок, заголовок: главное.заголовок, подпись: подпись, ждём: ждём,
                          нажать: нажатьГлавное)
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 14)
            .animation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.8)), value: видно)
    }

    @ViewBuilder
    private func малые(растянуть: Bool) -> some View {
        if торг {
            МалаяКнопкаОкна(значок: "tag", заголовок: ТекстыДействийОкна.т("ma_offer"),
                            голос: ТекстыДействийОкна.т("ma_offer_a11y"), растянуть: растянуть, нажать: нажатьТорг)
                .opacity(видно ? 1 : 0)
                .offset(y: видно ? 0 : 14)
                .animation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.8).delay(0.06)), value: видно)
        }
        if связаться {
            МалаяКнопкаОкна(значок: "bubble.left.and.bubble.right", заголовок: ТекстыДействийОкна.т("ma_contact"),
                            голос: ТекстыДействийОкна.т("ma_cc_title"), растянуть: растянуть, нажать: нажатьСвязаться)
                .opacity(видно ? 1 : 0)
                .offset(y: видно ? 0 : 14)
                .animation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.8).delay(0.12)), value: видно)
        }
    }
}

/**
 Главная кнопка окна: зелёный градиент панели связи, значок в светлом квадрате, заголовок и строка пояснения; один раз
 по появлении по ней проходит мягкий блик («мощная подача»), при «Уменьшении движения» — без него. Ждём ответа гаранта —
 вместо значка колесо, второе нажатие не уходит.
 компактно (сборка 84, окно v2): без квадрата и без строки пояснения — значок 17 pt прямо в строке, заголовок 15 pt
 heavy до двух строк без ужатия (не режется многоточием); пояснение — только подсказкой VoiceOver. Тень 6 / 20 % / 3,
 блик — один раз за запуск приложения (владелец 17.10.2026: движение само по себе сбивает фокус).
 */
struct ГлавнаяКнопкаОкна: View {
    let значок: String
    let заголовок: String
    let подпись: String
    let ждём: Bool
    let компактно: Bool
    let нажать: () -> Void
    @State private var блик: CGFloat = -0.7
    @ScaledMetric(relativeTo: .subheadline) private var кегль: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var кегльПодписи: CGFloat = 11
    /// Компактный блик уже прошёл за этот запуск — у следующих окон его нет.
    private static var бликЗаЗапускБыл = false

    init(значок: String, заголовок: String, подпись: String, ждём: Bool = false, компактно: Bool = false,
         нажать: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.подпись = подпись
        self.ждём = ждём
        self.компактно = компактно
        self.нажать = нажать
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        let тень: Color = Theme.панельСвязиКонец.opacity(компактно ? 0.2 : 0.45)
        let радиусТени: CGFloat = компактно ? 6 : 12
        let сдвигТени: CGFloat = компактно ? 3 : 8
        return Button(action: нажать) {
            содержимое
                .background(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    GeometryReader { г in
                        LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.26), Color.white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: г.size.width * 0.32)
                            .rotationEffect(.degrees(16))
                            .offset(x: блик * г.size.width)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .clipShape(форма)
                .overlay {
                    форма
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.clear],
                                                     startPoint: .top, endPoint: .center), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: тень, radius: радиусТени, x: 0, y: сдвигТени)
                .contentShape(форма)
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.97))
        .disabled(ждём)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        /* VoiceOver: имя кнопки — то, что она делает («Купить безопасно»), пояснение — подсказкой. */
        .accessibilityLabel(заголовок)
        .accessibilityHint(подпись)
        .onAppear { блеснуть() }
    }

    @ViewBuilder
    private var содержимое: some View {
        if компактно {
            содержимоеКомпактно
        } else {
            содержимоеПрежнее
        }
    }

    /// Окно v2: значок 17 pt в строке и заголовок до двух строк, по центру кнопки; подписи на экране нет.
    private var содержимоеКомпактно: some View {
        HStack(spacing: 8) {
            Group {
                if ждём {
                    SiteSpinner.белый
                } else {
                    Image(systemName: значок)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: кегль, weight: .heavy))
                .tracking(-0.15)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity)
    }

    /// Как до сборки 84: значок в светлом квадрате 34 pt, заголовок и строка пояснения.
    private var содержимоеПрежнее: some View {
        HStack(spacing: 10) {
            ZStack {
                if ждём {
                    SiteSpinner.белый
                } else {
                    Image(systemName: значок)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(заголовок)
                    .font(.system(size: кегль, weight: .heavy))
                    .tracking(-0.15)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: кегльПодписи, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity, alignment: .leading)
    }

    /// Блик проходит один раз, чуть погодя после появления; без движения — не проходит. Компактная кнопка — один раз за
    /// запуск приложения: следующее окно объявления открывается без блика.
    private func блеснуть() {
        guard !ДвижениеСайта.тихо, блик < 0 else { return }
        if компактно {
            guard !Self.бликЗаЗапускБыл else { return }
            Self.бликЗаЗапускБыл = true
        }
        withAnimation(.easeInOut(duration: 1.1).delay(0.5)) { блик = 1.3 }
    }
}

/// Плитка «Торг» / «Связаться»: значок над подписью, поверхность с тонкой рамкой, высота — как у главной. Компактно
/// (окно v2, сборка 84): ширина 68 и нейтральный значок цветом текста — зелёной в кадре остаётся одна главная.
private struct МалаяКнопкаОкна: View {
    let значок: String
    let заголовок: String
    let голос: String
    let растянуть: Bool
    let компактно: Bool
    let нажать: () -> Void
    @ScaledMetric(relativeTo: .caption) private var кегль: CGFloat = 12

    /// Явный init: private @ScaledMetric прячет готовый.
    init(значок: String, заголовок: String, голос: String, растянуть: Bool, компактно: Bool = false,
         нажать: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.голос = голос
        self.растянуть = растянуть
        self.компактно = компактно
        self.нажать = нажать
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        let краскаЗначка: Color = компактно ? Theme.текст : Theme.зелёный2
        let ширина: CGFloat = компактно ? 68 : 76
        let поле: CGFloat = компактно ? 4 : 6
        return Button(action: нажать) {
            VStack(spacing: 4) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(краскаЗначка)
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.system(size: кегль, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, поле)
            .padding(.vertical, 8)
            .frame(width: растянуть ? nil : ширина)
            .frame(maxWidth: растянуть ? CGFloat.infinity : nil, minHeight: 56, maxHeight: .infinity)
            .background(Theme.поверхность, in: форма)
            .overlay {
                форма
                    .strokeBorder(Theme.линия, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            .contentShape(форма)
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.94))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(голос)
    }
}

/// Продавец заблокирован: вместо покупки, торга и связи — «Связь недоступна» и «Разблокировать» (ma_blk_t сайта).
struct СтрокаСвязьНедоступна: View {
    let ждём: Bool
    let разблокировать: () -> Void

    init(ждём: Bool, разблокировать: @escaping () -> Void) {
        self.ждём = ждём
        self.разблокировать = разблокировать
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "nosign")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 34, height: 34)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ТекстыДействийОкна.т("ma_blk_t"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(ТекстыДействийОкна.т("ma_blk_s"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: разблокировать) {
                Group {
                    if ждём {
                        SiteSpinner(размер: 16)
                    } else {
                        Text(ТекстыДействийОкна.т("ma_unblock"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.зелёный2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.зелёный.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(НажатиеСПружинкой(сжатие: 0.95))
            .disabled(ждём)
        }
        .padding(12)
        .frame(minHeight: 56)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/**
 Вещь занята (сборка 84, владелец 17.10.2026 — ошибка из разбора окна: на зарезервированной вещи предлагался «Купить
 безопасно»): серая строка «В резерве — идёт сделка» или «Продано» над единственной «Связаться». Не нажимается, без
 цвета и движения; растёт с «Размером текста» до accessibility1, как вся панель.
 */
struct СтрокаЗанятоОкна: View {
    let занятость: ГлавноеДействиеОкна.Занятость
    @ScaledMetric(relativeTo: .footnote) private var кегль: CGFloat = 13

    init(занятость: ГлавноеДействиеОкна.Занятость) {
        self.занятость = занятость
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: занятость.значок)
                .font(.system(size: кегль, weight: .semibold))
                .accessibilityHidden(true)
            Text(занятость.текст)
                .font(.system(size: кегль, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.текстВторой)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Ещё» в шапке окна

/**
 «Ещё» над фото (новая раскладка сайта): «Заблокировать продавца» / «Разблокировать» и «Пожаловаться» — те же действия,
 что «⋮» карточки продавца (ДействияСПродавцом, ЛистЖалобы); «Заблокировать» сначала спрашивает. Гостю — один пункт
 «Войти, чтобы пожаловаться». Своё объявление и нет продавца — кнопки нет.
 */
struct КнопкаЕщёОкна: View {
    let товар: Listing
    @ObservedObject private var действия = ДействияСПродавцом.shared
    @ObservedObject private var сессия = СессияПриложения.shared
    @State private var вопросБлокировки = false
    @State private var жалоба = false

    init(товар: Listing) {
        self.товар = товар
    }

    /// Новая раскладка, жалобы включены и продавец известен.
    static func есть(_ т: Listing) -> Bool {
        guard let продавец = т.продавецID, !продавец.isEmpty else { return false }
        return Config.кнопкиОкнаV2 && Config.жалобы
    }

    private var продавецID: String { товар.продавецID ?? "" }

    private var своё: Bool {
        guard !продавецID.isEmpty else { return true }
        return действия.мой == продавецID || (!сессия.id.isEmpty && сессия.id == продавецID)
    }

    var body: some View {
        if !своё {
            Menu {
                пункты
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: МеркиКнопокНадФото.значок, weight: .bold))
                    .foregroundStyle(Color.white)
                    .фонКнопкиНадФото()
            }
            .menuStyle(.button)
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel(ТекстыДействийОкна.т("ma_more"))
            .alert(SellerText.т("block_q"), isPresented: $вопросБлокировки) {
                Button(SellerText.т("cancel"), role: .cancel) {}
                Button(SellerText.т("block"), role: .destructive) {
                    действия.переключитьБлокировку(продавецID, имя: товар.продавец ?? "")
                }
            } message: {
                Text(SellerText.т("block_msg"))
            }
            .sheet(isPresented: $жалоба) {
                ЛистЖалобы(продавецID: продавецID, объявление: товар.id)
            }
            .onAppear { действия.узнать(продавца: продавецID) }
        }
    }

    @ViewBuilder
    private var пункты: some View {
        if сессия.вошёл == false {
            Button {
                if !ОкнаПриложения.shared.показать(.вход, задержка: 300_000_000) { ВходПоверх.показать() }
            } label: {
                Label(ТекстыДействийОкна.т("ma_more_login"), systemImage: "person.crop.circle")
            }
        } else {
            let блок = действия.заблокирован(продавецID)
            Button {
                if блок {
                    действия.переключитьБлокировку(продавецID, имя: товар.продавец ?? "")
                } else {
                    вопросБлокировки = true
                }
            } label: {
                Label(блок ? ТекстыДействийОкна.т("ma_unblock") : ТекстыДействийОкна.т("ma_block"), systemImage: "nosign")
            }
            .disabled(действия.блокировкаВПути.contains(продавецID))
            Button(role: .destructive) {
                Task { @MainActor in
                    if await действия.можноЖаловаться() { жалоба = true }
                }
            } label: {
                Label(ТекстыДействийОкна.т("ma_report"), systemImage: "flag")
            }
        }
    }
}
