import SwiftUI

/**
 НАТИВНАЯ ЛЕНТА — ЭТАП 1 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «переделаем приложение полностью под SwiftUI»,
 «поэтапно, начни с ленты»).

 Что здесь: главная — лента объявлений с поиском, разделами, подгрузкой и «потяни, чтобы обновить». Всё остальное
 (карточка, чат, сделка, оплата, кабинет) пока страницы сайта: нажатие на карточку открывает объявление в той же
 веб-обёртке, где живёт сессия. Следующие этапы переносят экраны по одному.

 Лента живёт поверх веб-обёртки и не пересоздаётся, когда её прячут: вернулись со страницы — та же прокрутка,
 тот же поиск (RootWebView). Страница под ней грузится как раньше — ради сессии, пушей и плашки сделки.

 Разделы — из снимка, который присылает главная сайта (FeedSnapshot): там названия на языке человека и краски
 разделов, и второй словарь разделов в приложении не заводим. Снимка нет — лента без полосы разделов.

 С этапа 14 на iPad в широком окне лента и выбранное объявление — рядом, в две колонки (раскладкаРядом,
 Native/IPad/FeedSplit.swift); iPhone и узкое окно — прежний стек (раскладкаСтеком).
 */
struct NativeFeedView: View {
    @StateObject private var модель = FeedModel()
    /// Плитки и ряды «Рекомендуем» главной как на сайте (этап 26).
    @StateObject private var подборки = ПодборкиГлавной()
    /// «Вы смотрели» и история поиска (этап 6) — на телефоне, общие для всей ленты.
    @ObservedObject private var недавние = RecentStore.shared
    /// Открыть страницу сайта (объявление, кабинет) в веб-обёртке.
    let открыть: (URL) -> Void
    /// Лента API не работает — показать ленту сайта.
    let открытьСайт: () -> Void
    /// Стек ленты снаружи — у вкладок (этап 8): ссылка из пуша кладёт в него объявление. nil — стек свой, как раньше.
    private let внешнийПуть: Binding<NavigationPath>?
    @State private var свойПуть = NavigationPath()
    /// Поле поиска активно — снаружи его включает быстрое действие «Поиск» с иконки (этап 10). nil — своё, как раньше.
    private let внешнийПоиск: Binding<Bool>?
    @State private var свойПоиск = false
    /// Сохранённый поиск снаружи — уведомление о новых или строка кабинета (этап 12). nil — входа нет (без вкладок).
    private let внешнееИскомое: Binding<ИскомоеЛенты?>?
    /// Колокольчик «Сохранить поиск» (этап 12) спрашивает здесь, сохранён ли уже поиск ленты.
    @ObservedObject private var сохранённые = SavedSearchStore.shared
    /// Сохранённых поисков уже предел — объяснить, а не вытеснять старый молча.
    @State private var поисковПолно = false
    /// Лист «Уточнить» (этап 18) — город, цена, «только новые» по загруженному.
    @State private var уточнятьПоказан = false
    /// Поле поиска зелёной шапки в фокусе (этап 25) — вместо isPresented у .searchable.
    @FocusState private var полеВФокусе: Bool
    /// Что на экране у нативного слоя: строка состояния над шапкой, город, главная для нижней панели (этапы 25, 27).
    @ObservedObject private var вид = ВидСайта.shared
    /// Тема на экране — кнопка темы в шапке (этап 25) показывает луну в светлой и солнце в тёмной, как на сайте.
    @Environment(\.colorScheme) private var схема

    /// Владелец 25.09.2026, проверка на телефоне, сборка 33 («лента подвисает»): начальное значение @State считается
    /// при КАЖДОМ создании NativeFeedView, а создаётся она на каждую перерисовку вкладок — и каждый раз снимок читался с
    /// диска и разбирался JSONDecoder на главной очереди. Теперь — один раз за запуск (FeedStore.разделыНаЗапуске);
    /// @State и раньше брал только первое значение, так что показ тот же.
    @State private var разделы: [FeedSnapshot.Row] = FeedStore.разделыНаЗапуске

    /// Размер текста в Настройках: при крупном для доступности — сетка в одну колонку (этап 11, ListingCard.сетка).
    @Environment(\.dynamicTypeSize) private var размерТекста

    /// Выбранное объявление правой колонки на iPad (этап 14). Снаружи — у вкладок: ссылка из пуша выбирает объявление,
    /// а не кладёт его поверх ленты. nil — своё (лента без вкладок).
    private let внешнееВыбранное: Binding<Listing?>?
    @State private var своёВыбранное: Listing? = nil
    /// Колонки на iPad: обе на экране, и в вертикальном положении тоже; спрятать ленту можно кнопкой колонки.
    @State private var видимостьКолонок: NavigationSplitViewVisibility = .all
    /// Широкое окно iPad — лента и карточка рядом (ДвеКолонки.включены).
    @Environment(\.horizontalSizeClass) private var ширинаОкна
    /// Место внизу под нижней панелью сайта (владелец 25.09.2026, проверка на телефоне, сборка 33): панель теперь слой
    /// поверх вкладок, и корень ленты оставляет под неё место сам — внутри своего стека. Без нижних вкладок — 0.
    @Environment(\.местоПодПанельюСайта) private var местоПодПанелью
    /// Какая раскладка была на экране в прошлый раз: true — две колонки, nil — ещё никакой. onAppear раскладки
    /// приходит и при возврате на вкладку «Лента», а выбранное переезжает только при настоящей смене ширины окна.
    @State private var былиКолонки: Bool? = nil
    /// Выбранное положил в стек узкий режим (выбранноеВСтек): окно снова расширят — оно вернётся корнем правой колонки.
    @State private var выбранноеВПути = false

