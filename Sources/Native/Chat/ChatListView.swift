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
    /// Сколько раз список сверился с сайтом: пришёл ответ или «нужен вход». По нему вкладки ставят число на иконку
    /// приложения (этап 11) — после каждой сверки, даже если число то же: пуш сайта мог поставить на иконку своё.
    @Published private(set) var сверка = 0
    /// Этап 38: лиды — чаты по моим объявлениям (chat.php?action=leads, Config.чатОбъявления). Их непрочитанные входят в
    /// число на «Чате» рядом с dm.php list, как ulxBBChatBadge нижней панели сайта.
    @Published private(set) var лиды: [ЧатОбъявленияAPI.Лид] = []

    /// Этап 45: единый инбокс кабинета (dm.php list + chat.php leads + buyer_chats, склейка сайта) — непрочитанные
    /// его строк без корзины. Считает ИнбоксМодель; здесь — для числа на вкладке и иконке.
    @Published private(set) var непрочитаноИнбокса = 0

    func загрузить() async {
        грузим = true
        defer { грузим = false }
        /* Этап 45 (Config.нативныеСообщенияКабинета): список — единый инбокс кабинета, три источника сайта изнутри его
           страницы. Не ответил ни один — прежний путь этапа 3 не нужен: ошибка та же. */
        if Config.нативныеСообщенияКабинета {
            await загрузитьИнбокс()
            загружено = true
            return
        }
        do {
            let новые = try await ChatAPI.диалоги()
            /* Этап 38: лиды — до отметки сверки: число на иконку (этап 11) ставится по ней и должно быть уже общим. */
            await загрузитьЛиды()
            диалоги = новые
            ошибка = nil
            сверка += 1
        } catch let e as ChatAPI.Ошибка {
            if !Task.isCancelled {
                ошибка = e
                /* Вышел из аккаунта — диалоги ушедшего не держим: их непрочитанные остались бы на вкладке и на иконке.
                   Этап 38: и его лиды — гостю leads не спрашиваем. */
                if e == .нуженВход {
                    диалоги = []
                    лиды = []
                    сверка += 1
                }
            }
        } catch {
            if !Task.isCancelled { ошибка = .сеть }
        }
        загружено = true
    }

    /// Этап 45: инбокс — через ИнбоксМодель (она же держит строки экрана); здесь — ошибка, число и отметка сверки.
    private func загрузитьИнбокс() async {
        let итог = await ИнбоксМодель.shared.загрузить(ждать: false)
        guard !Task.isCancelled else { return }
        switch итог {
        case .готово:
            ошибка = nil
            непрочитаноИнбокса = ИнбоксМодель.shared.непрочитано
            сверка += 1
        case .нуженВход:
            ошибка = .нуженВход
            диалоги = []
            лиды = []
            непрочитаноИнбокса = 0
            сверка += 1
        case .сбой:
            if ИнбоксМодель.shared.строки.isEmpty { ошибка = .сеть }
        }
    }

    /// Этап 45: после действия в инбоксе (корзина, вернуть) — число на вкладке сразу, без нового запроса.
    func пересчитатьИнбокс() {
        непрочитаноИнбокса = ИнбоксМодель.shared.непрочитано
    }

    /// Этап 38: GET chat.php?action=leads. Нужен вход — лидов нет; не ответил — число остаётся прежним.
    private func загрузитьЛиды() async {
        guard Config.чатОбъявления && Config.нативныйЧат else {
            if !лиды.isEmpty { лиды = [] }
            return
        }
        switch await ЧатОбъявленияAPI.лиды() {
        case .список(let новые):
            if новые != лиды { лиды = новые }
        case .нуженВход:
            if !лиды.isEmpty { лиды = [] }
        case .нет:
            break
        }
    }

    /// Непрочитанных во всех диалогах — счётчик на вкладке «Сообщения». Этап 38: плюс лиды. Один и тот же диалог сайт
    /// может отдать и в dm.php list (tid), и в leads (chat_id) — кабинет сайта склеивает их по номеру и берёт большее
    /// число, так же и здесь: диалог не считается дважды.
    var непрочитано: Int {
        /* Этап 45: у инбокса склейка уже сделана (один диалог из нескольких источников — одна строка, большее число). */
        if Config.нативныеСообщенияКабинета { return непрочитаноИнбокса }
        let вДиалогах = диалоги.reduce(0) { $0 + $1.непрочитано }
        return вДиалогах + непрочитаноЛидов
    }

    /// Этап 38: сколько непрочитанных добавляют лиды сверх диалогов dm.php — число на карточке «Покупатели».
    var непрочитаноЛидов: Int {
        guard Config.чатОбъявления, !лиды.isEmpty else { return 0 }
        var поНомеру: [String: Int] = [:]
        for д in диалоги { поНомеру[д.id] = д.непрочитано }
        var добавка = 0
        for лид in лиды {
            if !лид.id.isEmpty, let вДиалоге = поНомеру[лид.id] {
                добавка += max(0, лид.непрочитано - вДиалоге)
            } else {
                добавка += лид.непрочитано
            }
        }
        return добавка
    }
}

/// Список диалогов со своей моделью — для входа из шапки ленты, когда нижних вкладок нет.
struct ChatListScreen: View {
    @StateObject private var модель = ChatListModel()
    let открыть: (URL) -> Void
    var body: some View { ChatListView(модель: модель, открыть: открыть) }
}

