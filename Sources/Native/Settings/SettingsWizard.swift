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

    private static let шагов = 5

    init(авто: Bool, открыть: @escaping (URL) -> Void) {
        self.авто = авто
        self.открыть = открыть
        _сВерификацией = State(initialValue: НастройкиМодель.shared.мастерСВерификацией)
    }

    var body: some View {
        NavigationStack {
            содержимое
                .background(Theme.фонСтраницы)
                .tint(Theme.акцент)
                .navigationTitle(заголовок)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(тН("close")) { крестик() }
                    }
                }
        }
        .sheet(item: $применить, onDismiss: { вперёд() }) { поле in
            ОкноПрименения(поле: поле)
                .presentationDetents([.medium])
        }
    }

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

    @ViewBuilder
    private var содержимое: some View {
        if шаг < 0 {
            вступление
        } else if шаг >= Self.шагов {
            финал
        } else {
            VStack(spacing: 0) {
                полоса
                шагМастера
            }
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
            VStack(alignment: .leading, spacing: 14) {
                Text(тН("cabwiz_lead"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(мета)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                VStack(alignment: .leading, spacing: 12) {
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
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                КнопкаСайта(подпись: тН("cabwiz_go"), идёт: false) { начать() }
                Button(тН("cabwiz_skip")) { пропуститьВсё() }
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
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

    /// Полоса шага (_cabWizПолоса): «Назад», «Шаг N из M», «Пропустить» и точки.
    private var полоса: some View {
        VStack(spacing: 6) {
            HStack {
                Button(тН("cabwiz_back")) { назад() }
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Text(тН("cabwiz_step").replacingOccurrences(of: "{n}", with: String(шаг + 1))
                        .replacingOccurrences(of: "{m}", with: String(Self.шагов)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                Button(тН("cabwiz_skip")) { вперёд() }
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityLabel(тН("cabwiz_skip_step"))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.поверхность)
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
            ProgressView()
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
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(тН(сВерификацией ? "cabwiz_ver_s" : "cabwiz_done_s"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if сВерификацией {
                    КнопкаСайта(подпись: тН("cabwiz_ver_go"), идёт: false) { пройтиВерификацию() }
                    Button(тН("cabwiz_later")) { закрыть() }
                        .font(.system(size: 15, weight: .bold))
                } else {
                    КнопкаСайта(подпись: тН("cabwiz_add"), идёт: false) { добавитьОбъявление() }
                    Button(тН("cabwiz_home")) { закрыть() }
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .padding(24)
        }
    }

    // MARK: - Переходы

    private func начать() {
        модель.отметитьМастер("started")
        шаг = 0
    }

    /// cabWizSkip(e): закрыть; skipped — только у самооткрывшегося.
    private func пропуститьВсё() {
        if авто { модель.отметитьМастер("skipped") }
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
            НастройкиВерификация.открыть(профиль: профиль, открыть: действие)
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

/// Шаг «Оформление» (cabPrefTheme): «Меняется сразу. «Как в системе» — как настроено на телефоне.», три кнопки темы,
/// «Далее». Тема ставится приложению сразу (этап 15) и уходит в аккаунт (ui_prefs), как у сайта.
struct ФормаТемыМастера: View {
    let готово: () -> Void
    @ObservedObject private var выбор = ВыборТемы.shared

    init(готово: @escaping () -> Void) {
        self.готово = готово
    }

    var body: some View {
        Form {
            Section {
                Picker(тН("cabwiz_theme_t"), selection: тема) {
                    Text(тН("ap_auto")).tag(ТемаОформления.системная)
                    Text(тН("ap_light")).tag(ТемаОформления.светлая)
                    Text(тН("ap_dark")).tag(ТемаОформления.тёмная)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(тН("cabwiz_theme_hint").replacingOccurrences(of: "{auto}", with: тН("ap_auto")))
                    .textCase(nil)
            }
            КнопкаНастройки(подпись: тН("cabwiz_next"), идёт: false) { готово() }
        }
        .scrollContentBackground(.hidden)
    }

    private var тема: Binding<ТемаОформления> {
        Binding(get: { выбор.тема }, set: { новая in
            выбор.тема = новая
            НастройкиМодель.shared.темаВыбрана(новая)
        })
    }
}
