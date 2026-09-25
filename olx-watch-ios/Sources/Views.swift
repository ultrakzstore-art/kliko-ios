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

    // Что сейчас на экране. Пока вы листаете ниже верха, новые объявления не вставляются
    // сверху (из-за этого лента дёргалась), а копятся под кнопкой «↑ N новых».
    @State private var feedAds: [Ad] = []
    @State private var feedAll: [Ad] = []
    @State private var pendingAds = 0
    @State private var pendingAll = 0
    @State private var atTop = true

    private var shown: [Ad] {
        switch scope {
        case .all: return feedAll
        case .matched:
            guard let id = subFilter else { return feedAds }
            return feedAds.filter { $0.subIds.contains(id) }
        }
    }

    private var pending: Int { scope == .all ? pendingAll : pendingAds }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Picker("Лента", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onAppear { atTop = true }
                    .onDisappear { atTop = false }
                    if scope == .matched && model.subs.count > 1 {
                        Picker("Запрос", selection: $subFilter) {
                            Text("Все запросы").tag(Int?.none)
                            ForEach(model.subs) { sub in Text(verbatim: sub.name).tag(Optional(sub.id)) }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .id("top")

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
                    ForEach(feedAll) { ad in
                        LinkRow(ad: ad).contextMenu { AdMenu(ad: ad) }
                    }
                } else if subFilter != nil {
                    ForEach(shown) { ad in adButton(ad) }
                } else {
                    // Отсортированные: у каждого запроса — свой раздел.
                    ForEach(model.subs) { sub in
                        let items = feedAds.filter { $0.subIds.contains(sub.id) }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { ad in adButton(ad) }
                            } header: {
                                Text(verbatim: "\(sub.name) · \(items.count)")
                            }
                        }
                    }
                    let orphans = feedAds.filter { ad in !model.subs.contains { ad.subIds.contains($0.id) } }
                    if !orphans.isEmpty {
                        Section("Удалённые запросы") {
                            ForEach(orphans) { ad in adButton(ad) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay(alignment: .top) {
                if pending > 0 {
                    Button {
                        sync(force: true)
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("top", anchor: .top) }
                    } label: {
                        Label("\(pending) новых", systemImage: "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.watchAccent, in: Capsule())
                            .foregroundStyle(.white)
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: pending)
        }
        .navigationTitle("Новые объявления")
        .refreshable { await model.pollAll(); sync(force: true) }
        .onAppear { sync(force: true) }
        .onChange(of: model.ads) { _, _ in sync() }
        .onChange(of: model.allAds) { _, _ in sync() }
        .onChange(of: atTop) { _, top in if top { sync() } }
    }

    /// Наверху — показываем всё как есть. Ниже — только обновляем то, что уже на экране
    /// (фото, описание), а новое считаем и ждём, пока вы вернётесь наверх или нажмёте кнопку.
    private func sync(force: Bool = false) {
        let a = merged(model.ads, into: feedAds, force: force)
        feedAds = a.list
        pendingAds = a.pending
        let b = merged(model.allAds, into: feedAll, force: force)
        feedAll = b.list
        pendingAll = b.pending
    }

    private func merged(_ new: [Ad], into current: [Ad], force: Bool) -> (list: [Ad], pending: Int) {
        if force || atTop || current.isEmpty { return (new, 0) }
        let onScreen = Set(current.map(\.id))
        let fresh = new.reduce(0) { $0 + (onScreen.contains($1.id) ? 0 : 1) }
        return (new.filter { onScreen.contains($0.id) }, fresh)
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
                Text(verbatim: ad.title.isEmpty ? "Объявление" : ad.title)
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

            AdDetails(ad: ad)
            ActionButtons(ad: ad)
        }
        .padding(.vertical, 6)
        .listRowBackground(highlighted ? Color.watchAccent.opacity(0.12) : nil)
        .fullScreenCover(item: $viewer) { start in PhotoViewer(photos: ad.gallery, start: start.index) }
    }
}

/// Кнопки действий, главное — номер. Есть в тексте — «Позвонить» звонит сразу. Нет — «Номер —
/// на OLX» открывает объявление, где его показывают. Рядом — все объявления автора.
struct ActionButtons: View {
    let ad: Ad
    var compact = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let phones = ad.phones
        HStack(spacing: 8) {
            if let phone = phones.first, let tel = URL(string: "tel:\(phone)") {
                Button { openURL(tel) } label: {
                    Label(compact ? "Позвонить" : "Позвонить · \(Phone.pretty(phone))", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                if let seller = ad.sellerURL {
                    Button { openURL(seller) } label: { Image(systemName: "person.crop.circle") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Все объявления автора")
                }
            } else if let url = ad.link {
                // Номера в тексте нет — главное всё равно номер: открываем объявление,
                // там «Показать телефон» (в приложении OLX или в Safari, где вы вошли).
                Button { openURL(url) } label: {
                    Label("Номер — на \(ad.site == .kaspi ? "Kaspi" : ad.site.title)", systemImage: "phone.arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                if let seller = ad.sellerURL {
                    Button { openURL(seller) } label: { Image(systemName: "person.crop.circle") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Все объявления автора")
                }
            }
            if !phones.isEmpty, let url = ad.link {
                Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Открыть на \(ad.site.title)")
            }
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .controlSize(compact ? .small : .regular)
    }
}

/// Рубрика, характеристики и описание — сразу в карточке, без перехода на OLX.
struct AdDetails: View {
    let ad: Ad
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        let category = model.categoryText(for: ad)
        VStack(alignment: .leading, spacing: 6) {
            if category != nil || !ad.params.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let category {
                            Label { Text(verbatim: category) } icon: { Image(systemName: "folder") }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.watchAccent.opacity(0.15), in: Capsule())
                        }
                        ForEach(ad.params, id: \.self) { p in
                            Text(verbatim: p)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            if !ad.description.isEmpty {
                Text(verbatim: ad.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if ad.description.count > 140 {
                    Button(expanded ? "Свернуть" : "Ещё") { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Строка «Все новые»: фото листаются сверху, дальше название, ссылка, цена, рубрика, описание.
struct LinkRow: View {
    let ad: Ad
    @Environment(\.openURL) private var openURL
    @State private var viewer: PhotoViewer.Start?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !ad.gallery.isEmpty {
                PhotoCarousel(photos: ad.gallery, height: 160) { index in viewer = .init(index: index) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: ad.title.isEmpty ? "Объявление" : ad.title)
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
            AdDetails(ad: ad)
            ActionButtons(ad: ad, compact: true)
        }
        .padding(.vertical, 4)
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
            if ad.site != .olx { Badge(text: "\(ad.site.emoji) \(ad.site.title)", color: .blue) }
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
            Button { openURL(url) } label: { Label("Открыть на \(ad.site.title)", systemImage: "safari") }
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
                Text("Нажмите «+»: выберите площадку (OLX, Kolesa, Krisha, Kaspi), рубрику, город и цену — или вставьте ссылку на поиск с сайта.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.subs) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "\(sub.site.emoji) \(sub.name)").font(.headline)
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
    @State private var site = Site.olx
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
        site.buildSearchURL(path: sub?.path ?? top?.path, city: citySlug.isEmpty ? nil : citySlug, words: site == .olx ? words : "",
                           priceFrom: Int(priceFrom.filter(\.isNumber)), priceTo: Int(priceTo.filter(\.isNumber)))
    }

    private var canSave: Bool {
        if saving { return false }
        switch mode {
        case .link: return !url.isEmpty
        case .pick:
            switch site {
            case .olx: return top != nil || !words.trimmingCharacters(in: .whitespaces).isEmpty
            case .kolesa, .krisha: return top != nil
            case .kaspi: return false
            }
        }
    }

    private var autoName: String {
        guard mode == .pick else { return "" }
        var parts = [site == .olx && !words.isEmpty ? words : (sub?.name ?? top?.name ?? "Поиск")]
        if site != .olx { parts.insert(site.title, at: 0) }
        if let city = site.cities.first(where: { $0.slug == citySlug }) { parts.append(city.name) }
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
                            if await model.addSub(url: link, name: title, categoryLabel: mode == .pick ? (sub?.name ?? top?.name) : nil) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: site) { _, newSite in
                top = nil
                sub = nil
                citySlug = ""
                words = ""
                if newSite == .kaspi { mode = .link }
            }
            .onChange(of: top) { _, newTop in
                sub = nil
                subcategories = []
                subsNote = ""
                guard let newTop, site == .olx else { return }
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
        Section {
            Picker("Площадка", selection: $site) {
                ForEach(Site.allCases) { s in Text(verbatim: "\(s.emoji) \(s.title)").tag(s) }
            }
        }
        if site == .kaspi {
            Section {
                Text("У Kaspi Объявлений выбора кнопками нет: откройте поиск на kaspi.kz, скопируйте ссылку и вставьте во вкладке «Ссылка».")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Перейти к ссылке") { mode = .link }
            }
        } else {
            sitePickForm
        }
    }

    @ViewBuilder private var sitePickForm: some View {
        Section("Рубрика") {
            Picker("Рубрика", selection: $top) {
                Text(site == .olx ? "Все рубрики" : "Выберите").tag(OLX.Category?.none)
                ForEach(site.categories) { c in Text(verbatim: c.name).tag(Optional(c)) }
            }
            if top != nil && site == .olx {
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
                ForEach(site.cities, id: \.slug) { c in Text(verbatim: c.name).tag(c.slug) }
            }
        }
        Section {
            if site == .olx {
                TextField(text: $words, prompt: Text(verbatim: "необязательно: iphone 13, hp 250")) { Text(verbatim: "Слова") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            HStack {
                TextField(text: $priceFrom, prompt: Text(verbatim: "Цена от")) { Text(verbatim: "От") }
                    .keyboardType(.numberPad)
                TextField(text: $priceTo, prompt: Text(verbatim: "до, ₸")) { Text(verbatim: "До") }
                    .keyboardType(.numberPad)
            }
        } header: {
            Text(verbatim: site == .olx ? "Слова и цена — необязательно" : "Цена — необязательно")
        } footer: {
            Text(verbatim: site == .olx
                 ? "Можно выбрать только рубрику — без слов придут все новые объявления в ней. Слова нужны, только если рубрика «Все». Первый проход запоминает, что уже есть, — дальше приходят только новые."
                 : "Марку, модель, комнаты и прочие фильтры \(site.title) задайте на сайте и вставьте ссылку во вкладке «Ссылка». Первый проход запоминает, что уже есть, — дальше приходят только новые.")
        }
    }

    @ViewBuilder private var linkForm: some View {
        Section {
            TextField(text: $url, prompt: Text(verbatim: "https://kolesa.kz/cars/… или olx.kz, krisha.kz, kaspi.kz"), axis: .vertical) { Text(verbatim: "Ссылка") }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Вставить из буфера") { url = UIPasteboard.general.string ?? url }
        } header: {
            Text("Ссылка на поиск: OLX, Kolesa, Krisha, Kaspi")
        } footer: {
            Text("На сайте настройте поиск (марка, модель, комнаты, цена — что угодно) и скопируйте ссылку из адресной строки. Турбо «раньше поиска» — пока только у OLX; Kolesa, Krisha и Kaspi проверяются поиском.")
        }
    }
}

// MARK: — Настройки

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false

    var body: some View {
        let st = model.stats
        Form {
            StatusSection()

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
                Toggle("Турбо: раньше поиска", isOn: Binding(get: { model.turboOn }, set: { model.setTurbo($0) }))
                LabeledContent("Проверено номеров", value: "\(st.turboProbes)")
                LabeledContent("Найдено по номерам", value: "\(st.turboFound)")
                if let hit = st.lastTurboHit {
                    LabeledContent("Последняя находка", value: hit.formatted(date: .omitted, time: .shortened))
                }
                LabeledContent("Последний номер", value: model.frontier > 0 ? "\(model.frontier)" : "—")
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

/// Тихие пуши-будильники: свой сервер будит приложение, и оно проверяет OLX в фоне.
struct PushSection: View {
    @Environment(AppModel.self) private var model
    @State private var endpoint = ""
    @State private var key = ""
    @State private var busy = false

    var body: some View {
        Section {
            TextField(text: $endpoint, prompt: Text(verbatim: "https://ваш-сервер/olx-watch/api.php")) { Text(verbatim: "Сервер") }
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
            Text("Свой сервер раз в несколько минут шлёт тихий пуш — iPhone будит приложение, и оно проверяет OLX с телефона даже когда закрыто. Сервер к OLX не ходит.")
        }
        .onAppear {
            endpoint = model.pushEndpoint
            key = model.pushKey
        }
    }
}

/// Работает ли сервис на самом деле: когда OLX последний раз ответил, с каким кодом и
/// как быстро. Зелёный — ответ был недавно; жёлтый — давно тишина; красный — ошибка.
struct StatusSection: View {
    @Environment(AppModel.self) private var model
    @State private var checking = false
    @State private var result = ""

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let s = status(now: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(s.color).frame(width: 12, height: 12)
                        Text(verbatim: s.title).font(.headline)
                    }
                    Text(verbatim: s.detail).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            let h = model.health
            if let code = h.lastCode {
                LabeledContent("Последний код OLX", value: "\(code)")
            }
            if let ms = h.lastLatencyMs {
                LabeledContent("Скорость ответа", value: "\(ms) мс")
            }
            if let hit = model.stats.lastTurboHit {
                LabeledContent("Турбо последний раз поймало", value: hit.formatted(date: .omitted, time: .standard))
            }
            if let fail = h.lastFailure, !h.lastError.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Последняя ошибка · \(fail.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: h.lastError).font(.caption).foregroundStyle(.red)
                }
            }
            Button(checking ? "Проверяю связь…" : "Проверить связь с OLX сейчас") {
                checking = true
                Task {
                    result = await model.checkConnection()
                    checking = false
                }
            }
            .disabled(checking)
            if !result.isEmpty {
                Text(verbatim: result).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Статус")
        } footer: {
            Text("Кнопка делает один настоящий запрос к OLX с этого телефона и показывает код ответа и время. 200 — всё работает; 403 или 429 — OLX временно ограничил запросы, сборщик сам сделает паузу.")
        }
    }

    private func status(now: Date) -> (color: Color, title: String, detail: String) {
        let h = model.health
        if let until = model.blockedUntil, until > now {
            return (.orange, "OLX ограничил запросы", "Пауза до \(until.formatted(date: .omitted, time: .shortened)), потом продолжу сам.")
        }
        if model.subs.isEmpty && h.lastSuccess == nil {
            return (.gray, "Нет поисков", "Добавьте поиск во вкладке «Поиски».")
        }
        if let fail = h.lastFailure, fail > (h.lastSuccess ?? .distantPast) {
            return (.red, "Ошибка связи", "\(ago(fail, now)): \(h.lastError)")
        }
        guard let ok = h.lastSuccess else {
            return (.yellow, "Ещё не было ответа", model.running ? "Жду первый ответ OLX…" : "Проверка начнётся, когда приложение откроется.")
        }
        let limit = max(model.speed.poll, model.speed.turbo) * 3 + 10
        if model.running && now.timeIntervalSince(ok) <= limit {
            return (.green, "Работает", "OLX ответил \(ago(ok, now)).")
        }
        if !model.running {
            return (.gray, "На паузе", "Приложение было в фоне. Последний ответ OLX — \(ago(ok, now)).")
        }
        return (.yellow, "Давно нет ответа", "Последний ответ OLX — \(ago(ok, now)).")
    }

    private func ago(_ date: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 5 { return "только что" }
        if s < 60 { return "\(s) с назад" }
        if s < 3600 { return "\(s / 60) мин назад" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
