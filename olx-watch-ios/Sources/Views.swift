import SwiftUI
import UIKit

extension Color {
    static let watchAccent = Color(red: 0.0, green: 0.62, blue: 0.58)
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { FeedView() }
                .tabItem { Label("Лента", systemImage: "bolt.fill") }
            NavigationStack { SubsView() }
                .tabItem { Label("Поиски", systemImage: "magnifyingglass") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}

// MARK: — Лента

struct FeedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    enum Scope: String, CaseIterable { case matched = "По запросам", all = "Все новые" }
    @State private var scope = Scope.matched
    @State private var subFilter: Int?          // nil — все запросы

    private var shown: [Ad] {
        switch scope {
        case .all: return model.allAds
        case .matched:
            guard let id = subFilter else { return model.ads }
            return model.ads.filter { $0.subIds.contains(id) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Лента", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if scope == .matched && model.subs.count > 1 {
                    Picker("Запрос", selection: $subFilter) {
                        Text("Все запросы").tag(Int?.none)
                        ForEach(model.subs) { sub in Text(verbatim: sub.name).tag(Optional(sub.id)) }
                    }
                }
            }
            .listRowSeparator(.hidden)

            if let error = model.error { ErrorRow(text: error) }

            if shown.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: scope == .all ? "bolt" : "tray")
                } description: {
                    Text(emptyText)
                }
                .listRowSeparator(.hidden)
            } else if scope == .all {
                // Несортированные: всё новое подряд — название и ссылка.
                ForEach(model.allAds) { ad in
                    LinkRow(ad: ad).contextMenu { AdMenu(ad: ad) }
                }
            } else if subFilter != nil {
                ForEach(shown) { ad in adButton(ad) }
            } else {
                // Отсортированные: у каждого запроса — свой раздел.
                ForEach(model.subs) { sub in
                    let items = model.ads.filter { $0.subIds.contains(sub.id) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { ad in adButton(ad) }
                        } header: {
                            Text(verbatim: "\(sub.name) · \(items.count)")
                        }
                    }
                }
                let orphans = model.ads.filter { ad in !model.subs.contains { ad.subIds.contains($0.id) } }
                if !orphans.isEmpty {
                    Section("Удалённые запросы") {
                        ForEach(orphans) { ad in adButton(ad) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Новые на OLX")
        .refreshable { await model.pollAll() }
    }

    private func adButton(_ ad: Ad) -> some View {
        AdRow(ad: ad, highlighted: ad.id == model.highlightedAdId)
            .contextMenu { AdMenu(ad: ad) }
    }

    private var emptyTitle: String {
        if model.subs.isEmpty { return "Добавьте поиск" }
        return scope == .all ? "Пока ничего" : "Пока пусто"
    }

    private var emptyText: String {
        if model.subs.isEmpty { return "Во вкладке «Поиски» выберите рубрику, город и цену — новые объявления появятся здесь." }
        if scope == .all { return "Здесь всё новое, что турбо поймало на OLX, в любой рубрике. Проверяю, пока приложение открыто." }
        return "Как только на OLX появится подходящее объявление, оно придёт сюда и уведомлением."
    }
}

/// Карточка «По запросам»: фото листаются свайпом (тап — на весь экран с увеличением),
/// ниже — цена, город, время и кнопки: позвонить (если номер есть в тексте), OLX, автор.
struct AdRow: View {
    let ad: Ad
    var highlighted = false
    @Environment(\.openURL) private var openURL
    @State private var viewer: PhotoViewer.Start?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotoCarousel(photos: ad.gallery, height: 200) { index in viewer = .init(index: index) }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: ad.title.isEmpty ? "Объявление \(ad.id)" : ad.title)
                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if !ad.priceText.isEmpty { Text(verbatim: ad.priceText).font(.headline) }
                    Spacer(minLength: 0)
                    Text("\(ad.postedDate, style: .relative) назад").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if !ad.city.isEmpty { Text(verbatim: ad.city).font(.caption).foregroundStyle(.secondary) }
                    if let lag = ad.lagText { Text(verbatim: "⏱ \(lag)").font(.caption2).foregroundStyle(.secondary) }
                }
                Badges(ad: ad)
            }
            .contentShape(Rectangle())
            .onTapGesture { if let url = ad.link { openURL(url) } }

            ActionButtons(ad: ad)
        }
        .padding(.vertical, 6)
        .listRowBackground(highlighted ? Color.watchAccent.opacity(0.12) : nil)
        .fullScreenCover(item: $viewer) { start in PhotoViewer(photos: ad.gallery, start: start.index) }
    }
}