    init(открыть: @escaping (URL) -> Void, открытьСайт: @escaping () -> Void, путь: Binding<NavigationPath>? = nil,
         поиск: Binding<Bool>? = nil, найти: Binding<ИскомоеЛенты?>? = nil, выбранное: Binding<Listing?>? = nil) {
        self.открыть = открыть
        self.открытьСайт = открытьСайт
        внешнийПуть = путь
        внешнийПоиск = поиск
        внешнееИскомое = найти
        внешнееВыбранное = выбранное
    }

    var body: some View {
        Group {
            /* Этап 14: iPad в широком окне — лента и карточка рядом. iPhone и узкое окно iPad — стек, как раньше. */
            if двеКолонки {
                раскладкаРядом
            } else {
                раскладкаСтеком
            }
        }
        .task { await модель.начать() }
        /* Этап 25: зелёная шапка под часами — только на корне ленты в стеке; SceneDelegate красит по этому часы. */
        .onAppear { отметитьКорень() }
        .onChange(of: путьСтека.wrappedValue.count) { _, _ in отметитьКорень() }
        .onChange(of: ширинаОкна) { _, _ in отметитьКорень() }
        /* Этап 27: первая кнопка панели сайта — «Категории» на главной и «Главная» в разделе или поиске. */
        .onChange(of: модель.действующее) { _, искомое in
            if вид.главная != искомое.пустое { вид.главная = искомое.пустое }
        }
    }

    /// Стек ленты (этапы 1–13): карточка, чат и избранное ложатся поверх ленты.
    private var раскладкаСтеком: some View {
        NavigationStack(path: путьСтека) {
            лента
                .оставитьМестоПодПанелью(местоПодПанелью)
                .navigationDestination(for: Listing.self) { товар in
                    ListingDetailView(товар: товар, открыть: открыть)
                }
                .чатМаршруты(открыть: открыть)
                .избранноеМаршруты(открыть: открыть)
        }
        /* Этап 14: окно iPad сузили (Split View, Slide Over) — правой колонки больше нет. На iPhone выбранного не
           бывает, и здесь ничего не происходит. */
        .onAppear {
            if былиКолонки != false { выбранноеВСтек() }
            былиКолонки = false
        }
        /* В узком окне вернулись к ленте («Назад», сброс стека ссылкой этапов 8, 10, 12) — выбранное закрыто: расширят
           окно — справа подсказка, а не объявление, из которого человек уже ушёл. */
        .onChange(of: путьСтека.wrappedValue.count) { _, стало in
            guard стало == 0 else { return }
            if выбранноеВПути { выбранноеВПути = false }
            if выбор.wrappedValue != nil { выбор.wrappedValue = nil }
        }
    }

    /**
     iPad, широкое окно (этап 14): слева лента, справа выбранное объявление со своим стеком — похожие и «Написать»
     ложатся в него, «Назад» ведёт к выбранному.

     Путь стека правой колонки — тот же, что у ленты в стеке (путьСтека). Поэтому «к корню ленты» у вкладок (этапы 8,
     10, 12) снимает открытое поверх выбранного, а при смене ширины окна открытые экраны сами переезжают из колонки в
     стек и обратно.
     */
    private var раскладкаРядом: some View {
        NavigationSplitView(columnVisibility: $видимостьКолонок) {
            /* Колонка ленты шире стандартной боковой: при 400 pt в ней две карточки в ряд, сетка та же (ListingCard.сетка). */
            лента
                .оставитьМестоПодПанелью(местоПодПанелью)
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            NavigationStack(path: путьСтека) {
                колонкаКарточки
                    .оставитьМестоПодПанелью(местоПодПанелью)
                    .navigationDestination(for: Listing.self) { товар in
                        ListingDetailView(товар: товар, открыть: открыть)
                    }
                    .чатМаршруты(открыть: открыть)
                    .избранноеМаршруты(открыть: открыть)
            }
        }
        /* balanced — колонки делят ширину, а не лента наплывает на карточку: иначе в вертикальном положении iPad
           лента пряталась бы за кнопку, и человек видел бы одну подсказку «Выберите объявление». */
        .navigationSplitViewStyle(.balanced)
        /* «Поиск» с иконки (этап 10) — поле в колонке ленты: спрятанную колонку показать. */
        .onChange(of: поискПоказан.wrappedValue) { _, показан in
            if показан { показатьЛенту() }
        }
        /* Окно снова расширили — выбранное из стека обратно в корень правой колонки. */
        .onAppear {
            if былиКолонки == false { выбранноеВКолонку() }
            былиКолонки = true
        }
    }

    /// Правая колонка: выбранное объявление или подсказка. Другое объявление — новая карточка со своим состоянием
    /// (.id); то же самое — прежняя, уже дотянутая: ссылка на открытое объявление не сбросит его к заготовке.
    @ViewBuilder
    private var колонкаКарточки: some View {
        if let товар = выбор.wrappedValue {
            ListingDetailView(товар: товар, открыть: открыть)
                .id(товар.id)
        } else {
            ЗаглушкаКарточки()
        }
    }

    /// Сама лента: «Вы смотрели», разделы, сетка, шапка и поиск — одна и та же в стеке и в левой колонке.
    /// Этап 25: шапка — либо зелёная как на сайте (лентаСайта), либо системная с .searchable, как раньше (лентаПрежняя);
    /// общее у них — ниже.
    private var лента: some View {
        Group {
            if Config.дизайнКакНаСайте {
                лентаСайта
            } else {
                лентаПрежняя
            }
        }
        .alert(SavedSearchText.т("full"), isPresented: $поисковПолно) {
            Button(SavedSearchText.т("ok"), role: .cancel) {}
        } message: {
            Text(String(format: SavedSearchText.т("full_msg"), SavedSearchStore.предел))
        }
        /* Сохранённый поиск снаружи (этап 12): пришёл, пока лента на экране, — onChange; раньше, чем она
           появилась (холодный старт по уведомлению), — onAppear. */
        .onChange(of: внешнееИскомое?.wrappedValue) { _, _ in применитьСнаружи() }
        .onAppear { применитьСнаружи() }
        /* Этап 18: лист уточнения — на самой ленте, поэтому один и тот же в стеке iPhone и в левой колонке iPad. */
        .sheet(isPresented: $уточнятьПоказан) { ЛистУточнения(модель: модель) }
    }

