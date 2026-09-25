import SwiftUI

/**
 КАРТОЧКА ОБЪЯВЛЕНИЯ — ЭТАП 2 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующий этап, карточку объявления»).

 Открывается из ленты сразу, с тем, что уже известно по строке ленты (обложка, цена, название, город), и тут же
 дотягивает полную карточку: GET /api/listings.php?id= (фото, описание, характеристики, продавец). Не дотянулась —
 карточка остаётся на экране с тем, что есть, а не превращается в экран ошибки.

 🔴 ДЕЙСТВИЯ — ПОКА НА САЙТЕ. Чат с продавцом, безопасная сделка, оплата и доставка живут страницей объявления на
 сайте: там гарант, проверка через eGov и платёжный шлюз, и второй их копии в приложении пока нет (этапы 3+).
 Кнопка внизу открывает ту же страницу объявления в веб-обёртке, с сессией человека, — одно нажатие до чата или
 сделки.
 */
struct ListingDetailView: View {
    @State private var товар: Listing
    @State private var догружаем = true
    @State private var неДогрузилась = false
    @State private var фотоНаВесьЭкран: Int?
    @State private var страница = 0
    /// Похожие из того же раздела (этап 7) — своё состояние: основная карточка их не ждёт.
    @State private var похожие: Похожие.Состояние = .нет
    /// Этап 13: на экране копия с телефона, а не ответ сайта, — когда она легла. nil — карточка живая (или строка ленты).
    @State private var сохранённаяКопия: Date?
    /// Масштаб экрана — в нём рисуется картинка для «Поделиться» (этап 19), чтобы в мессенджере она была чёткой.
    @Environment(\.displayScale) private var масштабЭкрана

    /// Открыть страницу сайта в веб-обёртке.
    let открыть: (URL) -> Void

    init(товар: Listing, открыть: @escaping (URL) -> Void) {
        _товар = State(initialValue: товар)
        self.открыть = открыть
    }

