import SwiftUI
import UIKit

/**
 «ДЛЯ ВАС» — ПОЛКА НА ГЛАВНОЙ И ЭКРАН ЦЕЛИКОМ (пачка 16.10.2026; docs/STANDARDS.md §6.3).

 Полка (ПолкаДляВас) стоит на главной после рядов разделов (Feed/NativeFeedView.swift, главнаяСайта — одна строка): тот
 же ряд, что у разделов (РядГлавной: точка, «Для вас», «Все ›», карточки по 2,2 на экран, «Смотреть все N» в конце), и те
 же карточки ленты со ссылкой — их даёт главная замыканием. Под каждой — плашка причины (ПлашкаДляВас): значок уровня
 («подходит» — галочка, «нужна деталь» — ключ) и «Для вашей Camry», «Ваш размер M», «Для кровати 160×200»; у одежды —
 кружок цвета моего гардероба, с которым вещь сочетается. Под рядом — честная строка «Подобрано на телефоне по «Моему»» и
 «Скрыть» одним касанием.

 Полки нет вовсе, пока «Моё» не прочитано, пусто, скрыто или ничего не подошло — ни заголовка, ни заглушки. Пока ждём
 ответа — на месте полки нулевая полоса (на ней живут onAppear и onChange): полка появляется плавно, карточки — волной
 (ПодъёмСайта); при «Уменьшении движения» и в лёгком режиме — сразу. Грузит полка, только когда подъехала к экрану и
 ряды главной уже пришли (готово), — не на запуске и не на каждом показе главной (ПодборкаДляВас.войти).

 Экран целиком (ЭкранДляВас) — окном поверх всего (ПоверхВсего): свой стек (объявление, похожие, чат), чипы групп с
 числами, сетка карточек ленты с подробной плашкой (с чем сверили, нужная деталь), «потянуть вниз» — заново. У ленты
 есть конец: «Это всё, что подходит сейчас» и «Дополнить «Моё»»; бесконечной подгрузки нет.

 Пачка 83: в заголовке полки — «Для вас · 3 новых» (НовинкиДляВас), на экране — чип «Новые»; открыл экран — новое
 стало показанным. Точных нет — ряд «Проверьте» с оранжевой плашкой без галочки («Размер не указан — уточните у
 продавца», в две строки). При ключе fit_subs — «Сообщать о новом» с согласием и «Что хранится на сервере» в меню.
 */
struct ПолкаДляВас<Карточка: View>: View {
    /// Ряды главной уже пришли (ПодборкиГлавной.числаГотовы): раньше полка в сеть не идёт.
    let готово: Bool
    /// Карточка ленты со ссылкой — та же, что в рядах главной (карточкаГлавнойСоСсылкой).
    let карточка: (Listing) -> Карточка
    @ObservedObject private var модель = ПодборкаДляВас.shared
    @State private var видно = false

    init(готово: Bool, @ViewBuilder карточка: @escaping (Listing) -> Карточка) {
        self.готово = готово
        self.карточка = карточка
    }

    private func т(_ ключ: String) -> String { ДляВасText.т(ключ) }

    /// Сменился — пора войти ещё раз: ряды главной пришли или в «Моём» появились новые разделы.
    private var ключВхода: String { модель.ключ + (готово ? "|1" : "|0") }

    var body: some View {
        switch модель.состояние {
        case .ждём, .пусто:
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
                .onAppear { модель.войти(готово: готово) }
                .onChange(of: ключВхода) { _, _ in модель.войти(готово: готово) }
        case .есть:
            полка
                .onAppear {
                    модель.войти(готово: готово)
                    показать()
                }
                .onChange(of: ключВхода) { _, _ in модель.войти(готово: готово) }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .неизвестно, .нечего, .скрыта:
            EmptyView()
        }
    }

    /// «Для вас», а с новинками с прошлого просмотра — «Для вас · 3 новых» (НовинкиДляВас).
    private var заголовок: String {
        guard модель.новых > 0 else { return т("fv_title") }
        return т("fv_title") + " · " + НовинкиМоегоText.сколькоНовых(модель.новых)
    }

    private var полка: some View {
        VStack(alignment: .leading, spacing: 0) {
            РядГлавной(раздел: ПодборДляВас.разделГлавной, название: заголовок, показано: модель.ряд.count,
                       всего: модель.находки.count, всё: { ОкноДляВас.открыть() }) {
                ForEach(Array(модель.ряд.enumerated()), id: \.element.id) { номер, находка in
                    ячейка(находка)
                        .containerRelativeFrame(.horizontal) { длина, _ in ШиринаКарточкиРяда.для(длина) }
                        .modifier(ПодъёмСайта(видно: видно, задержка: Double(min(номер, 5)) * 0.05, сдвиг: 12,
                                              масштаб: 0.97))
                }
            }
            строкаПочему
        }
    }