    /// Прежний вид (этапы 1–24): системная панель со знаком Kliko и .searchable.
    private var лентаПрежняя: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if показатьНедавние {
                    ПолосаНедавних(товары: недавние.товары, открыть: открыть, очистить: {
                        withAnimation(.easeInOut(duration: 0.2)) { недавние.очиститьПросмотры() }
                    }, выбрать: выборНедавнего)
                }
                /* Этап 18: «Уточнить» живёт в полосе разделов — и без снимка разделов полоса есть, с одной этой кнопкой. */
                if !разделы.isEmpty || Config.уточнениеЛенты { полосаРазделов }
                if показатьСохранитьПоиск { полосаСохранитьПоиск }
                содержимое
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await модель.обновить() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    KlikoLogoIcon(size: 22)
                    KlikoWordmark(height: 15)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kliko")
            }
            /* Этап 12: колокольчик — сохранить поиск, пока в ленте поиск или раздел. Заполненный — уже сохранён,
               нажатие убирает. Основной вход — полоса над выдачей (полосаСохранитьПоиск): эту панель iPhone прячет,
               пока открыт поиск. */
            if показатьСохранитьПоиск {
                ToolbarItem(placement: .topBarTrailing) {
                    кнопкаСохранитьПоиск
                }
            }
            /* С нижними вкладками (этап 4) избранное, сообщения и кабинет — там; в шапке их второй раз не показываем. */
            if Config.избранное && !Config.нижниеВкладки {
                ToolbarItem(placement: .topBarTrailing) {
                    ссылкаШапки(ИзбранноеЦель.список, значок: "heart", подпись: FavoritesText.т("title"))
                }
            }
            if Config.нативныйЧат && !Config.нижниеВкладки {
                ToolbarItem(placement: .topBarTrailing) {
                    ссылкаШапки(ЧатЦель.список, значок: "bubble.left.and.bubble.right", подпись: ChatText.т("title"))
                }
            }
            if !Config.нижниеВкладки {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let u = Config.url("/cabinet.php") { открыть(u) }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(FeedText.т("cabinet"))
                }
            }
        }
        .searchable(text: $модель.поиск, isPresented: поискПоказан,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: FeedText.т("search"))
        .searchSuggestions { подсказкиПоиска }
        .onSubmit(of: .search) {
            модель.искать()
            if Config.недавние { недавние.запомнитьЗапрос(модель.поиск) }
        }
        .onChange(of: модель.поиск) { _, текст in
            if текст.isEmpty { модель.поискОчищен() }
        }
    }

    // MARK: - Вид как на сайте (этап 25)

    /**
     Этап 25: зелёная шапка сайта вместо системной панели и .searchable. Шапка — вставкой над прокруткой
     (safeAreaInset): лента уходит под её скруглённый низ, как под фиксированную шапку сайта, а «потяни — обновится»
     появляется под ней. Системная панель спрятана только у корня: карточка и чат поверх ленты — со своей.
     */
    private var лентаСайта: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.верхЛенты)
                    if показатьИсторию { историяПоиска }
                    /* Этап 26: на главной — плитки разделов и ряды «Рекомендуем», под ними та же бесконечная лента.
                       Поиск или раздел — полоса разделов и сетка, как раньше. */
                    if наГлавной {
                        главнаяСайта
                    } else {
                        if показатьНедавние { полосаНедавнихСайта }
                        if !разделы.isEmpty || Config.уточнениеЛенты { полосаРазделов }
                    }
                    if показатьСохранитьПоиск { полосаСохранитьПоиск }
                    содержимое
                }
                .padding(.bottom, 24)
            }
            /* Сменили раздел, поиск или вернулись на главную — к началу: иначе новая выдача открывалась бы с середины. */
            .onChange(of: модель.действующее) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) { прокрутка.scrollTo(Self.верхЛенты, anchor: .top) }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.фонСтраницы)
        .refreshable {
            await модель.обновить()
            if наГлавной { await подборки.загрузить() }
        }
        .task { await подборки.начать() }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { шапкаСайта }
        .onChange(of: модель.поиск) { _, текст in
            if текст.isEmpty { модель.поискОчищен() }
        }
        /* Этап 10: «Поиск» с иконки — фокус в поле. Фокус ушёл — поиск закрыт, как «Отменить» у .searchable: следующее
           быстрое действие снова сменит значение и снова даст фокус. */
        .onChange(of: поискПоказан.wrappedValue) { _, показан in
            if показан && !полеВФокусе { полеВФокусе = true }
        }
        .onChange(of: полеВФокусе) { _, вФокусе in
            if поискПоказан.wrappedValue != вФокусе { поискПоказан.wrappedValue = вФокусе }
        }
        .onAppear {
            if поискПоказан.wrappedValue { полеВФокусе = true }
        }
        /* Город в шапке — как на странице сайта: спрашиваем её, когда она догрузилась и когда лента снова на экране
           (человек мог выбрать город на сайте). */
        .onReceive(WebBridge.shared.$progress.removeDuplicates()) { доля in
            if доля >= 1 { Task { await обновитьГород() } }
        }
        .onReceive(WebBridge.shared.$лентаВидна.removeDuplicates()) { видна in
            if видна { Task { await обновитьГород() } }
        }
    }

    private var шапкаСайта: some View {
        ШапкаСайта(текст: $модель.поиск, фокус: $полеВФокусе, город: вид.город ?? DesignText.т("all_kz"),
                   открытьГород: { if let u = Config.лентаСайта { открыть(u) } },
                   поискПоФото: { if let u = Config.лентаСайта { открыть(u) } },
                   найти: { отправитьПоиск() },
                   справа: { кнопкиШапкиСайта },
                   уПоиска: { кнопкиУПоискаСайта })
    }

    /// Первый ряд шапки справа: тема, как переключатель .mk-theme-sw сайта (луна в светлой, солнце в тёмной). Выбор —
    /// тот же, что в кабинете (этап 15): на всё приложение и страницы сайта.
    @ViewBuilder
    private var кнопкиШапкиСайта: some View {
        if Config.выборТемы {
            Button {
                ВыборТемы.shared.тема = схема == .dark ? .светлая : .тёмная
            } label: {
                КругШапкиСайта(значок: схема == .dark ? "sun.max" : "moon")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DesignText.т("theme"))
        }
    }

    /// Рядом с полем — где у сайта «Карта»: колокольчик сохранённого поиска (этап 12), а без нижних вкладок — избранное,
    /// сообщения и кабинет, которые раньше жили в системной панели.
    @ViewBuilder
    private var кнопкиУПоискаСайта: some View {
        if показатьСохранитьПоиск { колокольчикСайта }
        if Config.избранное && !Config.нижниеВкладки {
            ссылкаВШапкеСайта(ИзбранноеЦель.список, значок: "heart", подпись: FavoritesText.т("title"))
        }
        if Config.нативныйЧат && !Config.нижниеВкладки {
            ссылкаВШапкеСайта(ЧатЦель.список, значок: "bubble.left.and.bubble.right", подпись: ChatText.т("title"))
        }
        if !Config.нижниеВкладки {
            Button {
                if let u = Config.url("/cabinet.php") { открыть(u) }
            } label: {
                КругШапкиСайта(значок: "person")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FeedText.т("cabinet"))
        }
    }

    private var колокольчикСайта: some View {
        let искомое = модель.действующее
        let сохранён = сохранённые.есть(искомое)
        return Button { переключитьСохранённый(искомое) } label: {
            КругШапкиСайта(значок: сохранён ? "bell.fill" : "bell")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SavedSearchText.т(сохранён ? "unsave" : "save"))
    }

    /// Как ссылкаШапки, только кружком шапки сайта: в стеке — ссылка, в две колонки — в стек правой колонки.
    @ViewBuilder
    private func ссылкаВШапкеСайта<Цель: Hashable>(_ цель: Цель, значок: String, подпись: String) -> some View {
        if двеКолонки {
            Button { путьСтека.wrappedValue.append(цель) } label: {
                КругШапкиСайта(значок: значок)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(подпись)
        } else {
            NavigationLink(value: цель) {
                КругШапкиСайта(значок: значок)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(подпись)
        }
    }

    /// «Найти» на клавиатуре — то же, что onSubmit(of: .search) прежнего вида.
    private func отправитьПоиск() {
        модель.искать()
        if Config.недавние { недавние.запомнитьЗапрос(модель.поиск) }
    }

    /// История поиска (этап 6) под пустым полем в фокусе — вместо .searchSuggestions.
    private var показатьИсторию: Bool {
        Config.недавние && полеВФокусе && модель.поиск.isEmpty && !недавние.запросы.isEmpty
    }

    private var историяПоиска: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(недавние.запросы, id: \.self) { запрос in
                Button { искатьСнова(запрос) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.текстВторой)
                        Text(запрос)
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(RecentText.т("query_hint"))
                Divider().padding(.leading, 46)
            }
            Button(role: .destructive) { недавние.очиститьЗапросы() } label: {
                Label(RecentText.т("clear_history"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .теньКарточкиСайта()
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// Спросить подпись города у страницы. Сменилась — лента уже не про тот город: заново с первой страницы.
    private func обновитьГород() async {
        guard let подпись = await SiteSession.город() else { return }
        let было = вид.город
        guard было != подпись else { return }
        вид.город = подпись
        if было != nil {
            await модель.обновить()
            await подборки.загрузить()
        }
    }

    // MARK: - Главная как на сайте (этап 26)

    private static let верхЛенты = "верх-ленты"

    /// Главная — ни поиска, ни раздела в запросе ленты (набранное, но не отправленное, главную не прячет).
    private var наГлавной: Bool { модель.действующее.пустое }

    /// Плитки разделов, «Вы смотрели», «Рекомендуем» с рядами по разделам и заголовок бесконечной ленты под ними.
    @ViewBuilder
    private var главнаяСайта: some View {
        ПлиткиГлавной(название: { раздел in названиеРаздела(раздел) }, счёт: подборки.счёт,
                      выбрать: { раздел in модель.выбратьРаздел(раздел.ключ) }, открыть: открыть)
            .padding(.top, 6)
        if показатьНедавние { полосаНедавнихСайта }
        if !подборки.ряды.isEmpty {
            заголовокСайта(DesignText.т("reco"), крупный: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            ForEach(Array(подборки.ряды.enumerated()), id: \.element.id) { номер, ряд in
                РядГлавной(раздел: ряд.раздел, название: названиеРаздела(ряд.раздел), товары: ряд.товары,
                           всего: ряд.всего, чётный: номер % 2 == 1,
                           всё: { модель.выбратьРаздел(ряд.раздел.ключ) }) { товар in
                    карточкаСоСсылкой(товар)
                }
            }
        } else if подборки.неудача {
            неудачаПодборок
        }
        HStack(alignment: .center, spacing: 8) {
            заголовокСайта(DesignText.т("feed"), крупный: false)
            Spacer(minLength: 0)
            /* Этап 18: «Уточнить» на главной — у заголовка ленты: полосы разделов здесь нет, её место заняли плитки. */
            if Config.уточнениеЛенты {
                ЧипУточнения(уточнено: модель.уточнено) { уточнятьПоказан = true }
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var полосаНедавнихСайта: some View {
        ПолосаНедавних(товары: недавние.товары, открыть: открыть, очистить: {
            withAnimation(.easeInOut(duration: 0.2)) { недавние.очиститьПросмотры() }
        }, выбрать: выборНедавнего)
    }

    /// .mh-h2 — 21px, насыщенность 800; заголовок ленты под рядами — мельче.
    private func заголовокСайта(_ текст: String, крупный: Bool) -> some View {
        Text(текст)
            .font(крупный ? Font.system(.title2, weight: .heavy) : Font.system(.headline, weight: .heavy))
            .foregroundStyle(Theme.текст)
            .accessibilityAddTraits(.isHeader)
    }

    /// Название раздела — со снимка главной на языке сайта (FeedSnapshot), нет снимка — своё (DesignText).
    private func названиеРаздела(_ раздел: РазделГлавной) -> String {
        if let строка = разделы.first(where: { $0.k == раздел.ключ }), let t = строка.t, !t.isEmpty { return t }
        return DesignText.т("v_" + раздел.ключ)
    }

    /// Карточка ряда — туда же, куда карточка сетки: в две колонки справа, иначе нативная карточка или страница сайта.
    @ViewBuilder
    private func карточкаСоСсылкой(_ товар: Listing) -> some View {
        Group {
            if двеКолонки {
                Button { выбрать(товар) } label: { ListingCard(товар: товар) }
                    .выбраннаяКарточка(выбор.wrappedValue?.id == товар.id)
            } else if Config.нативнаяКарточка {
                NavigationLink(value: товар) { ListingCard(товар: товар) }
            } else {
                Button { if let u = товар.адрес { открыть(u) } } label: { ListingCard(товар: товар) }
            }
        }
        .buttonStyle(.plain)
        .сердечкоИзбранного(товар)
    }

    /// .mh-fail: подборки не пришли — строка с «Повторить»; лента под ней работает сама по себе.
    private var неудачаПодборок: some View {
        HStack(spacing: 10) {
            Text(DesignText.т("fail"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Button {
                Task { await подборки.загрузить() }
            } label: {
                Text(DesignText.т("retry"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .теньКарточкиСайта()
        .padding(.horizontal, 16)
    }

    /// Корень ленты в стеке на экране — зелёная шапка под часами (ВидСайта.кореньЛенты).
    private func отметитьКорень() {
        let корень = Config.дизайнКакНаСайте && !двеКолонки && путьСтека.wrappedValue.isEmpty
        if вид.кореньЛенты != корень { вид.кореньЛенты = корень }
    }

    // MARK: - Лента и карточка рядом (этап 14)

    /// Лента в две колонки — сейчас, в этом окне.
    private var двеКолонки: Bool { ДвеКолонки.включены(ширинаОкна) }

    /// Стек ленты или, в две колонки, стек правой колонки. Снаружи — у вкладок (этап 8), иначе свой.
    private var путьСтека: Binding<NavigationPath> { внешнийПуть ?? $свойПуть }

    /// Поле поиска активно. Снаружи его включает «Поиск» с иконки (этап 10), иначе своё.
    private var поискПоказан: Binding<Bool> { внешнийПоиск ?? $свойПоиск }

    /// Объявление в правой колонке: у вкладок — их, без вкладок — своё.
    private var выбор: Binding<Listing?> { внешнееВыбранное ?? $своёВыбранное }

    /// «Вы смотрели» в две колонки тоже выбирает в правую колонку; в стеке — nil: ссылки в стек, как раньше.
    private var выборНедавнего: ((Listing) -> Void)? {
        guard двеКолонки else { return nil }
        return { товар in выбрать(товар) }
    }

    /// Объявление — в правую колонку. Стек колонки — к началу: и другое объявление, и то же самое, закрытое сверху
    /// похожими или чатом, видно сразу, без «Назад».
    private func выбрать(_ товар: Listing) {
        путьСтека.wrappedValue = NavigationPath()
        выбор.wrappedValue = товар
        выбранноеВПути = false
    }

    /// Окно сузили — выбранное из правой колонки ложится в стек поверх ленты, как это делает и сама NavigationSplitView,
    /// когда сворачивается: человек остаётся в той же карточке. Выбранным оно при этом остаётся (исправление после ревью,
    /// владелец 25.09.2026): окно расширят — и выбранноеВКолонку вернёт его корнем колонки, с рамкой в ленте. Если над
    /// ним в колонке уже были похожие или чат, они и так в пути стека и остаются на экране; само выбранное под них не
    /// подложить — путь стека непрозрачен, — но в расширенном окне колонка снова покажет его под ними.
    private func выбранноеВСтек() {
        guard Config.айпадДвеКолонки, let товар = выбор.wrappedValue, путьСтека.wrappedValue.isEmpty else { return }
        путьСтека.wrappedValue.append(товар)
        выбранноеВПути = true
    }

    /// Окно снова расширили — выбранное, которое узкий режим положил в стек, снимаем: корень правой колонки и так оно
    /// (колонкаКарточки), и «Назад» не должен вести к подсказке. Поверх него в узком окне открыли ещё что-то — его из-под
    /// них не достать, путь непрозрачен: колонка покажет их над выбранным, а «Назад» один лишний раз — то же объявление.
    private func выбранноеВКолонку() {
        guard выбранноеВПути else { return }
        выбранноеВПути = false
        if путьСтека.wrappedValue.count == 1 { путьСтека.wrappedValue.removeLast() }
    }

    /// Колонку ленты спрятали кнопкой, а в неё пришёл поиск — показать, иначе поле и выдача остались бы за кадром.
    private func показатьЛенту() {
        guard двеКолонки, видимостьКолонок != .all else { return }
        видимостьКолонок = .all
    }

    /// Кнопка шапки, когда нижних вкладок нет (избранное, сообщения). В стеке — ссылка, как раньше; в две колонки у
    /// колонки ленты своего стека нет, и экран ложится в стек правой колонки.
    @ViewBuilder
    private func ссылкаШапки<Цель: Hashable>(_ цель: Цель, значок: String, подпись: String) -> some View {
        if двеКолонки {
            Button { путьСтека.wrappedValue.append(цель) } label: {
                Image(systemName: значок)
            }
            .accessibilityLabel(подпись)
        } else {
            NavigationLink(value: цель) {
                Image(systemName: значок)
            }
            .accessibilityLabel(подпись)
        }
    }

    // MARK: - Сохранённые поиски (этап 12)

    /// В ленте поиск или раздел — его можно сохранить.
    private var показатьСохранитьПоиск: Bool {
        Config.сохранённыеПоиски && !модель.действующее.пустое
    }

    /// «Сохранить поиск» строкой над выдачей (исправление после ревью, владелец 25.09.2026). 🔴 Колокольчик в шапке на
    /// iPhone для поиска по тексту недостижим: пока поиск открыт (а после «Найти» он открыт, с текстом), система прячет
    /// панель навигации вместе с ним, а «Отменить» очищает поле — и лента уже не по этому поиску. Полоса — в самой
    /// выдаче, её видно всегда. Действие то же (переключитьСохранённый); шапка остаётся вторым входом.
    private var полосаСохранитьПоиск: some View {
        let искомое = модель.действующее
        let сохранён = сохранённые.есть(искомое)
        return Button { переключитьСохранённый(искомое) } label: {
            Label(SavedSearchText.т(сохранён ? "saved" : "save"), systemImage: сохранён ? "bell.fill" : "bell")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(сохранён ? Color.white : Theme.green2)
                .background(сохранён ? Theme.green : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityHint(сохранён ? SavedSearchText.т("unsave") : "")
    }

    private var кнопкаСохранитьПоиск: some View {
        let искомое = модель.действующее
        let сохранён = сохранённые.есть(искомое)
        return Button { переключитьСохранённый(искомое) } label: {
            Image(systemName: сохранён ? "bell.fill" : "bell")
        }
        .accessibilityLabel(SavedSearchText.т(сохранён ? "unsave" : "save"))
    }

    /// Колокольчик: сохранить поиск или убрать. Точка отсчёта — выдача на экране, если она уже пришла именно по этому
    /// поиску: её человек видел, уведомлять о ней не надо. Первое сохранение спрашивает разрешение на уведомления.
    private func переключитьСохранённый(_ искомое: ИскомоеЛенты) {
        if сохранённые.есть(искомое) {
            сохранённые.убрать(искомое)
            return
        }
        let названиеРаздела = разделы.first(where: { $0.k == искомое.раздел })?.название
        let видели: [String]? = модель.выдачаГотова ? модель.items.map(\.id) : nil
        guard сохранённые.добавить(искомое, названиеРаздела: названиеРаздела, видели: видели) else {
            поисковПолно = true
            return
        }
        Task { await ПроверкаПоисков.попроситьРазрешение() }
    }

    /// Сохранённый поиск снаружи — в поле и раздел, и забыть: тот же вход второй раз ленту не сбросит.
    private func применитьСнаружи() {
        guard let внешнее = внешнееИскомое, let искомое = внешнее.wrappedValue else { return }
        внешнее.wrappedValue = nil
        модель.применить(искомое)
        показатьЛенту()                     // этап 14: колонку ленты могли спрятать — выдача там
    }

    // MARK: - Недавнее (этап 6)

    /// «Вы смотрели» — только в обычной ленте: пока в поле что-то набрано, место — под выдачу.
    private var показатьНедавние: Bool {
        Config.недавние && модель.поиск.isEmpty && !недавние.товары.isEmpty
    }

    /// История поиска под пустым полем. Нажали запрос — ищем сразу, как по кнопке «Найти»: подсказки только при
    /// пустом поле, поэтому после нажатия они сами уходят и видна выдача.
    @ViewBuilder
    private var подсказкиПоиска: some View {
        if Config.недавние && модель.поиск.isEmpty && !недавние.запросы.isEmpty {
            ForEach(недавние.запросы, id: \.self) { запрос in
                Button { искатьСнова(запрос) } label: {
                    Label {
                        Text(запрос).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint(RecentText.т("query_hint"))
            }
            Button(role: .destructive, action: { недавние.очиститьЗапросы() }) {
                Label(RecentText.т("clear_history"), systemImage: "trash")
            }
        }
    }

    private func искатьСнова(_ запрос: String) {
        модель.поиск = запрос
        модель.искать()
        недавние.запомнитьЗапрос(запрос)
        КлавиатураПоиска.спрятать()
    }

    // MARK: - Разделы

    private var полосаРазделов: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if Config.уточнениеЛенты {
                    ЧипУточнения(уточнено: модель.уточнено) { уточнятьПоказан = true }
                }
                if !разделы.isEmpty {
                    чип(ключ: "", название: FeedText.т("all"), краска: nil)
                    ForEach(разделы) { р in
                        чип(ключ: р.k, название: р.название, краска: р.c)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func чип(ключ: String, название: String, краска: String?) -> some View {
        let выбран = модель.раздел == ключ
        return Button { модель.выбратьРаздел(ключ) } label: {
            HStack(spacing: 6) {
                if краска != nil {
                    Circle().fill(FeedPreview.краска(краска)).frame(width: 7, height: 7)
                }
                Text(название)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(выбран ? Color.white : Color.primary)
            .background(выбран ? Theme.green : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    // MARK: - Лента и состояния

    @ViewBuilder
    private var содержимое: some View {
        if модель.items.isEmpty {
            /* Скелет — только пока ответа ещё не было или запрос в пути. Пустой ответ — это «ничего не нашлось», а не
               вечная загрузка (иначе и мерцание, и VoiceOver «загружаем» по уже законченному поиску). */
            if модель.грузим || (!модель.ответПришёл && модель.ошибка == nil && !модель.сДиска) {
                /* Этап 11: серые карточки той же сетки вместо колеса. Рубильник выключен — колесо, как раньше. */
                if Config.скелетЛенты {
                    СкелетЛенты(колонки: ListingCard.сетка(размерТекста))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            } else if let ошибка = модель.ошибка {
                заглушкаОшибки(ошибка)
            } else {
                заглушка(значок: "magnifyingglass", заголовок: FeedText.т("empty"), подпись: FeedText.т("empty_sub"))
            }
        } else {
            if модель.сДиска && модель.ошибка != nil {
                Label(FeedText.т("stale"), systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            /* Этап 18: лента уточнена — сколько подходит из загруженного; нажатие — лист, крестик — сброс. */
            if модель.уточнено {
                ПолосаУточнения(видно: модель.видимые.count, загружено: модель.items.count,
                                открыть: { уточнятьПоказан = true },
                                сбросить: { модель.уточнение = УточнениеЛенты() })
                if модель.видимые.isEmpty {
                    заглушка(значок: "line.3.horizontal.decrease.circle", заголовок: RefineText.т("none"),
                             подпись: RefineText.т("none_sub"))
                }
            }
            LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: 12) {
                ForEach(модель.видимые) { товар in
                    /* Этап 2: карточка нативная. Рубильник выключен — как на этапе 1, страница сайта. Этап 14: в две
                       колонки карточка не уводит с ленты, а открывается справа, и выбранная обведена. */
                    Group {
                        if двеКолонки {
                            Button { выбрать(товар) } label: { ListingCard(товар: товар) }
                                .выбраннаяКарточка(выбор.wrappedValue?.id == товар.id)
                        } else if Config.нативнаяКарточка {
                            NavigationLink(value: товар) { ListingCard(товар: товар) }
                        } else {
                            Button { if let u = товар.адрес { открыть(u) } } label: { ListingCard(товар: товар) }
                        }
                    }
                    .buttonStyle(.plain)
                    .сердечкоИзбранного(товар)          // этап 5: сердечко — слоем над карточкой, не внутри ссылки
                    .onAppear { модель.дальше(после: товар) }
                }
            }
            .padding(.horizontal, 12)
            if модель.уточнено { низУточнённой }
            низЛенты
        }
    }

    /**
     Низ выдачи под уточнением (этап 18). Подходящих мало — последняя видимая карточка уже на экране и второй раз
     onAppear не получит, а подгруженная страница могла не добавить ни одной подходящей. Отметка внизу просит следующую
     страницу, когда видна и когда число загруженного сменилось (task(id:) перезапускается), — до предела пустых
     подгрузок подряд; дальше решает человек кнопкой «Искать дальше».
     */
    @ViewBuilder
    private var низУточнённой: some View {
        Color.clear
            .frame(height: 1)
            .task(id: "\(модель.items.count)/\(модель.грузим)") { модель.дальшеУточнённой() }
        if модель.пустыхПодряд >= FeedModel.пустыхПодрядПредел && модель.можноЕщё && !модель.грузим
            && модель.ошибка == nil {
            VStack(spacing: 6) {
                Text(RefineText.т("more_sub"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(RefineText.т("more")) { модель.искатьДальше() }
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var низЛенты: some View {
        if модель.грузим {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if модель.ошибка != nil {
            Button(FeedText.т("retry")) { модель.повторить() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private func заглушкаОшибки(_ ошибка: ListingsAPI.Ошибка) -> some View {
        /* Сеть — «нет соединения». Всё прочее (сервер ответил не тем, разбор не сошёлся) — лента API сломана, и тогда
           у человека должен быть выход: лента сайта, которая работает независимо от этого API. */
        let нетСети: Bool
        if case .сеть = ошибка { нетСети = true } else { нетСети = false }
        return VStack(spacing: 14) {
            Image(systemName: нетСети ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(FeedText.т(нетСети ? "offline" : "failed"))
                .font(.title3.weight(.semibold))
            Text(FeedText.т(нетСети ? "offline_sub" : "failed_sub"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { модель.повторить() } label: {
                Text(FeedText.т("retry"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Theme.green, in: Capsule())
            }
            if !нетСети {
                Button(FeedText.т("site"), action: открытьСайт)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func заглушка(значок: String, заголовок: String, подпись: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: значок)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(заголовок).font(.title3.weight(.semibold))
            Text(подпись)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// Карточка объявления в сетке ленты.
///
/// Этап 11: шрифты — стилями текста, а не точками: при обычном размере те же 16/13/12 pt, а с «Размером текста» в
/// Настройках растут, но не дальше третьего крупного для доступности. Цена в одну строку ужимается до 0,6, а не
/// обрезается многоточием; название при крупном тексте — до трёх строк, и сетка тогда в одну колонку (сетка(_:)).
/// VoiceOver читает карточку одной фразой (Listing.голос), фото — украшение.
struct ListingCard: View {
    let товар: Listing
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(товар: Listing) {
        self.товар = товар
    }

    /// Колонки сетки карточек. Обычно — по ширине экрана, от 158 pt. При крупном тексте для доступности — от 300 pt: на
    /// iPhone это одна карточка во всю ширину, иначе цене и названию в узкой карточке не хватит места.
    static func сетка(_ размер: DynamicTypeSize) -> [GridItem] {
        if размер.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 12, alignment: .top)]
    }

    var body: some View {
        /* Этап 26: вид карточки сайта (.mh-c / .vx-c). Выключен — прежняя карточка этапов 1–23. */
        if Config.дизайнКакНаСайте {
            карточкаСайта
        } else {
            карточкаПрежняя
        }
    }

    private var карточкаПрежняя: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color(.tertiarySystemGroupedBackground)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        /* Проверка на телефоне, сборка 33: КартинкаЛенты вместо AsyncImage — см. FeedImages.swift. */
                        КартинкаЛенты(товар.обложка, пунктов: крупныйТекст ? 520 : 260) {
                            Image(systemName: "photo")
                                .font(.system(size: 22))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .clipped()

                HStack(spacing: 6) {
                    if товар.isTop { метка(FeedText.т("top"), Theme.green2) }
                    if товар.isNew { метка(FeedText.т("new"), Theme.green) }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.цена(товар))
                    .font(.system(.callout, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                /* Две строки места под название и при коротком — чтобы карточки в ряду были одной высоты; 34 pt — эти
                   две строки при обычном размере текста. В одну колонку (крупный текст) ровнять не с кем. */
                Text(товар.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(крупныйТекст ? 3 : 2, reservesSpace: !крупныйТекст)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                if !товар.city.isEmpty {
                    Text(товар.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 11)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)
    }

    private var крупныйТекст: Bool { размерТекста.isAccessibilitySize }

    /**
     Карточка сайта: фото 1:1 на подложке, золотая метка «★ ТОП» (linear-gradient(135deg, #d9b24c, #b88a1e), радиус 8,
     высота 24, 10 pt заглавными), цена 16 pt жирнее всего, название 14–15 pt полужирным в две строки, город мелко и
     приглушённо. Карточка скруглена на 14, на белой поверхности с мягкой тенью (в тёмной — рамка линии); в ТОПе —
     золотая рамка 1,5 pt и золотистый верх подложки. Шрифты — стилями текста, как на этапе 11: растут с «Размером
     текста» до accessibility3.
     */
    private var карточкаСайта: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.поверхность2
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    /* Владелец 25.09.2026, проверка на телефоне, сборка 33 («лента подвисает»): не AsyncImage, а
                       КартинкаЛенты — уменьшенная до ячейки, распакованная не на главной очереди и из памяти. */
                    КартинкаЛенты(товар.обложка, пунктов: крупныйТекст ? 520 : 260) {
                        Image(systemName: "photo")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.текстВторой.opacity(0.5))
                    }
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        if товар.isTop { меткаТоп }
                        if товар.isNew { меткаСайта(FeedText.т("new")) }
                    }
                    .padding(8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.цена(товар))
                    .font(.system(.callout, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(товар.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(крупныйТекст ? 3 : 2, reservesSpace: !крупныйТекст)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if !товар.city.isEmpty {
                    Text(товар.city)
                        .font(.caption2)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(фонКарточкиСайта)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            if товар.isTop {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.топРамка, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .теньКарточкиСайта()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)
    }

    /// Подложка: в ТОПе — золотистый верх (.mh-c.is-top), иначе поверхность.
    @ViewBuilder
    private var фонКарточкиСайта: some View {
        if товар.isTop {
            LinearGradient(stops: [Gradient.Stop(color: Theme.топФон, location: 0),
                                   Gradient.Stop(color: Theme.поверхность, location: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        } else {
            Theme.поверхность
        }
    }

    /// «★ ТОП» — .mh-top сайта.
    private var меткаТоп: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(FeedText.т("top").uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .frame(height: 24)
        /* Проверка на телефоне, сборка 33 («лента подвисает»): тень метки — заливкой подложки (ShapeStyle.shadow), а не
           .shadow на метке: та считалась вне экрана каждый кадр прокрутки, внутри и без того затенённой карточки. */
        .background(LinearGradient(colors: [Theme.топНачало, Theme.топКонец], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .shadow(.drop(color: Color(red: 176 / 255, green: 132 / 255, blue: 24 / 255).opacity(0.5),
                                      radius: 4, x: 0, y: 3)),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
    }

    /// «Новое» — той же формы, что «★ ТОП», в зелёном бренда.
    private func меткаСайта(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
    }

    private func метка(_ текст: String, _ фон: Color) -> some View {
        Text(текст)
            .font(.system(.caption2, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(фон, in: Capsule())
    }

    /// «14 900 000 ₸», аренда «5 000 ₸/сут», без цены — «Договорная» или «Цена по запросу».
    static func цена(_ т: Listing) -> String {
        if т.forRent, let день = т.rentPriceDay, день > 0 {
            return тенге(день) + FeedText.т("perday")
        }
        guard let p = т.price, p > 0 else {
            return FeedText.т(т.negotiable ? "neg" : "noprice")
        }
        return тенге(p)
    }

    /// «14 900 000 ₸».
    static func тенге(_ n: Double) -> String {
        (формат.string(from: NSNumber(value: n)) ?? String(Int(n))) + "\u{00A0}₸"
    }

    private static let формат: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"      // неразрывный пробел: цена не переносится посреди числа
        ф.maximumFractionDigits = 0
        return ф
    }()
}
