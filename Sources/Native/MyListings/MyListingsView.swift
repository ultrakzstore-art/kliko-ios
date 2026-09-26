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
   · 🔴 ДЕНЬГИ — только сайт: «Продвинуть» / «Продлить ТОП» (?promote=<id>), «Расширить» слоты, «Пакет Kliko AI», «В ТОП»
     у резюме. Config.цифровыеПокупки = false: натив показывает только сведения («В ТОПе до …», «Бесплатные
     авто-поднятия … включены») и ничего не покупает; своего окна покупки нет и при true: этап 48 (владелец
     26.09.2026) показал цены строкой «Платные услуги», а покупка — кабинет сайта, пока не решён вопрос In-App Purchase.
 Не перенесено в этом этапе: режим «Выбрать» с массовыми действиями и очередью публикаций (mass_edit_items, pubq_*),
 «Копия» (заполняет мастер подачи сайта) и «Экспорт CSV» — их делает страница кабинета.
 */
struct МоиОбъявленияЭкран: View {
    @ObservedObject private var модель = МоиОбъявленияМодель.shared
    let открыть: (URL) -> Void

    @State private var вопрос: ВопросОбъявлений? = nil
    @State private var поделиться: МоёОбъявление? = nil
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
            .task { await модель.загрузить(страницу: true) }
            .alert(вопрос?.заголовок ?? "", isPresented: вопросНаЭкране, presenting: вопрос) { в in
                Button(в.кнопка, role: .destructive) { в.действие() }
                Button(т("cancel"), role: .cancel) {}
            } message: { в in
                Text(в.текст)
            }
            .sheet(item: $поделиться) { товар in
                ЛистПоделитьсяОбъявлением(товар: товар, скопировано: { модель.показать(т("link_copied")) })
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузить(страницу: true) }
                })
            }
            .overlay { окноПоверх }
            .overlay(alignment: .bottom) { плашкаВнизу }
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
                                 расширить: { страница("cabinet.php?go=items") },
                                 верификация: { страница("cabinet.php?go=verify") })
                ВкладкиОбъявлений(выбрана: $модель.вкладка)
                ПолеПоискаОбъявлений(текст: $модель.запрос)
                if !модель.работа.isEmpty { блокРаботы }
                карточки
                кнопкаДобавить
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await модель.загрузить(страницу: true) }
    }

    @ViewBuilder
    private var карточки: some View {
        let видимые = модель.видимые
        if видимые.isEmpty {
            пусто
        } else {
            ForEach(видимые) { товар in
                КарточкаМоегоОбъявления(товар: товар, вкладка: модель.вкладка,
                                        магазин: модель.кабинет?.магазин ?? false,
                                        подписьОдобрено: модель.кабинет?.подписьОдобрено ?? "",
                                        занято: модель.занято.contains(товар.id), проверяем: модель.проверяем,
                                        действие: { д in нажато(д, товар) },
                                        скопироватьID: { скопировать(товар.id) })
            }
        }
    }

    /// Пустая вкладка или поиск без результата (.empty-state сайта); на пустых «Опубликованных» без единого
    /// объявления — ещё блок переноса по ссылке (.imp-empty).
    private var пусто: some View {
        VStack(spacing: 12) {
            if !модель.запрос.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(String(format: т("not_found"), модель.запрос.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                Button(т("search_clear")) { модель.запрос = "" }
                    .font(.system(size: 15, weight: .bold))
                    .tint(Theme.акцент)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(модель.вкладка.пусто)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                if модель.вкладка == .published && модель.товары.isEmpty { блокПереноса }
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private var блокПереноса: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("imp_t"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
            Text(т("imp_s"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Button(т("imp_b")) { страница("cabinet.php?go=import") }
                .font(.system(size: 14, weight: .bold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.зелёный)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// «+ Добавить объявление» — мастер подачи (этап 42); рубильник выключен — страница подачи сайта.
    private var кнопкаДобавить: some View {
        Button {
            if !ПодачаОкно.shared.открыть(.новое) {
                страница(Config.подачаНаСайте ?? "cabinet?go=add")
            }
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
            /* «В ТОП» — платно (Config.цифровыеПокупки): страница кабинета. */
            страница("cabinet.php?go=items")
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
            поделиться = товар
        case .продвинуть:
            /* 🔴 Деньги: ТОП и поднятия покупаются только на странице сайта (Config.цифровыеПокупки). */
            страница("cabinet.php?promote=" + номер(товар.id))
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
                               расширить: {
                                   модель.закрытьОкно()
                                   страница("cabinet.php?go=items")
                               },
                               верификация: {
                                   модель.закрытьОкно()
                                   страница("cabinet.php?go=verify")
                               },
                               кОстатку: { id in
                                   модель.закрытьОкно()
                                   правка(id: id)
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
                .padding(.bottom, 24)
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

/// #adv-tabs: три вкладки в одной плашке, выбранная — зелёный градиент (.adv-tab-active), «Удалённые» — красным.
struct ВкладкиОбъявлений: View {
    @Binding var выбрана: ВкладкаОбъявлений

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ВкладкаОбъявлений.allCases, id: \.self) { вкладка in
                кнопка(вкладка)
            }
        }
        .padding(4)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func кнопка(_ вкладка: ВкладкаОбъявлений) -> some View {
        let активна = выбрана == вкладка
        return Button {
            выбрана = вкладка
        } label: {
            Text(вкладка.название)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(активна ? Color.white : (вкладка == .deleted ? КраскаОбъявлений.плохоТекст : Theme.текстВторой))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if активна {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                    }
                }
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
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(МоиОбъявленияText.т("search"), text: $текст)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !текст.isEmpty {
                Button {
                    текст = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.текстВторой)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(МоиОбъявленияText.т("search_clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(Theme.поверхность, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}
