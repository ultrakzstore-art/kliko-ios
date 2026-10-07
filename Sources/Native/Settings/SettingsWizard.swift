import SwiftUI

/**
 МАСТЕР «НАЧАЛО РАБОТЫ» — ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»), cabWizStart сайта
 (карта §6.2.14).

 Вступление: «Начало работы», «Настроим кабинет за пару минут…», «{n} шагов · около {m} минут» (n — пять шагов и, если
 человек не верифицирован и KYC включён, строка «Верификация через eGov»; m = max(2, round(n / 2))), список шагов,
 «Начать» и «Пропустить». Шаги — те же окна, что в настройках, и в том же порядке: оформление, регион и адрес, мои
 категории, режим работы, личные данные на фото; сверху полоса «Назад · Шаг N из 5 · Пропустить», а «Сохранить» в шаге
 становится «Далее». Финал — «Кабинет настроен» (+ «Добавить объявление» / «В кабинет») или «Последний шаг —
 верификация» (+ «Пройти верификацию» / «Позже»).

 save_onboard, как у сайта: «Начать» — started, дошли до финала — done, «Пропустить» на вступлении — skipped, но только
 если мастер открылся сам (из настроек «Пропустить» ничего не шлёт, cabWizSkip). После адреса и режима работы вопрос
 «Применить к объявлениям?» задаётся, только если мастер запущен из настроек (у самооткрывшегося сайт его не задаёт).
 Крестик закрывает мастер целиком — сохранённое в шагах уже сохранено.
 */
struct ЛистНачалаРаботы: View {
    let авто: Bool
    let открыть: (URL) -> Void
    @ObservedObject private var модель = НастройкиМодель.shared
    @Environment(\.dismiss) private var закрыть
    /// -1 — вступление, 0…4 — шаги, 5 — финал.
    @State private var шаг = -1
    @State private var применить: ПолеПрименения? = nil
    /// Верификация нужна — считаем один раз при открытии: после финала профиль мог обновиться.
    @State private var сВерификацией: Bool
    /// «Пропустить» на вступлении уже отправил skipped — смахнутый следом лист второй раз не шлёт.
    @State private var пропускОтмечен = false

    private static let шагов = 5

    init(авто: Bool, открыть: @escaping (URL) -> Void) {
        self.авто = авто
        self.открыть = открыть
        _сВерификацией = State(initialValue: НастройкиМодель.shared.мастерСВерификацией)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                верх
                содержимое
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .tint(Theme.акцент)
            // Своя шапка вместо панели навигации: на iOS 26 «Закрыть» в панели — стеклянная капсула с тенью, и
            // заголовок уезжал из середины. Стек остаётся ради окон форм.
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        /* Самооткрывшийся мастер смахнули вниз на вступлении — как клик мимо окна у сайта (cabWizSkip(новый)): skipped,
           иначе CAB_ONBOARD_DUE остаётся на сервере, и мастер открывается сам при каждом запуске. */
        .onDisappear {
            if авто && шаг < 0 && !пропускОтмечен {
                пропускОтмечен = true
                модель.отметитьМастер("skipped")
            }
        }
        .sheet(item: $применить, onDismiss: { вперёд() }) { поле in
            ОкноПрименения(поле: поле)
        }
    }

    /// Заголовок шага крупно над карточкой (сама шапка листа — всегда «Начало работы»).
    private var заголовок: String {
        switch шаг {
        case 0: return тН("cabwiz_theme_t")
        case 1: return тН("cabset_geo")
        case 2: return тН("cabset_cats")
        case 3: return тН("cabset_hours")
        case 4: return тН("cabwiz_photo_t")
        default: return тН("cabwiz_t")
        }
    }

    /// Шапка листа и, на шагах, полоса шага — на том же фоне, что тело; снизу тонкая черта, как у листа фильтров.
    private var верх: some View {
        VStack(spacing: 0) {
            ШапкаЛистаМастера(заголовок: тН("cabwiz_t"), подписьЗакрыть: тН("close")) { крестик() }
            if шаг >= 0 && шаг < Self.шагов {
                полоса
            }
        }
        .background(Theme.фонСтраницы)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if шаг < 0 {
            вступление
        } else if шаг >= Self.шагов {
            финал
        } else {
            шагМастера
                .environment(\.заголовокШагаМастера, заголовок)
        }
    }