/// Кнопки действий: позвонить, открыть на OLX, все объявления автора.
struct ActionButtons: View {
    let ad: Ad
    var compact = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let phones = ad.phones
        HStack(spacing: 8) {
            if let phone = phones.first, let tel = URL(string: "tel:\(phone)") {
                Button { openURL(tel) } label: {
                    Label(compact ? "Позвонить" : Phone.pretty(phone), systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            if let url = ad.link {
                Button { openURL(url) } label: {
                    Label(phones.isEmpty ? "Открыть — позвонить на OLX" : "OLX", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: phones.isEmpty ? .infinity : nil)
                }
                .buttonStyle(.bordered)
            }
            if !compact, let seller = ad.sellerURL {
                Button { openURL(seller) } label: { Image(systemName: "person.crop.circle") }
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .controlSize(compact ? .small : .regular)
    }
}

/// Строка «Все новые»: название, ссылка, цена, город и время — компактно, с маленьким фото.
struct LinkRow: View {
    let ad: Ad
    @Environment(\.openURL) private var openURL
    @State private var viewer: PhotoViewer.Start?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let first = ad.gallery.first {
                    CachedImage(url: PhotoSize.thumb(first))
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { viewer = .init(index: 0) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: ad.title.isEmpty ? "Объявление \(ad.id)" : ad.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let url = ad.link {
                        Text(verbatim: url.absoluteString.replacingOccurrences(of: "https://www.", with: ""))
                            .font(.caption)
                            .foregroundStyle(Color.watchAccent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 4) {
                        if !ad.priceText.isEmpty { Text(verbatim: ad.priceText).fontWeight(.semibold) }
                        if !ad.city.isEmpty { Text(verbatim: "· \(ad.city)") }
                        Text("· \(ad.postedDate, style: .relative) назад")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if let lag = ad.lagText {
                        Text(verbatim: "⏱ \(lag)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if let url = ad.link { openURL(url) } }
            }
            if !ad.phones.isEmpty { ActionButtons(ad: ad, compact: true) }
        }
        .padding(.vertical, 2)
        .fullScreenCover(item: $viewer) { start in PhotoViewer(photos: ad.gallery, start: start.index) }
    }
}

/// Фото свайпом. Маленькие копии для ленты, тап — полноэкранный просмотр.
struct PhotoCarousel: View {
    let photos: [String]
    var height: CGFloat = 200
    var onTap: (Int) -> Void
    @State private var page = 0

    var body: some View {
        if photos.isEmpty {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
                .frame(height: 80)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        } else {
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                    CachedImage(url: PhotoSize.thumb(url))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(i) }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if photos.count > 1 {
                    Text(verbatim: "\(page + 1)/\(photos.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
        }
    }
}

/// Картинка через общий кэш (URLCache): пролистанное не грузится заново.
struct CachedImage: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url), transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else if phase.error != nil {
                Color.secondary.opacity(0.15).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            } else {
                Color.secondary.opacity(0.1).overlay(ProgressView())
            }
        }
    }
}

/// Полноэкранный просмотр: листать свайпом, увеличивать щипком или двойным тапом.
struct PhotoViewer: View {
    struct Start: Identifiable {
        var index: Int
        var id: Int { index }
    }

    let photos: [String]
    @State var start: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [String], start: Int) {
        self.photos = photos
        _start = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $start) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(url: url).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea()

            HStack {
                Text(verbatim: "\(start + 1) / \(photos.count)").foregroundStyle(.white).font(.subheadline.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title).symbolRenderingMode(.hierarchical).foregroundStyle(.white)
                }
            }
            .padding()
        }
        .statusBarHidden()
    }
}

