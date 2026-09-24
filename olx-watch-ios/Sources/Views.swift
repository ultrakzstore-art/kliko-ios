import SwiftUI
import UIKit

extension Color {
    static let watchAccent = Color(red: 0.0, green: 0.62, blue: 0.58)
}

struct RootView: View {
    @Environment(AppModel.self) private var model

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

    var body: some View {
        Group {
            if !model.configured {
                ContentUnavailableView {
                    Label("Подключите сервер", systemImage: "server.rack")
                } description: {
                    Text("Во вкладке «Настройки» укажите адрес api.php на kliko.kz и ключ доступа.")
                }
            } else if model.ads.isEmpty {
                ContentUnavailableView {
                    Label("Пока пусто", systemImage: "tray")
                } description: {
                    Text(model.subs.isEmpty
                         ? "Добавьте поиск во вкладке «Поиски» — новые объявления появятся здесь и придут пушем."
                         : "Как только на OLX появится подходящее объявление, оно придёт сюда и пушем.")
                }
            } else {
                List {
                    if let error = model.error { ErrorRow(text: error) }
                    ForEach(model.ads) { ad in
                        Button { if let url = URL(string: ad.url) { openURL(url) } } label: {
                            AdRow(ad: ad, highlighted: ad.id == model.highlightedAdId)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { AdMenu(ad: ad) }
                        .swipeActions(edge: .trailing) {
                            if let s = ad.sellerUrl, let url = URL(string: s) {
                                Button { openURL(url) } label: { Label("Автор", systemImage: "person.crop.circle") }
                                    .tint(.indigo)
                            }
                        }
                        .onAppear { if ad.id == model.ads.last?.id { Task { await model.loadMore() } } }
                    }
                    if model.loadingMore { ProgressView().frame(maxWidth: .infinity) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Новые на OLX")
        .refreshable { await model.refreshAll() }
        // Пока лента на экране — подтягиваем свежее раз в 20 секунд.
        .task {
            while !Task.isCancelled {
                await model.refreshFeed()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}

struct AdRow: View {
    let ad: Ad
    var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: ad.photo)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(ad.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !ad.priceText.isEmpty {
                    Text(ad.priceText).font(.headline)
                }
                HStack(spacing: 4) {
                    if !ad.city.isEmpty { Text(ad.city) }
                    Text("·")
                    Text("\(ad.postedDate, style: .relative) назад")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Badges(ad: ad)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(highlighted ? Color.watchAccent.opacity(0.12) : nil)
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
        Text(text)
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
        if let url = URL(string: ad.url) {
            Button { openURL(url) } label: { Label("Открыть на OLX", systemImage: "safari") }
            ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            Button { UIPasteboard.general.url = url } label: { Label("Скопировать ссылку", systemImage: "doc.on.doc") }
        }
        if let s = ad.sellerUrl, let url = URL(string: s) {
            Button { openURL(url) } label: { Label("Все объявления автора", systemImage: "person.crop.circle") }
        }
        if !ad.params.isEmpty || !ad.description.isEmpty {
            Section {
                ForEach(ad.params, id: \.self) { Text($0) }
                if !ad.description.isEmpty { Text(String(ad.description.prefix(200)) + "…") }
            }
        }
    }
}

struct ErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
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
            if let error = model.error { ErrorRow(text: error) }
            if model.subs.isEmpty {
                Text("На olx.kz настройте поиск (рубрика, город, цена, слова), скопируйте ссылку из адресной строки и добавьте её здесь.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.subs) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sub.name).font(.headline)
                        Spacer()
                        if sub.paused { Image(systemName: "pause.circle.fill").foregroundStyle(.secondary) }
                    }
                    Text(sub.ready ? "Прислано: \(sub.sent)" : "Первый проход — запоминаю, что уже есть…")
                        .font(.caption).foregroundStyle(.secondary)
                    if !sub.error.isEmpty { Text(sub.error).font(.caption).foregroundStyle(.red) }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await model.delete(sub) } } label: { Label("Удалить", systemImage: "trash") }
                    Button { Task { await model.togglePause(sub) } } label: {
                        Label(sub.paused ? "Продолжить" : "Пауза", systemImage: sub.paused ? "play" : "pause")
                    }
                    .tint(.gray)
                }
            }
        }
        .navigationTitle("Поиски")
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
                .disabled(!model.configured)
        }
        .refreshable { await model.refreshSubs() }
        .sheet(isPresented: $adding) { AddSubSheet() }
    }
}

struct AddSubSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $url, prompt: Text(verbatim: "https://www.olx.kz/d/…"), axis: .vertical) { Text(verbatim: "Ссылка") }
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Вставить из буфера") { url = UIPasteboard.general.string ?? url }
                } header: {
                    Text("Ссылка на поиск OLX")
                } footer: {
                    Text("Рубрика, город, цена и слова берутся из ссылки. Первый проход запоминает, что уже есть, — присылаются только новые.")
                }
                Section("Название (необязательно)") {
                    TextField("Ноутбуки до 300 000", text: $name)
                }
                if let error = model.error { ErrorRow(text: error) }
            }
            .navigationTitle("Новый поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        saving = true
                        Task {
                            if await model.addSub(url: url, name: name) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(url.isEmpty || saving)
                }
            }
        }
    }
}

