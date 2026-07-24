import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var app: AppState
    @State private var item: MarketItem
    @State private var page = 0
    @State private var showSoon = false
    @State private var openChat = false
    @State private var needLogin = false

    init(item: MarketItem) { _item = State(initialValue: item) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                gallery
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.priceText)
                        .font(.title2).bold().foregroundStyle(Theme.green2)
                    Text(item.displayTitle)
                        .font(.title3).fontWeight(.semibold).foregroundStyle(Theme.ink)

                    HStack(spacing: 8) {
                        chip(item.isNew ? "Новое" : "Б/у")
                        if let w = item.warrantyDays, w > 0 { chip("Гарантия \(w) дн", system: "checkmark.shield") }
                        if let c = item.city, !c.isEmpty { chip(c, system: "mappin.and.ellipse") }
                    }

                    if !item.specPairs.isEmpty { specGrid }

                    if let d = item.description, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("Описание").font(.headline).foregroundStyle(Theme.ink)
                        Text(d).font(.body).foregroundStyle(Theme.ink)
                    }

                    Divider().padding(.vertical, 2)
                    sellerRow
                }
                .padding(.horizontal, 16)
                Color.clear.frame(height: 96)   // место под нижнюю панель
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task { await loadFull() }
        .navigationDestination(isPresented: $openChat) {
            ChatThreadView(peerId: item.sellerId ?? "", peerName: item.seller ?? "Продавец", listingId: item.id)
        }
        .alert("Скоро", isPresented: $showSoon) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Безопасная сделка появится в следующем обновлении приложения.")
        }
        .alert("Нужен вход", isPresented: $needLogin) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Войдите в аккаунт на вкладке «Профиль», чтобы написать продавцу.")
        }
    }

    private func startChat() {
        guard app.isAuthed else { needLogin = true; return }
        guard let sid = item.sellerId, !sid.isEmpty else { showSoon = true; return }
        openChat = true
    }

    // MARK: - Галерея
    private var gallery: some View {
        let urls = item.photoURLs
        return Group {
            if urls.isEmpty {
                Rectangle().fill(Theme.mint)
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(Theme.muted))
                    .frame(height: 300)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            case .empty: Theme.mint.overlay(ProgressView())
                            default: Theme.mint.overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                        .tag(idx)
                    }
                }
                .frame(height: 300)
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))
            }
        }
    }

    private var specGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
            ForEach(item.specPairs, id: \.0) { pair in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.0).font(.caption2).foregroundStyle(Theme.muted)
                    Text(pair.1).font(.subheadline).foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var sellerRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.mint).frame(width: 42, height: 42)
                .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.green2))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.seller ?? "Продавец").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    if item.sellerVerified == true {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption)
                    }
                }
                if let v = item.views, v > 0 { Text("\(v) просмотров").font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { startChat() } label: {
                Label("Написать", systemImage: "message.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.green2)

            Button { showSoon = true } label: {
                Label("Купить безопасно", systemImage: "shield.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.green, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func chip(_ text: String, system: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let system { Image(systemName: system).font(.caption2) }
            Text(text).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.mint, in: Capsule())
        .foregroundStyle(Theme.green2)
    }

    private func loadFull() async {
        // подтягиваем полный товар (описание/спеки/продавец), если он ещё не загружен
        guard item.description == nil else { return }
        if let full = try? await API.shared.item(id: item.id) { item = full }
    }
}