struct ZoomableImage: View {
    let url: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else if phase.error != nil {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView().tint(.white)
            }
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(
            MagnifyGesture()
                .onChanged { value in scale = min(5, max(1, lastScale * value.magnification)) }
                .onEnded { _ in
                    lastScale = scale
                    if scale <= 1 { reset() }
                }
        )
        // Сдвиг увеличенного фото; при обычном масштабе свайп остаётся листанию.
        .gesture(
            DragGesture()
                .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                .onEnded { _ in lastOffset = offset },
            including: scale > 1 ? .all : .subviews
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.25)) {
                if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

struct Badges: View {
    let ad: Ad

    var body: some View {
        HStack(spacing: 6) {
            if ad.early { Badge(text: "⚡ раньше поиска", color: .orange) }
            if ad.onReview { Badge(text: "на проверке", color: .yellow) }
            if ad.business { Badge(text: "магазин", color: .indigo) }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

struct AdMenu: View {
    let ad: Ad
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = ad.link {
            Button { openURL(url) } label: { Label("Открыть на OLX", systemImage: "safari") }
            ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            Button { UIPasteboard.general.url = url } label: { Label("Скопировать ссылку", systemImage: "doc.on.doc") }
        }
        if let url = ad.sellerURL {
            Button { openURL(url) } label: { Label("Все объявления автора", systemImage: "person.crop.circle") }
        }
        if !ad.params.isEmpty || !ad.description.isEmpty {
            Section {
                ForEach(ad.params, id: \.self) { Text(verbatim: $0) }
                if !ad.description.isEmpty { Text(verbatim: String(ad.description.prefix(200)) + "…") }
            }
        }
    }
}

struct ErrorRow: View {
    let text: String

    var body: some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

// MARK: — Поиски

struct SubsView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        List {
            if model.subs.isEmpty {
                Text("Нажмите «+»: выберите рубрику, город и цену — или вставьте ссылку на поиск с olx.kz.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.subs) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: sub.name).font(.headline)
                        Spacer()
                        if sub.paused { Image(systemName: "pause.circle.fill").foregroundStyle(.secondary) }
                    }
                    Text(sub.ready ? "Прислано: \(sub.sent)" : "Первый проход — запоминаю, что уже есть…")
                        .font(.caption).foregroundStyle(.secondary)
                    if !sub.error.isEmpty { Text(verbatim: sub.error).font(.caption).foregroundStyle(.red) }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { model.delete(sub) } label: { Label("Удалить", systemImage: "trash") }
                    Button { model.togglePause(sub) } label: {
                        Label(sub.paused ? "Продолжить" : "Пауза", systemImage: sub.paused ? "play" : "pause")
                    }
                    .tint(.gray)
                }
            }
        }
        .navigationTitle("Поиски")
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
        }
        .refreshable { await model.pollAll() }
        .sheet(isPresented: $adding) { AddSubSheet() }
    }
}

