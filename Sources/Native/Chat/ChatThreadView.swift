import SwiftUI

/**
 ПЕРЕПИСКА — ЭТАП 3.

 Два входа: из списка диалогов (номер диалога известен — сразу poll) и «Написать» из карточки объявления (диалога
 может ещё не быть — open создаёт его по продавцу и объявлению). Новые сообщения — опросом раз в три секунды, пока
 экран открыт: dm.php отдаёт снимок мгновенно, отдельного канала для приложения у сайта нет.

 🔴 ОТПРАВКА ЗА РУБИЛЬНИКОМ (Config.нативныйЧатОтправка). Пока не проверено, что dm.php принимает запись с куками
 веб-сессии и CSRF-токеном страницы, вместо поля ввода — «Ответить на сайте»: переписку видно здесь, ответ пишется
 там, где он точно дойдёт. Сообщение, которое молча не ушло, хуже, чем лишнее нажатие.
 */
@MainActor
final class ChatThreadModel: ObservableObject {
    @Published private(set) var сообщения: [ЧатСообщение] = []
    @Published private(set) var загружено = false
    @Published private(set) var ошибка: ChatAPI.Ошибка?
    @Published private(set) var заблокирован = false
    @Published private(set) var отправляем = false
    @Published private(set) var неОтправлено = false
    /// Почему не ушло — коротко, под ошибкой: на проверке отправки (владелец 25.09.2026) это сразу скажет, что именно
    /// ответил сайт, а не только «не отправлено».
    @Published private(set) var причина = ""
    @Published var черновик = ""

    private(set) var tid: String
    private let собеседник: String
    private let объявление: String

    /// Переписка на сайте — туда ведут пуши о новых сообщениях (AppDelegate).
    static var адресПереписки: URL? { Config.url("/cabinet.php?s=messages") }

    init(tid: String = "", собеседник: String = "", объявление: String = "") {
        self.tid = tid
        self.собеседник = собеседник
        self.объявление = объявление
    }

    /// Диалог можно открыть нативно: он уже есть, или его можно создать (для создания нужна запись).
    var можноОткрыть: Bool { !tid.isEmpty || Config.нативныйЧатОтправка }

    func начать() async {
        do {
            if tid.isEmpty {
                let (переписка, блок) = try await ChatAPI.открыть(собеседник: собеседник, объявление: объявление)
                применить(переписка, блок)
            } else {
                let (переписка, блок) = try await ChatAPI.переписка(tid)
                применить(переписка, блок)
            }
            ошибка = nil
        } catch let e as ChatAPI.Ошибка {
            ошибка = e
        } catch {
            ошибка = .сеть
        }
        загружено = true
    }

    /// Опрос новых сообщений, пока экран открыт (задача .task отменяется при уходе с экрана).
    func опрос() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, !tid.isEmpty else { continue }
            if let снимок = try? await ChatAPI.переписка(tid) { применить(снимок.0, снимок.заблокирован) }
        }
    }

    func отправить() async {
        let текст = черновик.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Config.нативныйЧатОтправка, !текст.isEmpty, !tid.isEmpty, !отправляем else { return }
        отправляем = true
        неОтправлено = false
        let было = черновик
        черновик = ""
        defer { отправляем = false }
        do {
            if let переписка = try await ChatAPI.написать(tid: tid, текст: текст) {
                применить(переписка, заблокирован)
            } else {
                /* ok, но переписки в ответе нет — дотянем опросом, а не будем гадать. */
                if let снимок = try? await ChatAPI.переписка(tid) { применить(снимок.0, снимок.заблокирован) }
            }
        } catch {
            черновик = было
            неОтправлено = true
            причина = Self.код(error)
        }
    }

    private static func код(_ ошибка: Error) -> String {
        guard let e = ошибка as? ChatAPI.Ошибка else { return "?" }
        switch e {
        case .сеть:            return "network"
        case .нуженВход:       return "auth/csrf"
        case .статус(let к):   return "HTTP \(к)"
        case .разбор:          return "format"
        case .отказ(let п):    return п.isEmpty ? "refused" : п
        }
    }

    private func применить(_ переписка: ЧатПереписка?, _ блок: Bool) {
        заблокирован = блок
        guard let переписка else { return }
        if !переписка.id.isEmpty { tid = переписка.id }
        if переписка.сообщения != сообщения { сообщения = переписка.сообщения }
    }
}