    private func ячейка(_ находка: НаходкаДляВас) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            карточка(находка.товар)
            ПлашкаДляВас(находка: находка)
        }
    }

    /// «Подобрано на телефоне по «Моему»» и «Скрыть» — одной строкой под рядом.
    private var строкаПочему: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(т("fv_line"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: скрыть) {
                Text(т("fv_hide"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(т("fv_hide_m"))
        }
        .padding(.horizontal, 16)
        .padding(.top, -6)
    }

    /// Карточки волной — один раз за запуск (ленивый стек пересоздаёт полку при возврате); без движения — сразу.
    private func показать() {
        guard !видно else { return }
        if ДвижениеСайта.тихо || РежимУстройства.сейчас || модель.волнаБыла {
            var без = Transaction()
            без.disablesAnimations = true
            withTransaction(без) { видно = true }
        } else {
            модель.волнаБыла = true
            видно = true
        }
    }

    private func скрыть() {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.уход) { модель.скрыть() }
        UIAccessibility.post(notification: .announcement, argument: т("fv_hidden_a11y"))
    }
}

// MARK: - Плашка причины

/// Плашка под карточкой: значок уровня, причина, кружок цвета гардероба; подробно — с чем сверили и нужная деталь.
struct ПлашкаДляВас: View {
    let находка: НаходкаДляВас
    var подробно = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            капсула
            if подробно {
                if !находка.подробно.isEmpty, находка.подробно != находка.причина {
                    Text(находка.подробно)
                        .font(.caption2)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let деталь = находка.деталь, !деталь.isEmpty {
                    Text(ДляВасText.ф("fv_part", деталь))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(находка.уровень.краска)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
    }

    /// «Проверьте» (пачка 83): причина длиннее («Размер не указан — уточните у продавца») — в две строки.
    private var проверка: Bool { находка.уровень == .проверить }

    private var капсула: some View {
        HStack(spacing: 5) {
            Image(systemName: находка.уровень.значок)
                .font(.caption2.weight(.bold))
                .foregroundStyle(находка.уровень.краска)
            Text(находка.причина)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(проверка ? 2 : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: проверка)
            if let цвет = находка.цвет {
                Circle()
                    .fill(цвет.краска)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, проверка ? 3 : 0)
        .frame(minHeight: 24)
        .background(находка.уровень.краска.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// «Подходит: Для вашей Camry, сочетается с вашими вещами цвета «синий»»; подробно — и с чем сверили.
    private var голос: String {
        var части = [находка.уровень.слово + ": " + находка.причина]
        if let цвет = находка.цвет { части.append(ДляВасText.ф("fv_color_a11y", цвет.название.lowercased())) }
        if подробно, !находка.подробно.isEmpty, находка.подробно != находка.причина { части.append(находка.подробно) }
        if подробно, let деталь = находка.деталь, !деталь.isEmpty { части.append(ДляВасText.ф("fv_part", деталь)) }
        return части.joined(separator: ", ")
    }
}

// MARK: - Экран целиком

/// «Для вас» окном поверх любого экрана (из «Все ›» и «Смотреть все» полки).
@MainActor
enum ОкноДляВас {
    static func открыть() {
        guard Config.дляВас else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранДляВас(закрыть: закрыть)
        }
    }
}

/// Все находки «Для вас»: чипы групп (и «Новые»), сетка карточек ленты с подробной плашкой, честный конец; при ключе
/// fit_subs — «Сообщать о новом» с согласием одной строкой (MyThingsWatch.swift).
struct ЭкранДляВас: View {
    let закрыть: () -> Void
    @ObservedObject private var модель = ПодборкаДляВас.shared
    @ObservedObject private var новинки = НовинкиДляВас.shared
    @ObservedObject private var подписка = ПодпискаНовинокМоего.shared
    @State private var путь = NavigationPath()
    @State private var группа: ГруппаДляВас? = nil
    @State private var толькоНовые = false
    @State private var спроситьСкрыть = false
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ДляВасText.т(ключ) }

    /// Новые, что были на экране в этот показ и ещё на нём.
    private var новыеНаЭкране: [НаходкаДляВас] {
        модель.находки.filter { (н: НаходкаДляВас) -> Bool in новинки.новыеЭкрана.contains(н.id) }
    }

    private var показанные: [НаходкаДляВас] {
        if толькоНовые { return новыеНаЭкране }
        guard let выбрана = группа else { return модель.находки }
        return модель.находки.filter { $0.группа == выбрана }
    }

    /// Группы, в которых что-то нашлось, — порядком чипов.
    private var группы: [ГруппаДляВас] {
        let есть = Set(модель.находки.map(\.группа))
        return ГруппаДляВас.allCases.filter { есть.contains($0) }
    }

    var body: some View {
        NavigationStack(path: $путь) {
            список
                .navigationTitle(т("fv_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { панель }
                .navigationDestination(for: Listing.self) { товар in
                    ListingDetailView(товар: товар, открыть: { адрес in открытьАдрес(адрес) })
                }
                .чатМаршруты(открыть: { адрес in открытьАдрес(адрес) })
        }
        .environment(\.открытьОбъявлениеВСтеке, { товар in путь.append(товар) })
        .tint(Theme.акцент)
        .confirmationDialog(т("fv_hide_t"), isPresented: $спроситьСкрыть, titleVisibility: .visible) {
            Button(т("fv_hide"), role: .destructive) {
                модель.скрыть()
                закрыть()
            }
            Button(т("fv_cancel"), role: .cancel) {}
        } message: {
            Text(т("fv_hide_m"))
        }
        .alert(НовинкиМоегоText.т("nm_watch_stored_t"), isPresented: показХранимого) {
            Button(НовинкиМоегоText.т("nm_ok"), role: .cancel) {}
        } message: {
            Text((подписка.хранится ?? []).joined(separator: "\n"))
        }
        .onAppear { модель.открытьЭкран() }
        .onDisappear { модель.закрытьЭкран() }
        .onChange(of: группы) { _, есть in
            if let выбрана = группа, !есть.contains(выбрана) { группа = nil }
        }
        .onChange(of: новинки.новыеЭкрана.isEmpty) { _, пусто in
            if пусто && толькоНовые { толькоНовые = false }
        }
    }

    /// Окно «Хранится на сервере» — пока есть ответ sub_get.
    private var показХранимого: Binding<Bool> {
        Binding<Bool>(
            get: { подписка.хранится != nil },
            set: { (виден: Bool) in
                if !виден { подписка.хранится = nil }
            }
        )
    }

    @ToolbarContentBuilder
    private var панель: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(т("fv_close"), action: закрыть)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    ОкноМоего.открыть()
                } label: {
                    Label(т("fv_more"), systemImage: "square.grid.2x2")
                }
                if подписка.доступна && подписка.включено {
                    Button {
                        Task<Void, Never> { @MainActor in
                            await ПодпискаНовинокМоего.shared.спросить()
                        }
                    } label: {
                        Label(НовинкиМоегоText.т("nm_watch_stored"), systemImage: "server.rack")
                    }
                }
                Button(role: .destructive) {
                    спроситьСкрыть = true
                } label: {
                    Label(т("fv_menu_hide"), systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(т("fv_menu"))
        }
    }

    private var список: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                вступление
                if подписка.доступна { переключательПодписки }
                if группы.count > 1 || !новыеНаЭкране.isEmpty { чипы }
                содержимое
                if !показанные.isEmpty { конец }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.фонСтраницы)
        .refreshable { await модель.обновить() }
    }

    /// Вступление: «никуда не уходит» — пока значения и правда не уходят; подбор на сервере или включённая подписка —
    /// честный текст §10.3 («на сервер уходят только значения стандартов»). Пачка 84: значения ушли телом POST ленты
    /// (rules.fit_filters, модель.наСервере) — свой честный текст без рекламы (fv_lead_server); так же, если в этот
    /// запуск тела уходили от рядов «Подходит вам» (ПризнакиПодбораСервера.отправляли), — что бы ни ответил сервер.
    private var текстВступления: String {
        let уходит: Bool = РубильникиНовинок.подборНаСервере || (подписка.доступна && подписка.включено)
        if уходит { return НовинкиМоегоText.т("nm_lead_server") }
        let ушлиТела: Bool = модель.наСервере || ПризнакиПодбораСервера.отправляли
        return ушлиТела ? т("fv_lead_server") : т("fv_lead")
    }

    private var вступление: some View {
        Label {
            Text(текстВступления)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(Theme.зелёный2)
        }
        .font(.footnote)
        .foregroundStyle(Theme.текстВторой)
        .padding(.horizontal, 16)
    }

    /// «Сообщать о новом» (только при ключе fit_subs): согласие одной строкой; включение — окно разрешения push.
    private var переключательПодписки: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: включениеПодписки) {
                Text(НовинкиМоегоText.т("nm_watch"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
            }
            .disabled(подписка.занято)
            Text(НовинкиМоегоText.согласие(РубильникиНовинок.вСутки))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if let весть = текстВести {
                Text(весть)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(УровеньАвтоподбора.проверить.краска)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var включениеПодписки: Binding<Bool> {
        Binding<Bool>(
            get: { подписка.включено },
            set: { (вкл: Bool) in
                ОткликСайта.выбор()
                if вкл {
                    ПодпискаНовинокМоего.shared.включить()
                } else {
                    ПодпискаНовинокМоего.shared.выключить()
                }
            }
        )
    }

    private var текстВести: String? {
        switch подписка.весть {
        case .нет: return nil
        case .неОчем: return НовинкиМоегоText.т("nm_watch_empty")
        case .выключеноВНастройках: return НовинкиМоегоText.т("nm_watch_denied")
        case .частьНеПринята: return НовинкиМоегоText.т("nm_watch_dropped")
        case .сбой: return НовинкиМоегоText.т("nm_watch_fail")
        }
    }

    private var чипы: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ЧипМоего(т("fv_all") + " · " + String(модель.находки.count), выбран: группа == nil && !толькоНовые) {
                    выбрать(nil)
                }
                if !новыеНаЭкране.isEmpty {
                    ЧипМоего(НовинкиМоегоText.т("nm_new_chip") + " · " + String(новыеНаЭкране.count),
                             выбран: толькоНовые, значок: "sparkles") {
                        выбратьНовые()
                    }
                    .accessibilityLabel(НовинкиМоегоText.ф("nm_new_a11y", String(новыеНаЭкране.count)))
                }
                ForEach(группы) { г in
                    ЧипМоего(г.название + " · " + String(модель.находки.filter { $0.группа == г }.count),
                             выбран: группа == г && !толькоНовые, значок: г.значок) {
                        выбрать(г)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func выбрать(_ новая: ГруппаДляВас?) {
        guard новая != группа || толькоНовые else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.вставкаСписка) {
            толькоНовые = false
            группа = новая
        }
    }

    private func выбратьНовые() {
        guard !толькоНовые else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.вставкаСписка) {
            группа = nil
            толькоНовые = true
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if показанные.isEmpty {
            if модель.грузим {
                HStack(spacing: 10) {
                    SiteSpinner(стоит: ДвижениеСайта.тихо)
                    Text(т("fv_loading"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                пусто
            }
        } else {
            LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: ListingCard.зазор) {
                ForEach(показанные) { находка in
                    ячейка(находка)
                }
            }
            .padding(.horizontal, ListingCard.поле)
        }
    }

    private func ячейка(_ находка: НаходкаДляВас) -> some View {
        let товар = находка.товар
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if Config.нативнаяКарточка {
                    NavigationLink(value: товар) { ListingCard(товар: товар) }
                } else {
                    Button {
                        if let адрес = товар.адрес { открытьАдрес(адрес) }
                    } label: {
                        ListingCard(товар: товар)
                    }
                }
            }
            .buttonStyle(НажатиеСайта())
            .сердечкоИзбранного(товар)
            .поделитьсяНаКарточке(товар)
            .менюКарточкиОбъявления(товар)
            ПлашкаДляВас(находка: находка, подробно: true)
        }
    }

    private var пусто: some View {
        VStack(spacing: 8) {
            Image(systemName: модель.неудача ? "wifi.exclamationmark" : "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(модель.неудача ? т("fv_fail") : т("fv_none"))
                .font(.headline)
                .foregroundStyle(Theme.текст)
            if !модель.неудача {
                Text(т("fv_none_sub"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }

    /// Конец ленты: всё, что подходит сейчас, — и как получить больше (дополнить «Моё»), без бесконечной подгрузки.
    private var конец: some View {
        /* Одни «Проверьте» (точных нет) — без галочки и без «Это всё, что подходит»: под плашками «Размер не указан». */
        let проверка: Bool = модель.толькоПроверить
        return VStack(spacing: 6) {
            Image(systemName: проверка ? УровеньАвтоподбора.проверить.значок : "checkmark.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(проверка ? УровеньАвтоподбора.проверить.краска : Theme.зелёный2)
                .accessibilityHidden(true)
            Text(проверка ? НовинкиМоегоText.т("nm_end_check") : т("fv_end"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текст)
            Text(т("fv_end_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
            Button(т("fv_more")) {
                ОкноМоего.открыть()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Ссылка изнутри окна: окно закрывается, адрес — путём корня приложения.
    private func открытьАдрес(_ адрес: URL) {
        закрыть()
        ПоверхВсего.открытьАдрес(адрес)
    }
}
