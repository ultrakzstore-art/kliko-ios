import SwiftUI

/**
 СПИСОК ДИАЛОГОВ — ЭТАП 3 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующий этап» → чат).

 Открывается из шапки ленты (значок сообщений). Диалоги — dm.php?action=list с куками веб-сессии: те же, что на
 сайте. Не вошёл — экран «Войдите» с кнопкой входа на сайте: вход, коды из SMS и eGov остаются там.
 */
@MainActor
final class ChatListModel: ObservableObject {
    @Published private(set) var диалоги: [ЧатДиалог] = []
    @Published private(set) var грузим = false
    @Published private(set) var ошибка: ChatAPI.Ошибка?
    @Published private(set) var загружено = false

    func загрузить() async {
        грузим = true
        defer { грузим = false }
        do {
            диалоги = try await ChatAPI.диалоги()
            ошибка = nil
        } catch let e as ChatAPI.Ошибка {
            if !Task.isCancelled { ошибка = e }
        } catch {
            if !Task.isCancelled { ошибка = .сеть }
        }
        загружено = true
    }
}

struct ChatListView: View {
    @StateObject private var модель = ChatListModel()
    /// Открыть страницу сайта (вход, переписка на сайте).
    let открыть: (URL) -> Void

    var body: some View {
        Group {
            if !модель.загружено {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if модель.ошибка == .нуженВход {
                ContentUnavailableView {
                    Label(ChatText.т("login"), systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(ChatText.т("login_sub"))
                } actions: {
                    Button(ChatText.т("login_btn")) { if let u = Config.url("/cabinet.php") { открыть(u) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.green)
                }
            } else if модель.ошибка != nil && модель.диалоги.isEmpty {
                ContentUnavailableView {
                    Label(ChatText.т("failed"), systemImage: "exclamationmark.bubble")
                } actions: {
                    Button(ChatText.т("retry")) { Task { await модель.загрузить() } }
                    Button(ChatText.т("open_site")) { if let u = ChatThreadModel.адресПереписки { открыть(u) } }
                }
            } else if модель.диалоги.isEmpty {
                ContentUnavailableView(ChatText.т("empty"), systemImage: "bubble.left.and.bubble.right",
                                       description: Text(ChatText.т("empty_sub")))
            } else {
                List(модель.диалоги) { д in
                    NavigationLink(value: ЧатЦель.диалог(д)) { строка(д) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(ChatText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await модель.загрузить() }
        /* Возвращаемся из переписки — непрочитанные в списке должны погаснуть: перечитываем при каждом показе. */
        .task { await модель.загрузить() }
    }

    private func строка(_ д: ЧатДиалог) -> some View {
        HStack(spacing: 12) {
            обложка(д)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(д.собеседник.isEmpty ? ChatText.т("peer") : д.собеседник)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(ЧатВремя.коротко(д.последнееКогда))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !д.объявление.isEmpty {
                    Text(д.объявление)
                        .font(.caption)
                        .foregroundStyle(Theme.green2)
                        .lineLimit(1)
                }
                HStack {
                    Text((д.последнееМоё ? ChatText.т("you") : "") + д.последнее)
                        .font(.footnote)
                        .foregroundStyle(д.непрочитано > 0 ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    if д.непрочитано > 0 {
                        Text("\(д.непрочитано)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.green, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func обложка(_ д: ЧатДиалог) -> some View {
        Group {
            if let адрес = Config.url(д.обложка) {
                AsyncImage(url: адрес) { картинка in
                    картинка.resizable().scaledToFill()
                } placeholder: {
                    Theme.mint
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Circle()
                    .fill(Theme.mint)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.green))
            }
        }
        .frame(width: 48, height: 48)
    }
}

/// Куда ведёт навигация чата внутри стека ленты.
enum ЧатЦель: Hashable {
    /// Список диалогов.
    case список
    /// Диалог из списка — номер уже известен.
    case диалог(ЧатДиалог)
    /// «Написать» из карточки: диалог с продавцом по объявлению, создаётся при первом обращении.
    case продавец(id: String, имя: String, объявление: String)
}

/// Время сообщения: «14:05» сегодня, «24.09» раньше. Сервер шлёт «2026-09-25 14:05:12» — показываем как есть,
/// без перевода поясов: и сайт, и человек в Казахстане.
enum ЧатВремя {
    private static let разбор: DateFormatter = {
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.timeZone = TimeZone(identifier: "UTC")
        ф.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ф
    }()

    static func коротко(_ строка: String) -> String {
        guard let дата = разбор.date(from: String(строка.prefix(19))) else { return "" }
        /* «Сегодня» — по часам телефона: время сервера в строке уже местное, а Date() в UTC у Казахстана до пяти утра
           ещё вчерашний. */
        let день = DateFormatter()
        день.locale = Locale(identifier: "en_US_POSIX")
        день.dateFormat = "yyyy-MM-dd"
        let сегодня = день.string(from: Date())
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.timeZone = TimeZone(identifier: "UTC")
        ф.dateFormat = строка.hasPrefix(сегодня) ? "HH:mm" : "dd.MM"
        return ф.string(from: дата)
    }

    static func время(_ строка: String) -> String {
        guard let дата = разбор.date(from: String(строка.prefix(19))) else { return "" }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.timeZone = TimeZone(identifier: "UTC")
        ф.dateFormat = "HH:mm"
        return ф.string(from: дата)
    }
}