/// Новый поиск: выбрать рубрику, город, слова и цену — или вставить ссылку с сайта.
struct AddSubSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable { case pick = "Выбрать", link = "Ссылка" }
    @State private var mode = Mode.pick
    @State private var url = ""
    @State private var name = ""
    @State private var saving = false

    @State private var top: OLX.Category?
    @State private var subcategories: [OLX.Category] = []
    @State private var sub: OLX.Category?
    @State private var loadingSubs = false
    @State private var subsNote = ""
    @State private var citySlug = ""
    @State private var words = ""
    @State private var priceFrom = ""
    @State private var priceTo = ""

    private var builtURL: String {
        OLX.buildSearchURL(path: sub?.path ?? top?.path, city: citySlug.isEmpty ? nil : citySlug, words: words,
                           priceFrom: Int(priceFrom.filter(\.isNumber)), priceTo: Int(priceTo.filter(\.isNumber)))
    }

    private var canSave: Bool {
        if saving { return false }
        switch mode {
        case .link: return !url.isEmpty
        case .pick: return top != nil || !words.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var autoName: String {
        guard mode == .pick else { return "" }
        var parts = [words.isEmpty ? (sub?.name ?? top?.name ?? "Поиск") : words]
        if let city = OLX.cities.first(where: { $0.slug == citySlug }) { parts.append(city.name) }
        if !priceTo.isEmpty { parts.append("до \(priceTo)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Как", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == .pick { pickForm } else { linkForm }

                Section("Название (необязательно)") {
                    TextField(text: $name, prompt: Text(verbatim: "Ноутбуки до 300 000")) { Text(verbatim: "Название") }
                }
                if let error = model.error { ErrorRow(text: error) }
            }
            .navigationTitle("Новый поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Проверяю…" : "Добавить") {
                        saving = true
                        let link = mode == .pick ? builtURL : url
                        let title = name.isEmpty ? autoName : name
                        Task {
                            if await model.addSub(url: link, name: title) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: top) { _, newTop in
                sub = nil
                subcategories = []
                guard let newTop else { return }
                loadingSubs = true
                Task {
                    let result = await OLX.subcategories(of: newTop.path)
                    subcategories = result.list
                    subsNote = result.note
                    loadingSubs = false
                }
            }
        }
    }

    @ViewBuilder private var pickForm: some View {
        Section("Рубрика") {
            Picker("Рубрика", selection: $top) {
                Text("Все рубрики").tag(OLX.Category?.none)
                ForEach(OLX.topCategories) { c in Text(verbatim: c.name).tag(Optional(c)) }
            }
            if top != nil {
                if loadingSubs {
                    HStack { Text("Подрубрики"); Spacer(); ProgressView() }
                } else if !subcategories.isEmpty {
                    Picker("Подрубрика", selection: $sub) {
                        Text("Вся рубрика").tag(OLX.Category?.none)
                        ForEach(subcategories) { c in Text(verbatim: c.name).tag(Optional(c)) }
                    }
                } else {
                    Text("У этой рубрики подрубрик нет — ищем по всей рубрике").font(.footnote).foregroundStyle(.secondary)
                }
                if !subsNote.isEmpty {
                    Text(verbatim: subsNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("Город") {
            Picker("Город", selection: $citySlug) {
                Text("Весь Казахстан").tag("")
                ForEach(OLX.cities, id: \.slug) { c in Text(verbatim: c.name).tag(c.slug) }
            }
        }
        Section {
            TextField(text: $words, prompt: Text(verbatim: "необязательно: iphone 13, hp 250")) { Text(verbatim: "Слова") }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                TextField(text: $priceFrom, prompt: Text(verbatim: "Цена от")) { Text(verbatim: "От") }
                    .keyboardType(.numberPad)
                TextField(text: $priceTo, prompt: Text(verbatim: "до, ₸")) { Text(verbatim: "До") }
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("Слова и цена — необязательно")
        } footer: {
            Text("Можно выбрать только рубрику — без слов придут все новые объявления в ней. Слова нужны, только если рубрика «Все». Первый проход запоминает, что уже есть, — дальше приходят только новые.")
        }
    }

    @ViewBuilder private var linkForm: some View {
        Section {
            TextField(text: $url, prompt: Text(verbatim: "https://www.olx.kz/d/…"), axis: .vertical) { Text(verbatim: "Ссылка") }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Вставить из буфера") { url = UIPasteboard.general.string ?? url }
        } header: {
            Text("Ссылка на поиск OLX")
        } footer: {
            Text("На olx.kz настройте поиск и скопируйте ссылку из адресной строки.")
        }
    }
}

// MARK: — Настройки

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false

    var body: some View {
        let st = model.state.stats
        Form {
            Section {
                LabeledContent("Проверка", value: model.running ? "идёт, пока приложение открыто" : "на паузе")
                if let until = model.blockedUntil, until > Date() {
                    LabeledContent("OLX ограничил запросы", value: "до " + until.formatted(date: .omitted, time: .shortened))
                }
                if let error = model.error { ErrorRow(text: error) }
                Button(checking ? "Проверяю…" : "Проверить поиски сейчас") {
                    checking = true
                    Task { await model.pollAll(); checking = false }
                }
                .disabled(checking || model.subs.isEmpty)
            } header: {
                Text("Сборщик")
            } footer: {
                Text("Поиск и турбо — с выбранной скоростью, пока приложение на экране. В фоне iOS изредка даёт проверить поиски (обычно раз в 15+ минут).")
            }

            Section {
                Picker("Показывать поданные за", selection: Binding(get: { model.freshnessMinutes }, set: { model.freshnessMinutes = $0 })) {
                    ForEach(AppModel.freshnessChoices, id: \.self) { m in Text(m == 1 ? "последнюю минуту" : "\(m) мин").tag(m) }
                }
                Picker("Скорость", selection: Binding(get: { model.speed }, set: { model.speed = $0 })) {
                    ForEach(AppModel.Speed.allCases) { sp in Text(sp.title).tag(sp) }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Только новоиспечённые")
            } footer: {
                Text("Старое, которое продавец поднял или продвинул, и всё поданное раньше этого срока в ленту и уведомления не попадает. «Последняя минута» работает, пока приложение открыто: в фоне iOS будит его редко, и такие объявления к пробуждению уже старше минуты.")
            }

            Section {
                Toggle("Турбо: раньше поиска", isOn: Binding(get: { model.state.turbo }, set: { model.setTurbo($0) }))
                LabeledContent("Проверено номеров", value: "\(st.turboProbes)")
                LabeledContent("Найдено по номерам", value: "\(st.turboFound)")
                if let hit = st.lastTurboHit {
                    LabeledContent("Последняя находка", value: hit.formatted(date: .omitted, time: .shortened))
                }
                LabeledContent("Последний номер", value: model.state.frontier > 0 ? "\(model.state.frontier)" : "—")
                LabeledContent("Запросов поиска", value: "\(st.searchOk) / ошибок \(st.searchErr)")
            } header: {
                Text("Турбо")
            } footer: {
                Text("Турбо проверяет следующие номера объявлений напрямую — так ловятся объявления до попадания в поиск, в том числе на проверке.")
            }

            PushSection()

            Section {
                Button("Разрешить уведомления") { Task { await model.requestNotifications() } }
                Button("Очистить ленту", role: .destructive) { model.clearFeed() }
            }
        }
        .navigationTitle("Настройки")
    }
}

/// Тихие пуши-будильники: сервер на kliko.kz будит приложение, и оно проверяет OLX в фоне.
struct PushSection: View {
    @Environment(AppModel.self) private var model
    @State private var endpoint = ""
    @State private var key = ""
    @State private var busy = false

    var body: some View {
        Section {
            TextField(text: $endpoint, prompt: Text(verbatim: AppModel.defaultPushEndpoint)) { Text(verbatim: "Сервер") }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(text: $key, prompt: Text(verbatim: "Ключ api_token")) { Text(verbatim: "Ключ") }
            Button(busy ? "Подключаю…" : "Подключить будильник") {
                busy = true
                Task { await model.connectPushServer(endpoint: endpoint, key: key); busy = false }
            }
            .disabled(busy || endpoint.isEmpty || key.isEmpty)
            if !model.pushStatus.isEmpty {
                Text(verbatim: model.pushStatus).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Будильник через пуши (необязательно)")
        } footer: {
            Text("Сервер на kliko.kz раз в несколько минут шлёт тихий пуш — iPhone будит приложение, и оно проверяет OLX с телефона даже когда закрыто. Сервер к OLX не ходит.")
        }
        .onAppear {
            endpoint = model.pushEndpoint
            key = model.pushKey
        }
    }
}
