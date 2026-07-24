import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var threads: [DMThreadSummary] = []
    @Published var loading = true
    @Published var errorText: String?

    func load() async {
        do { threads = try await API.shared.dmList(); errorText = nil }
        catch { errorText = "Не удалось загрузить сообщения" }
        loading = false
    }
    func refresh() async {
        do { threads = try await API.shared.dmList(); errorText = nil } catch {}
    }
}

/// Вкладка «Чаты»: список диалогов. Требует входа.
struct InboxView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = InboxViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !app.isAuthed {
                    ContentUnavailableView {
                        Label("Войдите в аккаунт", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Сообщения доступны после входа — откройте вкладку «Профиль».")
                    }
                } else if vm.loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.threads.isEmpty {
                    ContentUnavailableView("Нет сообщений", systemImage: "tray",
                                           description: Text("Напишите продавцу из карточки товара."))
                } else {
                    List(vm.threads) { t in
                        NavigationLink {
                            ChatThreadView(peerId: t.peerId, peerName: t.peerName, listingId: t.listingId)
                        } label: { row(t) }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.refresh() }
                }
            }
            .navigationTitle("Чаты")
        }
        .task { if app.isAuthed { await vm.load() } }
    }

    private func row(_ t: DMThreadSummary) -> some View {
        HStack(spacing: 12) {
            avatar(t)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(t.peerName.isEmpty ? "Собеседник" : t.peerName)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    if t.unread > 0 {
                        Text("\(t.unread)").font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.green, in: Capsule())
                    }
                }
                if !t.listingTitle.isEmpty {
                    Text(t.listingTitle).font(.caption).foregroundStyle(Theme.green2).lineLimit(1)
                }
                if let last = t.last {
                    Text((last.mine ? "Вы: " : "") + last.preview)
                        .font(.footnote)
                        .foregroundStyle(t.unread > 0 ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func avatar(_ t: DMThreadSummary) -> some View {
        let url = Config.url(t.listingImg)
        return Group {
            if let url {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Theme.mint }
                    .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Circle().fill(Theme.mint).frame(width: 46, height: 46)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.green2))
            }
        }
    }
}
