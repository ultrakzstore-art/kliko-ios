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

    @State private var разделы: [FeedSnapshot.Row] = FeedStore.прочитать()?.rows.filter { !$0.k.isEmpty } ?? []

    private let колонки = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 12, alignment: .top)]

    init(открыть: @escaping (URL) -> Void, открытьСайт: @escaping () -> Void, путь: Binding<NavigationPath>? = nil) {
        self.открыть = открыть
        self.открытьСайт = открытьСайт
        внешнийПуть = путь
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
            .searchable(text: $модель.поиск, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: FeedText.т("search"))
            .searchSuggestions { подсказкиПоиска }
            .onSubmit(of: .search) {
                модель.искать()
                if Config.недавние { недавние.запомнитьЗапрос(модель.поиск) }
            }
            .onChange(of: модель.поиск) { _, текст in
                if текст.isEmpty { модель.поискОчищен() }
            }
        }
        .task { await модель.начать() }
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
            if модель.грузим || (модель.ошибка == nil && !модель.сДиска) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
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
            LazyVGrid(columns: колонки, spacing: 12) {
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
struct ListingCard: View {
    let товар: Listing

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
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(товар.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                if !товар.city.isEmpty {
                    Text(товар.city)
                        .font(.system(size: 12))
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
        .accessibilityElement(children: .combine)
    }

    private func метка(_ текст: String, _ фон: Color) -> some View {
        Text(текст)
            .font(.system(size: 10, weight: .heavy))
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