    // MARK: - Вступление

    private struct ПунктМастера: Identifiable {
        let id: Int
        let значок: String
        let заголовок: String
        let подпись: String
    }

    private var пункты: [ПунктМастера] {
        var список: [ПунктМастера] = [
            ПунктМастера(id: 0, значок: "circle.lefthalf.filled", заголовок: тН("cabwiz_theme_t"),
                         подпись: тН("cabwiz_s_theme")),
            ПунктМастера(id: 1, значок: "mappin.and.ellipse", заголовок: тН("cabset_geo"), подпись: тН("cabwiz_s_geo")),
            ПунктМастера(id: 2, значок: "square.grid.2x2", заголовок: тН("cabset_cats"), подпись: тН("cabwiz_s_cats")),
            ПунктМастера(id: 3, значок: "clock", заголовок: тН("cabset_hours"), подпись: тН("cabwiz_s_hours")),
            ПунктМастера(id: 4, значок: "lock", заголовок: тН("cabwiz_photo_t"), подпись: тН("cabwiz_s_photo"))
        ]
        if сВерификацией {
            список.append(ПунктМастера(id: 5, значок: "checkmark.shield", заголовок: тН("ver_row"),
                                       подпись: тН("ver_row_s")))
        }
        return список
    }

    private var вступление: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(тН("cabwiz_lead"))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(мета)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(пункты) { пункт in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: пункт.значок)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.акцент)
                                .frame(width: 34, height: 34)
                                .background(Theme.мята, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(пункт.заголовок)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.текст)
                                Text(пункт.подпись)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.текстВторой)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .padding(.top, 16)
            }
            .padding(.horizontal, РазметкаМастера.отступ)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ПанельКнопкиМастера {
                КнопкаСайта(подпись: тН("cabwiz_go"), идёт: false) { начать() }
                ВтораяКнопкаМастера(подпись: тН("cabwiz_skip")) { пропуститьВсё() }
            }
        }
    }

    /// «{n} шагов · около {m} минут».
    private var мета: String {
        let n = пункты.count
        let m = max(2, Int((Double(n) / 2).rounded()))
        return тН("cabwiz_meta").replacingOccurrences(of: "{n}", with: String(n))
            .replacingOccurrences(of: "{m}", with: String(m))
    }

    // MARK: - Шаги

    /// Полоса шага (_cabWizПолоса): «‹ Назад», «Шаг N из M», «Пропустить» и деления. С первого шага «Назад» ведёт на
    /// вступление, как у сайта, — там он приглушён.
    private var полоса: some View {
        VStack(spacing: 8) {
            ZStack {
                Text(тН("cabwiz_step").replacingOccurrences(of: "{n}", with: String(шаг + 1))
                        .replacingOccurrences(of: "{m}", with: String(Self.шагов)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Button { назад() } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .flipsForRightToLeftLayoutDirection(true)
                                .accessibilityHidden(true)
                            Text(тН("cabwiz_back"))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(шаг == 0 ? Theme.текстВторой : Theme.акцент)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    Button { вперёд() } label: {
                        Text(тН("cabwiz_skip"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.акцент)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(тН("cabwiz_skip_step"))
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<Self.шагов, id: \.self) { i in
                    Capsule()
                        .fill(i <= шаг ? Theme.зелёныйЯркий : Theme.линия)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, РазметкаМастера.отступ)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var шагМастера: some View {
        if let п = модель.профиль {
            switch шаг {
            case 0:
                ФормаТемыМастера(готово: { вперёд() })
            case 1:
                ФормаРегиона(профиль: п, кнопка: тН("cabwiz_next"), готово: { поле in сохранено(поле) })
                    .scrollContentBackground(.hidden)
            case 2:
                ФормаКатегорий(профиль: п, кнопка: тН("cabwiz_next"), готово: { вперёд() })
                    .scrollContentBackground(.hidden)
            case 3:
                ФормаЧасов(профиль: п, кнопка: тН("cabwiz_next"), готово: { поле in сохранено(поле) })
                    .scrollContentBackground(.hidden)
            default:
                ФормаФото(профиль: п, кнопка: тН("cabwiz_next"), готово: { вперёд() })
                    .scrollContentBackground(.hidden)
            }
        } else {
            SiteSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await модель.загрузить() }
        }
    }

    // MARK: - Финал

    private var финал: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 72, height: 72)
                    .background(Theme.мята, in: Circle())
                    .accessibilityHidden(true)
                Text(тН(сВерификацией ? "cabwiz_ver_t" : "cabwiz_done_t"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(тН(сВерификацией ? "cabwiz_ver_s" : "cabwiz_done_s"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, РазметкаМастера.отступ)
            .padding(.top, 32)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ПанельКнопкиМастера {
                if сВерификацией {
                    КнопкаСайта(подпись: тН("cabwiz_ver_go"), идёт: false) { пройтиВерификацию() }
                    ВтораяКнопкаМастера(подпись: тН("cabwiz_later")) { закрыть() }
                } else {
                    КнопкаСайта(подпись: тН("cabwiz_add"), идёт: false) { добавитьОбъявление() }
                    ВтораяКнопкаМастера(подпись: тН("cabwiz_home")) { закрыть() }
                }
            }
        }
    }

    // MARK: - Переходы

    private func начать() {
        модель.отметитьМастер("started")
        шаг = 0
    }

    /// cabWizSkip(e): закрыть; skipped — только у самооткрывшегося.
    private func пропуститьВсё() {
        if авто && !пропускОтмечен {
            пропускОтмечен = true
            модель.отметитьМастер("skipped")
        }
        закрыть()
    }

    private func крестик() {
        if шаг < 0 {
            пропуститьВсё()
        } else {
            закрыть()
        }
    }

    /// Шаг сохранён: у запущенного из настроек — вопрос «Применить к объявлениям?», потом дальше (onDismiss).
    private func сохранено(_ поле: ПолеПрименения?) {
        if let поле, !авто {
            применить = поле
        } else {
            вперёд()
        }
    }

    private func вперёд() {
        guard шаг >= 0, шаг < Self.шагов else { return }
        let следующий = шаг + 1
        шаг = следующий
        if следующий >= Self.шагов { модель.отметитьМастер("done") }
    }

    /// «Назад» с первого шага — снова вступление (сайт открывает cabWizStart заново).
    private func назад() {
        шаг = max(-1, шаг - 1)
    }

    private func пройтиВерификацию() {
        let профиль = модель.профиль
        let действие = открыть
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            НастройкиВерификация.открыть(профиль: профиль, открыть: действие, задержка: 250_000_000)
        }
    }

    /// showAdd: мастер подачи приложения (этап 42), выключен — страница сайта ?go=add.
    private func добавитьОбъявление() {
        let действие = открыть
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if !ПодачаОкно.shared.открыть(.новое), let адрес = Config.страницаСайта("cabinet?go=add") {
                действие(адрес)
            }
        }
    }
}

/// Шаг «Оформление» (cabPrefTheme): заголовок шага, «Меняется сразу. «Как в системе» — как настроено на телефоне.»,
/// три кнопки темы, «Далее» внизу. Тема ставится приложению сразу (этап 15) и уходит в аккаунт (ui_prefs), как у сайта.
struct ФормаТемыМастера: View {
    let готово: () -> Void
    @ObservedObject private var выбор = ВыборТемы.shared

    init(готово: @escaping () -> Void) {
        self.готово = готово
    }

    var body: some View {
        Form {
            РазделШагаМастера(подсказка: тН("cabwiz_theme_hint").replacingOccurrences(of: "{auto}", with: тН("ap_auto")))
            Section {
                Picker(тН("cabwiz_theme_t"), selection: тема) {
                    Text(тН("ap_auto")).tag(ТемаОформления.системная)
                    Text(тН("ap_light")).tag(ТемаОформления.светлая)
                    Text(тН("ap_dark")).tag(ТемаОформления.тёмная)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .scrollContentBackground(.hidden)
        .кнопкаШагаМастера(подпись: тН("cabwiz_next"), идёт: false) { готово() }
    }

    private var тема: Binding<ТемаОформления> {
        Binding(get: { выбор.тема }, set: { новая in
            выбор.тема = новая
            НастройкиМодель.shared.темаВыбрана(новая)
        })
    }
}

// MARK: - Общие части мастера

/// Отступ мастера от края листа — как у карточек формы и листа фильтров.
enum РазметкаМастера {
    static let отступ: CGFloat = 16
}

/// Шапка листа мастера, как у листа фильтров (.afx-h): «×» слева, заголовок строго посередине, без панели навигации.
struct ШапкаЛистаМастера: View {
    let заголовок: String
    let подписьЗакрыть: String
    let закрыть: () -> Void

    var body: some View {
        ZStack {
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button(action: закрыть) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(подписьЗакрыть)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 56)
    }
}

/// Нижняя панель мастера (.afx-f листа фильтров): кнопки закреплены внизу на всю ширину содержимого, над ними черта.
struct ПанельКнопкиМастера<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(spacing: 4) {
            содержимое
        }
        .padding(.horizontal, РазметкаМастера.отступ)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.фонСтраницы.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }
}

/// Вторая кнопка под зелёной (.cabwiz-later): «Пропустить», «Позже», «В кабинет».
struct ВтораяКнопкаМастера: View {
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ЗаголовокШагаМастераКлюч: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Форма настройки открыта шагом мастера: заголовок шага сверху, «Далее» закреплена внизу; nil — обычный лист.
    var заголовокШагаМастера: String? {
        get { self[ЗаголовокШагаМастераКлюч.self] }
        set { self[ЗаголовокШагаМастераКлюч.self] = newValue }
    }
}

/// Первый раздел формы в мастере: крупный заголовок шага и подсказка под ним, вровень с краем карточек.
/// Вне мастера — ничего (подсказка там в шапке раздела, ПодсказкаФормыНастройки).
struct РазделШагаМастера: View {
    let подсказка: String
    @Environment(\.заголовокШагаМастера) private var заголовок

    init(подсказка: String) {
        self.подсказка = подсказка
    }

    var body: some View {
        if let заголовок {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(заголовок)
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(подсказка)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))
            }
        }
    }
}

