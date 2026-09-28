import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ЭКРАН, ЭТАП 41 (владелец 26.09.2026: «всё одно и то же, просто код разный»; Config.нативныеОбъявления).

 Главный экран кабинета сайта (#main-screen, карта §3.0.1) сверху вниз: карточка «Доступно» (Kliko AI и слоты),
 вкладки «Опубликованные» / «Неактивные» / «Удалённые», поиск «Поиск: название, бренд, ID», блок «Работа», карточки
 объявлений, «+ Добавить объявление». Вход — строка «Мои объявления» во вкладке «Кабинет» и ссылка ?go=items.

 Что делается здесь, а что — страницей сайта:
   · своё: список, значки, счётчики и «кто», срок жизни и авто-продление, склад магазина, «Снять», «Активировать»
     и «Восстановить» с окном проверки Kliko AI, «Проверить сейчас», «Удалить», «Удалить навсегда», «Поделиться»
     (WhatsApp, Telegram, ссылка), «Работа» — снять, удалить, восстановить;
   · с этапа 42 (Config.нативнаяПодача): «Изменить», «Редактировать → на проверку» и «+ Добавить объявление» —
     свой мастер подачи и правки (ПодачаОкно); рубильник выключен — /cabinet.php?edit=<id> и cabinet?go=add сайта;
   · «Смотреть» — своя карточка объявления в стеке кабинета; верификация — окно «Стать продавцом» (ЛистВерификации),
     сама проверка eGov — страницей сайта;
   · сайт: перенос по ссылке (?go=import);
   · платные услуги («Продвинуть» / «Продлить ТОП», «Расширить» слоты, «Пакет Kliko AI», «В ТОП» у резюме) — только
     через App Store (ЛистУслугиApple) и только при Config.цифровыеПокупки. Выключено — кнопок нет, одни сведения
     («В ТОПе до …», «Бесплатные авто-поднятия … включены»); ссылок на оплату на сайте нет никогда.
 28.09.2026: «+ Добавить» в шапке, режим «Выбрать» (флажки, «Все», счётчик, нижняя панель) и масс-редактор с теми же
 действиями, что у сайта (mass_edit_items, pubq_schedule, по одному deactivate / activate / delete) — MyListingsBulk*.swift.
 Не перенесено: «Копия» (заполняет мастер подачи сайта) и «Экспорт CSV» — их делает страница кабинета.
 */
struct МоиОбъявленияЭкран: View {
    @ObservedObject private var модель = МоиОбъявленияМодель.shared
    /// Режим «Выбрать» и масс-редактор.
    @ObservedObject private var редактор = МассовыйРедактор.shared
    let открыть: (URL) -> Void

    @State private var вопрос: ВопросОбъявлений? = nil
    @State private var входОткрыт = false
    /// «Смотреть» — своя карточка объявления в стеке кабинета (маршрут Listing — у CabinetView).
    @State private var карточка: Listing? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаМоихОбъявлений(заголовок: т("title")))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if списокНаЭкране {
                        КнопкаДобавитьВШапке { добавить() }
                    }
                }
            }
            .task { await модель.загрузить(страницу: true) }
            .alert(вопрос?.заголовок ?? "", isPresented: вопросНаЭкране, presenting: вопрос) { в in
                Button(в.кнопка, role: .destructive) { в.действие() }
                Button(т("cancel"), role: .cancel) {}
            } message: { в in
                Text(в.текст)
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузить(страницу: true) }
                })
            }
            .overlay { окноПоверх }
            .overlay(alignment: .bottom) { плашкаВнизу }
            .overlay { окнаМассовых }
            .sheet(item: $редактор.лист) { лист in
                ЛистМассовых(лист: лист, про: модель.массовые.про)
            }
            .onChange(of: модель.вкладка) { _, _ in редактор.вкладкаСменилась() }
            .onChange(of: модель.товары) { _, _ in редактор.сверить() }
            .navigationDestination(item: $карточка) { товар in
                ListingDetailView(товар: товар, открыть: открыть)
            }
    }

    private var вопросНаЭкране: Binding<Bool> {
        Binding(get: { вопрос != nil }, set: { показан in
            if !показан { вопрос = nil }
        })
    }

    // MARK: - Состояния экрана

    private enum Вид {
        case вход
        case ошибка(String)
        case загрузка
        case список
    }

    private var вид: Вид {
        switch модель.загрузка {
        case .нуженВход:          return .вход
        case .ошибка(let текст):  return модель.товары.isEmpty ? .ошибка(текст) : .список
        case .нет, .идёт:         return модель.товары.isEmpty ? .загрузка : .список
        case .готово:             return .список
        }
    }

    /// «+ Добавить» в шапке — когда на экране список (не вход, не ошибка, не первая загрузка).
    private var списокНаЭкране: Bool {
        if case .список = вид { return true }
        return false
    }

    @ViewBuilder
    private var содержимое: some View {
        switch вид {
        case .вход:
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        case .ошибка(let текст):
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                       действие: { Task { await модель.загрузить(страницу: true) } })
        case .загрузка:
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .список:
            список
        }
    }

    private var список: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                КарточкаДоступно(ии: модель.кабинет?.ии, слоты: модель.слоты, товары: модель.товары,
                                 верификация: { страница("cabinet.php?go=verify") },
                                 расширить: { ЛистУслугиApple.показать(.слоты) },
                                 пакетИИ: { ЛистУслугиApple.показать(.пакетИИ) })
                ВкладкиОбъявлений(выбрана: $модель.вкладка)
                строкаПоиска
                if !модель.работа.isEmpty { блокРаботы }
                карточки
                кнопкаДобавить
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await модель.загрузить(страницу: true) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if редактор.включён {
                ПанельВыбораОбъявлений(вкладка: модель.вкладка, правка: модель.массовые.правка)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ДвижениеСайта.появление, value: редактор.включён)
    }

    /// #adv-selrow: поиск и «Выбрать» / «Отмена» справа (кнопка — у PRO, как у сайта).
    private var строкаПоиска: some View {
        HStack(spacing: 8) {
            ПолеПоискаОбъявлений(текст: $модель.запрос)
            if модель.массовые.выбор || редактор.включён {
                КнопкаВыбратьОбъявления(включён: редактор.включён) { редактор.переключить() }
            }
        }
    }

    @ViewBuilder
    private var карточки: some View {
        let видимые = модель.видимые
        if видимые.isEmpty {
            пусто
        } else {
            ForEach(видимые) { товар in
                карточка(товар)
            }
        }
    }

    /// Карточка; в режиме «Выбрать» — флажок в углу, рамка у отмеченной, нажатие по карточке отмечает (_advSelPick).
    private func карточка(_ товар: МоёОбъявление) -> some View {
        let выбор = редактор.включён
        let можно = выбор && товар.выбирается(модель.вкладка, сейчас: Date().timeIntervalSince1970)
        let отмечен = можно && редактор.отмечено(товар)
        return КарточкаМоегоОбъявления(товар: товар, вкладка: модель.вкладка,
                                       магазин: модель.кабинет?.магазин ?? false,
                                       подписьОдобрено: модель.кабинет?.подписьОдобрено ?? "",
                                       занято: модель.занято.contains(товар.id), проверяем: модель.проверяем,
                                       действие: { д in нажато(д, товар) },
                                       скопироватьID: { скопировать(товар.id) },
                                       режимВыбора: выбор)
            .allowsHitTesting(!выбор)
            .accessibilityHidden(выбор)
            .overlay {
                if отмечен {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.акцент, lineWidth: 2.5)
                        .shadow(color: Theme.зелёный2.opacity(0.18), radius: 4)
                }
            }
            .overlay {
                if выбор {
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .onTapGesture { редактор.отметить(товар) }
                        .accessibilityElement()
                        .accessibilityLabel(String(format: МассовыйРедакторText.т("a11y_check"), товар.название))
                        .accessibilityAddTraits(отмечен ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { редактор.отметить(товар) }
                }
            }
            .overlay(alignment: .topTrailing) {
                if можно {
                    ФлажокВыбораОбъявления(отмечен: отмечен)
                        .padding(9)
                        .onTapGesture { редактор.отметить(товар) }
                }
            }
            .offset(y: отмечен ? -2 : 0)
            .animation(ДвижениеСайта.выбор, value: отмечен)
    }

    /// Пустая вкладка или поиск без результата (.empty-state сайта); на пустых «Опубликованных» без единого
    /// объявления — ещё блок переноса по ссылке (.imp-empty).
    private var пусто: some View {
        VStack(spacing: 0) {
            if !модель.запрос.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                Text(String(format: т("not_found"), модель.запрос.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                Button(т("search_clear")) { модель.запрос = "" }
                    .font(.system(size: 14, weight: .bold))
                    .tint(Theme.акцент)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                Text(модель.вкладка.пусто)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                if модель.вкладка == .published && модель.товары.isEmpty {
                    блокПереноса
                        .padding(.top, 20)
                }
            }
        }
        .padding(.vertical, 50)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    /// .imp-empty: по центру, серая подложка с пунктирной рамкой, кнопка #16a34a во всю ширину.
    private var блокПереноса: some View {
        VStack(spacing: 0) {
            Text(т("imp_t"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
            Text(т("imp_s"))
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            Button { страница("cabinet.php?go=import") } label: {
                Text(т("imp_b"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(КраскаОбъявлений.зелёнаяКнопка,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// «+ Добавить объявление» — мастер подачи (этап 42); рубильник выключен — страница подачи сайта.
    private func добавить() {
        if !ПодачаОкно.shared.открыть(.новое) {
            страница(Config.подачаНаСайте ?? "cabinet?go=add")
        }
    }

    private var кнопкаДобавить: some View {
        Button {
            добавить()
        } label: {
            Text(т("add"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .leading,
                                           endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .padding(.top, 4)
    }

    // MARK: - «Работа»

    private var блокРаботы: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("as_jobs"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            ForEach(модель.работа) { запись in
                СтрокаРаботы(запись: запись, занято: модель.занято.contains("job:" + запись.id),
                             действие: { д in нажатоВРаботе(д, запись) })
            }
        }
    }

    private func нажатоВРаботе(_ действие: СтрокаРаботы.Действие, _ запись: МояРабота) {
        switch действие {
        case .восстановить:
            модель.действиеРаботы("restore", запись)
        case .снять:
            вопрос = ВопросОбъявлений(заголовок: т("jb_off_q"), текст: т("jb_off_s"),
                                      кнопка: запись.истёк ? т("jb_delete") : т("jb_off")) {
                модель.действиеРаботы("delete", запись)
            }
        case .изменить:
            /* Этап 50: мастер резюме и вакансии — свой (МастерРезюме, окно поверх экрана). */
            НативныеОкна.показать(.работа(вид: запись.вакансия ? .вакансия : .резюме, номер: запись.id))
        case .вТоп:
            /* «В ТОП» резюме — окно покупки App Store (кнопка есть только при Config.цифровыеПокупки). */
            ЛистУслугиApple.показать(.топРезюме, цель: запись.id)
        }
    }

    // MARK: - Нажатия на карточке

    private func нажато(_ действие: ДействиеКарточки, _ товар: МоёОбъявление) {
        switch действие {
        case .кнопка(let кнопка):
            нажатаКнопка(кнопка, товар)
        case .открыть:
            /* advView: одобренное — страница объявления, остальные — правка. */
            if товар.статус == "approved" { страницаОбъявления(товар) } else { правка(товар) }
        case .автоПродление(let включить):
            модель.автоПродление(товар, включить: включить)
        case .склад(let количество):
            модель.склад(товар, количество: количество)
        case .ждут:
            модель.окно = .ждутТовар(id: товар.id, сколько: товар.статистика.ждут)
        case .верификация:
            /* Окно «Стать продавцом» (ЛистВерификации), сама проверка eGov — страницей сайта из него. */
            let адрес = Config.страницаСайта("cabinet.php?go=verify")
            if !ОкнаПриложения.shared.показать(.верификация, запасной: адрес) { страница("cabinet.php?go=verify") }
        }
    }

    private func нажатаКнопка(_ кнопка: КнопкаОбъявления, _ товар: МоёОбъявление) {
        switch кнопка {
        case .изменить, .наПроверку:
            правка(товар)
        case .смотреть:
            страницаОбъявления(товар)
        case .поделиться:
            /* advShare сайта — окно кабинета showSocialModal(…, "share"), не лист ленты (CabinetShare.swift). */
            let имя = НастройкиМодель.shared.профиль?.имя ?? ""
            ОкноПоделитьсяКабинета.показать(ДанныеОтправкиСайта(моё: товар, продавец: имя))
        case .продвинуть:
            /* ТОП и поднятия — окно покупки App Store (кнопка есть только при Config.цифровыеПокупки). */
            ЛистУслугиApple.показать(.продвижение, цель: товар.id)
        case .снять:
            вопрос = ВопросОбъявлений(заголовок: т("deact_q"), текст: String(format: т("deact_msg"), товар.название),
                                      кнопка: т("deact_ok")) { модель.снять(товар) }
        case .активировать, .восстановить:
            модель.активировать(товар)
        case .проверить:
            модель.проверитьСейчас(товар)
        case .удалить:
            вопрос = ВопросОбъявлений(заголовок: т("del_q"), текст: String(format: т("del_msg"), товар.название),
                                      кнопка: т("del_ok")) { модель.удалить(товар) }
        case .удалитьНавсегда:
            вопрос = ВопросОбъявлений(заголовок: т("perm_q"), текст: String(format: т("perm_msg"), товар.название),
                                      кнопка: т("perm_ok")) { модель.удалитьНавсегда(товар) }
        }
    }

    /// Правка — мастер подачи в режиме правки (этап 42); рубильник выключен — страница кабинета с ?edit=<id> (сайт
    /// открывает её после загрузки списка, карта §3.2.11).
    private func правка(_ товар: МоёОбъявление) {
        правка(id: товар.id)
    }

    private func правка(id: String) {
        if ПодачаОкно.shared.открыть(.правка(id)) { return }
        страница("cabinet.php?edit=" + номер(id))
    }

    /// «Смотреть» — своя карточка объявления (ListingDetailView дотянет его по номеру); без неё — страница сайта
    /// /marketplace.php?item=<id>&ret=cabinet без локали, как ссылка сайта.
    private func страницаОбъявления(_ товар: МоёОбъявление) {
        if Config.нативнаяКарточка,
           товар.id.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            карточка = Listing(номер: товар.id)
            return
        }
        if let адрес = Config.url("/marketplace.php?item=" + номер(товар.id) + "&ret=cabinet") { открыть(адрес) }
    }

    /// Страница сайта /kz/<язык>/<хвост> в веб-обёртке.
    private func страница(_ хвост: String) {
        if let адрес = Config.страницаСайта(хвост) { открыть(адрес) }
    }

    private func номер(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }

    private func скопировать(_ id: String) {
        UIPasteboard.general.string = id
        модель.показать(т("adv_id_copied"))
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else {
            страница("cabinet.php")
        }
    }

    // MARK: - Окна и плашка

    @ViewBuilder
    private var окноПоверх: some View {
        if let окно = модель.окно {
            ОкноМоихОбъявлений(окно: окно, занято: !модель.занято.isEmpty,
                               закрыть: { модель.закрытьОкно() },
                               одобрено: { модель.закрытьОдобрено() },
                               ожидание: { модель.закрытьОжидание() },
                               наРучную: { id in модель.наРучнуюПроверку(id) },
                               верификация: {
                                   модель.закрытьОкно()
                                   страница("cabinet.php?go=verify")
                               },
                               кОстатку: { id in
                                   модель.закрытьОкно()
                                   правка(id: id)
                               },
                               расширить: {
                                   модель.закрытьОкно()
                                   ЛистУслугиApple.показать(.слоты)
                               })
            .transition(.opacity)
        }
    }

    /// Вопрос масс-редактора со сводкой и окно хода — поверх всего экрана.
    @ViewBuilder
    private var окнаМассовых: some View {
        if let ход = редактор.ход {
            ОкноХодаМассовых(ход: ход, закрыть: { редактор.закрытьХод() })
                .transition(.opacity)
        } else if let в = редактор.вопрос {
            ОкноВопросаМассовых(вопрос: в, отмена: { редактор.вопрос = nil }, да: {
                редактор.вопрос = nil
                в.действие()
            })
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var плашкаВнизу: some View {
        if let текст = модель.плашка {
            Text(текст)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.зелёный, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, редактор.включён ? 140 : 24)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

/// Вопрос перед записью — те же заголовок, текст и кнопка, что у окна подтверждения сайта (showConfirm / cabConfirm).
struct ВопросОбъявлений {
    let заголовок: String
    let текст: String
    let кнопка: String
    let действие: () -> Void

    init(заголовок: String, текст: String, кнопка: String, действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.текст = текст
        self.кнопка = кнопка
        self.действие = действие
    }
}

/// Шапка экрана: в виде сайта — панель сайта, иначе системная.
private struct ШапкаМоихОбъявлений: ViewModifier {
    let заголовок: String

    func body(content: Content) -> some View {
        if Config.дизайнКакНаСайте {
            content
                .шапкаЭкранаСайта(заголовок)
        } else {
            content
                .navigationTitle(заголовок)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Вкладки и поиск

/// #adv-tabs: три вкладки в одной плашке, выбранная — зелёный градиент (.adv-tab-active), у «Удалённых» — корзина.
/// Длинные kk/ar подписи не ужимаются: не влезли поровну — плашка листается вбок, как overflow-x сайта.
struct ВкладкиОбъявлений: View {
    @Binding var выбрана: ВкладкаОбъявлений

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(ВкладкаОбъявлений.allCases, id: \.self) { вкладка in
                    кнопка(вкладка)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ВкладкаОбъявлений.allCases, id: \.self) { вкладка in
                        кнопка(вкладка)
                            .fixedSize()
                    }
                }
                .padding(4)
            }
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .compositingGroup()
        .shadow(color: Color(red: 15 / 255, green: 40 / 255, blue: 25 / 255).opacity(0.14), radius: 5, y: 2)
    }

    private func кнопка(_ вкладка: ВкладкаОбъявлений) -> some View {
        let активна = выбрана == вкладка
        return Button {
            выбрана = вкладка
        } label: {
            HStack(spacing: 6) {
                if вкладка == .deleted {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(вкладка.название)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(активна ? Color.white : Theme.текстВторой)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background {
                if активна {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .shadow(color: Theme.зелёный2.opacity(0.35), radius: 7, y: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: МоиОбъявленияText.т("a11y_tab"), вкладка.название))
        .accessibilityAddTraits(активна ? .isSelected : [])
    }
}

/// #adv-search: пилюля с лупой и крестиком.
struct ПолеПоискаОбъявлений: View {
    @Binding var текст: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(МоиОбъявленияText.т("search"), text: $текст)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !текст.isEmpty {
                Button {
                    текст = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.цвет(0x51665B, 0x90A499))
                        .frame(width: 24, height: 24)
                        .background(Theme.поверхность2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(МоиОбъявленияText.т("search_clear"))
            }
        }
        // Высота 40 как у поля сайта (14 пт текст, отступ 10, рамка 1.5) и не прыгает, когда появляется крестик 24.
        .frame(minHeight: 24)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(Theme.поверхность, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}
