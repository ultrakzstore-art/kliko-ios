import SwiftUI

/**
 ЧАСТИ КОРНЯ ЛЕНТЫ, КОТОРЫЕ САМИ СЛЕДЯТ ЗА ОБЩИМИ ХРАНИЛИЩАМИ (скорость, владелец 16.10.2026: «чтобы он не тупил от
 слова совсем и моментально открывал всё»).

 Корень ленты (NativeFeedView) больше не наблюдает RecentStore: открытие объявления записывает его в «Вы смотрели», и
 наблюдающий корень пересобирал всю ленту — шапку, главную, сетку — ровно в момент перехода на карточку. Теперь за
 просмотрами и историей поиска следят только эти маленькие виды: меняются просмотры — перерисовываются только они.
 Вид и правила показа — прежние (mkRenderViewed, этап 6).
 */

// MARK: - Лента на экране

@MainActor
extension View {
    /// Лента на экране — выбрана её вкладка (ВидСайта.вкладкаЛенты), поверх корня ничего не открыто (кореньЛенты; в две
    /// колонки iPad корень всегда «под» правой колонкой — там достаточно вкладки) и не открыта страница сайта
    /// (WebBridge.лентаВидна). Пишет в `видна`; по ней то, что листается само, листается только на виду.
    func лентаНаЭкране(_ видна: Binding<Bool>) -> some View {
        modifier(СлежкаЗаЭкраномЛенты(видна: видна))
    }
}

/// Подписки, а не наблюдение ВидСайта целиком: его карточки и слои поверх меняются на каждое открытие объявления.
/// Значение из подписки — новое (@Published шлёт его до записи), остальные два признака читаются как есть.
@MainActor
private struct СлежкаЗаЭкраномЛенты: ViewModifier {
    @Binding var видна: Bool
    @Environment(\.horizontalSizeClass) private var ширинаОкна

    func body(content: Content) -> some View {
        content
            .onReceive(ВидСайта.shared.$вкладкаЛенты.removeDuplicates()) { вкладка in
                решить(вкладка: вкладка, корень: ВидСайта.shared.кореньЛенты, страница: WebBridge.shared.лентаВидна)
            }
            .onReceive(ВидСайта.shared.$кореньЛенты.removeDuplicates()) { корень in
                решить(вкладка: ВидСайта.shared.вкладкаЛенты, корень: корень, страница: WebBridge.shared.лентаВидна)
            }
            .onReceive(WebBridge.shared.$лентаВидна.removeDuplicates()) { страница in
                решить(вкладка: ВидСайта.shared.вкладкаЛенты, корень: ВидСайта.shared.кореньЛенты, страница: страница)
            }
            .onChange(of: ширинаОкна) { _, _ in
                решить(вкладка: ВидСайта.shared.вкладкаЛенты, корень: ВидСайта.shared.кореньЛенты,
                       страница: WebBridge.shared.лентаВидна)
            }
    }

    private func решить(вкладка: Bool, корень: Bool, страница: Bool) {
        let итог = вкладка && страница && (корень || ДвеКолонки.включены(ширинаОкна))
        if видна != итог { видна = итог }
    }
}

// MARK: - Недавнее (этап 6)

/// «Вы смотрели» прежнего вида (этап 6): полоса над разделами, пока в поле ничего не набрано.
struct НедавниеПрежнейЛенты: View {
    /// В поле поиска ничего не набрано.
    let поискПуст: Bool
    let открыть: (URL) -> Void
    /// Этап 14: в две колонки — объявление в правую колонку; nil — ссылка в стек ленты.
    let выбрать: ((Listing) -> Void)?
    @ObservedObject private var недавние = RecentStore.shared

    init(поискПуст: Bool, открыть: @escaping (URL) -> Void, выбрать: ((Listing) -> Void)?) {
        self.поискПуст = поискПуст
        self.открыть = открыть
        self.выбрать = выбрать
    }

    var body: some View {
        if Config.недавние && поискПуст && !недавние.товары.isEmpty {
            ПолосаНедавних(товары: недавние.товары, открыть: открыть, очистить: {
                withAnimation(.easeInOut(duration: 0.2)) { RecentStore.shared.очиститьПросмотры() }
            }, выбрать: выбрать)
        }
    }
}

