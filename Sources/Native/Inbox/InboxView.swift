import SwiftUI
import UIKit

/**
 ЕДИНЫЙ ИНБОКС «ЧАТ» — ЭКРАН, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»;
 Config.нативныеСообщенияКабинета).

 #messages-screen кабинета сайта сверху вниз: подзаголовок «Переписка, аренда и обмен — в одном месте», поле поиска и
 кнопка «Корзина», вкладки «Все / Покупатели / Аренда / Обмен» со счётчиками, в корзине — полоса «Удалённые переписки
 хранятся у поддержки 12 месяцев. Запросить данные у поддержки →», строки (.msg-row: аватар или фото товара, имя, время,
 значок статуса объявления, раздел, подпись, «с какого числа», теги, превью, счётчик) и меню «⋯» строки: «Закрепить /
 Открепить», «Убрать в корзину»; в корзине — «Вернуть», «Удалить навсегда» (после вопроса сайта).
 Нажатие строки: диалог и покупка — переписка dm.php (ChatThreadView через open с tid), лид — чат по лиду (ЭкранЛида).
 Живёт во вкладке «Сообщения» и в списке из шапки ленты — вместо списка этапов 3 и 38.
 */
struct ИнбоксЭкран: View {
    @ObservedObject var список: ChatListModel
    let открыть: (URL) -> Void

    @ObservedObject private var модель = ИнбоксМодель.shared
    @State private var входОткрыт = false
    @State private var запросДанных = false
    @State private var удалить: СтрокаИнбокса? = nil
    /// .msg-search input:focus — кромка --acc-on.
    @FocusState private var поискВФокусе: Bool

    init(список: ChatListModel, открыть: @escaping (URL) -> Void) {
        self.список = список
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ИнбоксКраска.фон)
            /* Заголовок «Чат» у сайта один — крупный h2 в содержимом; в панели только «Назад» (название остаётся
               навигационным для VoiceOver и «Назад» следующего экрана). */
            .navigationTitle(т("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            .toolbarBackground(ИнбоксКраска.фон, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Theme.акцент)
            .refreshable { await список.загрузить() }
            /* Возвращаемся из переписки — непрочитанные должны погаснуть: перечитываем при каждом показе. */
            .task { await загрузитьНаЭкране() }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await список.загрузить() }
                })
            }
            .sheet(isPresented: $запросДанных) {
                ОкноЗапросаДанных()
            }
            .confirmationDialog(т("purge"), isPresented: вопросУдаления, titleVisibility: .visible,
                                presenting: удалить) { строка in
                Button(т("purge"), role: .destructive) {
                    Task {
                        await модель.удалитьНавсегда(строка)
                        список.пересчитатьИнбокс()
                    }
                }
                Button(т("cancel"), role: .cancel) {}
            } message: { _ in
                Text(т("purge_q"))
            }
            .overlay(alignment: .bottom) { ПлашкаИнбокса(текст: модель.плашка) }
    }

    /// Первый показ ждёт страницу под слоем (человек сам открыл «Чат»), остальные — как опрос числа.
    private func загрузитьНаЭкране() async {
        if модель.загружено {
            await список.загрузить()
        } else {
            _ = await модель.загрузить(ждать: true)
            список.пересчитатьИнбокс()
        }
    }

    private var вопросУдаления: Binding<Bool> {
        Binding(get: { удалить != nil }, set: { показан in
            if !показан { удалить = nil }
        })
    }

    @ViewBuilder
    private var содержимое: some View {
        if модель.нуженВход {
            ПустоСайта(значок: "person.crop.circle.badge.questionmark", заголовок: ChatText.т("login"),
                       подпись: ChatText.т("login_sub"), кнопка: ChatText.т("login_btn"),
                       действие: { войти() })
        } else if модель.ошибка && модель.строки.isEmpty {
            ПустоСайта(значок: "exclamationmark.bubble", заголовок: т("err_load"),
                       кнопка: ChatText.т("retry"), действие: { Task { await список.загрузить() } })
        } else {
            лента
        }
    }

    /// #messages-screen: .wrap 14 по краям и сверху; шапка, инструменты и вкладки — с отступом снизу, строки — через 10.
    /// Пока список не пришёл, шапка, поиск и вкладки уже на месте, вместо строк — «Загрузка…» (как у сайта).
    private var лента: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                заголовок
                    .padding(.bottom, 14)
                инструменты
                    .padding(.bottom, 12)
                ВкладкиИнбокса(модель: модель)
                    .padding(.bottom, 12)
                if модель.фильтр == .trash {
                    полосаКорзины
                        .padding(.bottom, 12)
                }
                if модель.загружено {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        строки
                    }
                } else {
                    Text(т("loading"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Верх #messages-screen: значок чата и «Чат» крупно, под ними chat_sub «Переписка, аренда и обмен — в одном месте».
    private var заголовок: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 21, height: 21)
                    .foregroundStyle(ИнбоксКраска.акцент)
                    .accessibilityHidden(true)
                Text(т("title"))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(т("sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// .msg-tools: поле поиска и «Корзина».
    private var инструменты: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 17)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                TextField(т("search_ph"), text: $модель.поиск)
                    .font(.system(size: 16))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .focused($поискВФокусе)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel(т("search_ph"))
                if !модель.поиск.isEmpty {
                    Button {
                        модель.поиск = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.текстВторой)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(т("clear"))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(поискВФокусе ? ИнбоксКраска.акцент : ИнбоксКраска.линия, lineWidth: 1)
            }
            кнопкаКорзины
        }
    }

    private var кнопкаКорзины: some View {
        let включена = модель.фильтр == .trash
        return Button {
            модель.выбрать(.trash)
        } label: {
            /* .msg-trash на телефоне (до 480 px) — только значок 44×44, подпись .msg-trash-t скрыта; включённая —
               на --tint-bad с кромкой --edge-bad, значок --on-bad. Нажатие только переключает вид на корзину. */
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
                .foregroundStyle(включена ? ИнбоксКраска.плохоТекст : Theme.текстВторой)
                .frame(width: 44, height: 44)
                .background(включена ? ИнбоксКраска.плохоФон : ИнбоксКраска.карточка,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(включена ? ИнбоксКраска.плохоКромка : ИнбоксКраска.линия, lineWidth: 1)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .accessibilityLabel(т("trash"))
        .accessibilityAddTraits(включена ? .isSelected : [])
    }

    /// .msg-trashbar: срок хранения и «Запросить данные у поддержки →» (dataReqOpen('')).
    /// Ссылка — в том же абзаце, что и срок (у сайта <a> внутри текста), жирная акцентом, без переноса.
    private var полосаКорзины: some View {
        let срок = Text(т("retention") + " ")
        let ссылка = Text(т("request_data") + "\u{00A0}→")
            .fontWeight(.bold)
            .foregroundColor(ИнбоксКраска.акцент)
        return Button {
            запросДанных = true
        } label: {
            (срок + ссылка)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ИнбоксКраска.подложка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var строки: some View {
        let видимые = модель.видимые
        if видимые.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 36, weight: .regular))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(т(модель.фильтр == .trash ? "trash_empty" : "empty"))
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 20)
        } else {
            ForEach(видимые) { строка in
                СтрокаИнбоксаВид(строка: строка,
                                 закреплена: модель.фильтр != .trash && модель.закреплена(строка),
                                 отрывок: модель.отрывок(строка),
                                 вКорзине: модель.фильтр == .trash,
                                 занята: модель.занято.contains(строка.номер),
                                 действие: { д in выполнить(д, строка) })
            }
        }
    }

    private func выполнить(_ действие: СтрокаИнбоксаВид.Действие, _ строка: СтрокаИнбокса) {
        switch действие {
        case .закрепить:
            Task { await модель.закрепить(строка) }
        case .вКорзину:
            Task {
                await модель.вКорзину(строка, вернуть: false)
                список.пересчитатьИнбокс()
            }
        case .вернуть:
            Task {
                await модель.вКорзину(строка, вернуть: true)
                список.пересчитатьИнбокс()
            }
        case .удалить:
            удалить = строка
        }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let адрес = Config.страницаСайта("cabinet.php") {
            открыть(адрес)
        }
    }
}