struct ChatListView: View {
    /// Модель снаружи: вкладка «Сообщения» держит её и показывает счётчик непрочитанных.
    @ObservedObject var модель: ChatListModel
    /// Открыть страницу сайта (вход, переписка на сайте).
    let открыть: (URL) -> Void

    var body: some View {
        if Config.нативныеСообщенияКабинета {
            /* Этап 45: единый инбокс «Чат» кабинета — вкладки, поиск, корзина, закрепление, метки. */
            ИнбоксЭкран(список: модель, открыть: открыть)
        } else if Config.дизайнКакНаСайте {
            видСайта
        } else {
            видПрежний
        }
    }

    // MARK: - Как на сайте (этап 30)

    /// Диалоги — карточками сайта на фоне страницы; пусто, вход и ошибка — экраном ПустоСайта.
    private var видСайта: some View {
        Group {
            if !модель.загружено {
                ProgressView()
                    .tint(Theme.акцент)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if модель.ошибка == .нуженВход {
                ПустоСайта(значок: "person.crop.circle.badge.questionmark", заголовок: ChatText.т("login"),
                           подпись: ChatText.т("login_sub"), кнопка: ChatText.т("login_btn"),
                           действие: { if let u = Config.url("/cabinet.php") { открыть(u) } })
            } else if модель.ошибка != nil && модель.диалоги.isEmpty {
                ПустоСайта(значок: "exclamationmark.bubble", заголовок: ChatText.т("failed"),
                           кнопка: ChatText.т("retry"), действие: { Task { await модель.загрузить() } },
                           вторая: ChatText.т("open_site"),
                           второеДействие: { if let u = ChatThreadModel.адресПереписки { открыть(u) } })
            } else if модель.диалоги.isEmpty && модель.непрочитаноЛидов == 0 {
                ПустоСайта(значок: "bubble.left.and.bubble.right", заголовок: ChatText.т("empty"),
                           подпись: ChatText.т("empty_sub"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        /* Этап 38: непрочитанные чаты по моим объявлениям — в числе на вкладке; открыть их — в кабинете сайта. */
                        if модель.непрочитаноЛидов > 0 {
                            КарточкаЛидовЧата(непрочитано: модель.непрочитаноЛидов) {
                                if let u = ChatThreadModel.адресПереписки { открыть(u) }
                            }
                        }
                        ForEach(модель.диалоги) { д in
                            NavigationLink(value: ЧатЦель.диалог(д)) { СтрокаДиалогаСайта(диалог: д) }
                                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.фонСтраницы)
        .шапкаЭкранаСайта(ChatText.т("title"))
        .refreshable { await модель.загрузить() }
        .task { await модель.загрузить() }
    }

    // MARK: - Прежний вид (этапы 3–29)

    private var видПрежний: some View {
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
                            .accessibilityLabel(String(format: AccessText.т("unread"), д.непрочитано))   // этап 11
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func обложка(_ д: ЧатДиалог) -> some View {
        Group {
            if let адрес = ИнбоксКартинка.адрес(д.обложка) {
                /* Сборка 35: AsyncImage после отмены перерисовкой оставался заглушкой — КартинкиЛенты повторяет. */
                КартинкаЛенты(адрес, пунктов: 48) {
                    Theme.mint
                }
                /* Владелец 25.09.2026, проверка на телефоне, сборка 33: этот ряд и был в сборке 33 — широкие фото
                   вылезали за край экрана и на имя. Обрезка шла по размеру самой картинки после scaledToFill, а не по
                   ячейке 48×48; .frame у Group ниже не режет. Сначала рамка, потом обрезка. */
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Circle()
                    .fill(Theme.mint)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.green))
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)          // этап 11: обложка — украшение, объявление названо строкой ниже
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
    /// Этап 38: чат по объявлению (chat.php — Kliko AI-ассистент и продавец), как у страницы объявления сайта.
    /// предложить — открыт кнопкой «Предложить цену»: после загрузки сразу окно предложения (mkOfferOpen).
    case объявление(Listing, предложить: Bool)
    /// Этап 45: строка инбокса — личная переписка dm.php, открытая как openDM сайта: open с tid (диалог или chat_id
    /// покупки), собеседником и объявлением.
    case переписка(номер: String, собеседник: String, имя: String, объявление: String)
    /// Этап 45: чат по лиду — мой товар, пишет покупатель (chat.php seller_chat, #lead-chat-modal кабинета).
    case лид(номер: String, имя: String)
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

/// Экраны чата в стеке навигации — один набор и для ленты, и для вкладки «Сообщения».
extension View {
    func чатМаршруты(открыть: @escaping (URL) -> Void) -> some View {
        navigationDestination(for: ЧатЦель.self) { цель in
            switch цель {
            case .список:
                ChatListScreen(открыть: открыть)
            case .диалог(let д):
                ChatThreadView(модель: ChatThreadModel(tid: д.id), заголовок: д.собеседник, открыть: открыть)
            case .продавец(let id, let имя, let объявление):
                ChatThreadView(модель: ChatThreadModel(собеседник: id, объявление: объявление),
                               заголовок: имя, открыть: открыть)
            case .объявление(let товар, let предложить):
                ЭкранЧатаОбъявления(товар: товар, предложить: предложить, открыть: открыть)
            case .переписка(let номер, let собеседник, let имя, let объявление):
                ChatThreadView(модель: ChatThreadModel(собеседник: собеседник, объявление: объявление,
                                                       номерОткрытия: номер),
                               заголовок: имя, открыть: открыть)
            case .лид(let номер, let имя):
                ЭкранЛида(номер: номер, имя: имя, открыть: открыть)
            }
        }
    }
}
