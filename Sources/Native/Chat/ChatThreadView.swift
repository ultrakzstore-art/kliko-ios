import SwiftUI

/**
 ПЕРЕПИСКА — ЭТАП 3.

 Два входа: из списка диалогов (номер диалога известен — сразу poll) и «Написать» из карточки объявления (диалога
 может ещё не быть — open создаёт его по продавцу и объявлению). Новые сообщения — опросом раз в три секунды, пока
 экран открыт: dm.php отдаёт снимок мгновенно, отдельного канала для приложения у сайта нет.

 🔴 ОТПРАВКА ЗА РУБИЛЬНИКОМ (Config.нативныйЧатОтправка). Пока не проверено, что dm.php принимает запись с куками
 веб-сессии и CSRF-токеном страницы, вместо поля ввода — «Ответить на сайте»: переписку видно здесь, ответ пишется
 там, где он точно дойдёт. Сообщение, которое молча не ушло, хуже, чем лишнее нажатие.

 Этап 17 (Config.удобныйЧат): черновик по диалогу (ChatDrafts.swift), кнопка «вниз», «Копировать» и «потяни —
 обновится» (ChatComfort.swift). Опрос — прежний.
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
    @Published var черновик = "" {
        /* Этап 17: недописанное — в черновик диалога (ЧерновикиЧата). Пока сообщение уходит, поле уже пустое, но
           сохранённый черновик не трогаем: сотрёт его отправить(), когда сайт примет сообщение. */
        didSet {
            guard Config.удобныйЧат, !отправляем, черновик != oldValue else { return }
            ЧерновикиЧата.shared.запомнить(черновик, для: tid)
        }
    }

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
        сверитьЧерновик()
        загружено = true
    }

    /// Этап 17: номер диалога известен — в пустое поле возвращаем его черновик, а написанное, пока номера не было
    /// (open не прошёл, человек начал писать), кладём под этот номер. «Нужен вход» — не трогаем: переписка могла
    /// пережить в стеке вкладки выход из аккаунта, и её текст в памяти вернул бы на диск стёртый черновик ушедшего.
    private func сверитьЧерновик() {
        guard Config.удобныйЧат, !tid.isEmpty, ошибка != .нуженВход else { return }
        if черновик.isEmpty {
            if let сохранённый = ЧерновикиЧата.shared.черновик(tid) { черновик = сохранённый }
        } else {
            ЧерновикиЧата.shared.запомнить(черновик, для: tid)
        }
    }

    /// Этап 17: «потяни — обновится» — один внеочередной опрос. Не прошёл — молча, как и обычный опрос: на экране
    /// остаётся пришедшее, а через три секунды опрос попробует снова. Номера диалога нет — опрашивать нечего.
    func обновить() async {
        guard !tid.isEmpty else { return }
        if let снимок = try? await ChatAPI.переписка(tid) {
            применить(снимок.0, снимок.заблокирован)
            ошибка = nil
        }
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
        defer {
            отправляем = false
            /* Этап 17: ушло — поле пустое, и черновик диалога стирается; не ушло — в поле вернулся текст, он и остаётся
               черновиком. Написанное, пока сообщение уходило, тоже сохраняется. */
            if Config.удобныйЧат { ЧерновикиЧата.shared.запомнить(черновик, для: tid) }
        }
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
    /// Этап 17: отметка низа переписки на экране. Знает об этом только ленивый стек (onAppear/onDisappear отметки):
    /// onScrollGeometryChange — лишь с iOS 18.
    @State private var низВиден = true
    /// Кнопка «вниз» — когда низа нет на экране дольше 0,3 с. Сразу нельзя: новое сообщение на миг выталкивает отметку
    /// за край, пока лента доезжает вниз, и кнопка мигала бы. По ней же решаем, ехать ли вниз с новым сообщением.
    @State private var кнопкаВниз = false
    /// Сколько сообщений собеседника пришло, пока человек читал выше.
    @State private var новыхНиже = 0
    /// Поле ввода в фокусе (исправление после ревью этапа 17, владелец 25.09.2026). 🔴 Клавиатура сжимает ленту, и
    /// отметка низа уходит за край — без этого «человек читает выше» включалось само, и ответ собеседника, пока
    /// человек пишет, оставался числом на кнопке. Пишет — значит, он в конце переписки: туда и едем.
    @FocusState private var полеВФокусе: Bool
    /// Поле только что получило фокус, клавиатура ещё выезжает: пропавшая отметка низа — её работа, кнопку не показываем.
    @State private var клавиатураЕдет = false

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
        .background(Config.дизайнКакНаСайте ? Theme.поверхность : Color(.systemBackground))
        .navigationTitle(заголовок.isEmpty ? ChatText.т("peer") : заголовок)
        .navigationBarTitleDisplayMode(.inline)
        /* Этап 30: панель как .kc-head сайта — кружок с буквой и имя, поверхность вместо стекла. */
        .toolbar {
            if Config.дизайнКакНаСайте {
                ToolbarItem(placement: .principal) {
                    ШапкаПерепискиСайта(имя: заголовок.isEmpty ? ChatText.т("peer") : заголовок)
                }
            }
        }
        .toolbarBackground(Config.дизайнКакНаСайте ? Visibility.visible : Visibility.automatic, for: .navigationBar)
        .toolbarBackground(Config.дизайнКакНаСайте ? AnyShapeStyle(Theme.поверхность) : AnyShapeStyle(Material.bar),
                           for: .navigationBar)
        .tint(Config.дизайнКакНаСайте ? Theme.акцент : Theme.green)
        .task {
            await модель.начать()
            await модель.опрос()
        }
        /* Этап 16: переписка на экране — просьба оценить её не перебивает (ПросьбаОценить). */
        .onAppear { ПросьбаОценить.shared.делоНаЭкране() }
        .onDisappear {
            ПросьбаОценить.shared.делоУшло(карточка: false)
            /* Этап 17: ушли из переписки — черновик на диск сейчас, не дожидаясь паузы после последней буквы. */
            if Config.удобныйЧат { ЧерновикиЧата.shared.сохранитьСейчас() }
        }
    }

    private var лента: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if модель.сообщения.isEmpty {
                        if Config.дизайнКакНаСайте {
                            /* Этап 30: системная строка .kc-sys — по центру, серым на --kc-soft. С исправлений с
                               телефона (сборка 33) — та же строка, что у уведомлений сервера. */
                            УведомлениеЧатаСайта(текст: ChatText.т("first"))
                                .padding(.top, 40)
                        } else {
                            Text(ChatText.т("first"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }
                    ForEach(модель.сообщения) { с in пузырь(с).id(с.id) }
                    Color.clear.frame(height: 1).id("низ")
                        .onAppear { низВиден = true }
                        .onDisappear { низВиден = false }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .modifier(ОбновлениеПереписки(модель: модель))          // этап 17: «потяни — обновится»
            .overlay(alignment: .bottomTrailing) {
                if Config.удобныйЧат && кнопкаВниз {
                    КнопкаВнизЧата(новых: новыхНиже) { вниз(прокрутка) }
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .onChange(of: модель.сообщения.count) { было, стало in
                пришли(было: было, стало: стало, прокрутка)
            }
            .onChange(of: полеВФокусе) { _, вФокусе in
                if вФокусе { полеПолучилоФокус(прокрутка) }
            }
            .onAppear { прокрутка.scrollTo("низ", anchor: .bottom) }
            .task(id: низВиден) { await следитьЗаНизом() }
        }
    }

    /// Пришли сообщения. Человек внизу, пишет (поле в фокусе) или последнее — его собственное (только что отправил) —
    /// едем вниз, как раньше. Этап 17: читает выше — экран не дёргаем, а на кнопку «вниз» ставим, сколько пришло от
    /// собеседника.
    private func пришли(было: Int, стало: Int, _ прокрутка: ScrollViewProxy) {
        /* Владелец 25.09.2026, проверка на телефоне, сборка 33: уведомление сервера приходит с автором того, кто его
           вызвал. «Покупатель отозвал…» с mine = true не считаем своим сообщением (оно дёргало бы экран вниз), а
           уведомления со стороны собеседника — новыми сообщениями на кнопке «вниз». */
        let своё = модель.сообщения.last.map { $0.моё && !$0.системное } ?? false
        if Config.удобныйЧат && кнопкаВниз && !своё && !полеВФокусе {
            новыхНиже += модель.сообщения.suffix(max(0, стало - было)).filter { !$0.моё && !$0.системное }.count
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
    }

    /// Поле ввода получило фокус — вниз, когда клавиатура доедет и лента уже сжата: раньше прокручивать нечего, сжатие
    /// оставляет прокрутку от верха, и низ всё равно ушёл бы под клавиатуру. Пока едет — кнопку «вниз» не показываем;
    /// клавиатуру успели убрать, а низа на экране нет — кнопка, как обычно.
    private func полеПолучилоФокус(_ прокрутка: ScrollViewProxy) {
        guard Config.удобныйЧат else { return }
        новыхНиже = 0
        клавиатураЕдет = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            клавиатураЕдет = false
            if полеВФокусе {
                withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
            } else if !низВиден {
                withAnimation(.easeOut(duration: 0.2)) { кнопкаВниз = true }
            }
        }
    }

    /// Этап 17: кнопка «вниз» нажата.
    private func вниз(_ прокрутка: ScrollViewProxy) {
        новыхНиже = 0
        withAnimation(.easeOut(duration: 0.25)) { прокрутка.scrollTo("низ", anchor: .bottom) }
    }

    /// Этап 17: низ вернулся — кнопку прячем, число сбрасываем. Пропал — кнопка через 0,3 с, если он не вернулся:
    /// смена низВиден отменяет эту задачу (.task(id:)).
    private func следитьЗаНизом() async {
        guard Config.удобныйЧат else { return }
        if низВиден {
            новыхНиже = 0
            if кнопкаВниз { withAnimation(.easeOut(duration: 0.2)) { кнопкаВниз = false } }
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, !низВиден, !клавиатураЕдет else { return }
        withAnimation(.easeOut(duration: 0.2)) { кнопкаВниз = true }
    }

    /// Строка переписки: служебное уведомление — по центру без облака, остальное — облаком своей стороны.
    @ViewBuilder
    private func пузырь(_ с: ЧатСообщение) -> some View {
        if с.системное {
            уведомление(с)
        } else {
            сообщениеЧеловека(с)
        }
    }

    /// Владелец 25.09.2026, проверка на телефоне, сборка 33: «Продавец вышел из чата» было серым облаком собеседника
    /// с «Копировать». У сайта уведомления — строка .kc-sys по центру: без стороны, без времени, без меню. Голосом —
    /// один текст, без «Вы:» и имени.
    private func уведомление(_ с: ЧатСообщение) -> some View {
        Group {
            if Config.дизайнКакНаСайте {
                УведомлениеЧатаСайта(текст: с.текст)
            } else {
                Text(с.текст)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(с.голос(собеседник: заголовок))
    }

    private func сообщениеЧеловека(_ с: ЧатСообщение) -> some View {
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
                } else if Config.удобныйЧат && с.копируемое {
                    /* Этап 17: «Копировать» меню долгого нажатия вместо выделения текста — оба висят на долгом
                       нажатии и мешали бы друг другу. */
                    облако(с)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button {
                                ЧатБуфер.скопировать(с.текст)
                            } label: {
                                Label(ChatComfortText.т("copy"), systemImage: "doc.on.doc")
                            }
                        }
                } else if Config.удобныйЧат {
                    облако(с)
                } else {
                    облако(с).textSelection(.enabled)
                }
                let время = ЧатВремя.время(с.когда)
                /* Этап 30: у сайта время — внутри облака (.kc-time); под облаком — только у фото. */
                if !время.isEmpty && (!Config.дизайнКакНаСайте || с.фото != nil) {
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
        .modifier(КопироватьДляГолоса(текст: Config.удобныйЧат && с.копируемое ? с.текст : nil))   // этап 17
    }

    /// Текст сообщения в облачке. Этап 30: облако сайта (.kc-msg) — со временем внутри и краской чата сайта.
    @ViewBuilder
    private func облако(_ с: ЧатСообщение) -> some View {
        if Config.дизайнКакНаСайте {
            ОблакоСайта(текст: с.подпись, время: ЧатВремя.время(с.когда), моё: с.моё)
        } else {
            облакоПрежнее(с)
        }
    }

    private func облакоПрежнее(_ с: ЧатСообщение) -> some View {
        Text(с.подпись)
            .font(.body)
            .foregroundStyle(с.моё ? Color.white : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(с.моё ? Theme.green : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var низ: some View {
        if модель.заблокирован && Config.дизайнКакНаСайте {
            /* Этап 30: .kc-blocked — серый текст на --kc-soft с линией сверху. */
            Text(ChatText.т("blocked"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Theme.поверхность2)
                .overlay(alignment: .top) { Theme.линия.frame(height: 1) }
        } else if модель.заблокирован {
            Text(ChatText.т("blocked"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.regularMaterial)
        } else if Config.нативныйЧатОтправка && Config.дизайнКакНаСайте {
            /* Этап 30: строка ввода .kc-bar сайта. */
            VStack(spacing: 0) {
                if модель.неОтправлено {
                    Text(ChatText.т("not_sent") + (модель.причина.isEmpty ? "" : " (\(модель.причина))"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.малиновый)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.поверхность)
                }
                ПолеПерепискиСайта(текст: $модель.черновик, можно: можноОтправить,
                                   отправить: { Task { await модель.отправить() } }, фокус: $полеВФокусе)
            }
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
                        .focused($полеВФокусе)
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