// MARK: — Настройки

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var endpoint = ""
    @State private var token = ""
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                // Подсказки — verbatim: иначе SwiftUI читает строку как Markdown, и адрес в подсказке
                // рисуется синей ссылкой — выглядит как уже введённый текст, а поле на деле пустое.
                TextField(text: $endpoint, prompt: Text(verbatim: AppModel.defaultEndpoint)) { Text(verbatim: "Адрес сервера") }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Ключ доступа (api_token)", text: $token)
                Button(saving ? "Проверяю…" : saved ? "Подключено ✓" : "Подключить") {
                    saving = true
                    Task {
                        saved = await model.saveSettings(endpoint: endpoint, token: token)
                        if saved { await model.requestPushPermission() }
                        saving = false
                    }
                }
                .disabled(endpoint.isEmpty || token.isEmpty || saving)
                if let error = model.error { ErrorRow(text: error) }
            } header: {
                Text("Сервер")
            } footer: {
                Text("Адрес api.php из папки olx-watch-server на kliko.kz и ключ api_token из её config.php.")
            }

            if let st = model.status {
                Section("Как идут дела") {
                    LabeledContent("Сборщик", value: st.cronOk ? "работает" : "не запускается — проверьте cron")
                    Toggle("Турбо: раньше поиска", isOn: Binding(
                        get: { st.turbo },
                        set: { on in Task { await model.setTurbo(on) } }
                    ))
                    LabeledContent("Проверено номеров", value: "\(st.stats["turbo_probes"] ?? 0)")
                    LabeledContent("Найдено турбо", value: "\(st.stats["turbo_found"] ?? 0)")
                    LabeledContent("Запросов поиска", value: "\(st.stats["search_ok"] ?? 0) / ошибок \(st.stats["search_err"] ?? 0)")
                    if let until = st.blockedUntil {
                        LabeledContent("OLX ограничил запросы", value: "до " + Date(timeIntervalSince1970: TimeInterval(until)).formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Пуши на сервере", value: st.pushReady ? "настроены" : "нет ключа APNs")
                    LabeledContent("Устройств", value: "\(st.devices)")
                    Button("Прислать пробный пуш") { Task { await model.testPush() } }
                }
            }
        }
        .navigationTitle("Настройки")
        .onAppear {
            endpoint = model.endpoint.isEmpty ? AppModel.defaultEndpoint : model.endpoint
            token = model.token
            saved = model.configured
        }
        .task { await model.refreshStatus() }
    }
}