/// Подсказка в шапке раздела формы — только вне мастера (в мастере она под заголовком шага).
struct ПодсказкаФормыНастройки: View {
    let текст: String
    @Environment(\.заголовокШагаМастера) private var шагМастера

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        if шагМастера == nil {
            Text(текст).textCase(nil)
        }
    }
}

extension View {
    /// В мастере: «Далее» закреплена внизу листа (ПанельКнопкиМастера), разделы формы плотнее. Вне мастера — как было
    /// (кнопка — последней строкой формы, КнопкаНастройки).
    func кнопкаШагаМастера(подпись: String, идёт: Bool, действие: @escaping () -> Void) -> some View {
        modifier(КнопкаШагаМастера(подпись: подпись, идёт: идёт, действие: действие))
    }
}

struct КнопкаШагаМастера: ViewModifier {
    let подпись: String
    let идёт: Bool
    let действие: () -> Void
    @Environment(\.заголовокШагаМастера) private var шагМастера

    init(подпись: String, идёт: Bool, действие: @escaping () -> Void) {
        self.подпись = подпись
        self.идёт = идёт
        self.действие = действие
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if шагМастера != nil {
            content
                .listSectionSpacing(.compact)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ПанельКнопкиМастера {
                        КнопкаСайта(подпись: подпись, идёт: идёт, действие: действие)
                    }
                }
        } else {
            content
        }
    }
}