// MARK: - Вкладки

/// #msg-filters: четыре вкладки на подложке, выбранная — белая карточка; счётчик — зелёная пилюля. В корзине вкладки
/// гаснут (.msg-tabs.off), нажатие любой возвращает к ней.
struct ВкладкиИнбокса: View {
    @ObservedObject var модель: ИнбоксМодель

    var body: some View {
        РядВкладокИнбокса(промежуток: 4) {
            ForEach(ИнбоксМодель.Фильтр.вкладки, id: \.self) { ф in
                кнопка(ф)
            }
        }
        .padding(4)
        .background(ИнбоксКраска.подложка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private func кнопка(_ ф: ИнбоксМодель.Фильтр) -> some View {
        let выбрана = модель.фильтр == ф
        let число = модель.счётчик(ф)
        return Button {
            модель.выбрать(ф)
        } label: {
            HStack(spacing: 6) {
                Text(ф.название)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if число > 0 {
                    Text(число > 99 ? "99+" : String(число))
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(ИнбоксКраска.наАкценте)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(ИнбоксКраска.акцент, in: Capsule())
                }
            }
            .foregroundStyle(выбрана ? ИнбоксКраска.текст : Theme.текстВторой)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                if выбрана {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .fill(ИнбоксКраска.карточка)
                        .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(число > 0 ? ф.название + ", " + String(format: AccessText.т("unread"), число) : ф.название)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}

/// Ряд вкладок как flex: 1 1 auto у .msg-tab: каждая — своей ширины плюс равная доля остатка; не влезли — сжимаются
/// пропорционально своей ширине (текст обрежется, а не уменьшится).
struct РядВкладокИнбокса: Layout {
    var промежуток: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let размеры = subviews.map { $0.sizeThatFits(.unspecified) }
        let зазоры = промежуток * CGFloat(max(0, размеры.count - 1))
        let сумма = размеры.reduce(0) { $0 + $1.width } + зазоры
        let высота = размеры.map { $0.height }.max() ?? 0
        return CGSize(width: proposal.width ?? сумма, height: высота)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ширины = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard !ширины.isEmpty else { return }
        let зазоры = промежуток * CGFloat(ширины.count - 1)
        let сумма = ширины.reduce(0, +)
        let остаток = bounds.width - зазоры - сумма
        let доля = остаток / CGFloat(ширины.count)
        let сжатие = (bounds.width - зазоры) / max(сумма, 1)
        var x = bounds.minX
        for (место, вид) in subviews.enumerated() {
            let ширина = остаток >= 0 ? ширины[место] + доля : ширины[место] * сжатие
            вид.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: ширина, height: bounds.height))
            x += ширина + промежуток
        }
    }
}

/// Ряд колонок по долям — grid-template-columns: minmax(0,2fr) minmax(0,1fr) у кнопок торга (.kc-ofr-main, .mk-ofc-row):
/// ширина ряда делится по долям за вычетом промежутков, высота — у самой высокой.
struct РядДолейКабинета: Layout {
    var доли: [CGFloat] = [2, 1]
    var промежуток: CGFloat = 8

    private func ширины(_ всего: CGFloat, _ число: Int) -> [CGFloat] {
        let свои = (0..<число).map { $0 < доли.count ? доли[$0] : 1 }
        let сумма = max(свои.reduce(0, +), 0.001)
        let место = max(0, всего - промежуток * CGFloat(max(0, число - 1)))
        return свои.map { место * $0 / сумма }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let всего = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let ш = ширины(всего, subviews.count)
        var высота: CGFloat = 0
        for (место, вид) in subviews.enumerated() {
            высота = max(высота, вид.sizeThatFits(ProposedViewSize(width: ш[место], height: nil)).height)
        }
        return CGSize(width: всего, height: высота)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ш = ширины(bounds.width, subviews.count)
        var x = bounds.minX
        for (место, вид) in subviews.enumerated() {
            вид.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: ш[место], height: bounds.height))
            x += ш[место] + промежуток
        }
    }
}