    var body: some View {
        ScrollView {
            /* Этап 8: открыли по ссылке, а известен только номер — не пустая карточка, а ожидание или честный отказ. */
            if товар.заготовка {
                экранЗаготовки
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    галерея
                    VStack(alignment: .leading, spacing: 14) {
                        шапка
                        /* Этап 13: без связи — сохранённая копия с телефона; сказать, от когда она. */
                        if let когда = сохранённаяКопия { заметкаКопии(когда) }
                        if неДогрузилась {
                            Label(FeedText.т("detail_partial"), systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !товар.характеристики.isEmpty { характеристики }
                        if let описание = товар.описание { блокОписания(описание) }
                        if товар.продавец != nil { строкаПродавца }
                        if догружаем {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                    /* Этап 7: похожие — вне отступов карточки, чтобы полоса листалась от края до края. */
                    if Config.похожие { ПолосаПохожих(состояние: похожие) }
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            /* Заготовку по ссылке в избранное не кладём: сохранилась бы пустая запись (этап 8). */
            if Config.избранное && !товар.заготовка {
                ToolbarItem(placement: .topBarTrailing) {
                    КнопкаИзбранного(товар: товар, место: .шапка)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let адрес = товар.адрес {
                    /* Этап 19: ссылка и картинка объявления. Заготовке по ссылке (этап 8) рисовать нечего — только
                       ссылка, как и при выключенном рубильнике. */
                    if Config.поделитьсяКартинкой && !товар.заготовка {
                        Button { поделитьсяКартинкой(адрес) } label: { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(FeedText.т("share"))
                            .accessibilityHint(ShareCardText.т("hint"))
                    } else {
                        ShareLink(item: адрес) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(FeedText.т("share"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if !товар.заготовка { нижняяПанель } }
        .task { await догрузить() }
        /* Похожие — своей задачей, параллельно с догрузкой. Раздел у строки из избранного или «Вы смотрели» известен
           только из полной карточки, поэтому задача перезапускается, когда он появился. */
        .task(id: товар.категория) { await загрузитьПохожие() }
        /* Открыли — наверх полосы «Вы смотрели» над лентой (этап 6), в поиск iPhone и в Handoff (этап 10). */
        .onAppear {
            if Config.недавние && !товар.заготовка { RecentStore.shared.запомнить(товар) }
            ПоискТелефона.запомнить(товар)
            Передача.shared.показать(товар)
            /* Этап 16: открытое — в счёт просьбы оценить (заготовка по ссылке — когда дотянется); пока карточка на
               экране, просьба её не перебивает. */
            if !товар.заготовка { ПросьбаОценить.shared.открыли(товар.id) }
            ПросьбаОценить.shared.делоНаЭкране()
        }
        .onDisappear {
            Передача.shared.убрать(товар)
            ПросьбаОценить.shared.делоУшло(карточка: true)   // этап 16: досмотрел и закрыл — момент для просьбы оценить
        }
        /* Дотянулась полная карточка сохранённого — свежая цена и в избранное (этап 5), и в «Вы смотрели» (этап 6).
           Открытое по ссылке (этап 8) ложится в «Вы смотрели», поиск iPhone и Handoff только теперь, когда стало что
           показать. Сохранённая копия (этап 13) — не свежие данные: цену в избранном, «Вы смотрели» и поиске iPhone
           ею не переписываем. */
        .onChange(of: товар) { прежний, свежий in
            let изКопии = сохранённаяКопия != nil
            if Config.избранное && !изКопии { FavoritesStore.shared.освежить(свежий) }
            if !изКопии { ПоискТелефона.запомнить(свежий) }   // этап 10: свежая цена в поиске iPhone; заготовка — впервые
            Передача.shared.показать(свежий)
            if Config.недавние {
                if !прежний.заготовка {
                    if !изКопии { RecentStore.shared.освежить(свежий) }
                } else if !свежий.заготовка {
                    RecentStore.shared.запомнить(свежий)
                }
            }
            if прежний.заготовка && !свежий.заготовка { ПросьбаОценить.shared.открыли(свежий.id) }   // этап 16
        }
        .fullScreenCover(item: Binding(get: { фотоНаВесьЭкран.map(ФотоИндекс.init) },
                                       set: { фотоНаВесьЭкран = $0?.id })) { выбранное in
            ФотоНаВесьЭкран(адреса: товар.фотоАдреса, начало: выбранное.id)
        }
    }

    // MARK: - Открыто по ссылке (этап 8)

    /// Пока карточка грузится — колесо, а не «Цена по запросу» без названия; не дотянулась (сняли с продажи, нет
    /// связи) — сказать это и дать повторить или открыть страницу сайта.
    @ViewBuilder
    private var экранЗаготовки: some View {
        if догружаем {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 160)
                .accessibilityLabel(LinksText.т("opening"))
        } else {
            ContentUnavailableView {
                Label(LinksText.т("failed"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(LinksText.т("failed_sub"))
            } actions: {
                Button(FeedText.т("retry")) { Task { await догрузить() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                if let адрес = товар.адрес {
                    Button(FeedText.т("open_site")) { открыть(адрес) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    // MARK: - Сохранённая копия (этап 13)

    /// Карточка показана копией с телефона: от когда она, что могло измениться, и «Повторить» — снова в сеть.
    private func заметкаКопии(_ когда: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: OfflineText.т("copy"), OfflineText.когда(когда)))
                    .font(.footnote.weight(.semibold))
                Text(OfflineText.т("copy_sub"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if !догружаем {
                Button(FeedText.т("retry")) { Task { await догрузить() } }
                    .font(.footnote.weight(.semibold))
                    .tint(Theme.green)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Галерея

    private var галерея: some View {
        let адреса = товар.фотоАдреса
        return ZStack(alignment: .bottomTrailing) {
            if адреса.isEmpty {
                Color(.tertiarySystemGroupedBackground)
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary))
            } else {
                TabView(selection: $страница) {
                    ForEach(Array(адреса.enumerated()), id: \.offset) { номер, адрес in
                        AsyncImage(url: адрес) { фаза in
                            switch фаза {
                            case .success(let картинка):
                                картинка.resizable().scaledToFill()
                            case .empty:
                                Color(.tertiarySystemGroupedBackground).overlay(ProgressView())
                            default:
                                Color(.tertiarySystemGroupedBackground)
                                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { фотоНаВесьЭкран = номер }
                        .tag(номер)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                if адреса.count > 1 {
                    Text("\(страница + 1) / \(адреса.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(12)
                }
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Текст

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 26, weight: .heavy))
                if let старая = товар.oldPrice, let цена = товар.price, старая > цена {
                    Text(ListingCard.тенге(старая))
                        .font(.system(size: 15))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            }
            Text(товар.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    чип(FeedText.т(товар.isNew ? "new" : "used"), значок: nil)
                    if let дни = товар.гарантияДней {
                        чип(String(format: FeedText.т("warranty"), дни), значок: "checkmark.shield")
                    }
                    if !товар.city.isEmpty { чип(товар.city, значок: "mappin.and.ellipse") }
                }
            }
        }
    }

    private var характеристики: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FeedText.т("specs")).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top),
                                GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 8) {
                ForEach(товар.характеристики, id: \.self) { х in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(х.ключ).font(.caption).foregroundStyle(.secondary)
                        Text(х.значение).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func блокОписания(_ текст: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FeedText.т("description")).font(.headline)
            Text(текст)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var строкаПродавца: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.mint)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.green))
                .overlay {
                    if let адрес = товар.аватарПродавца.flatMap({ Config.url($0) }) {
                        AsyncImage(url: адрес) { картинка in
                            картинка.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                        .clipShape(Circle())
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(товар.продавец ?? FeedText.т("seller"))
                        .font(.subheadline.weight(.semibold))
                    if товар.продавецПроверен {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.green2)
                            .accessibilityLabel(FeedText.т("verified"))
                    }
                }
                if let строка = Self.доверие(товар) {
                    Text(строка)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let п = товар.просмотры, п > 0 {
                    Text(String(format: FeedText.т("views"), п))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// «★ 5,0 · 2 отзыва · 7 сделок» — только то, что пришло. Ничего нет — строки нет.
    private static func доверие(_ т: Listing) -> String? {
        var части: [String] = []
        if let р = т.рейтингПродавца {
            части.append("★ " + String(format: "%.1f", р).replacingOccurrences(of: ".", with: ","))
        }
        if let о = т.отзывыПродавца { части.append(String(format: FeedText.т("reviews"), о)) }
        if let с = т.сделкиПродавца { части.append(String(format: FeedText.т("deals"), с)) }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    private func чип(_ текст: String, значок: String?) -> some View {
        HStack(spacing: 4) {
            if let значок { Image(systemName: значок).font(.caption2) }
            Text(текст).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.mint, in: Capsule())
        .foregroundStyle(Theme.green)
    }

    // MARK: - Действия

    private var нижняяПанель: some View {
        VStack(spacing: 6) {
            /* Этап 3: «Написать» — нативный чат с продавцом, «Купить безопасно» — страница сделки на сайте. Диалог по
               объявлению создаётся запросом open, то есть записью, — поэтому кнопка появляется вместе с отправкой
               (Config.нативныйЧатОтправка). До того — одна кнопка на страницу объявления, как на этапе 2. */
            if Config.нативныйЧат && Config.нативныйЧатОтправка, let продавец = товар.продавецID {
                HStack(spacing: 10) {
                    NavigationLink(value: ЧатЦель.продавец(id: продавец, имя: товар.продавец ?? "", объявление: товар.id)) {
                        Label(ChatText.т("write"), systemImage: "bubble.left.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(Theme.green)
                            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button {
                        if let адрес = товар.адрес { открыть(адрес) }
                    } label: {
                        Label(ChatText.т("buy"), systemImage: "shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Theme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if let адрес = товар.адрес { открыть(адрес) }
                } label: {
                    Label(FeedText.т("contact"), systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Text(FeedText.т("contact_sub"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }

    // MARK: - Поделиться картинкой (этап 19)

    /// Картинка — с тем фото, что открыто в галерее (если оно уже скачано), и ссылка. Не нарисовалась — одна ссылка.
    private func поделитьсяКартинкой(_ адрес: URL) {
        let адреса = товар.фотоАдреса
        let фото = адреса.indices.contains(страница) ? адреса[страница] : адреса.first
        let картинка = ОтправкаКартинкой.картинка(товар, фото: фото, масштаб: масштабЭкрана)
        ОтправкаКартинкой.поделиться(адрес: адрес, картинка: картинка)
    }

    // MARK: - Загрузка

    private func догрузить() async {
        /* Этап 13: копия с телефона полная, но не свежая — повтор (кнопка, возврат на экран) снова идёт в сеть. */
        guard !товар.полная || сохранённаяКопия != nil else { догружаем = false; return }
        догружаем = true
        defer { догружаем = false }
        let взятое = ListingDetailCache.поколение      // до запроса: ответ, опоздавший за выходом, на диск не ляжет
        do {
            let ответ = try await ListingsAPI.объявлениеСОтветом(товар.id)
            var полный = ответ.товар
            /* Номер в ответе обязан совпасть: иначе сайт отдал не то (например, ленту вместо товара). */
            guard полный.id == товар.id else { неДогрузилась = true; return }
            /* Раздел для похожих (этап 7): нет его в ответе на ?id=, а строка ленты знала — не теряем. */
            if полный.категория == nil { полный.категория = товар.категория }
            сохранённаяКопия = nil          // раньше товара: onChange должен знать, что пришло свежее
            товар = полный
            неДогрузилась = false
            /* Этап 13: свежий ответ — копией на телефон, если объявление в избранном или ляжет в «Вы смотрели». */
            if Config.карточкиБезСети {
                КарточкиБезСети.shared.запомнить(ответ.сырое, id: полный.id, поколение: взятое, открыта: true)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if await показатьКопию(после: error) { return }
            неДогрузилась = true
        }
    }

    /// Этап 13: нет связи или сайт лёг — сохранённая копия с телефона вместо «не удалось». true — показали.
    private func показатьКопию(после ошибка: Error) async -> Bool {
        guard Config.карточкиБезСети, ListingDetailCache.подходитКопия(после: ошибка),
              let копия = await ListingDetailCache.прочитать(товар.id),
              !Task.isCancelled, копия.товар.id == товар.id else { return false }
        var сДиска = копия.товар
        if сДиска.категория == nil { сДиска.категория = товар.категория }
        сохранённаяКопия = копия.когда   // раньше товара: onChange не перепишет копией цену в избранном и «Вы смотрели»
        товар = сДиска
        неДогрузилась = false
        return true
    }

    /// Похожие (этап 7). Вернулись из похожего назад — .task запускается снова, но за тем же разделом второй раз не
    /// ходим. Не удалось — полосы нет, а попытка повторится при следующем показе карточки.
    private func загрузитьПохожие() async {
        guard Config.похожие, let раздел = товар.категория else { похожие = .нет; return }
        if case .готово(let прежний, _) = похожие, прежний == раздел { return }
        похожие = .грузим
        do {
            let найдено = try await Похожие.загрузить(раздел: раздел, кроме: товар.id)
            guard !Task.isCancelled else { return }
            похожие = .готово(раздел: раздел, товары: найдено)
        } catch {
            if !Task.isCancelled { похожие = .нет }
        }
    }
}

/// Номер фото для fullScreenCover(item:) — ему нужен Identifiable.
private struct ФотоИндекс: Identifiable {
    let id: Int
}

/// Фото на весь экран: листать, увеличивать двумя пальцами, закрыть.
private struct ФотоНаВесьЭкран: View {
    let адреса: [URL]
    @State var начало: Int
    @Environment(\.dismiss) private var закрыть

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $начало) {
                ForEach(Array(адреса.enumerated()), id: \.offset) { номер, адрес in
                    УвеличиваемоеФото(адрес: адрес).tag(номер)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: адреса.count > 1 ? .always : .never))
            .ignoresSafeArea()

            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel(FeedText.т("close"))
            .padding(16)
        }
        .statusBarHidden()
    }
}

private struct УвеличиваемоеФото: View {
    let адрес: URL
    @State private var масштаб: CGFloat = 1
    @State private var опорный: CGFloat = 1

    var body: some View {
        AsyncImage(url: адрес) { фаза in
            if case .success(let картинка) = фаза {
                картинка.resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .scaleEffect(масштаб)
        .gesture(
            MagnifyGesture()
                .onChanged { з in масштаб = max(1, min(4, опорный * з.magnification)) }
                .onEnded { _ in опорный = масштаб }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) { масштаб = масштаб > 1 ? 1 : 2 }
            опорный = масштаб
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
