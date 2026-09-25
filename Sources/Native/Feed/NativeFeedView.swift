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
 */
struct NativeFeedView: View {
    @StateObject private var модель = FeedModel()
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

    @State private var разделы: [FeedSnapshot.Row] = FeedStore.прочитать()?.rows.filter { !$0.k.isEmpty } ?? []

    /// Размер текста в Настройках: при крупном для доступности — сетка в одну колонку (этап 11, ListingCard.сетка).
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(открыть: @escaping (URL) -> Void, открытьСайт: @escaping () -> Void, путь: Binding<NavigationPath>? = nil,
         поиск: Binding<Bool>? = nil, найти: Binding<ИскомоеЛенты?>? = nil) {
        self.открыть = открыть
        self.открытьСайт = открытьСайт
        внешнийПуть = путь
        внешнийПоиск = поиск
        внешнееИскомое = найти
    }

    var body: some View {
        NavigationStack(path: внешнийПуть ?? $свойПуть) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if показатьНедавние {
                        ПолосаНедавних(товары: недавние.товары, открыть: открыть, очистить: {
                            withAnimation(.easeInOut(duration: 0.2)) { недавние.очиститьПросмотры() }
                        })
                    }
                    if !разделы.isEmpty { полосаРазделов }
                    содержимое
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await модель.обновить() }
            .navigationDestination(for: Listing.self) { товар in
                ListingDetailView(товар: товар, открыть: открыть)
            }
            .чатМаршруты(открыть: открыть)
            .избранноеМаршруты(открыть: открыть)
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
                   нажатие убирает. */
                if Config.сохранённыеПоиски && !модель.действующее.пустое {
                    ToolbarItem(placement: .topBarTrailing) {
                        кнопкаСохранитьПоиск
                    }
                }
                /* С нижними вкладками (этап 4) избранное, сообщения и кабинет — там; в шапке их второй раз не показываем. */
                if Config.избранное && !Config.нижниеВкладки {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: ИзбранноеЦель.список) {
                            Image(systemName: "heart")
                        }
                        .accessibilityLabel(FavoritesText.т("title"))
                    }
                }
                if Config.нативныйЧат && !Config.нижниеВкладки {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: ЧатЦель.список) {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel(ChatText.т("title"))
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
            .searchable(text: $модель.поиск, isPresented: внешнийПоиск ?? $свойПоиск,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: FeedText.т("search"))
            .searchSuggestions { подсказкиПоиска }
            .onSubmit(of: .search) {
                модель.искать()
                if Config.недавние { недавние.запомнитьЗапрос(модель.поиск) }
            }
            .onChange(of: модель.поиск) { _, текст in
                if текст.isEmpty { модель.поискОчищен() }
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
        }
        .task { await модель.начать() }
    }

    // MARK: - Сохранённые поиски (этап 12)

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
                чип(ключ: "", название: FeedText.т("all"), краска: nil)
                ForEach(разделы) { р in
                    чип(ключ: р.k, название: р.название, краска: р.c)
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
            LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: 12) {
                ForEach(модель.items) { товар in
                    /* Этап 2: карточка нативная. Рубильник выключен — как на этапе 1, страница сайта. */
                    Group {
                        if Config.нативнаяКарточка {
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
            низЛенты
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
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color(.tertiarySystemGroupedBackground)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: товар.обложка) { фаза in
                            if case .success(let картинка) = фаза {
                                картинка.resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.tertiary)
                            }
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