// MARK: - Строка

/// .msg-row: карточка со скруглением 14; непрочитанная — на мятной подложке с зелёной кромкой.
struct СтрокаИнбоксаВид: View {
    enum Действие { case закрепить, вКорзину, вернуть, удалить }

    let строка: СтрокаИнбокса
    let закреплена: Bool
    let отрывок: String?
    let вКорзине: Bool
    let занята: Bool
    let действие: (Действие) -> Void

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    private var непрочитана: Bool { строка.непрочитано > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            NavigationLink(value: строка.цель) {
                HStack(alignment: .top, spacing: 12) {
                    АватарИнбокса(строка: строка)
                        .padding(.top, 2)
                    тело
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.985))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(голос)
            .accessibilityAddTraits(.isButton)
            меню
        }
        .padding(12)
        .frame(minHeight: 72, alignment: .top)
        .background(непрочитана ? ИнбоксКраска.окФон : ИнбоксКраска.карточка,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(непрочитана ? ИнбоксКраска.окКромка : ИнбоксКраска.линия, lineWidth: 1)
        }
        .opacity(занята ? 0.6 : 1)
    }

    private var тело: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if закреплена {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.акцент)
                        .accessibilityHidden(true)
                }
                Text(строка.имя)
                    .font(.system(size: 14, weight: непрочитана ? Font.Weight.heavy : Font.Weight.bold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(ИнбоксВремя.коротко(строка.когда))
                    .font(.system(size: 11, weight: непрочитана ? Font.Weight.bold : Font.Weight.regular))
                    .monospacedDigit()
                    .foregroundStyle(непрочитана ? ИнбоксКраска.акцент : Theme.текстВторой)
                    .lineLimit(1)
                    .fixedSize()
            }
            ПодстрокаИнбокса(строка: строка)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                превью
                Spacer(minLength: 4)
                if непрочитана {
                    Text(строка.непрочитано > 99 ? "99+" : String(строка.непрочитано))
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(ИнбоксКраска.наАкценте)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(ИнбоксКраска.акцент, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var превью: some View {
        if let отрывок {
            Text(отрывок)
                .font(.system(size: 13))
                .foregroundStyle(ИнбоксКраска.текст)
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                if let значок = строка.значокПревью {
                    Image(systemName: значок)
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text((строка.превьюМоё ? т("you") : "") + строка.превью)
                    .lineLimit(1)
            }
            .font(.system(size: 13))
            .foregroundStyle(непрочитана ? ИнбоксКраска.текст : Theme.текстВторой)
        }
    }

    /// .msg-more: «⋯» справа сверху строки.
    private var меню: some View {
        Menu {
            if вКорзине {
                Button {
                    действие(.вернуть)
                } label: {
                    Label(т("restore"), systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    действие(.удалить)
                } label: {
                    Label(т("purge"), systemImage: "trash.slash")
                }
            } else {
                Button {
                    действие(.закрепить)
                } label: {
                    Label(т(закреплена ? "unpin" : "pin"), systemImage: закреплена ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    действие(.вКорзину)
                } label: {
                    Label(т("trash_to"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .disabled(занята)
        .padding(.top, -4)
        .padding(.trailing, -4)
        .padding(.leading, 12)
        .accessibilityLabel(т("more"))
    }

    private var голос: String {
        var части: [String] = [строка.имя]
        if !строка.подпись.isEmpty { части.append(строка.подпись) }
        let превью = отрывок ?? ((строка.превьюМоё ? т("you") : "") + строка.превью)
        if !превью.isEmpty { части.append(превью) }
        let время = ИнбоксВремя.коротко(строка.когда)
        if !время.isEmpty { части.append(время) }
        if строка.непрочитано > 0 { части.append(String(format: AccessText.т("unread"), строка.непрочитано)) }
        if закреплена { части.append(т("pinned_a11y")) }
        return части.joined(separator: ", ")
    }
}

/// .msg-sub (_msgSubline): одна строка без переноса — сначала теги (.msg-tags: «Покупка», «Аренда», «Лид»…), потом
/// через «·» значок статуса объявления, раздел жирным в цвете раздела (meta.catColor), название объявления или состояние
/// лида и «с какого числа» с календариком (msg-since). Не влезло — строка обрезается по правому краю карточки, как
/// overflow:hidden у .msg-sub на сайте (название «Телевизор SAMSUNG» режется, дата уходит за край).
struct ПодстрокаИнбокса: View {
    let строка: СтрокаИнбокса

    /// Части после тегов — в порядке сайта (i.join('<span class="msg-dot">·</span>')).
    private enum Часть {
        case статус(ТегИнбокса)
        case раздел(String, Color?)
        case текст(String)
        case с(String)
    }

    private var части: [Часть] {
        var список: [Часть] = []
        if let статус = ТегИнбокса.статусОбъявления(строка.статусОбъявления) { список.append(.статус(статус)) }
        if !строка.раздел.isEmpty { список.append(.раздел(строка.раздел, ИнбоксКраска.цвет(строка.цветРаздела))) }
        if !строка.подпись.isEmpty { список.append(.текст(строка.подпись)) }
        let с = ИнбоксВремя.коротко(строка.начат)
        if !с.isEmpty { список.append(.с(с)) }
        return список
    }

    var body: some View {
        let теги = ТегИнбокса.для(строка)
        let части = self.части
        if !теги.isEmpty || !части.isEmpty {
            /* Ширина — у карточки (прозрачная подложка на всю ширину), сама строка — своей длины поверх неё слева и
               обрезана по подложке: как overflow:hidden у сайта, без многоточия и без распирания карточки. */
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .overlay(alignment: .leading) {
                    HStack(spacing: 6) {
                        if !теги.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(теги) { тег in тег }
                            }
                        }
                        ForEach(Array(части.enumerated()), id: \.offset) { пара in
                            if пара.offset > 0 {
                                Text("·")
                                    .opacity(0.5)
                                    .accessibilityHidden(true)
                            }
                            вид(пара.element)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .fixedSize()
                }
                .clipped()
        }
    }

    @ViewBuilder
    private func вид(_ часть: Часть) -> some View {
        switch часть {
        case .статус(let тег):
            тег
        case .раздел(let название, let цвет):
            Text(название)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(цвет ?? Theme.текстВторой)
                .lineLimit(1)
        case .текст(let текст):
            Text(текст)
                .lineLimit(1)
        case .с(let дата):
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(дата)
                    .lineLimit(1)
            }
        }
    }
}

/// .msg-tag: маленькая плашка на подложке --tint-* с текстом --on-*.
struct ТегИнбокса: View, Identifiable {
    let id: String
    let текст: String
    let значок: String?
    let фон: Color
    let цвет: Color

    var body: some View {
        HStack(spacing: 4) {
            if let значок {
                Image(systemName: значок)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(цвет)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(фон, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Теги строки: метка диалога (CHAT_LABELS), у диалога — «Аренда» / «Обмен», у лида — «🔥 Лид» (горячий) или
    /// «Покупатель», у покупки — «Покупка».
    static func для(_ с: СтрокаИнбокса) -> [ТегИнбокса] {
        var теги: [ТегИнбокса] = []
        if let метка = МеткаДиалога(rawValue: с.метка) {
            теги.append(ТегИнбокса(id: "label", текст: метка.название, значок: nil, фон: метка.фон, цвет: метка.цвет))
        }
        switch с.источник {
        case .dm:
            if с.виды.contains("rental") {
                теги.append(ТегИнбокса(id: "rent", текст: ИнбоксText.т("tag_rent"), значок: nil,
                                       фон: ИнбоксКраска.аиФон, цвет: ИнбоксКраска.аиТекст))
            }
            if с.виды.contains("exchange") {
                теги.append(ТегИнбокса(id: "exch", текст: ИнбоксText.т("tag_exch"), значок: nil,
                                       фон: ИнбоксКраска.инфоФон, цвет: ИнбоксКраска.инфоТекст))
            }
        case .lead:
            if с.статусЛида == "hot_lead" {
                теги.append(ТегИнбокса(id: "hot", текст: ИнбоксText.т("tag_lead"), значок: "flame",
                                       фон: ИнбоксКраска.плохоФон, цвет: ИнбоксКраска.плохоТекст))
            } else {
                теги.append(ТегИнбокса(id: "lead", текст: ИнбоксText.т("tag_buyer"), значок: nil,
                                       фон: ИнбоксКраска.вниманиеФон, цвет: ИнбоксКраска.вниманиеТекст))
            }
        case .buyer:
            теги.append(ТегИнбокса(id: "buy", текст: ИнбоксText.т("tag_buy"), значок: nil,
                                   фон: ИнбоксКраска.инфоФон, цвет: ИнбоксКраска.инфоТекст))
        }
        return теги
    }

    /// _MSG_ITEM_ST: sold «Продано», reserved «В сделке», inactive/paused/archived «Снято», rejected «Не в выдаче»,
    /// deleted/deleted_permanent «Удалено» — краски сайта.
    static func статусОбъявления(_ статус: String) -> ТегИнбокса? {
        switch статус {
        case "sold":
            return ТегИнбокса(id: "st", текст: ИнбоксText.т("it_sold"), значок: nil,
                              фон: Theme.цвет(0xFEE2E2, 0x3A1414), цвет: Theme.цвет(0x7F1D1D, 0xFCA5A5))
        case "reserved":
            return ТегИнбокса(id: "st", текст: ИнбоксText.т("it_reserved"), значок: nil,
                              фон: Theme.цвет(0xE0E7FF, 0x1E1B4B), цвет: Theme.цвет(0x3730A3, 0xA5B4FC))
        case "inactive", "paused", "archived":
            return ТегИнбокса(id: "st", текст: ИнбоксText.т("it_inactive"), значок: nil,
                              фон: Theme.цвет(0xF3F4F6, 0x26262E), цвет: Theme.цвет(0x6B7280, 0x9CA3AF))
        case "rejected":
            return ТегИнбокса(id: "st", текст: ИнбоксText.т("it_off"), значок: nil,
                              фон: Theme.цвет(0xFDE8D8, 0x3A2212), цвет: Theme.цвет(0x9A3412, 0xFDBA74))
        case "deleted", "deleted_permanent":
            return ТегИнбокса(id: "st", текст: ИнбоксText.т("it_gone"), значок: nil,
                              фон: Theme.цвет(0xF3F4F6, 0x26262E), цвет: Theme.цвет(0x6B7280, 0x9CA3AF))
        default:
            return nil
        }
    }
}

/// Аватар строки (_msgAv, .msg-av): круг 40 pt. Есть meta.img — фото товара и в правом нижнем углу кружок .msg-catbadge
/// 18 pt на подложке карточки со значком раздела в цвете раздела (телефон — электроника, ключ — услуги…). Фото нет, но
/// есть значок раздела — значок крупно на подложке цвета раздела 14 %. Иначе — первая буква имени на подложке источника
/// (лид — янтарная, покупка — голубая, диалог — серо-зелёная).
///
/// Фото — через КартинкиЛенты, а не AsyncImage (проверка на телефоне, сборка 35: у большинства строк пустая заглушка).
/// AsyncImage грузит один раз: список перерисовывается опросом (каждые 12 с), pull-to-refresh и .task, загрузка в
/// ленивом стеке при этом отменяется (NSURLErrorCancelled), AsyncImage остаётся в фазе .failure и рисует ту же заглушку
/// навсегда, без повтора. Видны были только снимки, уже лежавшие в URLCache после ленты. КартинкиЛенты держит готовое в
/// памяти, отменяет загрузку лишь когда её не ждёт ни одна ячейка и при следующем показе строки качает заново.
struct АватарИнбокса: View {
    let строка: СтрокаИнбокса

    private static let сторона: CGFloat = 40

    private var фон: Color {
        switch строка.источник {
        case .lead: return Theme.цвет(0xFFF3E0, 0x3A2A10)
        case .buyer: return Theme.цвет(0xEEF4FF, 0x14223A)
        case .dm: return Theme.цвет(0xEEF2F0, 0x22302A)
        }
    }

    private var буква: Color {
        switch строка.источник {
        case .lead: return Theme.цвет(0x9A5B00, 0xFBBF24)
        case .buyer: return Theme.цвет(0x1B5FA8, 0x93C5FD)
        case .dm: return Theme.цвет(0x51665B, 0xA3B8AC)
        }
    }

    var body: some View {
        let адрес = ИнбоксКартинка.адрес(строка.обложка)
        let значок = ЗначокРаздела(svg: строка.значокРаздела, цвет: строка.цветРаздела)
        let цвет = ИнбоксКраска.цвет(строка.цветРаздела) ?? Theme.акцент
        ZStack(alignment: .bottomTrailing) {
            круг(адрес: адрес, значок: значок, цвет: цвет)
                .frame(width: Self.сторона, height: Self.сторона)
                .clipShape(Circle())
            if адрес != nil, let значок {
                значок.вид(размер: 11)
                    .foregroundStyle(цвет)
                    .frame(width: 18, height: 18)
                    .background(ИнбоксКраска.карточка, in: Circle())
                    .background(Circle().fill(ИнбоксКраска.линия).padding(-1))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: Self.сторона, height: Self.сторона)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func круг(адрес: URL?, значок: ЗначокРаздела?, цвет: Color) -> some View {
        if let адрес {
            ZStack {
                фон
                /* Сначала рамка ячейки, потом обрезка кругом (урок сборки 33): широкое фото режется по ячейке. */
                КартинкаЛенты(адрес, пунктов: Self.сторона) {
                    Color.clear
                }
                .frame(width: Self.сторона, height: Self.сторона)
                .clipped()
            }
        } else if let значок {
            ZStack {
                цвет.opacity(0.14)
                значок.вид(размер: 20)
                    .foregroundStyle(цвет)
            }
        } else {
            ZStack {
                фон
                Text(String(строка.имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(буква)
            }
        }
    }
}

/// Адрес фото из meta.img так, как его понимает браузер на странице кабинета (/kz/ru/cabinet.php): «/img/…» и прочие
/// от корня — от kliko.kz (_ULX_BASE = ""), «//…» — https, полный адрес — как есть, путь без «/» — от /kz/ru/, как
/// url(...) в стиле .msg-av. Пробелы и кириллица в имени файла кодируются. Всегда абсолютный URL — он же ключ кэша.
enum ИнбоксКартинка {
    static func адрес(_ путь: String) -> URL? {
        let p = путь.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return nil }
        let строка: String
        if p.hasPrefix("//") {
            строка = "https:" + p
        } else {
            строка = p
        }
        let готовая = URL(string: строка)
            ?? строка.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0) }
        guard let готовая else { return nil }
        if let схема = готовая.scheme?.lowercased() {
            return схема == "http" || схема == "https" ? готовая : nil
        }
        let база = p.hasPrefix("/") ? Config.apiBase : (URL(string: "/kz/ru/", relativeTo: Config.apiBase)?.absoluteURL ?? Config.apiBase)
        return URL(string: готовая.absoluteString, relativeTo: база)?.absoluteURL
    }
}

/// Значок раздела из meta.catIcon. Сервер кладёт туда SVG корневого раздела из справочника сайта (js/cats-ru.js, MK_CATS:
/// поля icon и color). SVG в SwiftUI не рисуется, поэтому узнаём раздел по его рисунку (запасной путь — по цвету) и берём
/// похожий SF Symbol. Не SVG (эмодзи) — показываем как текст.
enum ЗначокРаздела {
    case символ(String)
    case эмодзи(String)

    /// Корни MK_CATS: кусок рисунка (без кавычек и пробелов), цвет, символ.
    private static let корни: [(рисунок: String, цвет: String, символ: String)] = [
        ("width=12height=19rx=2.5", "2563EB", "iphone"),                 // electronics
        ("M511l1.6-4.3", "DC2626", "car"),                               // transport
        ("M311l9-89", "059669", "house"),                                // realty
        ("M8.53L46.5", "DB2777", "tshirt"),                              // clothing
        ("M511V8a220012-2h10", "D97706", "sofa"),                        // home-garden
        ("cx=6.5cy=7r=2.5", "FACC15", "teddybear"),                      // kids
        ("M123c2.524", "0891B2", "soccerball"),                          // sport
        ("ellipsecx=7cy=9.5", "7C3AED", "pawprint"),                     // animals
        ("rectx=3y=7width=18height=13", "4F46E5", "briefcase"),          // jobs
        ("M14.56.2a3.6", "0D9488", "wrench.adjustable"),                 // services
        ("M123a99010018c1", "C026D3", "paintpalette"),                   // hobby
        ("M128c-1-1.3", "65A30D", "carrot"),                             // food-farm
        ("M921V11h6v10z", "E11D48", "sparkles")                          // beauty
    ]

    init?(svg: String, цвет: String) {
        let сырой = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !сырой.isEmpty else { return nil }
        if !сырой.contains("<") {
            self = .эмодзи(String(сырой.prefix(4)))
            return
        }
        let плоский = сырой.filter { $0 != "\"" && $0 != "'" && $0 != "\\" && !$0.isWhitespace }
        if let корень = Self.корни.first(where: { плоский.contains($0.рисунок) }) {
            self = .символ(корень.символ)
            return
        }
        var hex = цвет.trimmingCharacters(in: .whitespaces).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        if let корень = Self.корни.first(where: { $0.цвет == hex }) {
            self = .символ(корень.символ)
            return
        }
        self = .символ("square.grid.2x2")
    }

    @ViewBuilder
    func вид(размер: CGFloat) -> some View {
        switch self {
        case .символ(let имя):
            Image(systemName: имя)
                .font(.system(size: размер, weight: .semibold))
        case .эмодзи(let знак):
            Text(знак)
                .font(.system(size: размер))
        }
    }
}

// MARK: - Метки диалога (CHAT_LABELS)

/// «Возможно купит», «Думает», «Купил», «Постоянный», «Отказ» — select в шапке обоих чатов, тег в строке инбокса.
enum МеткаДиалога: String, CaseIterable, Identifiable {
    case maybe, thinking, bought, regular, declined

    var id: String { rawValue }

    var название: String { ИнбоксText.т("lbl_" + rawValue) }

    var фон: Color {
        switch self {
        case .maybe: return ИнбоксКраска.вниманиеФон
        case .thinking: return ИнбоксКраска.инфоФон
        case .bought: return ИнбоксКраска.окФон
        case .regular: return ИнбоксКраска.аиФон
        case .declined: return ИнбоксКраска.плохоФон
        }
    }

    var цвет: Color {
        switch self {
        case .maybe: return ИнбоксКраска.вниманиеТекст
        case .thinking: return ИнбоксКраска.инфоТекст
        case .bought: return ИнбоксКраска.окТекст
        case .regular: return ИнбоксКраска.аиТекст
        case .declined: return ИнбоксКраска.плохоТекст
        }
    }
}

/// Краски кабинета сайта (css_cabinet.css :root и [data-theme=dark], --acc-on из css_ui-prefs) — у инбокса, лид-чата,
/// переписки dm.php, заявок и уведомлений. Не краски «Моих объявлений» и не витрины (--mk-*): у кабинета свои.
enum ИнбоксКраска {
    /// --acc-on: --g #0f5132 / тёмная --g3 #5cd39a; --acc-ink — текст на нём #fff / #10131a.
    static let акцент = Theme.цвет(0x0F5132, 0x5CD39A)
    static let наАкценте = Theme.цвет(0xFFFFFF, 0x10131A)
    /// --bg страницы, --card карточки, --surf2 подложки, --line, --ink.
    static let фон = Theme.цвет(0xEEF3F0, 0x101017)
    static let карточка = Theme.цвет(0xFFFFFF, 0x1C1C26)
    static let подложка = Theme.цвет(0xF6FAF8, 0x23232F)
    static let линия = Theme.цвет(светлый: Theme.hex(0xE6EFE9), тёмный: Theme.hex(0xFFFFFF, 0.10))
    static let текст = Theme.цвет(0x0F1712, 0xEAF3EE)
    /// --tint-ok / --on-ok / --edge-ok.
    static let окФон = Theme.цвет(светлый: Theme.hex(0xE7F6EE), тёмный: Theme.hex(0x34C997, 0.14))
    static let окТекст = Theme.цвет(0x0F7A44, 0x5CD39A)
    static let окКромка = Theme.цвет(светлый: Theme.hex(0xCDEBD7), тёмный: Theme.hex(0x34C997, 0.32))
    /// --tint-warn / --on-warn / --edge-warn.
    static let вниманиеФон = Theme.цвет(светлый: Theme.hex(0xFFF4E5), тёмный: Theme.hex(0xE0BD5E, 0.15))
    static let вниманиеТекст = Theme.цвет(0x92400E, 0xE0BD5E)
    static let вниманиеКромка = Theme.цвет(светлый: Theme.hex(0xFDE68A), тёмный: Theme.hex(0xE0BD5E, 0.34))
    /// --tint-bad / --on-bad / --edge-bad.
    static let плохоФон = Theme.цвет(светлый: Theme.hex(0xFEE2E2), тёмный: Theme.hex(0xFF6168, 0.15))
    static let плохоТекст = Theme.цвет(0x991B1B, 0xFF8A8F)
    static let плохоКромка = Theme.цвет(светлый: Theme.hex(0xFECACA), тёмный: Theme.hex(0xFF6168, 0.34))
    /// --tint-ai #f4eefb / --on-ai #6c3fc5 (тёмная — rgba(167,139,250,.15) на карточке / #b79bf5).
    static let аиФон = Theme.цвет(0xF4EEFB, 0x2A2440)
    static let аиТекст = Theme.цвет(0x6C3FC5, 0xB79BF5)
    /// --tint-info #eef4ff / --on-info #1e40af (тёмная — #7cb8f5).
    static let инфоФон = Theme.цвет(0xEEF4FF, 0x1C2A3E)
    static let инфоТекст = Theme.цвет(0x1E40AF, 0x7CB8F5)
    /// --edge-info.
    static let инфоКромка = Theme.цвет(светлый: Theme.hex(0xC7D6F5), тёмный: Theme.hex(0x60A5FA, 0.34))

    // Переписка (.kc css_chat в кабинете)
    /// .kc-msg.me: --kc-acc — #1d7d4a; тёмная #5cd39a под чёрным 44 % = #337656.
    static let облакоМоё = Theme.цвет(0x1D7D4A, 0x337656)
    /// .kc-msg.peer и заглушки фото: --kc-peer.
    static let облакоЧужое = Theme.цвет(0xEEF2F0, 0x1F2A24)
    static let облакоЧужоеТекст = Theme.цвет(0x0F1B14, 0xEAF3EE)
    /// --kc-mut: время чужого облака.
    static let облакоВремя = Theme.цвет(0x5F7168, 0x90A499)
    /// --kc-soft / --kc-line / --kc-deep карточек торга (.kc-ofr).
    static let мягкий = Theme.цвет(0xF2F7F4, 0x1A221D)
    static let мягкаяЛиния = Theme.цвет(0xE2ECE6, 0x243029)
    static let глубокий = Theme.цвет(0x0F5132, 0x34C997)
    /// Градиент кнопок кабинета linear-gradient(135deg, --g, --g2).
    static var градиент: LinearGradient {
        LinearGradient(colors: [Theme.цвет(0x0F5132, 0x22A05B), Theme.цвет(0x1D7D4A, 0x34C997)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// --acc-tint: rgba(29,125,74,.1) / rgba(52,201,151,.14).
    static let оттенок = Theme.цвет(светлый: Theme.hex(0x1D7D4A, 0.10), тёмный: Theme.hex(0x34C997, 0.14))
    /// .toast кабинета: #0f1712 в обеих темах.
    static let плашка = Color(uiColor: Theme.hex(0x0F1712))

    /// «#1d9e5e» → цвет; не цвет — nil.
    static func цвет(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { String([$0, $0]) }.joined() }
        guard s.count == 6, let число = UInt32(s, radix: 16) else { return nil }
        return Color(uiColor: Theme.hex(число))
    }
}

// MARK: - Общие части переписок кабинета

/// Служебная строка переписки кабинета: зелёная пилюля (--on-ok на --tint-ok) по центру; у dm.php — с рамкой, у лид-чата
/// — без (карта §6.4.10).
struct ПилюляСлужебнаяКабинета: View {
    let текст: String
    let рамка: Bool

    var body: some View {
        Text(текст)
            .font(.system(size: 12))
            .foregroundStyle(ИнбоксКраска.окТекст)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(ИнбоксКраска.окФон, in: Capsule())
            .overlay {
                if рамка {
                    Capsule().strokeBorder(ИнбоксКраска.окТекст, lineWidth: 1)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
    }
}

/// Облако переписки кабинета (.kc-msg в #dm-messages и #lcm-messages): 14 с высотой строки 1.4, отступы 8/12,
/// скругление 14 и «хвост» 5 на своей стороне. Своё — --kc-acc кабинета (#1d7d4a, тёмная — под 44 % чёрного), чужое —
/// --kc-peer без кромки. Время — 11 справа, у своего белым 60 %, у чужого --kc-mut. «Kliko AI-ассистент» (.kc-who) и «из
/// Telegram» — внутри облака над текстом.
struct ОблакоКабинета: View {
    let текст: String
    let время: String
    let моё: Bool
    var кто: String? = nil
    var изTelegram: Bool = false
    /// Голосовое и видео без плеера — значок перед подписью (у сайта SVG, не эмодзи).
    var значок: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let кто {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                        Text(кто)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(моё ? Color.white.opacity(0.85) : ИнбоксКраска.глубокий.opacity(0.85))
                    .padding(.bottom, 3)
                }
                if изTelegram {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text(ИнбоксText.т("via_tg"))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(uiColor: Theme.hex(0x229ED9)))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(ИнбоксКраска.инфоФон, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 6)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let значок {
                        Image(systemName: значок)
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                    }
                    Text(текст)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(моё ? Color.white : ИнбоксКраска.облакоЧужоеТекст)
            }
            if !время.isEmpty {
                Text(время)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(моё ? Color.white.opacity(0.6) : ИнбоксКраска.облакоВремя)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(моё ? ИнбоксКраска.облакоМоё : ИнбоксКраска.облакоЧужое, in: форма)
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: моё ? 14 : 5,
                               bottomTrailingRadius: моё ? 5 : 14, topTrailingRadius: 14, style: .continuous)
    }
}

/// Фото в переписке кабинета (.kc-msg.media): своими пропорциями, не выше 280 и не шире 260, скругление 14, время под
/// ним серым. Нажатие — снимок во весь экран внутри приложения (у сайта window.open(src)).
struct ФотоПерепискиКабинета: View {
    let адрес: URL
    let моё: Bool
    let время: String
    @State private var крупно = false

    /// Явный init: скрытое состояние делает встроенный init видимым только внутри этого файла, а фото берут переписка
    /// dm.php и лид-чат.
    init(адрес: URL, моё: Bool, время: String) {
        self.адрес = адрес
        self.моё = моё
        self.время = время
    }

    var body: some View {
        HStack(spacing: 0) {
            if моё { Spacer(minLength: 48) }
            VStack(alignment: .trailing, spacing: 3) {
                Button {
                    крупно = true
                } label: {
                    КартинкаЛенты(адрес, пунктов: 280, заполнить: false) {
                        ИнбоксКраска.облакоЧужое
                            .frame(width: 200, height: 200)
                    }
                    .frame(maxWidth: 260, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ChatText.т("photo"))
                if !время.isEmpty {
                    Text(время)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            if !моё { Spacer(minLength: 48) }
        }
        .fullScreenCover(isPresented: $крупно) {
            ФотоПерепискиКрупно(адрес: адрес)
        }
    }
}

/// Снимок из переписки во весь экран на чёрном, «Закрыть» сверху.
struct ФотоПерепискиКрупно: View {
    let адрес: URL
    @Environment(\.dismiss) private var закрыть

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            КартинкаЛенты(адрес, пунктов: 1000, заполнить: false) {
                SiteSpinner.цвета(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                закрыть()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .accessibilityLabel(ИнбоксText.т("close"))
        }
    }
}

/// «✓✓ Прочитано» (зелёным) или «✓ Отправлено» под последним моим сообщением (§6.4.8 i).
struct ОтметкаПрочтения: View {
    let прочитано: Bool

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(ИнбоксText.т(прочитано ? "read" : "sent"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(прочитано ? Color(uiColor: Theme.hex(0x1D9E5E)) : Theme.текстВторой)
                .padding(.trailing, 2)
                .padding(.top, 1)
        }
    }
}

/// Короткая плашка внизу — .toast кабинета: #0f1712 в обеих темах, белый 14, отступы 12/20, скругление 12, не шире
/// 420. Голосом её уже произнесла модель (announcement).
struct ПлашкаИнбокса: View {
    let текст: String?

    var body: some View {
        if let текст {
            Text(текст)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(ИнбоксКраска.плашка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.opacity)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}