/// История поиска (этап 6) под пустым полем в фокусе — вида сайта, вместо .searchSuggestions.
struct ИсторияПоискаЛенты: View {
    /// Поле в фокусе и пустое.
    let видна: Bool
    let искать: (String) -> Void
    @ObservedObject private var недавние = RecentStore.shared

    init(видна: Bool, искать: @escaping (String) -> Void) {
        self.видна = видна
        self.искать = искать
    }

    var body: some View {
        if Config.недавние && видна && !недавние.запросы.isEmpty {
            список
        }
    }

    private var список: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(недавние.запросы, id: \.self) { запрос in
                Button { искать(запрос) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.текстВторой)
                        Text(запрос)
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(RecentText.т("query_hint"))
                Divider().padding(.leading, 46)
            }
            Button(role: .destructive) { RecentStore.shared.очиститьЗапросы() } label: {
                Label(RecentText.т("clear_history"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .теньКарточкиСайта()
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// История поиска прежнего вида — подсказки .searchSuggestions под пустым полем. Нажали запрос — ищем сразу.
struct ПодсказкиПоискаЛенты: View {
    /// В поле поиска ничего не набрано.
    let поискПуст: Bool
    let искать: (String) -> Void
    @ObservedObject private var недавние = RecentStore.shared

    init(поискПуст: Bool, искать: @escaping (String) -> Void) {
        self.поискПуст = поискПуст
        self.искать = искать
    }

    var body: some View {
        if Config.недавние && поискПуст && !недавние.запросы.isEmpty {
            ForEach(недавние.запросы, id: \.self) { запрос in
                Button { искать(запрос) } label: {
                    Label {
                        Text(запрос).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint(RecentText.т("query_hint"))
            }
            Button(role: .destructive, action: { RecentStore.shared.очиститьЗапросы() }) {
                Label(RecentText.т("clear_history"), systemImage: "trash")
            }
        }
    }
}

/**
 «Вы смотрели» над выдачей вида сайта. Есть ли полоса, решает корень (решитьПолосуНедавних) — только у верха ленты или
 при новой выдаче; содержимое — живое: высота полосы от числа карточек не зависит, и сетка под пальцем не сдвигается.
 */
struct СмотрелиНадВыдачей: View {
    @ObservedObject private var модель: FeedModel
    /// Решение корня: полоса на экране.
    let полоса: Bool
    /// Карточка со ссылкой — её ставит лента: в стек, в правую колонку iPad или страницей сайта.
    let карточка: (Listing) -> AnyView
    @ObservedObject private var недавние = RecentStore.shared

    init(модель: FeedModel, полоса: Bool, карточка: @escaping (Listing) -> AnyView) {
        _модель = ObservedObject(wrappedValue: модель)
        self.полоса = полоса
        self.карточка = карточка
    }

    var body: some View {
        let смотрели = полоса ? Self.вЛенте(модель, просмотры: недавние.товары) : []
        if !смотрели.isEmpty {
            ПолосаНедавнихСайта(товары: смотрели, очистить: {
                withAnimation(.easeInOut(duration: 0.2)) { RecentStore.shared.очиститьПросмотры() }
            }, карточка: карточка)
            .padding(.top, 10)
        }
    }

    /**
     «Вы смотрели» ленты — правила mkRenderViewed: нет поиска и раздела (набор «Товары» — не раздел), из просмотренных —
     те, что есть среди загруженных объявлений ленты, в порядке просмотра, до двенадцати; меньше двух — полосы нет.
     Скорость: не словарь всего загруженного на каждую перерисовку, а поиск каждого из ≤ 30 просмотренных по номеру
     (FeedModel.товар).
     */
    @MainActor
    static func вЛенте(_ модель: FeedModel, просмотры: [Listing]) -> [Listing] {
        let искомое = модель.действующее
        guard Config.недавние, искомое.текст.isEmpty, искомое.раздел.isEmpty || искомое.раздел == "goods",
              !просмотры.isEmpty else { return [] }
        var итог: [Listing] = []
        for товар in просмотры {
            guard итог.count < 12 else { break }
            if let свежий = модель.товар(товар.id) { итог.append(свежий) }
        }
        return итог
    }
}