struct ChatThreadView: View {
    @StateObject private var модель: ChatThreadModel
    let заголовок: String
    let открыть: (URL) -> Void

    init(модель: @autoclosure @escaping () -> ChatThreadModel, заголовок: String, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: модель())
        self.заголовок = заголовок
        self.открыть = открыть
    }

    var body: some View {
        VStack(spacing: 0) {
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
            } else if модель.ошибка != nil && модель.сообщения.isEmpty {
                ContentUnavailableView {
                    Label(ChatText.т("failed"), systemImage: "exclamationmark.bubble")
                } actions: {
                    Button(ChatText.т("retry")) { Task { await модель.начать() } }
                    Button(ChatText.т("open_site")) { if let u = ChatThreadModel.адресПереписки { открыть(u) } }
                }
            } else {
                лента
            }
            if модель.загружено && модель.ошибка != .нуженВход { низ }
        }
        .background(Color(.systemBackground))
        .navigationTitle(заголовок.isEmpty ? ChatText.т("peer") : заголовок)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await модель.начать()
            await модель.опрос()
        }
        /* Этап 16: переписка на экране — просьба оценить её не перебивает (ПросьбаОценить). */
        .onAppear { ПросьбаОценить.shared.делоНаЭкране() }
        .onDisappear { ПросьбаОценить.shared.делоУшло(карточка: false) }
    }

    private var лента: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if модель.сообщения.isEmpty {
                        Text(ChatText.т("first"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(модель.сообщения) { с in пузырь(с).id(с.id) }
                    Color.clear.frame(height: 1).id("низ")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: модель.сообщения.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
            }
            .onAppear { прокрутка.scrollTo("низ", anchor: .bottom) }
        }
    }

    private func пузырь(_ с: ЧатСообщение) -> some View {
        HStack {
            if с.моё { Spacer(minLength: 48) }
            VStack(alignment: с.моё ? .trailing : .leading, spacing: 3) {
                if let фото = с.фото {
                    AsyncImage(url: фото) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Text(с.подпись)
                        .font(.body)
                        .foregroundStyle(с.моё ? Color.white : Color.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(с.моё ? Theme.green : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                let время = ЧатВремя.время(с.когда)
                if !время.isEmpty {
                    Text(время)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            if !с.моё { Spacer(minLength: 48) }
        }
        /* Этап 11: VoiceOver — одной фразой «Вы: …» или «<собеседник>: …» со временем, а не текст и время порознь. */
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(с.голос(собеседник: заголовок))
    }

    @ViewBuilder
    private var низ: some View {
        if модель.заблокирован {
            Text(ChatText.т("blocked"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.regularMaterial)
        } else if Config.нативныйЧатОтправка {
            VStack(spacing: 4) {
                if модель.неОтправлено {
                    Text(ChatText.т("not_sent") + (модель.причина.isEmpty ? "" : " (\(модель.причина))"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(ChatText.т("placeholder"), text: $модель.черновик, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button { Task { await модель.отправить() } } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(можноОтправить ? Theme.green : Color.secondary)
                    }
                    .disabled(!можноОтправить)
                    .accessibilityLabel(ChatText.т("send"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        } else {
            Button {
                if let u = ChatThreadModel.адресПереписки { открыть(u) }
            } label: {
                Label(ChatText.т("reply_site"), systemImage: "arrowshape.turn.up.left.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(Theme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var можноОтправить: Bool {
        !модель.отправляем && !модель.черновик.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
